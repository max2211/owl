import UIKit
import Foundation
import Photos

final class PhotosViewController: UICollectionViewController {
	
	// MARK: - Properties
	fileprivate let reuseIdentifier = "360Cell"
	fileprivate let sectionInsets = UIEdgeInsets(top: 0.0, left: 0.0, bottom: 0.0, right: 0.0)
	var gvrImageView:GVRPanoramaView?
	var gvrImageDisplayMode = GVRWidgetDisplayMode.embedded
	
	var selectedPhotoIndexPath: IndexPath? {
		didSet {
			var indexPaths = [IndexPath]()
			if let selectedPhotoIndexPath = selectedPhotoIndexPath {
				indexPaths.append(selectedPhotoIndexPath)
				}
			if let oldValue = oldValue {
				indexPaths.append(oldValue)
				}
			
			collectionView?.performBatchUpdates({
				self.collectionView?.reloadItems(at: indexPaths)
			}) { completed in
				if let selectedPhotoIndexPath = self.selectedPhotoIndexPath {
					self.collectionView?.scrollToItem(
						at: selectedPhotoIndexPath,
						at: .centeredVertically,
						animated: true)
					}
				}
			}
		}
	
	var photoAlbum : PhotoAlbum!
	var photoAlbumContents : PHFetchResult<PHAsset>!
	var numAssets : Int!
	var images = [UIImage]()
	var fullResImages = [UIImage?]()
	let imageManager = PHImageManager.default()
	let requestOptions = PHImageRequestOptions()
	
	override func viewDidLoad() {
		super.viewDidLoad()
		// Do any additional setup after loading the view, typically from a nib.
		photoAlbum = PhotoAlbum()
		
		gvrImageView = GVRPanoramaView(frame: CGRect(x: 0, y: 0, width: view.frame.width, height: view.frame.width))
		gvrImageView?.enableCardboardButton = true
		gvrImageView?.enableFullscreenButton = true
		gvrImageView?.enableInfoButton = false
		
		let fetchOptions = PHFetchOptions()
		fetchOptions.sortDescriptors = [ NSSortDescriptor(key:"creationDate", ascending: true) ]
		photoAlbumContents = PHAsset.fetchAssets(in: photoAlbum.assetCollection, options: fetchOptions)
		numAssets = photoAlbumContents.count
		
		requestOptions.isSynchronous = true
		for index in 0..<numAssets {
			imageManager.requestImage(for: photoAlbumContents.object(at: index) as PHAsset, 
									  targetSize: CGSize(width: view.bounds.width, height: view.bounds.width/2), 
									  contentMode: PHImageContentMode.aspectFill, 
									  options: requestOptions) { (image, _) in
				
				if let image = image {
					self.images.append(image)
					self.fullResImages.append(nil)
					}
				}
			}
		}
	}

// MARK: - UICollectionViewDataSource
extension PhotosViewController {
	override func numberOfSections(in collectionView: UICollectionView) -> Int {
		return 1
		}
	
	override func collectionView(_ collectionView: UICollectionView,
								 numberOfItemsInSection section: Int) -> Int {
		return numAssets
		}
	
	override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier,
													  for: indexPath) as! PhotoCell
						
		let photo = images[indexPath.item]
		cell.backgroundColor = UIColor.white
		
		if indexPath == selectedPhotoIndexPath {
			if fullResImages[indexPath.item] == nil {
				imageManager.requestImage(for: photoAlbumContents.object(at: indexPath.item) as PHAsset, 
										  targetSize: PHImageManagerMaximumSize, 
										  contentMode: PHImageContentMode.aspectFill, 
										  options: requestOptions) { (image, _) in
											if let image = image {self.fullResImages[indexPath.item] = image}
											}
				}
			self.gvrImageView!.load(fullResImages[indexPath.item])
			cell.imageView.addSubview(self.gvrImageView!)
			cell.contentView.isUserInteractionEnabled = false
			}
		else {
			if selectedPhotoIndexPath == nil { self.gvrImageView!.load(nil) }
			cell.imageView.image = photo
			}
		return cell
		}
	}


extension PhotosViewController : UICollectionViewDelegateFlowLayout {
	// size of the cell
	func collectionView(_ collectionView: UICollectionView,
						layout collectionViewLayout: UICollectionViewLayout,
						sizeForItemAt indexPath: IndexPath) -> CGSize {
		if indexPath == selectedPhotoIndexPath {
			return CGSize(width: view.frame.width, height: view.frame.width)
			}
		return CGSize(width: view.frame.width, height: view.frame.width/2)
		}
	
	// leading & trailing margins
	func collectionView(_ collectionView: UICollectionView,
						layout collectionViewLayout: UICollectionViewLayout,
						insetForSectionAt section: Int) -> UIEdgeInsets {
		return sectionInsets
		}
	
	// spacing between rows
	func collectionView(_ collectionView: UICollectionView, 
						layout collectionViewLayout: UICollectionViewLayout, 
						minimumLineSpacingForSectionAt section: Int) -> CGFloat {
		return 0 
		}
	}

// MARK: - UICollectionViewDelegate
extension PhotosViewController {
	override func collectionView(_ collectionView: UICollectionView,
								 shouldSelectItemAt indexPath: IndexPath) -> Bool {
		if selectedPhotoIndexPath != indexPath { selectedPhotoIndexPath = indexPath }
		else if gvrImageDisplayMode == GVRWidgetDisplayMode.embedded { 
			gvrImageView?.displayMode = GVRWidgetDisplayMode.fullscreen
			}
		return false
		}
	}


// MARK: GVR Delegates
extension PhotosViewController: GVRWidgetViewDelegate {
	// GVRView loaded some content
	func widgetView(_ widgetView: GVRWidgetView!, didLoadContent content: Any!) {
		}
	
	// GVRView could not load requested content
	func widgetView(_ widgetView: GVRWidgetView!, didFailToLoadContent content: Any!, 
					withErrorMessage errorMessage: String!)  {
		print(errorMessage)
		}
	
	// GVRView changed mode
	func widgetView(_ widgetView: GVRWidgetView!, didChange displayMode: GVRWidgetDisplayMode) {
		gvrImageDisplayMode = displayMode
		//currentView = widgetView
		//if currentView == imageVRView && currentDisplayMode != GVRWidgetDisplayMode.embedded { view.isHidden = true } 
		//else { view.isHidden = false }
		}
	
	func widgetViewDidTap(_ widgetView: GVRWidgetView!) {
		}
}
