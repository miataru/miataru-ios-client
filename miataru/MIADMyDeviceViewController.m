//
//  MIADSecondViewController.m
//  miataru
//
//  Created by Daniel Kirstenpfad on 31.08.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import "MIADMyDeviceViewController.h"
#import <QREncoder/QREncoder.h>

static const CGFloat kPadding = 10;

@interface MIADMyDeviceViewController ()

@end

@implementation MIADMyDeviceViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    //NSString* deviceID = [UIDevice currentDevice].identifierForVendor.UUIDString;
    //NSString* deviceID = @"DBD02046-EAA5-40F2-8C3B-8C884893A57C-service.miataru.com";
    //NSString* deviceID = @"dbd02046-eaa5-40f2-8c3b-8c884893a57c";
	// Do any additional setup after loading the view, typically from a nib.
    NSString *deviceID = [[UIDevice currentDevice].identifierForVendor.UUIDString lowercaseString];
    
    UIImage* image = [QREncoder encode:deviceID size:4 correctionLevel:QRCorrectionLevelMedium scale:6];
    [self.QRCodeView layer].magnificationFilter = kCAFilterNearest;
    [self.QRCodeView setImage:image];
    
    self.DeviceIDLabel.text = deviceID;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
