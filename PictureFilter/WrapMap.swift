//
//  WrapMap.swift
//  PictureFilter
//
//  Created by Matthew Mayers on 10/7/16.
//  Copyright © 2016 Matthew Mayers. All rights reserved.
//  (deprecated)

import UIKit
import AssetsLibrary

struct PixelData {
    var r:UInt8
    var g:UInt8
    var b:UInt8
    var a:UInt8 = 255
    }

class WrapMap : NSObject, NSCoding  {
    //MARK: Archiving Paths
    static let documentsDirectory = FileManager().urls(for: .documentDirectory, in: .userDomainMask).first! 
    static let archiveURL = documentsDirectory.appendingPathComponent("map_data")
    
    // MARK: Properties
    var width : Int
    var pixels : [PixelData]
    var map : CGImage?
    
    struct PropertyKey {
        static let mapKey = "map"
        }
    
    override init() {
        // perform some initialization here
        width = 300
        pixels = [PixelData]()
        
        super.init()
        }
    
    init (cgimg: CGImage) {
        width = 300
        pixels = [PixelData]()   // get image pixels?
        map = cgimg
        
        super.init()
        }
    
    // compute pixel in fisheye image corresponding to (x,y) in unwrapped image
    func computeMapValue(x: Int, y: Int) -> PixelData {
        let alpha = Double(x - width/2)/Double(width)*Double.pi
        let beta = Double(y - width/2)/Double(width)*Double.pi
        var rx = cos(beta)*sin(alpha)
        let ry = cos(beta)*cos(alpha)
        var rz = sin(beta)
        let norm = sqrt(rx*rx + rz*rz)
        
        let d2 = rx*rx + (1.0-ry)*(1.0-ry) + rz*rz
        let gamma = acos(1.0 - d2/2.0)
        let r = gamma/(Double.pi/2.0)
        //if ((x == 10 || x == 150 || x == 290) && y == 10){print(x,y,alpha,beta,rx,ry,rz,r)}
        
        //return PixelData(r: UInt8((Float(x)/Float(width)*255)), g: UInt8((Float(y)/Float(width)*255)), b: 0, a: 255)
        //return PixelData(r: UInt8(127.0 + 128.0*Float(x)/Float(width)), g: UInt8(127.0 + 128.0*Float(y)/Float(width)), b: 0, a: 255)
        if (norm == 0){return PixelData(r: UInt8((rx + 1.0)*127.5), g: UInt8((rz + 1.0)*127.5), b: 0, a: 255)}
        rx = rx/norm*r
        rz = rz/norm*r
        
        return PixelData(r: UInt8((rx + 1.0)*127.5), g: UInt8((rz + 1.0)*127.5), b: 0, a: 255)
        }
    
    // compute data for wrap map
    func makeMapping(){
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo:CGBitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        //populate pixels with pixel colour values and alpha information
        for i in 0 ..< width {
            for j in 0 ..< width {
                //if ((j == 290 || j == 150 || j == 10) && (i == 290)){print(j, width-i, computeMapValue(x: j, y: width-i))}
                pixels.append(computeMapValue(x: j, y: width-i))
                //if (i == 225 && j == 75){print(computeMapValue(x: j, y: width-i))}
                }
            }
        
        let providerRef = CGDataProvider(data: NSData(bytes: &pixels, length: pixels.count * MemoryLayout<PixelData>.size))
    
        
        map = CGImage(width: width,height: width,bitsPerComponent: 8,bitsPerPixel: 32,bytesPerRow: width * Int(MemoryLayout<PixelData>.size),space: rgbColorSpace,bitmapInfo: bitmapInfo,provider: providerRef!,decode: nil,shouldInterpolate: true,intent: .defaultIntent)
        //map = CGImage(maskWidth: width, height: width, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * Int(MemoryLayout<PixelData>.size), provider: providerRef!, decode: nil, shouldInterpolate: true)
        }
    
    
    // MARK: NSCoding
    required convenience init?(coder aDecoder: NSCoder) {
        let savedMap = (aDecoder.decodeObject(forKey: PropertyKey.mapKey) as! CGImage)
        self.init(cgimg: savedMap)
        }
    
    
    func encode(with aCoder: NSCoder) {
        aCoder.encode(self.map, forKey: PropertyKey.mapKey)
        }
    }
