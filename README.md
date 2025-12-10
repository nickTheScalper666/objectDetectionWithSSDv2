# iOS Object Detection & Navigation Assistance App**


---

## **📘 Project Overview**

This project presents an iOS application designed to assist users—particularly individuals with visual impairments—by providing **real-time object detection, distance estimation, and spatial audio navigation cues**.  
Using **ARKit**, **CoreML**, and the **LiDAR sensor** available on modern iPhones, the system identifies objects in the user’s environment and communicates their position and distance through audio.

The app is intended as a research-driven prototype demonstrating how mobile computer vision and augmented reality can improve spatial awareness and accessibility.

---

## **🎯 Objectives**

1. Build a real-time mobile vision system capable of identifying everyday objects.  
2. Use LiDAR depth data to compute accurate object distance.  
3. Deliver spatial audio feedback to guide the user in physical space.  
4. Demonstrate a fully on-device, low-latency assistive navigation prototype.  
5. Provide a polished, installable iOS application for demonstration and evaluation.

---

## **🧪 Technical Features**

### **1. Real-Time Object Detection**
- Uses CoreML ssd/mobilenet-based object detection models  
- Identifies certain classes of objects. Read the coreMl file on xcode
- Runs entirely on-device using the Apple Neural Engine/GPU for performance

### **2. LiDAR-Based Distance Estimation**
- Measures depth via LiDAR sensor  
- Computes distance to the center of each detected object  
- Converts values into meter-based announcements

### **3. Spatial Audio Navigation**
- Announces object name, direction, and distance   
- Helps users orient themselves without visual input

### **4. Augmented Reality Visualization**
- Bounding boxes over real-world objects  
- Depth map interpretation  
- Debug UI for calibration and demonstration

---


---

# **📱 Installation Guide – Running on a Physical iPhone**

This section provides a full, step-by-step guide for professors, graders, or research collaborators to install and test the prototype on an iPhone.

---

## **1. Requirements**

- macOS with **Xcode** installed  
- iPhone with **LiDAR** (iPhone 12 Pro or newer)  
- iOS 16+  
- Apple ID for code signing  
- USB-C or Lightning cable

---

## **2. Install Xcode**

Download from the official source:  
https://apps.apple.com/us/app/xcode/id497799835

---

## **3. Open the Project**

1. Unzip the project folder  
2. Open:


---

## **4. Connect the iPhone**

- Plug in the device with a wired connection to a mac  
- Unlock the phone  
- Tap **“Trust This Computer”** if prompted

---

## **5. Enable Developer Mode (Required by Apple)**

1. Run the app once in Xcode  
2. iPhone will show:

   **“Enable Developer Mode?”**  
3. Go to Settings → Privacy & Security → Developer Mode → **Enable**  
4. Device restarts  
5. Run again

---

## **6. Configure Signing (Most Important Step)**

In Xcode:

1. Select the **project** in the Navigator  
2. Select the **app target**  
3. Go to **Signing & Capabilities**  
4. Enable:


5. Under **Team**, choose your Apple ID  
6. Ensure the Bundle Identifier is unique, for example:


---

## **7. Build & Run the App**

Press:


Xcode will:
- Build the project  
- Install it on the iPhone  
- Launch it automatically  

If iPhone shows “Untrusted Developer”, go to:

**Settings → General → VPN & Device Management → Developer App → Trust**

---

# **🧭 Usage Instructions**

### **Object Detection**
- Point the camera at surroundings  
- Detected objects appear with bounding boxes  

### **Distance Estimation**
- App determines depth using LiDAR  
- Displays and announces distance in meters  

### **Spatial Audio Navigation**
- Speaks object labels + estimated position  
- Helps users orient themselves without visual input  

