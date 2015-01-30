/*
     File: AVCamPreviewView.h
 Abstract: Application preview view.
  Version: 3.1 
 */

#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
#import <CoreMotion/CoreMotion.h>

@class AVCaptureSession;

@interface AVCamPreviewView : UIView <CLLocationManagerDelegate> {
    
}

@property (nonatomic, strong) NSArray *placesOfInterest;
@property (nonatomic) AVCaptureSession *session;

- (void)start;
- (void)stop;

@end
