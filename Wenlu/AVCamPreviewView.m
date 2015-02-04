/*
     File: AVCamPreviewView.m
 Abstract: Application preview view.
  Version: 3.1
 
 Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
 Inc. ("Apple") in consideration of your agreement to the following
 terms, and your use, installation, modification or redistribution of
 this Apple software constitutes acceptance of these terms.  If you do
 not agree with these terms, please do not use, install, modify or
 redistribute this Apple software.
 
 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software (the
 "Apple Software"), to use, reproduce, modify and redistribute the Apple
 Software, with or without modifications, in source and/or binary forms;
 provided that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the following
 text and disclaimers in all such redistributions of the Apple Software.
 Neither the name, trademarks, service marks or logos of Apple Inc. may
 be used to endorse or promote products derived from the Apple Software
 without specific prior written permission from Apple.  Except as
 expressly stated in this notice, no other rights or licenses, express or
 implied, are granted by Apple herein, including but not limited to any
 patent rights that may be infringed by your derivative works or by other
 works in which the Apple Software may be incorporated.
 
 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
 
 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
 
 Copyright (C) 2014 Apple Inc. All Rights Reserved.
 
 */

#import "AVCamPreviewView.h"
#import "PlaceOfInterest.h"
#import "MapCamViewController.h"

#import <AVFoundation/AVFoundation.h>
//#import <AssetsLibrary/AssetsLibrary.h>
#import <MAMapKit/MAMapKit.h>
#import <AMapSearchKit/AMapSearchAPI.h>

#pragma mark -
#pragma mark Math utilities declaration

#define DEGREES_TO_RADIANS (M_PI/180.0)
#define RADIANS_TO_DEGREES (180.0/M_PI)

#define APIKey  @"1648f9781b1ce1387c2127536b332c12"
#define AUTONAVI

typedef float mat4f_t[16];	// 4x4 matrix in column major order
typedef float vec4f_t[4];	// 4D vector


// Creates a projection matrix using the given y-axis field-of-view, aspect ratio, and near and far clipping planes
void createProjectionMatrixStd(mat4f_t mout, float fovy, float aspect, float zNear, float zFar);

// Matrix-vector and matrix-matricx multiplication routines
void multiplyMatrixAndVectorStd(vec4f_t vout, const mat4f_t m, const vec4f_t v);
void multiplyMatrixAndMatrixStd(mat4f_t c, const mat4f_t a, const mat4f_t b);

// Initialize mout to be an affine transform corresponding to the same rotation specified by m
void transformFromCMRotationMatrixStd(vec4f_t mout, const CMRotationMatrix *m);

#pragma mark -
#pragma mark Geodetic utilities declaration

#define WGS84_A	(6378137.0)				// WGS 84 semi-major axis constant in meters
#define WGS84_E (8.1819190842622e-2)	// WGS 84 eccentricity

// Converts latitude, longitude to ECEF coordinate system
void latLonToEcef(double lat, double lon, double alt, double *x, double *y, double *z);

// Coverts ECEF to ENU coordinates centered at given lat, lon
void ecefToEnu(double lat, double lon, double x, double y, double z, double xr, double yr, double zr, double *e, double *n, double *u);



#pragma mark -
#pragma mark AVCamPreviewView Interface
@interface AVCamPreviewView () <AMapSearchDelegate,MAMapViewDelegate>
{
    UIView *captureView;
    AVCaptureSession *captureSession;
    AVCaptureVideoPreviewLayer *captureLayer;
    
    CADisplayLink *displayLink;
    CMMotionManager *motionManager;
    CLLocationManager *locationManager;

    NSArray *placesOfInterest;
    mat4f_t projectionTransform;
    mat4f_t cameraTransform;
    vec4f_t *placesOfInterestCoordinates;
    
    MAMapView *mapView;
    AMapSearchAPI *search;
    CLLocation *currentLocation;
}


// Session management.
@property (nonatomic) dispatch_queue_t sessionQueue; // Communicate with the session and other session objects on this queue.
//@property (nonatomic) AVCaptureSession *session;
@property (nonatomic) AVCaptureDeviceInput *videoDeviceInput;

// Utilities.
@property (nonatomic) UIBackgroundTaskIdentifier backgroundRecordingID;
@property (nonatomic, getter = isDeviceAuthorized) BOOL deviceAuthorized;
@property (nonatomic, readonly, getter = isSessionRunningAndDeviceAuthorized) BOOL sessionRunningAndDeviceAuthorized;
@property (nonatomic) BOOL lockInterfaceRotation;
@property (nonatomic) id runtimeErrorHandlingObserver;


- (void)initialize;

- (void)startCameraPreview;
- (void)stopCameraPreview;

- (void)startDeviceMotion;
- (void)stopDeviceMotion;

- (void)startDisplayLink;
- (void)stopDisplayLink;
- (void)onDisplayLink:(id)sender;

- (void)updatePlacesOfInterestCoordinates;




@end

@implementation AVCamPreviewView


#pragma mark - Init

- (void)initMapView
{
    [MAMapServices sharedServices].apiKey = APIKey;
    mapView = [[MAMapView alloc] init];
    mapView.delegate = self;
    //[self.view addSubview:_mapView];
    mapView.showsUserLocation = YES;
}

- (void)initSearch
{
    //MAMapServices is the root of other GaoDe Services? try delete it 2014-12-13
    [MAMapServices sharedServices].apiKey = APIKey;
    search = [[AMapSearchAPI alloc] initWithSearchKey:APIKey Delegate:self];
}

- (void)initialize
{
    captureView = self;
    createProjectionMatrixStd(projectionTransform, 60.0f*DEGREES_TO_RADIANS, self.bounds.size.width*1.0f / self.bounds.size.height,0.25f, 1000.0f);
}

//rewrite UIView's initWithFrame
- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self initialize];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self initialize];
    }
    return self;
}

#pragma mark - Start & Stop
- (void)dealloc
{
    [self stop];
    [captureView removeFromSuperview];
    if (placesOfInterestCoordinates != NULL) {
        free(placesOfInterestCoordinates);
    }
}

- (void)start
{
    [self startCameraPreview];
    [self initMapView];
    [self initSearch];
    [self startDeviceMotion];
    [self startDisplayLink];
}

- (void)stop
{
    [self stopCameraPreview];
    [self stopDeviceMotion];
    [self stopDisplayLink];
}

/*
 2015-01-29
 The startCameraPreview's flow chart
 1.AVCaptureDevice              defaultDeviceWithMediaType:AVMediaTypeVideo 代表抽象的硬件设备
 2.AVCaptureDeviceInput         initWithDevice:AVCaptureDevice  代表输入设备（可以是它的子类），它配置抽象硬件设备的ports
 3.AVCaptureSession             addInput:AVCaptureDeviceInput   它是input和output的桥梁。它协调着intput到output的数据传输
 4.AVCaptureVideoPreviewLayer   initWithSession:AVCaptureSession
 5.UIView.layer                 addSublayer:AVCaptureVideoPreviewLayer
 6.dispatch_async               AVCaptureSession
 */

- (void)startCameraPreview
{
    // Check for device authorization
    [self checkDeviceAuthorizationStatus];
    
    //1.create session layer
    captureSession = [[AVCaptureSession alloc] init];
    
    //2.create AVCaptureDevice
    AVCaptureDevice* camera = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (camera == nil) {
        return;
    }
    NSError *error = nil;
    
    //3.create AVCaptureDeviceInput initWithDevice:camera
    AVCaptureDeviceInput *newVideoInput = [[AVCaptureDeviceInput alloc] initWithDevice:camera error:&error];
    
    //4.add AVCaptureDeviceInput to AVCaptureSession
    [captureSession addInput:newVideoInput];
    
    captureLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:captureSession];
    captureLayer.frame = captureView.bounds;
    if ([captureLayer respondsToSelector:@selector(connection)]) {
        if ([captureLayer.connection isVideoOrientationSupported]) {
            [captureLayer.connection setVideoOrientation:AVCaptureVideoOrientationPortrait];
        }
    }
    [captureLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
    [captureView.layer addSublayer:captureLayer];
    
    // Start the session. This is done asychronously since -startRunning doesn't return until the session is running.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [captureSession startRunning];
    });
}

- (void)stopCameraPreview
{
//    
    [captureSession stopRunning];
    [captureLayer removeFromSuperlayer];
    captureSession = nil;
    captureLayer = nil;
}

- (void)startDeviceMotion
{
    motionManager = [[CMMotionManager alloc] init];
    
    // Tell CoreMotion to show the compass calibration HUD when required to provide true north-referenced attitude
    motionManager.showsDeviceMovementDisplay = YES;
    
    
    motionManager.deviceMotionUpdateInterval = 1.0 / 60.0;
    
    // New in iOS 5.0: Attitude that is referenced to true north
    [motionManager startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXTrueNorthZVertical];
}

- (void)stopDeviceMotion
{
    [motionManager stopDeviceMotionUpdates];
    motionManager = nil;
}

/*
 1> 包含QuartzCore框架
 2> 固定刷新频率（1秒钟刷新60次）
 3> 对刷新速度要求高，适合快刷新
 4> 创建displaylink
 
 // 返回一个CADisplayLink计时器对象，1秒内会调用60次target的sel方法，并且将CADisplayLink当做参数传入
 + (CADisplayLink *)displayLinkWithTarget:(id)target selector:(SEL)sel;
 5> 开始计时
 - (void)addToRunLoop:(NSRunLoop *)runloop forMode:(NSString *)mode;
 6> 停止计时
 - (void)invalidate;
 7> 刷帧间隔
 @property(readonly, nonatomic) CFTimeInterval duration;
 8> 控制暂停或者继续
 @property(getter=isPaused, nonatomic) BOOL paused;
 
 You can associate a display link with multiple input modes. While the run loop is executing in a mode you have specified, the display link notifies the target when new frames are required.
 
 The run loop retains the display link. To remove the display link from all run loops, send an invalidate message to the display link.
 
*/

#pragma mark - displayLink, auto redraw screen
- (void)startDisplayLink
{
    displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(onDisplayLink:)];
    [displayLink setFrameInterval:1];
    [displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
}

- (void)stopDisplayLink
{
    [displayLink invalidate];
    displayLink = nil;
}

- (void)onDisplayLink:(id)sender
{
    CMDeviceMotion *d = motionManager.deviceMotion;
    if (d != nil) {
        CMRotationMatrix r = d.attitude.rotationMatrix;
        transformFromCMRotationMatrixStd(cameraTransform, &r);
        [self setNeedsDisplay];
    }
}

- (void)drawRect:(CGRect)rect
{
    if (placesOfInterestCoordinates == nil) {
        return;
    }
    
    mat4f_t projectionCameraTransform;
    
    multiplyMatrixAndMatrixStd(projectionCameraTransform, projectionTransform, cameraTransform);
    int i = 0;
    for (PlaceOfInterest *poi in [placesOfInterest objectEnumerator]) {
        vec4f_t v;
        //        NSLog(@"poi.view: %@",poi.view);
        multiplyMatrixAndVectorStd(v, projectionCameraTransform, placesOfInterestCoordinates[i]);
        //        NSLog(@"v[]: %f, %f, %f, %f", v[0],v[1],v[2],v[3]);
        
        float x = (v[0] / v[3] + 1.0f) * 0.5f;
        float y = (v[1] / v[3] + 1.0f) * 0.5f;
        if (v[2] < 0.0f) {
            //			poi.view.center = CGPointMake(x*self.bounds.size.width, self.bounds.size.height-y*self.bounds.size.height);
            // because iOS device's origin(0,0) is on the top left of the screen, and the projection coordinate's origin
            // is at the bottom left of the screen, so we inverse y axis upsidedown, and keep x axis no change.
            poi.view.center = CGPointMake(x*self.bounds.size.width, self.bounds.size.height-y*self.bounds.size.height);
            poi.view.hidden = NO;
            
        } else {
            poi.view.hidden = YES;
        }
        i++;
    }
    
}

#pragma mark - UserLocationChanged delegate
//位置或者设备方向更新后，会调用此函数
- (void)mapView:(MAMapView *)mapView didUpdateUserLocation:(MAUserLocation *)userLocation updatingLocation:(BOOL)updatingLocation
{
    if (updatingLocation == true) {
        currentLocation = [userLocation.location copy];
        if (placesOfInterest != nil) {
            [self updatePlacesOfInterestCoordinates];
        }
    }
    
}

#pragma mark - placesOfInterest's getter&setter
@dynamic placesOfInterest;

- (void)setPlacesOfInterest:(NSArray *)pois
{
    for (PlaceOfInterest *poi in [placesOfInterest objectEnumerator]) {
        [poi.view removeFromSuperview];
    }
    
    placesOfInterest = pois;
    //    location = userLocation;
    if (currentLocation != nil) {
        [self updatePlacesOfInterestCoordinates];
    }
}

- (NSArray *)placesOfInterest
{
    return placesOfInterest;
}

- (void)removePlacesOfInterest:(NSMutableArray *)pois
{
    for (PlaceOfInterest *poi in [placesOfInterest objectEnumerator]) {
        [poi.view removeFromSuperview];
    }
}

- (void)updatePlacesOfInterestCoordinates
{
    NSLog(@"updatePlacesOfInterestCoordinates");
    if (placesOfInterestCoordinates != NULL) {
        free(placesOfInterestCoordinates);
    }
    placesOfInterestCoordinates = (vec4f_t *)malloc(sizeof(vec4f_t)*placesOfInterest.count);
    
    int i = 0;
    
    double myX, myY, myZ;
    //because AutoNavi's map sdk does not give altitude of poi, so set our altitude = 0 ,too. 2015-01-30
    //    latLonToEcef(currentLocation.coordinate.latitude, currentLocation.coordinate.longitude, currentLocation.altitude, &myX, &myY, &myZ);
    latLonToEcef(currentLocation.coordinate.latitude, currentLocation.coordinate.longitude, 0, &myX, &myY, &myZ);
    
    // Array of NSData instances, each of which contains a struct with the distance to a POI and the
    // POI's index into placesOfInterest
    // Will be used to ensure proper Z-ordering of UIViews
    typedef struct {
        float distance;
        int index;
    } DistanceAndIndex;
    NSMutableArray *orderedDistances = [NSMutableArray arrayWithCapacity:placesOfInterest.count];
    
    // Compute the world coordinates of each place-of-interest
    for (PlaceOfInterest *poi in [[self placesOfInterest] objectEnumerator]) {
        double poiX, poiY, poiZ, e, n, u;
        //        NSLog(@"curLocation: %@", currentLocation);
        //        NSLog(@"poi.poi.location.altitude: %f", poi.location.altitude);
        
        latLonToEcef(poi.location.coordinate.latitude, poi.location.coordinate.longitude, poi.location.altitude, &poiX, &poiY, &poiZ);
        ecefToEnu(currentLocation.coordinate.latitude, currentLocation.coordinate.longitude, myX, myY, myZ, poiX, poiY, poiZ, &e, &n, &u);
        
        placesOfInterestCoordinates[i][0] = (float)n;
        placesOfInterestCoordinates[i][1]= -(float)e;
        placesOfInterestCoordinates[i][2] = (float)u;//0.0f;
        placesOfInterestCoordinates[i][3] = 1.0f;
        
        // Add struct containing distance and index to orderedDistances
        DistanceAndIndex distanceAndIndex;
        distanceAndIndex.distance = sqrtf(n*n + e*e);
        distanceAndIndex.index = i;
        [orderedDistances insertObject:[NSData dataWithBytes:&distanceAndIndex length:sizeof(distanceAndIndex)] atIndex:i++];
    }
    
    
    // Sort orderedDistances in ascending order based on distance from the user
    [orderedDistances sortUsingComparator:(NSComparator)^(NSData *a, NSData *b) {
        const DistanceAndIndex *aData = (const DistanceAndIndex *)a.bytes;
        const DistanceAndIndex *bData = (const DistanceAndIndex *)b.bytes;
        if (aData->distance < bData->distance) {
            return NSOrderedAscending;
        } else if (aData->distance > bData->distance) {
            return NSOrderedDescending;
        } else {
            return NSOrderedSame;
        }
    }];
    // Add subviews in descending Z-order so they overlap properly
    for (NSData *d in [orderedDistances reverseObjectEnumerator]) {
        const DistanceAndIndex *distanceAndIndex = (const DistanceAndIndex *)d.bytes;
        PlaceOfInterest *poi = (PlaceOfInterest *)[placesOfInterest objectAtIndex:distanceAndIndex->index];
        [self addSubview:poi.view];
    }
}



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

#pragma mark - Device Configuration

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

#pragma mark - camera setup
#if false
- (void) initialSession
{
    //这个方法的执行我放在init方法里了
    self.session = [[AVCaptureSession alloc] init];
    self.videoInput = [[AVCaptureDeviceInput alloc] initWithDevice:[self backCamera] error:nil];
    //[self fronCamera]方法会返回一个AVCaptureDevice对象，因为我初始化时是采用前摄像头，所以这么写，具体的实现方法后面会介绍
    self.stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
    NSDictionary * outputSettings = [[NSDictionary alloc] initWithObjectsAndKeys:AVVideoCodecJPEG,AVVideoCodecKey, nil];
    //这是输出流的设置参数AVVideoCodecJPEG参数表示以JPEG的图片格式输出图片
    [self.stillImageOutput setOutputSettings:outputSettings];
    
    if ([self.session canAddInput:self.videoInput]) {
        [self.session addInput:self.videoInput];
    }
    if ([self.session canAddOutput:self.stillImageOutput]) {
        [self.session addOutput:self.stillImageOutput];
    }
    
}

- (AVCaptureDevice *)cameraWithPosition:(AVCaptureDevicePosition) position {
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in devices) {
        if ([device position] == position) {
            return device;
        }
    }
    return nil;
}


- (AVCaptureDevice *)frontCamera {
    return [self cameraWithPosition:AVCaptureDevicePositionFront];
}

- (AVCaptureDevice *)backCamera {
    return [self cameraWithPosition:AVCaptureDevicePositionBack];
}

- (void) setUpCameraLayer
{
//    if (_cameraAvaible == NO) return;
    
    if (self.previewLayer == nil) {
        self.previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.session];
        UIView * view = self.cameraShowView;
        CALayer * viewLayer = [view layer];
        [viewLayer setMasksToBounds:YES];
        
        CGRect bounds = [view bounds];
        [self.previewLayer setFrame:bounds];
        [self.previewLayer setVideoGravity:AVLayerVideoGravityResizeAspect];
        
        [viewLayer insertSublayer:self.previewLayer below:[[viewLayer sublayers] objectAtIndex:0]];
        
    }
}
#endif


@end




#pragma mark -
#pragma mark Math utilities definition STD Version

/*apple's matrix multiplication is vector(1*4)*matrix(4*4),vector in front, and matrix after, This
 looks wierd.
 v[](1x4) = POICoordinate[](1x4) * cameraTransform(4x4) * projectionTransform(4x4);
 v[](1x4) is clip coordinate.
 each of the vector/matrix is a transpose of a standard
 */

// Creates a projection matrix using the given y-axis field-of-view, aspect ratio, and near and far clipping planes
void createProjectionMatrixStd(mat4f_t mout, float fovy, float aspect, float zNear, float zFar)
{
    float f = 1.0f / tanf(fovy/2.0f);
    
    mout[0] = f / aspect;
    mout[1] = 0.0f;
    mout[2] = 0.0f;
    mout[3] = 0.0f;
    
    mout[4] = 0.0f;
    mout[5] = f;
    mout[6] = 0.0f;
    mout[7] = 0.0f;
    
    mout[8] = 0.0f;
    mout[9] = 0.0f;
    mout[10] = (zFar+zNear) / (zNear-zFar);
    mout[11] = 2 * zFar * zNear / (zNear-zFar);//-1.0f;
    
    mout[12] = 0.0f;
    mout[13] = 0.0f;
    mout[14] = -1.0f;//2 * zFar * zNear /  (zNear-zFar);
    mout[15] = 0.0f;
}



// Matrix-vector and matrix-matricx multiplication routines
void multiplyMatrixAndVectorStd(vec4f_t vout, const mat4f_t m, const vec4f_t v)
{
    vout[0] = m[0]*v[0] + m[1]*v[1] + m[2]*v[2] + m[3]*v[3];
    vout[1] = m[4]*v[0] + m[5]*v[1] + m[6]*v[2] + m[7]*v[3];
    vout[2] = m[8]*v[0] + m[9]*v[1] + m[10]*v[2] + m[11]*v[3];
    vout[3] = m[12]*v[0] + m[13]*v[1] + m[14]*v[2] + m[15]*v[3];
}

void multiplyMatrixAndMatrixStd(mat4f_t c, const mat4f_t a, const mat4f_t b)
{
    uint8_t col, row, i;
    memset(c, 0, 16*sizeof(float));
    for (row = 0; row < 4; row++) {
        for (col = 0; col < 4; col++) {
            for (i = 0; i < 4; i++) {
                c[row*4+col] += a[row*4+i]*b[col+i*4];//a[i*4+row]*b[col*4+i];
            }
        }
    }
    
}

// Initialize mout to be an affine transform corresponding to the same rotation specified by m
void transformFromCMRotationMatrixStd(vec4f_t mout, const CMRotationMatrix *m)
{
    /*
     r.m11: 0.975744, r.m12: -0.218411, r.m13: -0.014855,
     r.m21: 0.218153, r.m22: 0.975763, r.m23: -0.017207,
     r.m31: 0.018254, r.m32: 0.013549, r.m33: 0.999742
     */
    mout[0] = (float)m->m11;
    mout[1] = (float)m->m12;
    mout[2] = (float)m->m13;
    mout[3] = 0.0f;
    
    mout[4] = (float)m->m21;
    mout[5] = (float)m->m22;
    mout[6] = (float)m->m23;
    mout[7] = 0.0f;
    
    mout[8] = (float)m->m31;
    mout[9] = (float)m->m32;
    mout[10] = (float)m->m33;
    mout[11] = 0.0f;
    
    mout[12] = 0.0f;
    mout[13] = 0.0f;
    mout[14] = 0.0f;
    mout[15] = 1.0f;
    
}



#pragma mark -
#pragma mark Geodetic utilities definition

// References to ECEF and ECEF to ENU conversion may be found on the web.

// Converts latitude, longitude to ECEF coordinate system
void latLonToEcef(double lat, double lon, double alt, double *x, double *y, double *z)
{
    double clat = cos(lat * DEGREES_TO_RADIANS);
    double slat = sin(lat * DEGREES_TO_RADIANS);
    double clon = cos(lon * DEGREES_TO_RADIANS);
    double slon = sin(lon * DEGREES_TO_RADIANS);
    
    double N = WGS84_A / sqrt(1.0 - WGS84_E * WGS84_E * slat * slat);
    
    *x = (N + alt) * clat * clon;
    *y = (N + alt) * clat * slon;
    *z = (N * (1.0 - WGS84_E * WGS84_E) + alt) * slat;
}

// Coverts ECEF to ENU coordinates centered at given lat, lon
void ecefToEnu(double lat, double lon, double x, double y, double z, double xr, double yr, double zr, double *e, double *n, double *u)
{
    double clat = cos(lat * DEGREES_TO_RADIANS);
    double slat = sin(lat * DEGREES_TO_RADIANS);
    double clon = cos(lon * DEGREES_TO_RADIANS);
    double slon = sin(lon * DEGREES_TO_RADIANS);
    double dx = x - xr;
    double dy = y - yr;
    double dz = z - zr;
    
    *e = -slon*dx  + clon*dy;
    *n = -slat*clon*dx - slat*slon*dy + clat*dz;
    *u = clat*clon*dx + clat*slon*dy + slat*dz;
}
