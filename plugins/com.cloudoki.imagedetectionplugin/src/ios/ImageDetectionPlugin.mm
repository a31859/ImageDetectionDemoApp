#import "ImageDetectionPlugin.h"
#import "ImageUtils.h"
#import <opencv2/highgui/ios.h>
#import <opencv2/features2d/features2d.hpp>

using namespace cv;

@interface ImageDetectionPlugin()
{
    std::vector<Mat> triggers, triggers_descs;
    std::vector< std::vector<KeyPoint> > triggers_kps;
    bool processFrames, debug, save_files, thread_over, called_success_detection, called_failed_detection;
    int detected_index;
    NSMutableArray *detection;
    NSString *callbackID;
    NSDate *last_time, *ease_last_time, *timeout_started;
    float timeout, full_timeout, ease_time;
    NSUInteger triggers_size;
}

@end

@implementation ImageDetectionPlugin

@synthesize camera, img;

- (void)greet:(CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{
        CDVPluginResult* plugin_result = nil;
        NSString* name = [command.arguments objectAtIndex:0];
        NSString* msg = [NSString stringWithFormat: @"Hello, %@", name];

        if (name != nil && [name length] > 0) {
            plugin_result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:msg];
        } else {
            plugin_result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR];
        }

        [self.commandDelegate sendPluginResult:plugin_result callbackId:command.callbackId];
    }];
}

-(void)isDetecting:(CDVInvokedUrlCommand*)command
{
    callbackID = command.callbackId;
}

- (void)setPatterns:(CDVInvokedUrlCommand*)command;
{
    [self.commandDelegate runInBackground:^{
        CDVPluginResult* plugin_result = nil;
        NSMutableString* msg = [NSMutableString stringWithString:@""];
        NSArray* patterns = [[NSArray alloc] init];
        patterns = command.arguments;

        if (patterns != nil && [patterns count] > 0) {
            triggers_size = [patterns count];
            triggers.clear();
            triggers_kps.clear();
            triggers_descs.clear();
            [msg appendFormat:@"Patterns to be set - %lu", (unsigned long)[patterns count]];
            int triggers_length = 0;
            if(!triggers.empty()){
                triggers_length = (int)triggers.size();
            }
            [msg appendFormat:@"\nBefore set pattern - %d", triggers_length];
            [self setBase64Pattern: patterns];
            if(!triggers.empty()){
                triggers_length = (int)triggers.size();
            }
            [msg appendFormat:@"\nAfter set pattern - %d", triggers_length];
            if((int) triggers.size() == triggers_size){
                [msg appendFormat:@"\nPatterns set - %d", triggers_length];
                plugin_result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:msg];
            } else {
                [msg appendString:@"\nOne or more patterns failed to be set."];
                plugin_result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:msg];
            }
        } else {
            [msg appendString:@"At least one pattern must be set."];
            plugin_result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:msg];
        }

        [self.commandDelegate sendPluginResult:plugin_result callbackId:command.callbackId];
    }];
}

- (void)startProcessing:(CDVInvokedUrlCommand*)command;
{
    [self.commandDelegate runInBackground:^{
        CDVPluginResult* plugin_result = nil;
        NSNumber* argVal = [command.arguments objectAtIndex:0];
        NSString* msg;

        if (argVal != nil) {
            BOOL argValBool;
            @try {
                argValBool = [argVal boolValue];
            }
            @catch (NSException *exception) {
                argValBool = YES;
                NSLog(@"%@", exception.reason);
            }
            if (argValBool == YES) {
                processFrames = true;
                msg = @"Frame processing set to 'true'";
            } else {
                processFrames = false;
                msg = @"Frame processing set to 'false'";
            }
            plugin_result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:msg];
        } else {
            msg = @"No value";
            plugin_result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:msg];
        }

        [self.commandDelegate sendPluginResult:plugin_result callbackId:command.callbackId];
    }];
}

- (void)setDetectionTimeout:(CDVInvokedUrlCommand*)command;
{
    [self.commandDelegate runInBackground:^{
        CDVPluginResult* plugin_result = nil;
        NSNumber* argVal = [command.arguments objectAtIndex:0];
        NSString* msg;

        if (argVal != nil && argVal > 0) {
            timeout = [argVal floatValue];
            ease_time = 0.5;
            timeout_started = [NSDate date];
            msg = [NSString stringWithFormat:@"Processing timeout set to %@", argVal];
            plugin_result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:msg];
        } else {
            msg = @"No value or timeout value negative.";
            plugin_result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:msg];
        }

        [self.commandDelegate sendPluginResult:plugin_result callbackId:command.callbackId];
    }];
}

-(void)setBase64Pattern:(NSArray *)patterns
{
    ORB orb = ORB::ORB();

    for (int i = 0; i < [patterns count]; i++) {
        [detection insertObject:[NSNumber numberWithInt:0] atIndex:i];
        NSString *image_base64 = [patterns objectAtIndex:i];

        if ([image_base64 rangeOfString:@"data:"].location == NSNotFound) {
            // do nothing
        } else {
            NSArray *lines = [image_base64 componentsSeparatedByString: @","];
            image_base64 = lines[1];
        }

        int width_limit = 400, height_limit = 400;

        UIImage *image = [ImageUtils decodeBase64ToImage: image_base64];
        UIImage *scaled = image;

        // scale image to improve detection
        //NSLog(@"SCALE BEFORE %f", (scaled.size.width));
        if(image.size.width > width_limit) {
            scaled = [UIImage imageWithCGImage:[image CGImage] scale:(image.size.width/width_limit) orientation:(image.imageOrientation)];
            if(scaled.size.height > height_limit) {
                scaled = [UIImage imageWithCGImage:[scaled CGImage] scale:(scaled.size.height/height_limit) orientation:(scaled.imageOrientation)];
            }
        }
        //NSLog(@"SCALE AFTER %f", (scaled.size.width));

        Mat patt, desc1;
        std::vector<KeyPoint> kp1;

        patt = [ImageUtils cvMatFromUIImage: scaled];

        patt = [ImageUtils cvMatFromUIImage: scaled];
        cvtColor(patt, patt, CV_BGRA2GRAY);
        //equalizeHist(patt, patt);

        //save mat as image
        if (save_files)
        {
            UIImageWriteToSavedPhotosAlbum([ImageUtils UIImageFromCVMat:patt], nil, nil, nil);
        }
        orb.detect(patt, kp1);
        orb.compute(patt, kp1, desc1);

        triggers.push_back(patt);
        triggers_kps.push_back(kp1);
        triggers_descs.push_back(desc1);
    }
}

- (void)pluginInitialize {
    // set orientation portraint
    NSNumber *value = [NSNumber numberWithInt:UIInterfaceOrientationPortrait];
    [[UIDevice currentDevice] setValue:value forKey:@"orientation"];

    // set webview and it's subviews to transparent
    for (UIView *subview in [self.webView subviews]) {
        [subview setOpaque:NO];
        [subview setBackgroundColor:[UIColor clearColor]];
    }
    [self.webView setBackgroundColor:[UIColor clearColor]];
    [self.webView setOpaque: NO];
    // setup view to render the camera capture
    CGRect screenRect = [[UIScreen mainScreen] bounds];
    img = [[UIImageView alloc] initWithFrame: screenRect];
    img.contentMode = UIViewContentModeScaleAspectFill;
    [self.webView.superview addSubview: img];
    // set views order
    [self.webView.superview bringSubviewToFront: self.webView];

    //Camera
    self.camera = [[CvVideoCamera alloc] initWithParentView: img];
    self.camera.useAVCaptureVideoPreviewLayer = YES;
    self.camera.defaultAVCaptureDevicePosition = AVCaptureDevicePositionBack;
    self.camera.defaultAVCaptureSessionPreset = AVCaptureSessionPresetMedium;
    self.camera.defaultAVCaptureVideoOrientation = AVCaptureVideoOrientationPortrait;
    self.camera.defaultFPS = 30;
    self.camera.grayscaleMode = NO;

    self.camera.delegate = self;

    processFrames = true;
    debug = false;
    save_files = false;
    thread_over = true;
    called_success_detection = false;
    called_failed_detection = true;

    timeout = 0.0;
    full_timeout = 6.0;
    ease_time = 0.0;
    last_time = [NSDate date];
    timeout_started = last_time;
    ease_last_time = last_time;

    detection = [[NSMutableArray alloc] init];
    triggers_size = -1;
    detected_index = -1;

    [self.camera start];
    NSLog(@"----------- CAMERA STARTED ----------");
    NSLog(@"----------- CV_VERSION %s ----------", CV_VERSION);
}

#pragma mark - Protocol CvVideoCameraDelegate
#ifdef __cplusplus
- (void)processImage:(Mat &)image;
{
    //get current time and calculate time passed since last time update
    NSDate *current_time = [NSDate date];
    NSTimeInterval time_passed = [current_time timeIntervalSinceDate:last_time];
    NSTimeInterval time_diff_passed = [current_time timeIntervalSinceDate:timeout_started];
    NSTimeInterval passed_ease = [current_time timeIntervalSinceDate:ease_last_time];

    //NSLog(@"time passed %f, time full %f, passed ease %f", time_passed, time_diff_passed, passed_ease);

    //process frames if option is true and timeout passed
    BOOL hasTriggerSet = false;
    if(!triggers.empty()){
        hasTriggerSet = triggers.size() == triggers_size;
    }
    if (processFrames && time_passed > timeout && hasTriggerSet) {
        //check if time passed full timout time
        if(time_diff_passed > full_timeout) {
            ease_time = 0.0;
        }
        // ease detection after timeout
        if (passed_ease > ease_time) {
            // process each image in new thread
            if(!image.empty() && thread_over){
                for (int i = 0; i < triggers.size(); i++) {
                    Mat patt = triggers.at(i);
                    std::vector<KeyPoint> kp1 = triggers_kps.at(i);
                    Mat desc1 = triggers_descs.at(i);
                    thread_over = false;
                    Mat image_copy = image.clone();
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        [self backgroundImageProcessing: image_copy pattern:patt keypoints:kp1 descriptor:desc1 index:i];
                        dispatch_sync(dispatch_get_main_queue(), ^{
                            if(i == (triggers.size() - 1)) {
                                thread_over = true;
                            }
                        });
                    });
                }
            }
            ease_last_time = current_time;
        }

        //update time and reset timeout
        last_time = current_time;
        timeout = 0.0;
    }
}
#endif

#ifdef __cplusplus
- (void)backgroundImageProcessing:(const Mat &)image pattern:(const Mat &)patt keypoints:(const std::vector<KeyPoint> &)kp1 descriptor:(const Mat &)desc1 index:(const int &)idx
{
    if(!image.empty() && !patt.empty())
    {
        Mat gray = image;
        //Mat image_copy = image;
        Mat desc2;
        std::vector<KeyPoint> kp2;

        cvtColor(image, gray, CV_BGRA2GRAY);
        //equalizeHist(gray, gray);

        ORB orb = ORB::ORB();
        orb.detect(gray, kp2);
        orb.compute(gray, kp2, desc2);

        BFMatcher bf = BFMatcher::BFMatcher(NORM_HAMMING2, true);
        std::vector<DMatch> matches;
        std::vector<DMatch> good_matches;

        if(!desc1.empty() && !desc2.empty())
        {
            bf.match(desc1, desc2, matches);

            int size = 0;
            double min_dist = 1000;
            if(desc1.rows < matches.size())
                size = desc1.rows;
            else
                size = (int)matches.size();

            for(int i = 0; i < size; i++)
            {
                double dist = matches[i].distance;
                if(dist < min_dist)
                {
                    min_dist = dist;
                }
            }

            std::vector<DMatch> good_matches_reduced;

            for(int i = 0; i < size; i++)
            {
                if(matches[i].distance <=  2 * min_dist && good_matches.size() < 500)
                {
                    good_matches.push_back(matches[i]);
                    if(i < 10 && debug)
                    {
                        good_matches_reduced.push_back(matches[i]);
                    }
                }
            }

            if(good_matches.size() >= 8)
            {
                if(debug)
                {
                    Mat imageMatches;
                    drawMatches(patt, kp1, gray, kp2, good_matches_reduced, imageMatches, Scalar::all(-1), Scalar::all(-1), std::vector<char>(), DrawMatchesFlags::NOT_DRAW_SINGLE_POINTS);
                    //image_copy = imageMatches;
                }

                Mat img_matches = image;
                //-- Localize the object
                std::vector<Point2f> obj;
                std::vector<Point2f> scene;

                for( int i = 0; i < good_matches.size(); i++ )
                {
                    //-- Get the keypoints from the good matches
                    obj.push_back( kp1[ good_matches[i].queryIdx ].pt );
                    scene.push_back( kp2[ good_matches[i].trainIdx ].pt );
                }

                Mat H = findHomography( obj, scene, CV_RANSAC);

                bool result = true;

                if (!H.empty()) {
                    const double p1 = H.at<double>(0, 0);
                    const double p2 = H.at<double>(1, 1);
                    const double p3 = H.at<double>(1, 0);
                    const double p4 = H.at<double>(0, 1);
                    const double p5 = H.at<double>(2, 0);
                    const double p6 = H.at<double>(2, 1);
                    double det = 0, N1 = 0, N2 = 0, N3 = 0;

                    if (p1 && p2 && p3 && p4) {
                        det = p1 * p2 - p3 * p4;
                        if (det < 0)
                            result = false;
                    } else {
                        result = false;
                    }

                    if (p1 && p3) {
                        N1 = sqrt(p1 * p1 + p3 * p3);
                        if (N1 > 4 || N1 < 0.1)
                            result =  false;
                    } else {
                        result = false;
                    }

                    if (p2 && p4) {
                        N2 = sqrt(p4 * p4 + p2 * p2);
                        if (N2 > 4 || N2 < 0.1)
                            result = false;
                    } else {
                        result = false;
                    }

                    if (p5 && p6) {
                    N3 = sqrt(p5 * p5 + p6 * p6);
                    if (N3 > 0.002)
                        result = false;
                    } else {
                        result = false;
                    }

                    //NSLog(@"det %f, N1 %f, N2 %f, N3 %f, result %i", det, N1, N2, N3, result);
                } else {
                    result = false;
                }

                if(result)
                {
                    NSLog(@"detecting for index - %d", (int)idx);
                    [self updateState: true index:(int)idx];
                    if(save_files)
                    {
                        UIImageWriteToSavedPhotosAlbum([ImageUtils UIImageFromCVMat:gray], nil, nil, nil);
                    }
                    if(debug)
                    {
                        //-- Get the corners from the image_1 ( the object to be "detected" )
                        std::vector<Point2f> obj_corners(4);
                        obj_corners[0] = cvPoint(0,0); obj_corners[1] = cvPoint( patt.cols, 0 );
                        obj_corners[2] = cvPoint( patt.cols, patt.rows ); obj_corners[3] = cvPoint( 0, patt.rows );
                        std::vector<Point2f> scene_corners(4);

                        perspectiveTransform( obj_corners, scene_corners, H);

                        //-- Draw lines between the corners (the mapped object in the scene - image_2 )
                        line( img_matches, scene_corners[0] + Point2f( patt.cols, 0), scene_corners[1] + Point2f( patt.cols, 0), Scalar(0, 255, 0), 4 );
                        line( img_matches, scene_corners[1] + Point2f( patt.cols, 0), scene_corners[2] + Point2f( patt.cols, 0), Scalar( 0, 255, 0), 4 );
                        line( img_matches, scene_corners[2] + Point2f( patt.cols, 0), scene_corners[3] + Point2f( patt.cols, 0), Scalar( 0, 255, 0), 4 );
                        line( img_matches, scene_corners[3] + Point2f( patt.cols, 0), scene_corners[0] + Point2f( patt.cols, 0), Scalar( 0, 255, 0), 4 );

                        //image_copy = img_matches;
                    }
                } else {
                    [self updateState: false index:(int)idx];
                }
                H.release();
                img_matches.release();
            }
            matches.clear();
            good_matches.clear();
            good_matches_reduced.clear();
        }
        gray.release();
        desc2.release();
        kp2.clear();
        //image = image_copy;
    }
}
#endif

-(void)updateState:(BOOL) state index:(const int &)idx
{
    int detection_limit = 6;
//
//    if(detection.count > detection_limit)
//    {
//        [detection removeObjectAtIndex:0];
//    }

    NSLog(@"updating state for index - %d", (int)idx);

    if(state)
    {
        int result = [[detection objectAtIndex:(int)idx] intValue] + 1;
        if(result < detection_limit) {
            [detection replaceObjectAtIndex:idx withObject:[NSNumber numberWithInt:result]];
        }
    } else {
        for (int i = 0; i < triggers.size(); i++) {
            int result = [[detection objectAtIndex:(int)i] intValue] - 1;
            if(result < 0) {
                result = 0;
            }
            [detection replaceObjectAtIndex:idx withObject:[NSNumber numberWithInt:result]];
        }
    }

    if([self getState:(int)idx] && called_failed_detection && !called_success_detection) {
        [self.commandDelegate runInBackground:^{
            CDVPluginResult* plugin_result = nil;
            NSString* msg = [NSString stringWithFormat:@"{\"message\":\"pattern detected\", \"index\":%d}", (int)idx];
            plugin_result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:msg];
            [plugin_result setKeepCallbackAsBool:YES];

            [self.commandDelegate sendPluginResult:plugin_result callbackId:callbackID];
        }];
        called_success_detection = true;
        called_failed_detection = false;
        detected_index = (int)idx;
    }

    bool valid_index = detected_index == (int)idx;

    if(![self getState:(int)idx] && !called_failed_detection && called_success_detection && valid_index) {
        [self.commandDelegate runInBackground:^{
            CDVPluginResult* plugin_result = nil;
            NSString* msg = @"{\"message\":\"pattern not detected\"}";
            plugin_result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:msg];
            [plugin_result setKeepCallbackAsBool:YES];

            [self.commandDelegate sendPluginResult:plugin_result callbackId:callbackID];
        }];
        called_success_detection = false;
        called_failed_detection = true;
    }
}

-(BOOL)getState: (const int &) index
{
    int detection_thresh = 3;
    NSNumber *total = 0;
    total = [detection objectAtIndex:index];

    if ([total intValue] >= detection_thresh) {
        return true;
    } else {
        return false;
    }
}

@end
