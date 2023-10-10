//
//  VideoCapture.swift
//  Awesome ML
//
//  Created by Eugene Bokhan on 3/13/18.
//  Updated by Doyoung Gwak on 03/07/2018.
//  Copyright © 2018 Eugene Bokhan. All rights reserved.
//

import UIKit
import AVFoundation
import CoreVideo

public protocol VideoCaptureDelegate: class {
    func videoCapture(_ capture: VideoCapture, didCaptureVideoSampleBuffer: CMSampleBuffer)
}

public class VideoCapture: NSObject{
    public var previewLayer: AVCaptureVideoPreviewLayer?
    public weak var delegate: VideoCaptureDelegate?
    public weak var depthDelegate: AVCaptureDepthDataOutputDelegate?
    
    //Giles - change frames per second FPS with the below command? Was 15
    //Giles5 change again?
    public var fps = 50
    
    let captureSession = AVCaptureSession()
    let videoOutput = AVCaptureVideoDataOutput()
    
    //Giles5 depthdata commented out
    
    ///
    ///
    ///
    let depthDataOutput = AVCaptureDepthDataOutput()
    ///
    ///
    ///
    
    let queue = DispatchQueue(label: "com.tucan9389.camera-queue")
    let sessionQueue = DispatchQueue(label: "data queue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    var outputSynchronizer: AVCaptureDataOutputSynchronizer?
    var videoTextureCache: CVMetalTextureCache?
    
    //Gileszzz could selection of this be what overly zooms in the image? .vga640x480
    public func setUp(sessionPreset: AVCaptureSession.Preset = .vga640x480,
                      completion: @escaping (Bool) -> Void) {
        self.setUpCamera(sessionPreset: sessionPreset, completion: { success in
            completion(success)
        })
    }
    //Giles change .front (selfie) to .back for the back camera
    //Giles5 - what other cameras and FoV options are available?
    func setUpCamera(sessionPreset: AVCaptureSession.Preset, position: AVCaptureDevice.Position? = .back, completion: @escaping (_ success: Bool) -> Void) {
        
        captureSession.beginConfiguration()
        captureSession.sessionPreset = sessionPreset
        
        
        let device: AVCaptureDevice?
//        if let position = position {
//            //Giles5 - .builtintruedepthcamera + .front above = selfie depth cam, .builtInWideAngleCamera
//            device = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: position).devices.first
//        }
//
//        else {
//            device = AVCaptureDevice.default(for: AVMediaType.video)
//        }
////            device = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTrueDepthCamera], mediaType: .video, position: position).devices.first
////        } else {
////            device = AVCaptureDevice.default(.builtInDualCamera, for: AVMediaType.video,position: .back)
////        }
        ///
        ///
        ///
//        if let position = position {
            if #available(iOS 15.4, *) {
                device = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInLiDARDepthCamera], mediaType: .video, position: .back).devices.first
                print("LiDAR available")
            } else {
                device = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .back).devices.first
                print("LiDAR not available, using wide angle cam")
                // Fallback on earlier versions
            }
//        }
//        else if #available(iOS 15.4, *) {
//            device = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInLiDARDepthCamera], mediaType: .video, position: position ?? .back).devices.first
//            print("LiDAR available")
//        } else {
//            device = AVCaptureDevice.default(.builtInDualCamera, for: AVMediaType.video,position: .back)
//        }
        ///
        ///
        ///
        ///
        
        guard let captureDevice = device else {
            print("Error: no video devices available")
            return
        }
        
        guard let videoInput = try? AVCaptureDeviceInput(device: captureDevice) else {
            print("Error: could not create AVCaptureDeviceInput")
            return
        }
        
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        }
        
        let settings: [String : Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA),
        ]
        
        videoOutput.videoSettings = settings
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        
        //Giles5 - commented out depthdata
        if captureSession.canAddOutput(depthDataOutput) {
            depthDataOutput.setDelegate(self, callbackQueue: queue)
            depthDataOutput.isFilteringEnabled = true
            captureSession.addOutput(depthDataOutput)
            let depthConnection = depthDataOutput.connection(with: .depthData)
            depthConnection?.videoOrientation = .portrait
        }
       
        
        // We want the buffers to be in portrait orientation otherwise they are
        // rotated by 90 degrees. Need to set this _after_ addOutput()!
        videoOutput.connection(with: AVMediaType.video)?.videoOrientation = .portrait
        
        outputSynchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [videoOutput, depthDataOutput])
//        outputSynchronizer!.setDelegate(self, queue: queue)
        captureSession.commitConfiguration()
        
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, sharedMetalRenderingDevice.device, nil, &videoTextureCache)
        
        let success = true
        completion(success)
    }
    
    public func start() {
        if !captureSession.isRunning {
            captureSession.startRunning()
        }
    }
    
    public func stop() {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }
    
    public func makePreview() -> AVCaptureVideoPreviewLayer? {
        guard self.previewLayer == nil else { return self.previewLayer }
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = AVLayerVideoGravity.resizeAspect
        previewLayer.connection?.videoOrientation = .portrait
        self.previewLayer = previewLayer
        return previewLayer
    }
    
    //Giles this needs to be public in order to initialize the distance values BUT the below print code never activates
    public func depthDataOutput(depthDelegate output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
       var convertedDepth : AVDepthData
       let depthDataType=kCVPixelFormatType_DepthFloat32
       if depthData.depthDataType != depthDataType {
           convertedDepth = depthData.converting(toDepthDataType: depthDataType)
       } else {
           convertedDepth = depthData
       }

       let depthDataMap = convertedDepth.depthDataMap
       //depthDataMap.clamp()
//        let depthMap=CIImage(cvPixelBuffer: depthDataMap)
//        let depthUIImage = UIImage(ciImage: depthMap)
//        print(saveImage(image: depthUIImage, id:"\(Date())"))
//        [UIImagePNGRepresentation(depthUIImage), writeToFile,:[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0], stringByAppendingString,:@"/myImage.png"] atomically:NO];

       //Width is 180 and Height is 320 on this
//        let width = CVPixelBufferGetWidth(depthDataMap) //768 on an iPhone 7+
//        let height = CVPixelBufferGetHeight(depthDataMap) //576 on an iPhone 7+

//        print("depthMap pixel width is \(width)")
//        print("depthMap pixel height is \(height)")

       CVPixelBufferLockBaseAddress(depthDataMap, CVPixelBufferLockFlags(rawValue: 0))

       // Convert the base address to a safe pointer of the appropriate type
       let floatBuffer = unsafeBitCast(CVPixelBufferGetBaseAddress(depthDataMap), to: UnsafeMutablePointer<Float32>.self)

       // Read the data (returns value of type Float)
       // Accessible values : (width-1) * (height-1) = 767 * 575

       //This is 28890
//        let middleLocation = ((width * (height/2))+width/2)
       //This is 28890
       let middleLocationSimpleInt:Int = 28890
//        print("middle location is \(middleLocation)")
//
////        let distanceAtXYPoint = floatBuffer[Int(3 * 3)]
//        let widthDouble:Double = Double(width)
//        let heightDouble:Double = Double(height)
//
//        let proportionX:Double = 0.5
//        let proportionY:Double = 0.5
//        let pixelSelected:Double = ((widthDouble*proportionX)*(heightDouble*proportionY))
//
//        let pixelSelectedInt:Int = Int(pixelSelected)
//        print("The pixel selected is \(pixelSelected)")

//        let distanceAtXYPoint = floatBuffer[Int(middleLocation)]
//        let distanceAtXYPoint = floatBuffer[pixelSelectedInt]
       let distanceAtXYPoint = floatBuffer[middleLocationSimpleInt]

//        redirectLogs(flag:true)
//        print("The distance is \(distanceAtXYPoint)")
       print("First \(distanceAtXYPoint)")
//
////        Tactile feedback style 1
//       var impactFeedbackGenerator:UIImpactFeedbackGenerator
//       if distanceAtXYPoint < 0.5 {
//           impactFeedbackGenerator = UIImpactFeedbackGenerator(style: .heavy)
//           impactFeedbackGenerator.impactOccurred(intensity: 1)
//       }
//
//       else if distanceAtXYPoint < 2 {
//           impactFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
//           impactFeedbackGenerator.impactOccurred(intensity: 0.5)
//       }
//       else if distanceAtXYPoint < 3 {
//           impactFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
//           impactFeedbackGenerator.impactOccurred(intensity: 0.1)
//       }
   }


}
    
class DataManager {
    static let shared = DataManager()
    var depthPoints = Array(repeating: Float(0), count: 10)
    var sharedDistanceAtXYPoint:Float = 0
    private init() {}
}

extension VideoCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        delegate?.videoCapture(self, didCaptureVideoSampleBuffer: sampleBuffer)
    }
    
    public func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        //print("dropped frame")
    }
}

extension CVPixelBuffer {
  func clamp() {
    let width = CVPixelBufferGetWidth(self)
    let height = CVPixelBufferGetHeight(self)
    
    CVPixelBufferLockBaseAddress(self, CVPixelBufferLockFlags(rawValue: 0))
    let floatBuffer = unsafeBitCast(CVPixelBufferGetBaseAddress(self), to: UnsafeMutablePointer<Float>.self)

    /// You might be wondering why the for loops below use `stride(from:to:step:)`
    /// instead of a simple `Range` such as `0 ..< height`?
    /// The answer is because in Swift 5.1, the iteration of ranges performs badly when the
    /// compiler optimisation level (`SWIFT_OPTIMIZATION_LEVEL`) is set to `-Onone`,
    /// which is eactly what happens when running this sample project in Debug mode.
    /// If this was a production app then it might not be worth worrying about but it is still
    /// worth being aware of.

    for y in stride(from: 0, to: height, by: 1) {
      for x in stride(from: 0, to: width, by: 1) {
        let pixel = floatBuffer[y * width + x]
        floatBuffer[y * width + x] = min(1.0, max(pixel, 0.0))
      }
    }
    
    CVPixelBufferUnlockBaseAddress(self, CVPixelBufferLockFlags(rawValue: 0))
  }
}

// MARK: - VideoCapture + AVCaptureDepthDataOutputDelegate

extension VideoCapture: AVCaptureDepthDataOutputDelegate {
    public func depthDataOutput(
        _: AVCaptureDepthDataOutput,
        didOutput depthData: AVDepthData,
        timestamp _: CMTime,
        connection _: AVCaptureConnection
    ) {
        var convertedDepth: AVDepthData
        let depthDataType = kCVPixelFormatType_DepthFloat32
        if depthData.depthDataType != depthDataType {
            convertedDepth = depthData.converting(toDepthDataType: depthDataType)
        } else {
            convertedDepth = depthData
        }

        let depthDataMap = convertedDepth.depthDataMap
        CVPixelBufferLockBaseAddress(depthDataMap, CVPixelBufferLockFlags(rawValue: 0))

        // Convert the base address to a safe pointer of the appropriate type
        let floatBuffer = unsafeBitCast(
            CVPixelBufferGetBaseAddress(depthDataMap),
            to: UnsafeMutablePointer<Float32>.self
        )

        for i in 0..<10 {
            DataManager.shared.depthPoints[i] = floatBuffer[28804 + i * 19]
        }

        let middleLocationSimpleInt = 28890
        let distanceAtXYPoint = floatBuffer[middleLocationSimpleInt]
        DataManager.shared.sharedDistanceAtXYPoint = distanceAtXYPoint
    }
}

func redirectLogs(flag:Bool)  {
    if flag {
        if let documentsPathString = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first {
            let logPath = documentsPathString.appending("app.log")
            freopen(logPath.cString(using: String.Encoding.ascii), "a+",stderr)
        }
    }
}

//func saveImage(image: UIImage, id:String) -> Bool {
//    guard let data = image.jpegData(compressionQuality: 1) ?? image.pngData() else {
//        return false
//    }
//    guard let directory = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false) as NSURL else {
//        return false
//    }
//    do {
//        try data.write(to: directory.appendingPathComponent(id+".png")!)
//        return true
//    } catch {
//        print(error.localizedDescription)
//        return false
//    }
//}

// Giles5 - depthdata printed here

//extension VideoCapture: AVCaptureDepthDataOutputDelegate {
//    public func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
//        var convertedDepth : AVDepthData
//        let depthDataType=kCVPixelFormatType_DepthFloat32
//        if depthData.depthDataType != depthDataType {
//            convertedDepth = depthData.converting(toDepthDataType: depthDataType)
//        } else {
//            convertedDepth = depthData
//        }
//
//        let depthDataMap = convertedDepth.depthDataMap
//        //depthDataMap.clamp()
//        let depthMap=CIImage(cvPixelBuffer: depthDataMap)
//        let depthUIImage = UIImage(ciImage: depthMap)
        
        //Giles5 - depth image printed at this point, was printing "true" statements and crashing the system
        //print(saveImage(image: depthUIImage, id:"\(Date())"))
        
        
//        e [UIImagePNGRepresentation(depthUIImage), writeToFile:[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0] stringByAppendingString:@"/myImage.png"] atomically:NO];
//        let width = CVPixelBufferGetWidth(depthDataMap) //768 on an iPhone 7+
//        let height = CVPixelBufferGetHeight(depthDataMap) //576 on an iPhone 7+
//        CVPixelBufferLockBaseAddress(depthDataMap, CVPixelBufferLockFlags(rawValue: 0))

//        // Convert the base address to a safe pointer of the appropriate type
//        let floatBuffer = unsafeBitCast(CVPixelBufferGetBaseAddress(depthDataMap), to: UnsafeMutablePointer<Float32>.self)
//
//        // Read the data (returns value of type Float)
//        // Accessible values : (width-1) * (height-1) = 767 * 575
//
//        let distanceAtXYPoint = floatBuffer[Int(3 * 3)]
//        redirectLogs(flag:true)
//        print(distanceAtXYPoint)

//    }
//}


