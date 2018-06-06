//
//  CVWrapper.m
//  PictureFilter
//
//  Created by Matthew Mayers on 1/4/17.
//  Copyright © 2017 Matthew Mayers. All rights reserved.
//

#import "CVWrapper.h"
#import "UIImage+OpenCV.h"
#import "circles.h"

@implementation CVWrapper

+ (UIImage*) drawImageCircle:(UIImage*)inputImage
{
    NSLog (@"searching for circles...");
    cv::Mat matInputImage = [inputImage CVMat3];
    cv::Mat circlesMat = computeImageCircle (matInputImage);
    UIImage* result =  [UIImage imageWithCVMat:circlesMat];
    return result;
}

@end
