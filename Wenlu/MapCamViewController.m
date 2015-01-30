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
    
#ifndef MCVC
#if true
    [self initMapView];
    [self initSearch];
//#define COR_TEST
#ifdef COR_TEST
     AVCamPreviewView *mapView = (AVCamPreviewView *)self.view;
    
    // Create array of hard-coded places-of-interest, in this case some famous parks

    const char *poiNames[] = {
        "Jinan Railway Station JN",
        "QingDao Railway Station QD",
        "HUANGJIA ZHUTI CANTING SHANDABEILU",
        "Hyde Park UK",
        "Mont Royal QC",
        "Retiro Park ES"};
    
    CLLocationCoordinate2D poiCoords[] = {
        {36.6712, 116.99089000000004},
        {36.06547, 117.056056},
        {36.679618, 117.060371},
        {51.5068670, -0.1708030},
        {45.5126399, -73.6802448},
        {40.4152519, -3.6887466}};
    
    int numPois = sizeof(poiCoords) / sizeof(CLLocationCoordinate2D);
    
    NSMutableArray *pOfI = [NSMutableArray arrayWithCapacity:numPois];
    for (int i = 0; i < numPois; i++) {
        UILabel *label = [[UILabel alloc] init];
        label.adjustsFontSizeToFitWidth = NO;
        label.opaque = NO;
        label.backgroundColor = [UIColor colorWithRed:0.1f green:0.1f blue:0.1f alpha:0.5f];
        label.center = CGPointMake(200.0f, 200.0f);
        label.textAlignment = NSTextAlignmentCenter;
        label.textColor = [UIColor whiteColor];
        label.text = [NSString stringWithCString:poiNames[i] encoding:NSASCIIStringEncoding];
        //        CGSize size = [label.text sizeWithFont:label.font];
        CGSize size = [label.text sizeWithAttributes:@ {NSFontAttributeName: label.font}];
        label.bounds = CGRectMake(0.0f, 0.0f, size.width, size.height);
        
        PlaceOfInterest *poi = [PlaceOfInterest placeOfInterestWithView:label at:[[CLLocation alloc] initWithLatitude:poiCoords[i].latitude longitude:poiCoords[i].longitude]];
        [pOfI insertObject:poi atIndex:i];
    }

    [mapView setPlacesOfInterest:pOfI];
#else
    AVCamPreviewView *mapView = (AVCamPreviewView *)self.view;
    
    // Create array of hard-coded places-of-interest, in this case some famous parks
    
    NSMutableArray *pOfI = [NSMutableArray array];
    for (AMapPOI *poigd in self.places){
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
#endif
    
#endif
#else
   
    // Create the AVCaptureSession

    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    [self setSession:session];
    
    // Setup the preview view
    [[self mapPreviewView] setSession:session];
    
    // Check for device authorization
    [self checkDeviceAuthorizationStatus];
    
    // In general it is not safe to mutate an AVCaptureSession or any of its inputs, outputs, or connections from multiple threads at the same time.
    // Why not do all of this on the main queue?
    // -[AVCaptureSession startRunning] is a blocking call which can take a long time. We dispatch session setup to the sessionQueue so that the main queue isn't blocked (which keeps the UI responsive).
    
    dispatch_queue_t sessionQueue = dispatch_queue_create("session queue", DISPATCH_QUEUE_SERIAL);
    [self setSessionQueue:sessionQueue];
    
    dispatch_async(sessionQueue, ^{
        [self setBackgroundRecordingID:UIBackgroundTaskInvalid];
        
        NSError *error = nil;
        
        AVCaptureDevice *videoDevice = [MapCamViewController deviceWithMediaType:AVMediaTypeVideo preferringPosition:AVCaptureDevicePositionBack];
        AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
        
        if (error)
        {
            NSLog(@"%@", error);
        }
        
        if ([session canAddInput:videoDeviceInput])
        {
            [session addInput:videoDeviceInput];
            [self setVideoDeviceInput:videoDeviceInput];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                // Why are we dispatching this to the main queue?
                // Because AVCaptureVideoPreviewLayer is the backing layer for AVCamPreviewView and UIView can only be manipulated on main thread.
                // Note: As an exception to the above rule, it is not necessary to serialize video orientation changes on the AVCaptureVideoPreviewLayer’s connection with other session manipulation.
                
                [[(AVCaptureVideoPreviewLayer *)[[self mapPreviewView] layer] connection] setVideoOrientation:(AVCaptureVideoOrientation)[self interfaceOrientation]];
            });
        }
        
    });
#endif
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




