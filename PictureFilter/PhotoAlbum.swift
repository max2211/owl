//
//  PhotoAlbum.swift
//  PictureFilter
//
//  Created by Matthew Mayers on 10/20/17.
//  Copyright © 2017 Matthew Mayers. All rights reserved.
//

import Foundation
import Photos

class PhotoAlbum: NSObject {
	static let albumName = "Cardboard Camera"
	static let sharedInstance = PhotoAlbum()
	
	var assetCollection: PHAssetCollection!
	
	override init() {
		super.init()
		
		// album already exits so just return it
		if let assetCollection = fetchAssetCollectionForAlbum() {
			self.assetCollection = assetCollection
			return
			}
		
		if PHPhotoLibrary.authorizationStatus() != PHAuthorizationStatus.authorized {
			PHPhotoLibrary.requestAuthorization({ (status: PHAuthorizationStatus) -> Void in () })
			}
		
		if PHPhotoLibrary.authorizationStatus() == PHAuthorizationStatus.authorized {
			self.createAlbum()		// otherwise create album here
			} else {
			PHPhotoLibrary.requestAuthorization(requestAuthorizationHandler)
			}
		}
	
	func requestAuthorizationHandler(status: PHAuthorizationStatus) {
		if PHPhotoLibrary.authorizationStatus() == PHAuthorizationStatus.authorized {
			print("trying again to create the album")
			self.createAlbum()		// or here if permission was needed
			} else {
			print("should really prompt the user to let them know it's failed")
			}
		}
	
	func createAlbum() {
		PHPhotoLibrary.shared().performChanges({
			PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: PhotoAlbum.albumName)
			}) { success, error in
			if success {
				self.assetCollection = self.fetchAssetCollectionForAlbum()
				
				self.save(image: UIImage(named: "grand_canyon.jpg")!)		// save a few sample images for the user
				self.save(image: UIImage(named: "sindhu_beach.jpg")!)
				self.save(image: UIImage(named: "underwater.jpg")!)
				} else {
				print("error \(String(describing: error))")
				}
			}
		}
	
	func fetchAssetCollectionForAlbum() -> PHAssetCollection? {
		let fetchOptions = PHFetchOptions()
		fetchOptions.predicate = NSPredicate(format: "title = %@", PhotoAlbum.albumName)
		let collection = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
		
		if let _: AnyObject = collection.firstObject {
			return collection.firstObject
			}
		return nil
		}
	
	func save(image: UIImage) {
		if assetCollection == nil { return }
		
		PHPhotoLibrary.shared().performChanges({
			let assetChangeRequest = PHAssetChangeRequest.creationRequestForAsset(from: image)
			let assetPlaceHolder = assetChangeRequest.placeholderForCreatedAsset
			let albumChangeRequest = PHAssetCollectionChangeRequest(for: self.assetCollection)
			let enumeration: NSArray = [assetPlaceHolder!]
			albumChangeRequest!.addAssets(enumeration)
			}, completionHandler: { success, error in
				if (success){ print("Image saved!") }
				else{ print("error \(String(describing: error))") }
				})
		}
	}
