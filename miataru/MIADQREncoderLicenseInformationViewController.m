//
//  MIADQREncoderLicenseInformationViewController.m
//  Miataru
//
//  Created by Daniel Kirstenpfad on 25.09.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import "MIADQREncoderLicenseInformationViewController.h"

@interface MIADQREncoderLicenseInformationViewController ()

@end

@implementation MIADQREncoderLicenseInformationViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
- (IBAction)DoneButtonPressed:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
