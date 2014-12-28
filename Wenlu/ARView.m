/*
     File: ARView.m
 Abstract: Augmented reality view. Displays a live camera feed with specified places-of-interest overlayed in the correct position based on the direction the user is looking. Uses Core Location to determine the user's location relative the places-of-interest and Core Motion to determine the direction the user is looking.
  Version: 1.0
 */

#import "ARView.h"
#import "PlaceOfInterest.h"
//#import "ViewController.h"

#import <AVFoundation/AVFoundation.h>
#import <MAMapKit/MAMapKit.h>
#import <AMapSearchKit/AMapSearchAPI.h>

#pragma mark -
#pragma mark Math utilities declaration

#define DEGREES_TO_RADIANS (M_PI/180.0)
#define RADIANS_TO_DEGREES (180.0/M_PI)

#define APIKey  @"1648f9781b1ce1387c2127536b332c12"
#define AUTONAVI
//#define IOS_MATRIX_VECTOR

typedef float mat4f_t[16];	// 4x4 matrix in column major order
typedef float vec4f_t[4];	// 4D vector




// Creates a projection matrix using the given y-axis field-of-view, aspect ratio, and near and far clipping planes
void createProjectionMatrixStd(mat4f_t mout, float fovy, float aspect, float zNear, float zFar);

// Matrix-vector and matrix-matricx multiplication routines
void multiplyMatrixAndVectorStd(vec4f_t vout, const mat4f_t m, const vec4f_t v);
void multiplyMatrixAndMatrixStd(mat4f_t c, const mat4f_t a, const mat4f_t b);

// Initialize mout to be an affine transform corresponding to the same rotation specified by m
void transformFromCMRotationMatrixStd(vec4f_t mout, const CMRotationMatrix *m);

//#endif



#pragma mark -
#pragma mark Geodetic utilities declaration

#define WGS84_A	(6378137.0)				// WGS 84 semi-major axis constant in meters
#define WGS84_E (8.1819190842622e-2)	// WGS 84 eccentricity

// Converts latitude, longitude to ECEF coordinate system
void latLonToEcef(double lat, double lon, double alt, double *x, double *y, double *z);

// Coverts ECEF to ENU coordinates centered at given lat, lon
void ecefToEnu(double lat, double lon, double x, double y, double z, double xr, double yr, double zr, double *e, double *n, double *u);

#pragma mark -
#pragma mark ARView extension

@interface ARView () <AMapSearchDelegate,MAMapViewDelegate>
{
	UIView *captureView;
	AVCaptureSession *captureSession;
	AVCaptureVideoPreviewLayer *captureLayer;
	
	CADisplayLink *displayLink;
	CMMotionManager *motionManager;
	CLLocationManager *locationManager;
    double currentYaw;
    double oldYaw;
#ifndef AUTONAVI
	CLLocation *location;
#endif
	NSArray *placesOfInterest;
	mat4f_t projectionTransform;
	mat4f_t cameraTransform;	
	vec4f_t *placesOfInterestCoordinates;
    
    MAMapView *mapView;
    AMapSearchAPI *search;
    CLLocation *currentLocation;
}

- (void)initialize;

- (void)startCameraPreview;
- (void)stopCameraPreview;

#ifndef AUTONAVI
- (void)startLocation;
- (void)stopLocation;
#endif

- (void)startDeviceMotion;
- (void)stopDeviceMotion;

- (void)startDisplayLink;
- (void)stopDisplayLink;

- (void)updatePlacesOfInterestCoordinates;

- (void)onDisplayLink:(id)sender;
#ifndef AUTONAVI
- (void)locationManager:(CLLocationManager *)manager didUpdateToLocation:(CLLocation *)newLocation fromLocation:(CLLocation *)oldLocation;
#endif
@end






@implementation ARView

#pragma mark - AutoNavi & Adi's map api


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

- (void)mapView:(MAMapView *)mapView didUpdateUserLocation:(MAUserLocation *)userLocation updatingLocation:(BOOL)updatingLocation
{
//    NSLog(@"userLocation: %@", userLocation.location);
    if (updatingLocation == true) {
        currentLocation = [userLocation.location copy];
//        NSLog(@"curLocation: %@", currentLocation);
//        NSLog(@"curLocation.altitude: %f", currentLocation.altitude);
        //    NSLog(@"ARViewlocation: %@", location);
        if (placesOfInterest != nil) {
            [self updatePlacesOfInterestCoordinates];
        }
    }

}

#pragma mark -
#pragma mark ARView implementation


@dynamic placesOfInterest;

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
#ifndef AUTONAVI
	[self startLocation];
#endif
    [self initMapView];
    [self initSearch];
	[self startDeviceMotion];
	[self startDisplayLink];
}

- (void)stop
{
	[self stopCameraPreview];
#ifndef AUTONAVI
	[self stopLocation];
#endif
	[self stopDeviceMotion];
	[self stopDisplayLink];
}

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

- (void)initialize
{
//    NSLog(@"ARView before: %@", self);
	captureView = [[UIView alloc] initWithFrame:self.bounds];
	captureView.bounds = self.bounds;
	[self addSubview:captureView];
	[self sendSubviewToBack:captureView];
	
	// Initialize projection matrix
//#ifdef
//	createProjectionMatrix(projectionTransform, 60.0f*DEGREES_TO_RADIANS, self.bounds.size.width*1.0f / self.bounds.size.height, 0.25f, 1000.0f);
    
    createProjectionMatrixStd(projectionTransform, 60.0f*DEGREES_TO_RADIANS, self.bounds.size.width*1.0f / self.bounds.size.height,0.25f, 1000.0f);

    
    NSLog(@"ARView after: %@", self);
}

- (void)startCameraPreview
{	
	AVCaptureDevice* camera = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
	if (camera == nil) {
		return;
	}
	
	captureSession = [[AVCaptureSession alloc] init];
	AVCaptureDeviceInput *newVideoInput = [[AVCaptureDeviceInput alloc] initWithDevice:camera error:nil];
	[captureSession addInput:newVideoInput];
	
	captureLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:captureSession];
	captureLayer.frame = captureView.bounds;
    if ([captureLayer respondsToSelector:@selector(connection)]) {
        if ([captureLayer.connection isVideoOrientationSupported]) {
            NSLog(@"isVideoOrientationSupported");
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
	[captureSession stopRunning];
	[captureLayer removeFromSuperlayer];
	captureSession = nil;
	captureLayer = nil;
}

#ifndef AUTONAVI
- (void)startLocation
{
	locationManager = [[CLLocationManager alloc] init];
    if ([locationManager respondsToSelector:@selector(requestWhenInUseAuthorization)]) {
        [locationManager requestWhenInUseAuthorization];
    }
	locationManager.delegate = self;
	locationManager.distanceFilter = 100.0;
	[locationManager startUpdatingLocation];
}

- (void)stopLocation
{
	[locationManager stopUpdatingLocation];
	locationManager = nil;
}

#endif
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

//#warning This is static test userLocation coordinate, should replace with realtime data.
#define LATITUDE_GAODE      36.67825978
#define LONGTITUDE_GAODE    117.05896659

- (void)updatePlacesOfInterestCoordinates
{
    NSLog(@"updatePlacesOfInterestCoordinates");
	if (placesOfInterestCoordinates != NULL) {
		free(placesOfInterestCoordinates);
	}
	placesOfInterestCoordinates = (vec4f_t *)malloc(sizeof(vec4f_t)*placesOfInterest.count);
			
	int i = 0;
    
	double myX, myY, myZ;
	latLonToEcef(currentLocation.coordinate.latitude, currentLocation.coordinate.longitude, currentLocation.altitude, &myX, &myY, &myZ);

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

- (void)onDisplayLink:(id)sender
{
	CMDeviceMotion *d = motionManager.deviceMotion;
//    NSLog(@"motionManager: %@",motionManager);
	if (d != nil) {
		CMRotationMatrix r = d.attitude.rotationMatrix;
        currentYaw = d.attitude.yaw;
#if false
        NSLog(@"motionManager.attitude: %@",d.attitude);
//        NSLog(@")
        NSLog(@"motionManager.quaternion: w: %f, x: %f, y: %f, z: %f",
              d.attitude.quaternion.w, d.attitude.quaternion.x, d.attitude.quaternion.y, d.attitude.quaternion.z);
        NSLog(@"CMRotationMatrix: \nr.m11: %f, r.m12: %f, r.m13: %f, \nr.m21: %f, r.m22: %f, r.m23: %f, \nr.m31: %f, r.m32: %f, r.m33: %f",
              r.m11,r.m12,r.m13,
              r.m21,r.m22,r.m23,
              r.m31,r.m32,r.m33);
#endif

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
#if false
    NSLog(@"projectionCameraTransform");
    for (int i = 0; i<4; i++) {
        NSLog(@"%f %f %f %f",projectionCameraTransform[i*4],projectionCameraTransform[i*4+1],projectionCameraTransform[i*4+2],projectionCameraTransform[i*4+3]);
    }
    
    NSLog(@"projectionTransform");
    for (int i = 0; i<4; i++) {
        NSLog(@"%f %f %f %f",projectionTransform[i*4],projectionTransform[i*4+1],projectionTransform[i*4+2],projectionTransform[i*4+3]);
    }
    
    NSLog(@"projectionTransform");
    for (int i = 0; i<4; i++) {
        NSLog(@"%f %f %f %f",cameraTransform[i*4],cameraTransform[i*4+1],cameraTransform[i*4+2],cameraTransform[i*4+3]);
    }
#endif
	int i = 0;
    static BOOL coYaw = true;
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
        oldYaw = currentYaw;
        coYaw = !coYaw;
		i++;
	}

}
#ifndef AUTONAVI
- (void)locationManager:(CLLocationManager *)manager didUpdateToLocation:(CLLocation *)newLocation fromLocation:(CLLocation *)oldLocation
{
//    location = currentLocation;
	location = newLocation;
//    location = self.locationGaode;
    NSLog(@"ARViewlocation: %@", location);
	if (placesOfInterest != nil) {
		[self updatePlacesOfInterestCoordinates];
	}	
}
#endif

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

@end




#pragma mark -
#pragma mark Math utilities definition




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
#ifdef IOS_MATRIX_VECTOR

    
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
    mout[11] = -1.0f;
    
    mout[12] = 0.0f;
    mout[13] = 0.0f;
    mout[14] = 2 * zFar * zNear /  (zNear-zFar);
    mout[15] = 0.0f;
#else
    
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
#endif
}



// Matrix-vector and matrix-matricx multiplication routines
void multiplyMatrixAndVectorStd(vec4f_t vout, const mat4f_t m, const vec4f_t v)
{
#ifdef IOS_MATRIX_VECTOR
    vout[0] = m[0]*v[0] + m[4]*v[1] + m[8]*v[2] + m[12]*v[3];
    vout[1] = m[1]*v[0] + m[5]*v[1] + m[9]*v[2] + m[13]*v[3];
    vout[2] = m[2]*v[0] + m[6]*v[1] + m[10]*v[2] + m[14]*v[3];
    vout[3] = m[3]*v[0] + m[7]*v[1] + m[11]*v[2] + m[15]*v[3];
#else
    vout[0] = m[0]*v[0] + m[1]*v[1] + m[2]*v[2] + m[3]*v[3];
    vout[1] = m[4]*v[0] + m[5]*v[1] + m[6]*v[2] + m[7]*v[3];
    vout[2] = m[8]*v[0] + m[9]*v[1] + m[10]*v[2] + m[11]*v[3];
    vout[3] = m[12]*v[0] + m[13]*v[1] + m[14]*v[2] + m[15]*v[3];
#endif
}

void multiplyMatrixAndMatrixStd(mat4f_t c, const mat4f_t a, const mat4f_t b)
{
    uint8_t col, row, i;
    memset(c, 0, 16*sizeof(float));
#ifdef IOS_MATRIX_VECTOR
    
    for (col = 0; col < 4; col++) {
        for (row = 0; row < 4; row++) {
            for (i = 0; i < 4; i++) {
                c[col*4+row] += a[i*4+row]*b[col*4+i];
            }
        }
    }
#else
    
    for (row = 0; row < 4; row++) {
        for (col = 0; col < 4; col++) {
            for (i = 0; i < 4; i++) {
                c[row*4+col] += a[row*4+i]*b[col+i*4];//a[i*4+row]*b[col*4+i];
            }
        }
    }

#endif
}

// Initialize mout to be an affine transform corresponding to the same rotation specified by m
void transformFromCMRotationMatrixStd(vec4f_t mout, const CMRotationMatrix *m)
{
    /*
     r.m11: 0.975744, r.m12: -0.218411, r.m13: -0.014855,
     r.m21: 0.218153, r.m22: 0.975763, r.m23: -0.017207,
     r.m31: 0.018254, r.m32: 0.013549, r.m33: 0.999742
     */
#if false
#ifdef IOS_MATRIX_VECTOR
    
    mout[0] = 0.975744;
    mout[1] = 0.218153;
    mout[2] = 0.018254;
    mout[3] = 0.0f;
    
    mout[4] = -0.218411;
    mout[5] = 0.975763;
    mout[6] = 0.013549;
    mout[7] = 0.0f;
    
    mout[8] = -0.014855;
    mout[9] = -0.017207;
    mout[10] = 0.999742;
    mout[11] = 0.0f;
    
    mout[12] = 0.0f;
    mout[13] = 0.0f;
    mout[14] = 0.0f;
    mout[15] = 1.0f;
    
#else
    
    mout[0] = 0.975744f;
    mout[1] = -0.218411;
    mout[2] = -0.014855;
    mout[3] = 0.0f;
    
    mout[4] = 0.218153;
    mout[5] = 0.975763;
    mout[6] = -0.017207;
    mout[7] = 0.0f;
    
    mout[8] = 0.018254;
    mout[9] = 0.013549;
    mout[10] = 0.999742;
    mout[11] = 0.0f;
    
    mout[12] = 0.0f;
    mout[13] = 0.0f;
    mout[14] = 0.0f;
    mout[15] = 1.0f;
#endif
#endif
#ifdef IOS_MATRIX_VECTOR
    mout[0] = (float)m->m11;
    mout[1] = (float)m->m21;
    mout[2] = (float)m->m31;
    mout[3] = 0.0f;
    
    mout[4] = (float)m->m12;
    mout[5] = (float)m->m22;
    mout[6] = (float)m->m32;
    mout[7] = 0.0f;
    
    mout[8] = (float)m->m13;
    mout[9] = (float)m->m23;
    mout[10] = (float)m->m33;
    mout[11] = 0.0f;
    
    mout[12] = 0.0f;
    mout[13] = 0.0f;
    mout[14] = 0.0f;
    mout[15] = 1.0f;
#else
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
    

#endif

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
