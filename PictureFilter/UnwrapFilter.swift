//
//  UnwrapFilter.swift
//  PictureFilter
//
//  Created by Matthew Mayers on 10/10/16.
//  Copyright © 2016 Matthew Mayers. All rights reserved.
//

import UIKit
import CoreImage

let CategoryCustomFilters = "Custom Filters"

class CustomFiltersVendor: NSObject, CIFilterConstructor {
    
    static func registerFilters() {
        CIFilter.registerName(
            "UnwrapFilter",
            constructor: CustomFiltersVendor(),
            classAttributes: [kCIAttributeFilterCategories: [CategoryCustomFilters.nsString]])
        }
    
    func filter(withName name: String) -> CIFilter? {
        switch name {
            case "UnwrapFilter":
                return UnwrapFilter()
            
            default:
                return nil
            }
        }
    }


//-------------------- unwrap input image --------------------------
class UnwrapFilter: CIFilter {
	// @objc dynamic  is needed for key-value coding:
	// https://stackoverflow.com/questions/46566076/this-class-is-not-key-value-coding-compliant-using-coreimage
	@objc dynamic var inputImage : CIImage?
	@objc dynamic var inputCenter : CIVector = CIVector(x: 150.0, y: 150.0)
	@objc dynamic var inputRadius : CGFloat = CGFloat(150.0)
	@objc dynamic var outputSize : CGFloat = CGFloat(300.0)
	
	override var attributes: [String : Any]
	{
		return [
			kCIAttributeFilterDisplayName: "Unwrap Filter",
			"inputImage": [  kCIAttributeIdentity: 0,
									kCIAttributeClass: "CIImage",
									kCIAttributeDisplayName: "Fisheye Image",
									kCIAttributeType: kCIAttributeTypeImage],
			"inputCenter": [        kCIAttributeIdentity: 0,
									kCIAttributeClass: "CIVector",
									kCIAttributeDisplayName: "Fisheye Center",
									kCIAttributeDefault: CIVector(x: 150.0, y: 150.0),
									kCIAttributeType: kCIAttributeTypePosition],
			"inputRadius": [        kCIAttributeIdentity: 0,
									kCIAttributeClass: "NSNumber",
									kCIAttributeDefault: 150,
									kCIAttributeDisplayName: "Circle Radius",
									kCIAttributeMin: 0,
									kCIAttributeType: kCIAttributeTypeScalar],
			"outputSize": [         kCIAttributeIdentity: 0,
									kCIAttributeClass: "NSNumber",
									kCIAttributeDefault: 300,
									kCIAttributeDisplayName: "Output Image Width",
									kCIAttributeMin: 1,
									kCIAttributeType: kCIAttributeTypeScalar],
		]
	}
	
	/*    override func setDefaults()
	{
	inputThreshold = 0.75
	}*/
	
	override init(){
		super.init();
		}
	
	let unwrapKernel = CIWarpKernel(source:
		"kernel vec2 unwrapFilter(vec2 center, float radius, float height) { \n" + 
			"float FOV = 3.141592654/2.0; \n" +  // FOV of the fisheye, eg: 180 degrees
			
			// Polar angles
			"float theta = 3.14159265 * (destCoord().x/height - 1.0); \n" +	// pi/2 to pi
			"float phi = destCoord().y/height; \n" +					// 0 to 1 (distance from center)
			
			
			// Calculate pixel location relative to center
			"vec2 disp; \n" + 
			"float r = radius*phi; \n" + 
			"disp.x = r * cos(theta); \n" + 
			"disp.y = r * sin(theta); \n" + 
			
			//"return sample(src, samplerTransform(src, center + pfish)); \n" + 
			"return center + disp; \n" + 
		"} \n")
	
	required init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	override var outputImage: CIImage! {
		guard let inputImage = inputImage, let kernel = unwrapKernel else {
			print("ERROR")
			return nil
		}
		
		let extent = CGRect(x: 0, y: 0, width: 2*outputSize, height: outputSize)
		let imageROI = CGRect(x: Int(inputCenter.x - inputRadius), y: Int(inputCenter.y - inputRadius), width: Int(2*inputRadius), height: Int(2*inputRadius))
		
		return kernel.apply(  extent: extent, 
							  roiCallback:
			{
				(index, rect) in
				return imageROI
		},
							  image: inputImage,
							  arguments: [inputCenter, inputRadius, outputSize])
	}
}


/*let unwrapKernel = CIWarpKernel(source:
	"kernel vec2 unwrapFilter(vec2 center, float radius, float height) { \n" + 
		"float FOV = 3.141592654/2.0; \n" +  // FOV of the fisheye, eg: 180 degrees
		
		// Polar angles
		"float theta = 3.14159265 * (destCoord().x/height - 1.0); \n" +	// pi/2 to pi
		"float phi = destCoord().y/height; \n" +					// 0 to 1 (distance from center)
		
		
		// Calculate pixel location relative to center
		"vec2 disp; \n" + 
		"float r = radius*phi; \n" + 
		"disp.x = r * cos(theta); \n" + 
		"disp.y = r * sin(theta); \n" + 
		
		//"return sample(src, samplerTransform(src, center + pfish)); \n" + 
		"return center + disp; \n" + 
	"} \n")*/


// MARK: Extensions
extension String {
    var nsString: NSString {
        return NSString(string: self)
        }
    }

extension CIVector {
    func multiply(value: CGFloat) -> CIVector {
        let n = self.count
        var targetArray = [CGFloat]()
        
        for i in 0 ..< n {
            targetArray.append(self.value(at: i) * value)
            }
        
        return CIVector(values: targetArray, count: n)
        }
    }
