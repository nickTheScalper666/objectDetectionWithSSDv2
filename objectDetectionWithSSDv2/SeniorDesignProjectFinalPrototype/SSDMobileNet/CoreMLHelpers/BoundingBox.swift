//
//  BoundingBox.swift
//  SSDMobileNet  (modernized for Swift 5 / iOS 12+)
//

import Foundation
import UIKit

final class BoundingBox {
    private let shapeLayer = CAShapeLayer()
    private let textLayer  = CATextLayer()

    init() {
        // --- Box layer ---
        shapeLayer.fillColor   = UIColor.clear.cgColor
        shapeLayer.strokeColor = UIColor.red.cgColor
        shapeLayer.lineWidth   = 4
        shapeLayer.isHidden    = true

        // --- Label layer ---
        textLayer.contentsScale = UIScreen.main.scale
        textLayer.fontSize       = 14
        // `font` expects a CFType; using UIFont bridged as CFTypeRef is OK
        if let uiFont = UIFont(name: "Avenir", size: textLayer.fontSize) {
            textLayer.font = uiFont as CFTypeRef
        }
        textLayer.alignmentMode  = .center        // was kCAAlignmentCenter
        textLayer.foregroundColor = UIColor.black.cgColor
        textLayer.backgroundColor = UIColor.white.withAlphaComponent(0.75).cgColor
        textLayer.cornerRadius    = 3
        textLayer.isHidden        = true
        textLayer.masksToBounds   = true
    }

    // Attach to a parent CALayer (e.g., view.layer)
    func addToLayer(_ parent: CALayer) {
        parent.addSublayer(shapeLayer)
        parent.addSublayer(textLayer)
    }

    func remove() {
        shapeLayer.removeFromSuperlayer()
        textLayer.removeFromSuperlayer()
    }

    func show(frame: CGRect, label: String, color: UIColor, textColor: UIColor = .black) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Box
        shapeLayer.path       = UIBezierPath(rect: frame).cgPath
        shapeLayer.strokeColor = color.cgColor
        shapeLayer.isHidden    = false

        // Label (build attributed string with modern keys)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: textColor,
            .backgroundColor: UIColor.white.withAlphaComponent(0.75)
        ]
        let attributed = NSAttributedString(string: label, attributes: attrs)
        textLayer.string         = attributed
        textLayer.foregroundColor = textColor.cgColor
        textLayer.backgroundColor = UIColor.white.withAlphaComponent(0.75).cgColor
        textLayer.alignmentMode   = .center

        // Size label to content and position near the top-left of the box
        let size = attributed.size()
        let labelW = size.width + 8
        let labelH = size.height + 4
        let labelX = frame.origin.x
        // put label just above the box if possible; otherwise inside at the top
        let proposedY = frame.origin.y - labelH - 2
        let labelY = proposedY >= 0 ? proposedY : frame.origin.y + 2

        textLayer.frame  = CGRect(x: labelX, y: labelY, width: labelW, height: labelH)
        textLayer.isHidden = false

        CATransaction.commit()
    }

    func hide() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeLayer.isHidden = true
        textLayer.isHidden  = true
        CATransaction.commit()
    }
}

