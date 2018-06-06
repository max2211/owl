//
//  PhotoCaptureDelegate.swift
//  PictureFilter
//
//  Created by Matthew Mayers on 10/18/17.
//  Copyright © 2017 Matthew Mayers. All rights reserved.
//

import AVFoundation
import Photos

class PhotoCaptureProcessor: NSObject {
	private(set) var requestedPhotoSettings: AVCapturePhotoSettings
	private let willCapturePhotoAnimation: () -> Void
	private let completionHandler: (PhotoCaptureProcessor) -> Void
	
	private var deviceColorSpace : AVCaptureColorSpace
	private var photoSampleBuffer: CMSampleBuffer?
	let photoAlbum = PhotoAlbum()
	
	init(with requestedPhotoSettings: AVCapturePhotoSettings,
		 deviceColorSpace : AVCaptureColorSpace,
		 willCapturePhotoAnimation: @escaping () -> Void,
		 completionHandler: @escaping (PhotoCaptureProcessor) -> Void) {
		self.requestedPhotoSettings = requestedPhotoSettings
		self.deviceColorSpace = deviceColorSpace
		self.willCapturePhotoAnimation = willCapturePhotoAnimation
		self.completionHandler = completionHandler
		}
	
	private func didFinish() {
		completionHandler(self)
		}
	
	func checkPhotoLibraryAuthorization(_ completionHandler: @escaping ((_ authorized: Bool) -> Void)) {
		switch PHPhotoLibrary.authorizationStatus() {
		case .authorized:
			// The user has previously granted access to the photo library.
			completionHandler(true)
			
		case .notDetermined:
			// The user has not yet been presented with the option to grant photo library access so request access.
			PHPhotoLibrary.requestAuthorization({ status in
				completionHandler((status == .authorized))
				})
			
		case .denied:
			// The user has previously denied access.
			completionHandler(false)
			
		case .restricted:
			// The user doesn't have the authority to request access e.g. parental restriction.
			completionHandler(false)
			}
		}
	
	func applyFilterAndSaveToPhotoLibrary(_ sampleBuffer: CMSampleBuffer,
										  completionHandler: ((_ success: Bool, _ error: Error?) -> Void)?) {
		self.checkPhotoLibraryAuthorization({ authorized in
			guard authorized else {
				print("Permission to access photo library denied.")
				completionHandler?(false, nil)
				return
				}
			guard let cvPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
				print("sampleBuffer does not contain a CVPixelBuffer.")
				completionHandler?(false, nil)
				return
				}
			
			let image = CIImage(cvPixelBuffer: cvPixelBuffer)
			let sourceExtent:CGRect = image.extent
			
			if let filter = CIFilter(name: "UnwrapFilter") {
				filter.setValue(image, forKey: "inputImage")
				filter.setValue(CIVector(x:sourceExtent.size.width/2, y:sourceExtent.size.height/2), forKey: "inputCenter")
				filter.setValue(CGFloat(sourceExtent.size.width/4.0), forKey: "inputRadius")
				filter.setValue(CGFloat(sourceExtent.size.width/2.0), forKey: "outputSize")
				if let filteredImage = filter.outputImage {
					// Get a JPEG data representation of the filter output.
					let colorSpaceMap: [AVCaptureColorSpace: CFString] = [
						.sRGB   : CGColorSpace.sRGB,
						.P3_D65 : CGColorSpace.displayP3,
						]
					let colorSpace = CGColorSpace(name: colorSpaceMap[self.deviceColorSpace]!)!
					guard let jpegData = CIContext().jpegRepresentation(of: filteredImage, colorSpace: colorSpace) else {
						print("Unable to create filtered JPEG.")
						completionHandler?(false, nil)
						return
						}
					
					// Write it to the Photos library.
					self.photoAlbum.save(image: UIImage(data: jpegData)!)
					/*
					PHPhotoLibrary.shared().performChanges( {
						let creationRequest = PHAssetCreationRequest.forAsset()
						creationRequest.addResource(with: PHAssetResourceType.photo, data: jpegData, options: nil)
						}, completionHandler: { success, error in
						DispatchQueue.main.async { completionHandler?(success, error) }
						})*/
					}
				}
			})
		}
	}

extension PhotoCaptureProcessor: AVCapturePhotoCaptureDelegate {
	func photoOutput(_ output: AVCapturePhotoOutput, 
					 willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
		willCapturePhotoAnimation()
		}
	
	func photoOutput(_ captureOutput: AVCapturePhotoOutput,
					 didFinishProcessingPhoto photoSampleBuffer: CMSampleBuffer?,
					 previewPhoto previewPhotoSampleBuffer: CMSampleBuffer?,
					 resolvedSettings: AVCaptureResolvedPhotoSettings,
					 bracketSettings: AVCaptureBracketedStillImageSettings?,
					 error: Error?) {
		guard error == nil, let photoSampleBuffer = photoSampleBuffer else {
			print("Error capturing photo: \(String(describing: error))")
			return
			}
		
		self.photoSampleBuffer = photoSampleBuffer
		}
	
	func photoOutput(_ captureOutput: AVCapturePhotoOutput,
					 didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
					 error: Error?) {
		guard error == nil else {
			print("Error in capture process: \(String(describing: error))")
			return
			}
	
		if let photoSampleBuffer = self.photoSampleBuffer {
			applyFilterAndSaveToPhotoLibrary(photoSampleBuffer,
											 completionHandler: { success, error in
												if success { print("Added 360 photo to library.") } 
												else { print("Error adding 360 photo to library: \(String(describing: error))") } })
			}
		}
	}
