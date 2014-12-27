//
//  SearchPOI.m
//  Wenlu
//
//  Created by 王增迪 on 12/26/14.
//  Copyright (c) 2014 Wang Zengdi. All rights reserved.
//

#import "SearchPOI.h"
#import <MAMapKit/MAMapKit.h>
#import <AMapSearchKit/AMapSearchAPI.h>

#define APIKey  @"1648f9781b1ce1387c2127536b332c12"

#define kDefaultLocationZoomLevel       16.1
#define kDefaultControlMargin           22

@interface SearchPOI ()<MAMapViewDelegate, AMapSearchDelegate>
{
}

@property (nonatomic, strong) MAMapView *_mapView;
@property (nonatomic, strong) AMapSearchAPI *_search;

@property (nonatomic, strong) CLLocation *_currentLocation;
@property (nonatomic, strong) UIButton *_locationButton;

@property (nonatomic, strong) UITableView *_tableView;
@property (nonatomic, strong) NSArray *_pois;

@property (nonatomic, strong) NSMutableArray *_annotations;
@end

@implementation SearchPOI

@end
