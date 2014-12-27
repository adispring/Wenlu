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

@interface MenuViewController ()

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
        if ([segue.destinationViewController isKindOfClass:[MapCamViewController class]]) {
            //            TextStatsViewController *tsvc = (TextStatsViewController *)segue.destinationViewController;
            //          tsvc.textToAnalyze = self.body.textStorage;
        }
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
