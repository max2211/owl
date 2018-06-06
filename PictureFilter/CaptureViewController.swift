//
//  GLViewController.swift
//  Camera
//
//  Created by Matteo Caldari on 28/01/15.
//  Copyright (c) 2015 Matteo Caldari. All rights reserved.
//
//	https://github.com/BradLarson/GPUImage/issues/2022
//	I have talked with the apple Engineers in the WWDC Labs and the only thing that we could figure out is if you go to Product -> Scheme -> Edit Scheme ...
//	And for the Run Debug configuration (on left side) choose "Options" (on right side) and configure "GPU Frame Capture" as Disabled.



import UIKit
import GLKit
import CoreImage
import OpenGLES
import AVFoundation
import Photos

class CaptureViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    // MARK: Properties
	var isCalibrated:Bool = false
	var isInPhotoMode:Bool = true
	var shouldSavePhoto:Bool = false
	
	var calibrateFilter:CIFilter?
	var unwrapFilter:CIFilter?
	var calibrateRect:CGRect!
	var viewBounds:CGRect!
    var unwrapRect:CGRect!
	var movieBounds:CGRect!
    var drawImage:CIImage!
    
	var photoSettings : AVCapturePhotoSettings?
	private var inProgressPhotoCaptureDelegates = [Int64: PhotoCaptureProcessor]()
	
    var assetWriter : AVAssetWriter?
    var assetWriterAudioInput : AVAssetWriterInput?
    var assetWriterVideoInput : AVAssetWriterInput?
    var assetWriterInputPixelBufferAdaptor : AVAssetWriterInputPixelBufferAdaptor?
    var currentAudioSampleBufferFormatDescription : CMFormatDescription?
    var currentVideoDimensions : CMVideoDimensions?
    
    var backgroundRecordingID : UIBackgroundTaskIdentifier?
    var videoWritingStarted : Bool?
    var labelUpdateTimer : Timer?
    var videoWritingStartTime : CMTime?
    var currentVideoTime : CMTime?
    let kFPSLabelUpdateInterval : TimeInterval = 0.25
    
    
    // MARK: Private properties
    
    fileprivate var currentCameraDevice:AVCaptureDevice?
    fileprivate var session:AVCaptureSession!
	fileprivate var sessionQueue:DispatchQueue = DispatchQueue(label: "capture session queue", attributes: [])
    fileprivate var backCameraDevice:AVCaptureDevice?
    fileprivate var micDevice:AVCaptureDevice?
    fileprivate var frontCameraDevice:AVCaptureDevice?
    fileprivate var photoOutput:AVCapturePhotoOutput!
    
    fileprivate var colorSpace:CGColorSpace?
	fileprivate var glContext:EAGLContext?
	fileprivate var ciContext:CIContext?
    fileprivate var glView:GLKView {
        get {
            return view as! GLKView
			}
		}
    
    // Mark: Outlets
    
    @IBOutlet weak var recordButton: UIButton!
    @IBOutlet weak var durationLabel: UILabel!
	@IBOutlet weak var calibrateDirections: UILabel!
	@IBOutlet weak var calibrateButton: UIButton!
	@IBOutlet weak var photoVideoSelector: UISegmentedControl!
	@IBOutlet weak var unwindButton: UIButton!
	
    // MARK: Initialization
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        CustomFiltersVendor.registerFilters()
		
        glContext = EAGLContext(api: .openGLES3)
		glView.context = glContext!
		//glView.drawableDepthFormat = .Format24
        //glView.transform = CGAffineTransform(rotationAngle: CGFloat(M_PI_2))
        if let window = glView.window {
            glView.frame = window.bounds
            }
		viewBounds = glView.bounds
        
        ciContext = CIContext(eaglContext: glContext!)
        colorSpace = CGColorSpaceCreateDeviceRGB()
		
        configureDrawRects()
		recordButton.isHidden = true
        
        initializeSession()
        }
    
    
    override func viewDidAppear(_ animated: Bool) {
        self.startRunning()
        }
    
    
    func performConfiguration(_ block: @escaping (() -> Void)) {
		// allow jobs to be asynchronously queued
        sessionQueue.async { () -> Void in
            block()
            }
        }
    
    func initializeSession() {
        session = AVCaptureSession()
        session.sessionPreset =  AVCaptureSession.Preset.high
        
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
    
    func configureSession() {
        configureDeviceInputs()
		
        configurePhotoOutput()
        configureVideoOutput()
        configureAudioOutput()
		}
    
    
    func configureDeviceInputs() {
        performConfiguration { () -> Void in
			// identify available devices
            self.backCameraDevice = AVCaptureDevice.default(AVCaptureDevice.DeviceType.builtInWideAngleCamera, for: AVMediaType.video, position: .back)
            self.frontCameraDevice = AVCaptureDevice.default(AVCaptureDevice.DeviceType.builtInWideAngleCamera, for: AVMediaType.video, position: .front)
            self.micDevice = AVCaptureDevice.default(for: AVMediaType.audio) 
            
            // add back camera input
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
            
			// add mic input
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
                //print("added microphone input")
                }
            }
        }
    
    
    func configurePhotoOutput() {
        performConfiguration { () -> Void in
            self.photoOutput = AVCapturePhotoOutput()
            
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
                }
			
			// generate template photo settings
			let pixelFormatType = NSNumber(value: kCVPixelFormatType_32BGRA)
			guard self.photoOutput.availablePhotoPixelFormatTypes.contains(OSType(truncating: pixelFormatType)) 
			else { 
				print("Photo settings not available")
				return }
			self.photoSettings = AVCapturePhotoSettings(format: [kCVPixelBufferPixelFormatTypeKey as String : pixelFormatType])
			
			/* generate RAW settings
			let rawFormatType = kCVPixelFormatType_14Bayer_RGGB
			guard self.photoOutput.availableRawPhotoPixelFormatTypes.contains(OSType(truncating: NSNumber(value: rawFormatType))) 
			else { 
				print("RAW settings not available")
				return 
				}
			self.photoSettings = AVCapturePhotoSettings(rawPixelFormatType: rawFormatType)*/
			}
        }
    
    
    func configureVideoOutput() {
		// allow view controller to collect video frames
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
		// allow view controller to collect audio output
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
    
	// MARK: Filtering Elements
    
    func configureDrawRects(){
        let xmax = glView.frame.size.width
        let ymax = glView.frame.size.height
        //print("\(xmax) \(ymax)")
        //print(glView.frame)
        print(glView.bounds)
        
        unwrapRect = CGRect(x: xmax - ymax/2, y: 0, width: ymax, height: 2*ymax)
        //print(unwrapRect)
        }
    
    func computeDrawRect(sourceExtent:CGRect) -> CGRect {
        let sourceAspect:CGFloat = sourceExtent.size.height / sourceExtent.size.width;
        let previewAspect:CGFloat = viewBounds.size.width  / viewBounds.size.height;
        //print("\(sourceAspect) \(previewAspect)")
        
        var drawRect:CGRect = viewBounds
        drawRect.size.width *= 2.0
        drawRect.size.height *= 2.0
        if (sourceAspect > previewAspect) {
            // use full height of the video image, and center crop the width
            drawRect.size.height = drawRect.size.width / sourceAspect;
            drawRect.origin.y += (viewBounds.size.height*2.0 - drawRect.size.height) / 2.0;
            }
        else {
            // use full width of the video image, and center crop the height
            drawRect.size.width = drawRect.size.height * sourceAspect;
            drawRect.origin.x += (viewBounds.size.width*2.0 - drawRect.size.width) / 2.0;
            }
        
        return drawRect;
        }
    
    
    // MARK: AssetWriter
    
    func startLabelUpdateTimer() {
        labelUpdateTimer = Timer.scheduledTimer(timeInterval: kFPSLabelUpdateInterval, target: self, selector: #selector(updateLabel), userInfo: nil, repeats: true) 
        }
    
    func stopLabelUpdateTimer() {
        labelUpdateTimer?.invalidate()
        labelUpdateTimer = nil
        }
    
    @objc func updateLabel(timer:Timer) {
        //durationLabel.text = NSString.string("%.1f fps", _frameRateCalculator.frameRate)
        if (assetWriter != nil) {
            let diff:CMTime = CMTimeSubtract(currentVideoTime!, videoWritingStartTime!)
            let seconds : UInt32 = UInt32(CMTimeGetSeconds(diff))
            durationLabel.text = "\(seconds/60):\(seconds%60)"
			print("\(seconds/60):\(seconds%60)")
            }
        }
    
    func startWriting() {
        recordButton.setImage(#imageLiteral(resourceName: "button_video_pressed"), for: UIControlState.normal)
        //recordButton.setTitle("Stop", for: UIControlState.normal)
        durationLabel.text = "00:00"
        
        sessionQueue.async(execute: {
            // remove the temp file, if any
            let tmpdir = NSTemporaryDirectory()
            let outputPath = "\(tmpdir)recording.mov"
            let outputURL = NSURL(fileURLWithPath:outputPath as String)
            let filemgr = FileManager.default
            if filemgr.fileExists(atPath: outputPath) {
                do {
                    try filemgr.removeItem(at: outputURL as URL)
                    }
                catch {
                    NSLog("cannot remove temp video file")
                    }
                }
                
			// create asset writer with specified dimensions
            var newAssetWriter : AVAssetWriter?
            do {
                try newAssetWriter = AVAssetWriter.init(url: outputURL as URL, fileType: AVFileType.mov)
				}
            catch {
                NSLog("Cannot create asset writer, error: \(error)")
                return
				}
			
			//create video input
            let videoCompressionSettings = [    AVVideoCodecKey : AVVideoCodecH264,
                                                AVVideoWidthKey : 480,
                                                AVVideoHeightKey : 240] as [String : Any]
            self.assetWriterVideoInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoCompressionSettings)
            self.assetWriterVideoInput?.expectsMediaDataInRealTime = true
                
            // create a pixel buffer adaptor for the asset writer; we need to obtain pixel buffers for rendering later from its pixel buffer pool
            self.assetWriterInputPixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor.init(assetWriterInput: self.assetWriterVideoInput!, sourcePixelBufferAttributes: 
                [   kCVPixelBufferPixelFormatTypeKey as String : kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String : 480,
                    kCVPixelBufferHeightKey as String : 240,
                    kCVPixelFormatOpenGLESCompatibility as String : kCFBooleanTrue]) 
			self.movieBounds = CGRect(x: 0, y: 0, width: 480, height: 240)
                
                
            /* device orientation information
            UIDeviceOrientation orientation = ((FHAppDelegate *)[UIApplication sharedApplication].delegate).realDeviceOrientation;
            //UIDeviceOrientation orientation = [UIDevice currentDevice].orientation;
                 
            // give correct orientation information to the video
            if (_videoDevice.position == AVCaptureDevicePositionFront)
            _assetWriterVideoInput.transform = FCGetTransformForDeviceOrientation(orientation, YES);
            else
            _assetWriterVideoInput.transform = FCGetTransformForDeviceOrientation(orientation, NO);
            */
			
			// add input to asset writer
            let canAddInput = newAssetWriter?.canAdd(self.assetWriterVideoInput!)
            if (canAddInput == false){
                NSLog("Cannot add asset writer video input")
                self.assetWriterAudioInput = nil
                self.assetWriterVideoInput = nil
                return
                }
            newAssetWriter?.add(self.assetWriterVideoInput!)
			
			// set up and add audio input
            if (self.micDevice != nil) {
                //var layoutSize : UnsafeMutablePointer<Int>? = nil 
                //print(self.currentAudioSampleBufferFormatDescription)
                //let channelLayout : UnsafePointer<AudioChannelLayout>? = CMAudioFormatDescriptionGetChannelLayout(self.currentAudioSampleBufferFormatDescription!, layoutSize)
                //var channelLayout : UnsafePointer<AudioChannelLayout>? = AudioChannelLayout.init(mChannelLayoutTag: <#T##AudioChannelLayoutTag#>, mChannelBitmap: <#T##AudioChannelBitmap#>, mNumberChannelDescriptions: <#T##UInt32#>, mChannelDescriptions: <#T##(AudioChannelDescription)#>)
                //channelLayout?.pointee.mChannelLayoutTag = kAudioChannelLayoutTag_Mono
                //print(channelLayout)
                let basicDescription : UnsafePointer<AudioStreamBasicDescription>? = CMAudioFormatDescriptionGetStreamBasicDescription(self.currentAudioSampleBufferFormatDescription!)
                //print(basicDescription?.pointee)
                    
                //let channelLayoutData : NSData = NSData(bytes: channelLayout, length: layoutSize!.pointee)
                    
                // record the audio at AAC format, bitrate 64000, sample rate and channel number using the basic description from the audio samples
                let audioCompressionSettings = [AVFormatIDKey : kAudioFormatMPEG4AAC,
												AVNumberOfChannelsKey : basicDescription?.pointee.mChannelsPerFrame ?? 0,
												AVSampleRateKey : basicDescription?.pointee.mSampleRate ?? 0,
                                                AVEncoderBitRateKey : 64000//,
                                                //AVChannelLayoutKey : channelLayoutData
                                                ] as [String : Any]
                    
                if (newAssetWriter?.canApply(outputSettings: audioCompressionSettings, forMediaType:AVMediaType.audio))! {
                    self.assetWriterAudioInput = AVAssetWriterInput(mediaType:AVMediaType.audio, outputSettings:audioCompressionSettings)
                    self.assetWriterAudioInput?.expectsMediaDataInRealTime = true
                        
                    if (newAssetWriter?.canAdd(self.assetWriterAudioInput!))!{
                        newAssetWriter?.add(self.assetWriterAudioInput!)
                        }
                    else { NSLog("Couldn't add asset writer audio input") }
                    }
				else {NSLog("Couldn't apply audio output settings.") }
                }
                
            // Make sure we have time to finish saving the movie if the app is backgrounded during recording
            // cf. the RosyWriter sample app from WWDC 2011
            if (UIDevice.current.isMultitaskingSupported){
                self.backgroundRecordingID = UIApplication.shared.beginBackgroundTask(expirationHandler: {})
                self.videoWritingStarted = false
                self.assetWriter = newAssetWriter
                }
            })
        }
            
            
    func abortWriting() {
        if (assetWriter == nil) { return }
                
        assetWriter?.cancelWriting()
        assetWriterAudioInput = nil
        assetWriterVideoInput = nil
                
        // remove the temp file
        let fileURL : NSURL = assetWriter!.outputURL as NSURL
        let filemgr = FileManager.default
        do {
            try filemgr.removeItem(at: fileURL as URL)
            }
        catch {
            NSLog("cannot remove temp video file")
            }
		assetWriter = nil
                
        /*void (^resetUI)(void) = ^(void) {
        recordButton.setTitle("Record", for: UIControlState.normal)
        recordButton.enabled = YES;
        
        // end the background task if it's done there
        // cf. The RosyWriter sample app from WWDC 2011
        if (UIDevice.currentDevice.isMultitaskingSupported) {
        UIApplication.sharedApplication.endBackgroundTask(backgroundRecordingID)
        }
        }*/
                
        DispatchQueue.main.async(execute: {
            self.recordButton.setTitle("Record", for: UIControlState.normal)
            self.recordButton.isEnabled = true
            
            self.startLabelUpdateTimer()
            
            // end the background task if it's done there
            // cf. The RosyWriter sample app from WWDC 2011
            if (UIDevice.current.isMultitaskingSupported == true) {
                UIApplication.shared.endBackgroundTask(self.backgroundRecordingID!) 
                }
            })    
        }
            
    func stopWriting() {
        if (assetWriter == nil) {return}
        
        let writer : AVAssetWriter = assetWriter!
                
        assetWriterAudioInput = nil
        assetWriterVideoInput = nil
        assetWriterInputPixelBufferAdaptor = nil
        assetWriter = nil
                
        self.stopLabelUpdateTimer()
        durationLabel.text = "Saving..."
        recordButton.isEnabled = false;
        recordButton.setImage(#imageLiteral(resourceName: "button_video_normal"), for: UIControlState.normal)
                
        /*
        void (^resetUI)(void) = ^(void) {
        recordButton.setTitle("Record")
        recordButton.enabled = true
                 
        self.startLabelUpdateTimer()
                 
        // end the background task if it's done there
        // cf. The RosyWriter sample app from WWDC 2011
        if (UIDevice.currentDevice.isMultitaskingSupported) {
        UIApplication.sharedApplication.endBackgroundTask(backgroundRecordingID) 
        }
        }*/
                
        sessionQueue.async(execute: {
            let fileURL : NSURL = writer.outputURL as NSURL
                    
            writer.finishWriting(completionHandler: {
                if (writer.status == AVAssetWriterStatus.failed ){
                    DispatchQueue.main.async(execute: {                 // RESET UI
                        //self.recordButton.setTitle("Record", for: UIControlState.normal)
                        self.recordButton.isEnabled = true
                                
                        self.startLabelUpdateTimer()
                                
                        // end the background task if it's done there
                        // cf. The RosyWriter sample app from WWDC 2011
                        if (UIDevice.current.isMultitaskingSupported == true) {
                            UIApplication.shared.endBackgroundTask(self.backgroundRecordingID!) 
                            }
                        })
                    NSLog("Cannot complete writing the video. The output could be corrupt.")
                    }
                else if (writer.status == AVAssetWriterStatus.completed){
                    var placeHolder: PHObjectPlaceholder?
                            
                    PHPhotoLibrary.shared().performChanges({
                        let changeRequest = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL as URL)
                        if let changeRequest = changeRequest {
                            // maybe set date, location & favouriteness here?
                            placeHolder = changeRequest.placeholderForCreatedAsset
                            } 
                                
                        }) { success, error in
                                //placeHolder?.localIdentifier    // should identify asset from now on?
                                if ((error) != nil) {NSLog("Error saving the video to the photo library. %@")}
                                
                                let filemgr = FileManager.default
                                do {
                                    try filemgr.removeItem(at: fileURL as URL)
                                }
                                catch {
                                    NSLog("cannot remove temp video file")
                                }
                            }
                        }
                        
                DispatchQueue.main.async(execute: {
                    //self.recordButton.setTitle("Record", for: UIControlState.normal)
                    self.recordButton.isEnabled = true
					self.durationLabel.text = ""
                            
                    self.startLabelUpdateTimer()
                            
                    // end the background task if it's done there
                    // cf. The RosyWriter sample app from WWDC 2011
                    if (UIDevice.current.isMultitaskingSupported == true) {
                        UIApplication.shared.endBackgroundTask(self.backgroundRecordingID!) 
                        }
                    })
                })
            })
        }

	func takePhoto(){
		//let videoPreviewLayerOrientation = previewView.videoPreviewLayer.connection?.videoOrientation
	
		sessionQueue.async {
			let freshPhotoSettings = AVCapturePhotoSettings(from: self.photoSettings!)
	
			// Use a separate object for the photo capture delegate to isolate each capture life cycle.
			let photoCaptureProcessor = PhotoCaptureProcessor(with: self.photoSettings!, 
															  deviceColorSpace: (self.currentCameraDevice?.activeColorSpace)!,
															  willCapturePhotoAnimation: {
				DispatchQueue.main.async {
					self.glView.alpha = 0.0
					UIView.animate(withDuration: 0.25) {
						self.glView.alpha = 1.0
						}
					}
				}, 
															  completionHandler: { photoCaptureProcessor in
						// When the capture is complete, remove a reference to the photo capture delegate so it can be deallocated.
						self.sessionQueue.async {
							self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = nil
							}
						}
					)
			/*
			The Photo Output keeps a weak reference to the photo capture delegate so
			we store it in an array to maintain a strong reference to this object
			until the capture is completed.
			*/
			self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = photoCaptureProcessor
			self.photoOutput.capturePhoto(with: freshPhotoSettings, delegate: photoCaptureProcessor)
			}
		}
	
    // MARK: Actions
	private enum CaptureMode: Int {
		case photo = 0
		case movie = 1
		}
	
    @IBAction func recordButtonPressed(_ sender: Any) {
		if photoVideoSelector.selectedSegmentIndex == CaptureMode.photo.rawValue { takePhoto() }
		else {
			if ((assetWriter) != nil){ self.stopWriting() }
			else { self.startWriting() }
			}
        }
    
	@IBAction func calibrateButtonPressed(_ sender: Any) {
		isCalibrated = true
		calibrateButton.isHidden = true
		calibrateDirections.isHidden = true
		recordButton.isHidden = false
		durationLabel.text = "duration"
		}
	
	@IBAction func unwindButtonPressed(_ sender: Any) {
		performSegue(withIdentifier: "unwindSeguetoBrowseViewController", sender: self)
		}
	
	
	@IBAction func photoVideoStateChanged(_ sender: Any) {
		// change session preset?
		}
	
	
	// MARK: Delegate
	func captureOutput(_ captureOutput: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let formatDesc : CMFormatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)!
        let mediaType : CMMediaType = CMFormatDescriptionGetMediaType(formatDesc)
        
        // write the audio data if it's from the audio connection
        if (mediaType == kCMMediaType_Audio){
			// store format description for initializing asset writer
            currentAudioSampleBufferFormatDescription = formatDesc
            
            // we need to retain the sample buffer to keep it alive across the different queues (threads)
            if (assetWriter != nil &&
                assetWriterAudioInput?.isReadyForMoreMediaData == true &&
                assetWriterAudioInput?.append(sampleBuffer) == false) {
                NSLog("Cannot write audio data, recording aborted")
                abortWriting()
                }
            
            return
            }
        
        // if not from the audio capture connection, handle video writing    
        let timestamp : CMTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
		// update video dimensions information
        currentVideoDimensions = CMVideoFormatDescriptionGetDimensions(formatDesc)
        
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        let image = CIImage(cvPixelBuffer: pixelBuffer!)
        
        //let drawRect:CGRect = computeDrawRect(sourceExtent: image.extent)
        //ciContext?.draw(image, in: drawRect, from: image.extent)
        
        glView.bindDrawable();
        
        if glContext != EAGLContext.current() {
            EAGLContext.setCurrent(glContext)
            }
        
        // clear eagl view to black
        glClearColor(0.0, 0.0, 0.0, 1.0)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        
        // set the blend mode to "source over" so that CI will use that
        glEnable(GLenum(GL_BLEND))
        glBlendFunc(GLenum(GL_ONE), GLenum(GL_ONE_MINUS_SRC_ALPHA))
        
        let sourceExtent:CGRect = image.extent
		
		if isCalibrated == false {
			if let filter = CIFilter(name: "CIRadialGradient") {
				filter.setValue(CIVector(x:sourceExtent.size.width/2, y:sourceExtent.size.height/2), forKey: "inputCenter")
				filter.setValue(CGFloat(sourceExtent.size.height*0.5), forKey: "inputRadius0") 
				filter.setValue(CGFloat(sourceExtent.size.height*0.6), forKey: "inputRadius1")
				
				let blend = CIFilter(name: "CIBlendWithMask")!
				blend.setValue(image, forKey: "inputImage")
				blend.setValue(filter.outputImage, forKey: "inputMaskImage")
				
				if calibrateRect == nil {calibrateRect = computeDrawRect(sourceExtent: image.extent)}
				
				if let drawImage = blend.outputImage?.transformed(by: CGAffineTransform(rotationAngle: -.pi/2)) {
					ciContext?.draw(drawImage, in:calibrateRect, from: drawImage.extent)
					}
				}
			}
		else {
			if let filter = CIFilter(name: "UnwrapFilter") {
				filter.setValue(image, forKey: "inputImage")
				filter.setValue(CIVector(x:sourceExtent.size.width/2, y:sourceExtent.size.height/2), forKey: "inputCenter")
				filter.setValue(CGFloat(sourceExtent.size.width/4.0), forKey: "inputRadius")
				filter.setValue(CGFloat(sourceExtent.size.width/2.0), forKey: "outputSize")
				if let drawImage = filter.outputImage?.transformed(by: CGAffineTransform(rotationAngle: -.pi/2)) {
					ciContext?.draw(drawImage, in:unwrapRect, from: drawImage.extent)
					}
				if (assetWriter != nil) {
					// if we need to write video and haven't started yet, start writing
					if (videoWritingStarted == false){
						videoWritingStarted = true
						let success : Bool = assetWriter!.startWriting()
						if (success == false) {
							NSLog("Cannot write video data, recording aborted")
							self.startWriting()
							return
							}
						
						assetWriter!.startSession(atSourceTime: timestamp) 
						videoWritingStartTime = timestamp
						self.currentVideoTime = videoWritingStartTime
						}
						
					var renderedOutputPixelBuffer : CVPixelBuffer? = nil
						
					let err : CVReturn = CVPixelBufferPoolCreatePixelBuffer(nil, assetWriterInputPixelBufferAdaptor!.pixelBufferPool!, &renderedOutputPixelBuffer)
					if (renderedOutputPixelBuffer == nil) {
						NSLog("Cannot obtain a pixel buffer from the buffer pool. Error: \(err)")
						return
						}
					
					self.currentVideoTime = timestamp 
					if let movieImage = filter.outputImage {
						ciContext?.render(movieImage, to: renderedOutputPixelBuffer!, bounds:movieBounds, colorSpace: colorSpace)           
						
						// write the video data
						if (assetWriterVideoInput?.isReadyForMoreMediaData == true){
							assetWriterInputPixelBufferAdaptor?.append(renderedOutputPixelBuffer!, withPresentationTime: timestamp) 
							}
						}
					}
				}
			}
        glView.display()
        }
    }
    
