//
//  CameraController.swift
//  Camera
//
//  Created by Matteo Caldari on 20/01/15.
//  Copyright (c) 2015 Matteo Caldari. All rights reserved.
//

import AVFoundation
import UIKit
import GLKit

let CameraControllerDidStartSession = "CameraControllerDidStartSession"
let CameraControllerDidStopSession = "CameraControllerDidStopSession"


protocol CameraControllerDelegate : class {
    func cameraController(_ cameraController:CameraController, didOutputImage image: CIImage)
}

enum CameraControllerPreviewType {
    case previewLayer
    case manual
}


class CameraController: NSObject {
    weak var delegate:CameraControllerDelegate?
    var previewType:CameraControllerPreviewType
    var previewLayer:AVCaptureVideoPreviewLayer!
    fileprivate var currentCameraDevice:AVCaptureDevice?
    
    
    // MARK: Private properties
    
    fileprivate var sessionQueue:DispatchQueue = DispatchQueue(label: "capture session queue", attributes: [])
    fileprivate var session:AVCaptureSession!
    fileprivate var backCameraDevice:AVCaptureDevice?
    fileprivate var micDevice:AVCaptureDevice?
    fileprivate var frontCameraDevice:AVCaptureDevice?
    fileprivate var stillCameraOutput:AVCapturePhotoOutput!
    
    // MARK: - Initialization
    
    required init(previewType:CameraControllerPreviewType) {
        self.previewType = previewType
        
        super.init()
        
        initializeSession()
    }
    
    required init(previewType:CameraControllerPreviewType, delegate:CameraControllerDelegate) {
        self.delegate = delegate
        self.previewType = previewType
        
        super.init()
        
        initializeSession()
    }
    
    
    func initializeSession() {
        
        session = AVCaptureSession()
        session.sessionPreset =  AVCaptureSession.Preset.medium
        
        if previewType == .previewLayer {
            previewLayer = AVCaptureVideoPreviewLayer(session: self.session) as AVCaptureVideoPreviewLayer
        }
        
        let authorizationStatus = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
        
        switch authorizationStatus {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: AVMediaType.video,
                                          completionHandler: { (granted:Bool) -> Void in
                                            if granted {
                                                self.configureSession()
                                            }
                                            else {
                                                NSLog("Permission to use camera not granted")
                                            }
            })
        case .authorized:
            configureSession()
        case .denied, .restricted:
            NSLog("Permission to use camera not granted")
        }
    }
    
    
    // MARK: - Camera Control
    
    func startRunning() {
        performConfiguration { () -> Void in
            //self.observeValues()
            self.session.startRunning()
            NotificationCenter.default.post(name: Notification.Name(rawValue: CameraControllerDidStartSession), object: self)
        }
    }
    
    
    func stopRunning() {
        performConfiguration { () -> Void in
            //self.unobserveValues()
            self.session.stopRunning()
        }
    }
}


// MARK: - Delegate methods

extension CameraController: AVCaptureMetadataOutputObjectsDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    
    func captureOutput(captureOutput: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        let image = CIImage(cvPixelBuffer: pixelBuffer!)
        
        self.delegate?.cameraController(self, didOutputImage: image)
    }
}



// MARK: - Private

private extension CameraController {
    
    func performConfiguration(_ block: @escaping (() -> Void)) {
        sessionQueue.async { () -> Void in
            block()
        }
    }
    
    
    func configureSession() {
        configureDeviceInputs()
        configureStillImageCameraOutput()
        //configureFaceDetection()
        
        if previewType == .manual {
            configureVideoOutput()
            configureAudioOutput()
        }
    }
    
    
    func configureDeviceInputs() {
        
        performConfiguration { () -> Void in
            self.backCameraDevice = AVCaptureDevice.default(AVCaptureDevice.DeviceType.builtInWideAngleCamera, for: AVMediaType.video, position: .back)
            self.frontCameraDevice = AVCaptureDevice.default(AVCaptureDevice.DeviceType.builtInWideAngleCamera, for: AVMediaType.video, position: .front)
            self.micDevice = AVCaptureDevice.default(for: AVMediaType.audio) 
            
            // set the back camera as the initial device
            
            self.currentCameraDevice = self.backCameraDevice
            var possibleCameraInput: AnyObject?
            do {
                try possibleCameraInput = AVCaptureDeviceInput(device: self.currentCameraDevice!)
            }
            catch {
                NSLog("could not initiate camera input")
                return
            }
            
            if let backCameraInput = possibleCameraInput as? AVCaptureDeviceInput {
                if self.session.canAddInput(backCameraInput) {
                    self.session.addInput(backCameraInput)
                }
            }
            
            var micDeviceInput : AnyObject?
            do { 
                try micDeviceInput = AVCaptureDeviceInput(device: self.micDevice!)
                }
            catch {
                NSLog("could not initiate microphone input")
                return
                }
            if self.session.canAddInput(micDeviceInput as! AVCaptureInput!) {
                self.session.addInput(micDeviceInput as! AVCaptureInput!)
                }
        }
    }
    
    
    func configureStillImageCameraOutput() {
        performConfiguration { () -> Void in
            self.stillCameraOutput = AVCapturePhotoOutput()
            
            if self.session.canAddOutput(self.stillCameraOutput) {
                self.session.addOutput(self.stillCameraOutput)
            }
        }
    }
    
    
    func configureVideoOutput() {
        performConfiguration { () -> Void in
            var videoDataOutput : AVCaptureVideoDataOutput? = nil
            if (self.backCameraDevice != nil){
                videoDataOutput = AVCaptureVideoDataOutput()
                videoDataOutput?.setSampleBufferDelegate(self, queue: self.sessionQueue)
                }
            if (videoDataOutput != nil){
                if self.session.canAddOutput(videoDataOutput!) {
                    self.session.addOutput(videoDataOutput!)
                    }
                else {NSLog("Cannot add video data output")}
                }
            }
        }
    
    func configureAudioOutput(){
        performConfiguration { () -> Void in
            var audioDataOutput : AVCaptureAudioDataOutput? = nil
            if (self.micDevice != nil) {
                audioDataOutput = AVCaptureAudioDataOutput()
                audioDataOutput?.setSampleBufferDelegate(self, queue: self.sessionQueue)
                }
            if (audioDataOutput != nil) {
                if (self.session.canAddOutput(audioDataOutput!)) {
                    self.session.addOutput(audioDataOutput!)
                    }
                else{NSLog("Cannot add audio data output")}        
                }
            }
        }
    
    
    
}


