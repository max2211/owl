//
//  circles.cpp
//  PictureFilter
//
//  Created by Matthew Mayers on 1/4/17.
//  Copyright © 2017 Matthew Mayers. All rights reserved.
//

#include "circles.h"
#include <iostream>
#include <stdio.h>

//openCV 3.x
#include "opencv2/highgui/highgui.hpp"
#include "opencv2/imgproc/imgproc.hpp"

using namespace std;
using namespace cv;

cv::Mat computeImageCircle (cv::Mat src){
    if (!src.data){return src;}
    
    /// Convert it to gray
    cv::Mat src_gray;
    cvtColor( src, src_gray, CV_BGR2GRAY );
    
    /// Reduce the noise so we avoid false circle detection
    GaussianBlur( src_gray, src_gray, Size(3, 3), 1, 1 );
    
    //return src_gray;
    
    vector<Vec3f> circles;
    
    /// Apply the Hough Transform to find the circles
    //              input  circles vec      method     accumulator size, min center dist, Canny param, accumulator min, min radius, max radius
    HoughCircles( src_gray, circles, CV_HOUGH_GRADIENT, 1, 20, 200, 20, 75, 77 );
    
    cout << circles.size() << '\n';
    /// Draw the circles detected
    for (size_t i = 0; i < circles.size(); i++){
        Point center(cvRound(circles[i][0]), cvRound(circles[i][1]));
        int radius = cvRound(circles[i][2]);
        cout << " " << center << " " << radius << '\n';
        // circle center
        circle(src, center, 3, Scalar(255,0,0), -1, 8, 0);
        // circle outline
        circle(src, center, radius, Scalar(0,0,255), 2, 8, 0);
        }
    
	// comment out later
    HoughCircles( src_gray, circles, CV_HOUGH_GRADIENT, 1, 20, 200, 20, 62, 70 );
    
    cout << circles.size() << '\n';
    /// Draw the circles detected
    for (size_t i = 0; i < circles.size(); i++){
        Point center(cvRound(circles[i][0]), cvRound(circles[i][1]));
        int radius = cvRound(circles[i][2]);
        cout << " " << center << " " << radius << '\n';
        // circle center
        circle(src, center, 3, Scalar(255,0,0), -1, 8, 0);
        // circle outline
        circle(src, center, radius, Scalar(0,0,255), 2, 8, 0);
    }
    
    return src;
    }
