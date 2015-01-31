//
//  MapCamViewController.m
//  AVCam
//
//  Created by 王增迪 on 12/25/14.
//  Copyright (c) 2014 Apple Inc. All rights reserved.
//

#import "MapCamViewController.h"
#import "AVCamPreviewView.h"
#import "PlaceOfInterest.h"

#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <MAMapKit/MAMapKit.h>
#import <AMapSearchKit/AMapSearchAPI.h>

#define APIKey  @"1648f9781b1ce1387c2127536b332c12"

#pragma mark - 
#pragma mark Math utilities declaration


@interface MapCamViewController ()<AMapSearchDelegate,MAMapViewDelegate>
{


}

// For use in the storyboards.

@property (weak, nonatomic) IBOutlet AVCamPreviewView *mapPreviewView;
@property (nonatomic, strong) NSArray *placesOfInterest;

@property (nonatomic, strong) MAMapView *mapView;
@property (nonatomic, strong) AMapSearchAPI *search;
@property (nonatomic, strong) CLLocation *currentLocation;

// Session management.
@property (nonatomic) dispatch_queue_t sessionQueue; // Communicate with the session and other session objects on this queue.
@property (nonatomic) AVCaptureSession *session;
@property (nonatomic) AVCaptureDeviceInput *videoDeviceInput;

// Utilities.
@property (nonatomic) UIBackgroundTaskIdentifier backgroundRecordingID;
@property (nonatomic, getter = isDeviceAuthorized) BOOL deviceAuthorized;
@property (nonatomic, readonly, getter = isSessionRunningAndDeviceAuthorized) BOOL sessionRunningAndDeviceAuthorized;
@property (nonatomic) BOOL lockInterfaceRotation;
@property (nonatomic) id runtimeErrorHandlingObserver;

@end

@implementation MapCamViewController

#pragma mark - AutoNavi Init
- (void)initMapView
{
    [MAMapServices sharedServices].apiKey = APIKey;
    self.mapView = [[MAMapView alloc] init];
    
    self.mapView.delegate = self;
    
    self.mapView.showsUserLocation = YES;
}

- (void)initSearch
{
    //MAMapServices is the root of other GaoDe Services? try delete it 2014-12-13
    [MAMapServices sharedServices].apiKey = APIKey;
    self.search = [[AMapSearchAPI alloc] initWithSearchKey:APIKey Delegate:self];
}

- (void)mapView:(MAMapView *)mapView didUpdateUserLocation:(MAUserLocation *)userLocation updatingLocation:(BOOL)updatingLocation
{
    //    NSLog(@"userLocation: %@", userLocation.location);
    self.currentLocation = [userLocation.location copy];
}


- (void)initPOIWithPlaces:(NSArray*)placesOfI
{
    AVCamPreviewView *mapView = (AVCamPreviewView *)self.view;
    
    // Create array of hard-coded places-of-interest, in this case some famous parks
    
    NSMutableArray *pOfI = [NSMutableArray array];
    for (AMapPOI *poigd in placesOfI){
        UILabel *label = [[UILabel alloc] init];
        label.adjustsFontSizeToFitWidth = NO;
        label.opaque = NO;
        label.backgroundColor = [UIColor colorWithRed:0.1f green:0.1f blue:0.1f alpha:0.5f];
        label.center = CGPointMake(200.0f, 200.0f);
        label.textAlignment = NSTextAlignmentCenter;
        label.textColor = [UIColor whiteColor];
        label.text = [NSString stringWithFormat:@"%@:%ldM",poigd.name,(long)poigd.distance];//poigd.name;
        //            CGSize size = [label.text sizeWithFont:label.font];
        CGSize size = [label.text sizeWithAttributes:@ {NSFontAttributeName: label.font}];
        label.bounds = CGRectMake(0.0f, 0.0f, size.width, size.height);
        
        PlaceOfInterest *poi = [PlaceOfInterest placeOfInterestWithView:label at:[[CLLocation alloc] initWithLatitude:poigd.location.latitude longitude:poigd.location.longitude]];
        //            NSLog(@"poigd.location.longitude: %@",poigd.)
        [pOfI addObject:poi];
    }
    
    [mapView setPlacesOfInterest:pOfI];
}

#pragma - Check iPAD status

- (BOOL)isSessionRunningAndDeviceAuthorized
{
    return [[self session] isRunning] && [self isDeviceAuthorized];
}


- (BOOL)prefersStatusBarHidden
{
    return YES;
}

- (BOOL)shouldAutorotate
{
    // Disable autorotation of the interface when recording is in progress.
    return ![self lockInterfaceRotation];
}

- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAll;
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    [[(AVCaptureVideoPreviewLayer *)[[self mapPreviewView] layer] connection] setVideoOrientation:(AVCaptureVideoOrientation)toInterfaceOrientation];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


#pragma mark - UI

- (void)checkDeviceAuthorizationStatus
{
    NSString *mediaType = AVMediaTypeVideo;
    
    [AVCaptureDevice requestAccessForMediaType:mediaType completionHandler:^(BOOL granted) {
        if (granted)
        {
            //Granted access to mediaType
            [self setDeviceAuthorized:YES];
        }
        else
        {
            //Not granted access to mediaType
            dispatch_async(dispatch_get_main_queue(), ^{
                [[[UIAlertView alloc] initWithTitle:@"AVCam!"
                                            message:@"AVCam doesn't have permission to use Camera, please change privacy settings"
                                           delegate:self
                                  cancelButtonTitle:@"OK"
                                  otherButtonTitles:nil] show];
                [self setDeviceAuthorized:NO];
            });
        }
    }];
}

#pragma mark Device Configuration

- (void)focusWithMode:(AVCaptureFocusMode)focusMode exposeWithMode:(AVCaptureExposureMode)exposureMode atDevicePoint:(CGPoint)point monitorSubjectAreaChange:(BOOL)monitorSubjectAreaChange
{
    dispatch_async([self sessionQueue], ^{
        AVCaptureDevice *device = [[self videoDeviceInput] device];
        NSError *error = nil;
        if ([device lockForConfiguration:&error])
        {
            if ([device isFocusPointOfInterestSupported] && [device isFocusModeSupported:focusMode])
            {
                [device setFocusMode:focusMode];
                [device setFocusPointOfInterest:point];
            }
            if ([device isExposurePointOfInterestSupported] && [device isExposureModeSupported:exposureMode])
            {
                [device setExposureMode:exposureMode];
                [device setExposurePointOfInterest:point];
            }
            [device setSubjectAreaChangeMonitoringEnabled:monitorSubjectAreaChange];
            [device unlockForConfiguration];
        }
        else
        {
            NSLog(@"%@", error);
        }
    });
}

+ (void)setFlashMode:(AVCaptureFlashMode)flashMode forDevice:(AVCaptureDevice *)device
{
    if ([device hasFlash] && [device isFlashModeSupported:flashMode])
    {
        NSError *error = nil;
        if ([device lockForConfiguration:&error])
        {
            [device setFlashMode:flashMode];
            [device unlockForConfiguration];
        }
        else
        {
            NSLog(@"%@", error);
        }
    }
}

+ (AVCaptureDevice *)deviceWithMediaType:(NSString *)mediaType preferringPosition:(AVCaptureDevicePosition)position
{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:mediaType];
    AVCaptureDevice *captureDevice = [devices firstObject];
    
    for (AVCaptureDevice *device in devices)
    {
        if ([device position] == position)
        {
            captureDevice = device;
            break;
        }
    }
    
    return captureDevice;
}



#pragma mark - View Loading

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self initMapView];
    [self initSearch];
    [self initPOIWithPlaces:self.places];
}


- (void)viewWillAppear:(BOOL)animated
{
#ifndef MCVC
    [super viewWillAppear:animated];
    AVCamPreviewView *mapView = (AVCamPreviewView *)self.view;
    [mapView start];
#else
    dispatch_async([self sessionQueue], ^{
        [[self session] startRunning];
    });
#endif
}

- (void)viewDidDisappear:(BOOL)animated
{
    
}

@end




