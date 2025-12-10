
//
//  DepthAndSizeEstimator.swift
//  SSDMobileNet
//
//  Adds LiDAR depth sampling and 2D->metric size estimation.
//
//  Requirements: iOS 14+ (depth APIs), iOS 15+ recommended. ARKit frame semantics: .sceneDepth
//

import Foundation
import ARKit
import Accelerate

public struct DepthSample {
    public let median: Float          // median depth in meters
    public let validCount: Int        // number of valid depth samples
    public let coverage: Float        // 0...1: fraction of sampled points that were valid
}

public struct DimensionEstimate {
    public let distanceM: Float?      // distance from camera to object plane (meters)
    public let widthM: Float?         // approximate physical width of bounding box (meters)
    public let heightM: Float?        // approximate physical height of bounding box (meters)
    public let confidence: Float      // 0...1
}

// Typical coarse size priors per COCO class label; used for the "overfit" clamping.
// Ranges are purposefully wide to avoid egregious errors.
public struct TypicalSize {
    public let widthRangeM: ClosedRange<Float>
    public let heightRangeM: ClosedRange<Float>
    public let nominalM: (w: Float, h: Float)
}

public enum OverfitMode {
    case off
    case clampToRange   // clamp into a typical size range if depth/intrinsics computation is noisy
    case blendToNominal(strength: Float) // 0...1: 0 = no blend, 1 = fully nominal
}

public final class DepthAndSizeEstimator {

    // MARK: - Typical sizes (selected COCO labels)
    // You can extend or adjust as needed.
    public static let typical: [String: TypicalSize] = [
        "person":  .init(widthRangeM: 0.35...0.75, heightRangeM: 1.45...1.95, nominalM: (0.5, 1.70)),
        "chair":   .init(widthRangeM: 0.40...0.70, heightRangeM: 0.75...1.10, nominalM: (0.55, 0.90)),
        "cup":     .init(widthRangeM: 0.06...0.09, heightRangeM: 0.08...0.14, nominalM: (0.08, 0.11)),
        "bottle":  .init(widthRangeM: 0.06...0.09, heightRangeM: 0.18...0.32, nominalM: (0.07, 0.24)),
        "tv":      .init(widthRangeM: 0.70...1.60, heightRangeM: 0.40...0.95, nominalM: (1.20, 0.70)),
        "laptop":  .init(widthRangeM: 0.28...0.38, heightRangeM: 0.20...0.27, nominalM: (0.33, 0.23)),
        "keyboard":.init(widthRangeM: 0.25...0.50, heightRangeM: 0.03...0.05, nominalM: (0.35, 0.04)),
        "book":    .init(widthRangeM: 0.12...0.25, heightRangeM: 0.18...0.32, nominalM: (0.17, 0.24)),
        "car":     .init(widthRangeM: 1.60...2.20, heightRangeM: 1.20...1.80, nominalM: (1.90, 1.45))
    ]

    // MARK: - Public API

    /// Estimate distance and size for a detection.
    /// - Parameters:
    ///   - rect300: Bounding rectangle in model space (300x300 pixels, top-left origin).
    ///   - label: Optional COCO label for applying typical-size priors.
    ///   - frame: Current ARFrame with sceneDepth enabled.
    ///   - overfit: Strategy for clamping/adjusting size.
    public static func estimate(rect300: CGRect,
                                label: String?,
                                frame: ARFrame,
                                overfit: OverfitMode = .off) -> DimensionEstimate {

        // 1) Convert model-space rect (300x300) to full captured-image pixel space.
        let imgResolution = CGSize(width: CGFloat(frame.camera.imageResolution.width),
                                   height: CGFloat(frame.camera.imageResolution.height))
        let imageRect = self.imageRectForPrediction(rect300, imageResolution: imgResolution)

        // 2) Sample depth (median) from the sceneDepth map at this ROI.
        let depthSample = self.medianDepth(inImageRect: imageRect, frame: frame)
        guard let medianDepth = depthSample?.median, medianDepth.isFinite, medianDepth > 0 else {
            return DimensionEstimate(distanceM: nil, widthM: nil, heightM: nil, confidence: 0.0)
        }

        // 3) Convert pixel extent to meters using camera intrinsics.
        let (w, h) = self.sizeInMeters(of: imageRect,
                                       depthM: medianDepth,
                                       intrinsics: frame.camera.intrinsics)

        // 4) Optionally clamp / blend with typical sizes.
        let (wAdj, hAdj, conf) = self.applyOverfit(widthM: w, heightM: h, label: label, mode: overfit)

        return DimensionEstimate(distanceM: medianDepth,
                                 widthM: wAdj,
                                 heightM: hAdj,
                                 confidence: conf)
    }

    // MARK: - Depth sampling

    /// Samples the LiDAR scene depth inside `imageRect` and returns a robust median.
    /// `imageRect` is in the pixel space of `capturedImage` (not the depth map).
    public static func medianDepth(inImageRect imageRect: CGRect, frame: ARFrame) -> DepthSample? {
        guard let sceneDepth = frame.sceneDepth ?? frame.smoothedSceneDepth else { return nil }
        let depthBuffer = sceneDepth.depthMap

        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        // Map from image-resolution pixels -> depth-map pixels.
        let depthW = CVPixelBufferGetWidth(depthBuffer)
        let depthH = CVPixelBufferGetHeight(depthBuffer)
        let imgW = CGFloat(frame.camera.imageResolution.width)
        let imgH = CGFloat(frame.camera.imageResolution.height)
        let sx = CGFloat(depthW) / imgW
        let sy = CGFloat(depthH) / imgH
        let dRect = CGRect(
            x: imageRect.origin.x * sx,
            y: imageRect.origin.y * sy,
            width: imageRect.size.width * sx,
            height: imageRect.size.height * sy
        ).integral

        let bounds = CGRect(x: 0, y: 0, width: depthW, height: depthH)
        let roi = dRect.intersection(bounds)
        guard !roi.isNull, roi.width >= 2, roi.height >= 2 else { return nil }

        // Grid sample to reduce cost; skip invalid (<= 0) and non-finite points.
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthBuffer)
        let rowStride = bytesPerRow / MemoryLayout<Float32>.size
        guard let base = CVPixelBufferGetBaseAddress(depthBuffer)?.assumingMemoryBound(to: Float32.self) else { return nil }

        let stepX = max(1, Int(roi.width / 24))  // ~ <= 24x24 samples in ROI
        let stepY = max(1, Int(roi.height / 24))

        var values = [Float]()
        var sampleSlots = 0
        for y in Int(roi.minY)..<Int(roi.maxY) {
            if (y - Int(roi.minY)) % stepY != 0 { continue }
            let row = base + y * rowStride
            for x in Int(roi.minX)..<Int(roi.maxX) {
                if (x - Int(roi.minX)) % stepX != 0 { continue }
                sampleSlots += 1
                let d = row[x]
                if d.isFinite && d > 0.0 && d < 20.0 { // ignore extreme outliers
                    values.append(d)
                }
            }
        }
        guard !values.isEmpty else { return nil }
        values.sort()
        let median = values[values.count / 2]
        let coverage = Float(values.count) / max(1.0, Float(sampleSlots))
        return DepthSample(median: median, validCount: values.count, coverage: coverage)
    }

    // MARK: - Size conversion

    /// Convert model-space (300x300) rectangle into full captured-image pixel space (accounts for center crop).
    public static func imageRectForPrediction(_ rect300: CGRect, imageResolution: CGSize) -> CGRect {
        let cropSide = min(imageResolution.width, imageResolution.height)
        let scale = cropSide / 300.0
        let rectCropped = CGRect(
            x: rect300.origin.x * scale,
            y: rect300.origin.y * scale,
            width: rect300.width * scale,
            height: rect300.height * scale
        )

        if imageResolution.height >= imageResolution.width {
            // Portrait: vertical letterboxing
            let yOffset = (imageResolution.height - cropSide) / 2.0
            return rectCropped.offsetBy(dx: 0, dy: yOffset)
        } else {
            // Landscape: horizontal letterboxing
            let xOffset = (imageResolution.width - cropSide) / 2.0
            return rectCropped.offsetBy(dx: xOffset, dy: 0)
        }
    }

    /// Compute physical (meter) width & height of the 2D rect at depth `depthM` using camera intrinsics.
    public static func sizeInMeters(of imageRect: CGRect,
                                    depthM: Float,
                                    intrinsics: simd_float3x3) -> (width: Float, height: Float) {
        // Pinhole: w_m = w_px * Z / fx, h_m = h_px * Z / fy
        let fx = intrinsics[0, 0]
        let fy = intrinsics[1, 1]
        // Avoid divide-by-zero
        let w_px = Float(imageRect.width)
        let h_px = Float(imageRect.height)
        let w_m = (w_px * depthM) / max(fx, 1e-6)
        let h_m = (h_px * depthM) / max(fy, 1e-6)
        return (abs(w_m), abs(h_m))
    }

    // MARK: - Overfit / Priors

    private static func applyOverfit(widthM: Float,
                                     heightM: Float,
                                     label: String?,
                                     mode: OverfitMode) -> (Float, Float, Float) {
        guard let label = label?.lowercased(),
              let prior = typical[label] else {
            switch mode {
            case .off: return (widthM, heightM, 1.0)
            case .clampToRange: return (widthM, heightM, 0.8) // no prior found; keep raw
            case .blendToNominal(let strength):
                let s = max(0, min(1, strength))
                return (widthM*(1-s), heightM*(1-s), 0.8)
            }
        }

        switch mode {
        case .off:
            return (widthM, heightM, 1.0)

        case .clampToRange:
            let w = min(max(widthM, prior.widthRangeM.lowerBound), prior.widthRangeM.upperBound)
            let h = min(max(heightM, prior.heightRangeM.lowerBound), prior.heightRangeM.upperBound)
            // Confidence increases if we clamp only slightly
            let dw = abs(w - widthM)
            let dh = abs(h - heightM)
            let delta = max(dw, dh)
            let conf = Float( max(0.5, 1.0 - (delta / max(0.01, prior.nominalM.w))) )
            return (w, h, conf)

        case .blendToNominal(let strength):
            let s = max(0, min(1, strength))
            let bw = prior.nominalM.w * s + widthM * (1 - s)
            let bh = prior.nominalM.h * s + heightM * (1 - s)
            return (bw, bh, 0.9)
        }
    }
}
