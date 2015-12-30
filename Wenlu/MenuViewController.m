//
//  MenuViewController.m
//  AVCam
//
//  Created by 王增迪 on 12/25/14.
//  Copyright (c) 2014 Apple Inc. All rights reserved.
//

#import "MenuViewController.h"
#import "AVCamViewController.h"
#import "MapCamViewController.h"
#import "Cell.h"

#import <MAMapKit/MAMapKit.h>
#import <AMapSearchKit/AMapSearchAPI.h>

#define APIKey  @"1648f9781b1ce1387c2127536b332c12"

#define kDefaultLocationZoomLevel       16.1
#define kDefaultControlMargin           22

@interface MenuViewController ()<MAMapViewDelegate, AMapSearchDelegate, UITableViewDataSource, UITableViewDelegate,UICollectionViewDataSource,UICollectionViewDelegate, UITextFieldDelegate>

@property (weak, nonatomic) IBOutlet UIBarButtonItem *searchBarButton;
@property (weak, nonatomic) IBOutlet UITextField *searchTextField;


@property (nonatomic, strong) MAMapView *mapView;
@property (nonatomic, strong) AMapSearchAPI *search;

@property (nonatomic, strong) CLLocation *currentLocation;
@property (nonatomic, strong) UIButton *locationButton;

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *pois;

@property (nonatomic, strong) NSMutableArray *annotations;

@end

@implementation MenuViewController



-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"Show Way"]) {
        if ([segue.destinationViewController isKindOfClass:[AVCamViewController class]]) {
//            TextStatsViewController *tsvc = (TextStatsViewController *)segue.destinationViewController;
  //          tsvc.textToAnalyze = self.body.textStorage;
        }
    }
    else if ([segue.identifier isEqualToString:@"Show MyCam"]) {
        NSLog(@"prepareForSegue");
        if ([segue.destinationViewController isKindOfClass:[MapCamViewController class]]) {
            //Let the pointer mcvc points to destinationViewController, we don't create a new object but just a point. 2015-01-24
            MapCamViewController *mcvc = (MapCamViewController *)segue.destinationViewController;
            mcvc.places = self.pois;
        }
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];


    [self initEvent];
    [self initMapView];
    [self initSearch];
    [self initControls];
    [self initTableView];
    [self initAttributes];
    self.searchTextField.delegate = self;
}

- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
}

- (void)initEvent
{
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *plistPath = [bundle pathForResource:@"events"
                                           ofType:@"plist"];
    //获取属性列表文件中的全部数据
    NSArray *array = [[NSArray alloc] initWithContentsOfFile:plistPath];
    self.events = array;
}


#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    return [self.events count] / 2;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return 2;
}
#if true
- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    NSLog(@"CELL FOR output");

    Cell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"Cell" forIndexPath:indexPath];
    NSDictionary *event = [self.events objectAtIndex:(indexPath.section*2 + indexPath.row)];
    cell.label.text = [event objectForKey:@"name"];
    cell.imageView.image = [UIImage imageNamed:[event objectForKey:@"image"]];

    return cell;
}
#endif

#pragma mark - UICollectionViewDelegate
- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    NSDictionary *event = [self.events objectAtIndex:(indexPath.section*2 + indexPath.row)];

    NSLog(@"select event name : %@", [event objectForKey:@"name"]);
    if (self.currentLocation == nil || self.search == nil)
    {
        NSLog(@"search failed");
        return;
    }
    
    NSString *keyWords = [event objectForKey:@"name"];
    if (keyWords.length > 0) {
        [self searchAction:keyWords];
    }
    
}

#pragma mark - AutoNavi api


- (void)initMapView
{
    [MAMapServices sharedServices].apiKey = APIKey;
    self.mapView = [[MAMapView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.view.bounds), CGRectGetHeight(self.view.bounds) * 0.5)];
    
    self.mapView.delegate = self;
    self.mapView.compassOrigin = CGPointMake(self.mapView.compassOrigin.x, kDefaultControlMargin);
    self.mapView.scaleOrigin = CGPointMake(self.mapView.scaleOrigin.x, kDefaultControlMargin);
    NSLog(@"self.view: %@",self.view);
    
//    [self.view addSubview:self.mapView];
    
    self.mapView.showsUserLocation = YES;
}

- (void)initSearch
{
    self.search = [[AMapSearchAPI alloc] initWithSearchKey:APIKey Delegate:self];
}

- (void)initControls
{
    self.locationButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.locationButton.frame = CGRectMake(kDefaultControlMargin, CGRectGetHeight(self.mapView.bounds) - 80, 40, 40);
    self.locationButton.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;
    self.locationButton.backgroundColor = [UIColor whiteColor];
    
    [self.locationButton addTarget:self action:@selector(locateAction) forControlEvents:UIControlEventTouchUpInside];
    
    [self.locationButton setImage:[UIImage imageNamed:@"location_no"] forState:UIControlStateNormal];
    
    [self.mapView addSubview:self.locationButton];
    
    //
    UIButton *searchButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    searchButton.frame = CGRectMake(80, CGRectGetHeight(self.mapView.bounds) - 80, 40, 40);
    searchButton.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;
    searchButton.backgroundColor = [UIColor whiteColor];
    [searchButton setImage:[UIImage imageNamed:@"search"] forState:UIControlStateNormal];
    
    [searchButton addTarget:self action:@selector(searchAction) forControlEvents:UIControlEventTouchUpInside];
    
    [self.mapView addSubview:searchButton];
    
}

- (void)initAttributes
{
    self.annotations = [NSMutableArray array];
    self.pois = nil;
}

- (void)initTableView
{
    CGFloat halfHeight = CGRectGetHeight(self.view.bounds) * 0.5;
    
    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, halfHeight, CGRectGetWidth(self.view.bounds), halfHeight) style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    
//    [self.view addSubview:self.tableView];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Helpers

- (void)searchAction
{
    if (self.currentLocation == nil || self.search == nil)
    {
        NSLog(@"search failed");
        return;
    }
    
    AMapPlaceSearchRequest *request = [[AMapPlaceSearchRequest alloc] init];
    request.searchType = AMapSearchType_PlaceAround;
    request.location = [AMapGeoPoint locationWithLatitude:self.currentLocation.coordinate.latitude longitude:self.currentLocation.coordinate.longitude];
    
    request.keywords = @"餐饮";
    
    [self.search AMapPlaceSearch:request];
}

- (void)searchAction:(NSString *)keyWords
{
    if (self.currentLocation == nil || self.search == nil)
    {
        NSLog(@"search failed");
        return;
    }
    
    AMapPlaceSearchRequest *request = [[AMapPlaceSearchRequest alloc] init];
    request.searchType = AMapSearchType_PlaceAround;
    request.location = [AMapGeoPoint locationWithLatitude:self.currentLocation.coordinate.latitude longitude:self.currentLocation.coordinate.longitude];
    
    request.keywords = keyWords;
    
    [self.search AMapPlaceSearch:request];
}

- (void)locateAction
{
    if (self.mapView.userTrackingMode != MAUserTrackingModeFollow)
    {
        self.mapView.userTrackingMode = MAUserTrackingModeFollow;
        [self.mapView setZoomLevel:kDefaultLocationZoomLevel animated:YES];
    }
}

- (void)reGeoAction
{
    if (self.currentLocation)
    {
        AMapReGeocodeSearchRequest *request = [[AMapReGeocodeSearchRequest alloc] init];
        
        request.location = [AMapGeoPoint locationWithLatitude:self.currentLocation.coordinate.latitude longitude:self.currentLocation.coordinate.longitude];
        
        [self.search AMapReGoecodeSearch:request];
    }
}

#pragma mark - AMapSearchDelegate

- (void)searchRequest:(id)request didFailWithError:(NSError *)error
{
    NSLog(@"request :%@, error :%@", request, error);
}

- (void)onReGeocodeSearchDone:(AMapReGeocodeSearchRequest *)request response:(AMapReGeocodeSearchResponse *)response
{
    NSLog(@"response :%@", response);
    
    NSString *title = response.regeocode.addressComponent.city;
    if (title.length == 0)
    {
        // 直辖市的city为空，取province
        title = response.regeocode.addressComponent.province;
    }
    
    // 更新我的位置title
    self.mapView.userLocation.title = title;
    self.mapView.userLocation.subtitle = response.regeocode.formattedAddress;
}

- (void)onPlaceSearchDone:(AMapPlaceSearchRequest *)request response:(AMapPlaceSearchResponse *)response
{
    NSLog(@"request: %@", request);
    NSLog(@"response: %@", response);
    
    if (response.pois.count > 0)
    {
        self.pois = response.pois;
        
        [self.tableView reloadData];
        
        // 清空标注
        [self.mapView removeAnnotations:self.annotations];
        [self.annotations removeAllObjects];
        
        [self performSegueWithIdentifier:@"Show MyCam" sender:self];
        NSLog(@"onPlaceSearchDone");
    }
}


#pragma mark - MAMapViewDelegate

- (MAAnnotationView *)mapView:(MAMapView *)mapView viewForAnnotation:(id<MAAnnotation>)annotation
{
    if ([annotation isKindOfClass:[MAPointAnnotation class]])
    {
        static NSString *reuseIndetifier = @"annotationReuseIndetifier";
        MAPinAnnotationView *annotationView = (MAPinAnnotationView*)[mapView dequeueReusableAnnotationViewWithIdentifier:reuseIndetifier];
        if (annotationView == nil)
        {
            annotationView = [[MAPinAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:reuseIndetifier];
        }
        annotationView.canShowCallout = YES;
        
        return annotationView;
    }
    
    return nil;
}

- (void)mapView:(MAMapView *)mapView didChangeUserTrackingMode:(MAUserTrackingMode)mode animated:(BOOL)animated
{
    // 修改定位按钮状态
    if (mode == MAUserTrackingModeNone)
    {
        [self.locationButton setImage:[UIImage imageNamed:@"location_no"] forState:UIControlStateNormal];
    }
    else
    {
        [self.locationButton setImage:[UIImage imageNamed:@"location_yes"] forState:UIControlStateNormal];
    }
}

- (void)mapView:(MAMapView *)mapView didUpdateUserLocation:(MAUserLocation *)userLocation updatingLocation:(BOOL)updatingLocation
{
    //    NSLog(@"userLocation: %@", userLocation.location);
    self.currentLocation = [userLocation.location copy];
}

- (void)mapView:(MAMapView *)mapView didSelectAnnotationView:(MAAnnotationView *)view
{
    // 选中定位annotation的时候进行逆地理编码查询
    if ([view.annotation isKindOfClass:[MAUserLocation class]])
    {
        [self reGeoAction];
    }
}

#pragma mark - UITableViewDataSource

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cellIdentifier = @"cellIdentifier";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    
    if (cell == nil)
    {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellIdentifier];
    }
    
    AMapPOI *poi = self.pois[indexPath.row];
    
    cell.textLabel.text = poi.name;
    cell.detailTextLabel.text = poi.address;
    
    return cell;
    
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.pois.count;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    // 为点击的poi点添加标注
    AMapPOI *poi = self.pois[indexPath.row];
    
    MAPointAnnotation *annotation = [[MAPointAnnotation alloc] init];
    annotation.coordinate = CLLocationCoordinate2DMake(poi.location.latitude, poi.location.longitude);
    annotation.title = poi.name;
    annotation.subtitle = poi.address;
    
    [self.mapView addAnnotation:annotation];
    
    [self.annotations addObject:annotation];
    
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

#pragma mark input delegate

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField
{
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField
{
    
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    if (![textField.text isEqualToString:@""]) {
        [self searchAction:textField.text];
    }
    [textField resignFirstResponder];
    return YES;
}

@end
