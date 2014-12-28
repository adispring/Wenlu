/*
     File: ARView.h
 Abstract: Augmented reality view. Displays a live camera feed with specified places-of-interest overlayed in the correct position based on the direction the user is looking. Uses Core Location to determine the user's location relative the places-of-interest and Core Motion to determine the direction the user is looking.
  Version: 1.0 
 */

#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
#import <CoreMotion/CoreMotion.h>


@interface ARView : UIView  <CLLocationManagerDelegate> {
}

@property (nonatomic, strong) NSArray *placesOfInterest;


- (void)start;
- (void)stop;

@end
