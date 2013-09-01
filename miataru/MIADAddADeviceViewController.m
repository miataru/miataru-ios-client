//
//  MIADAddADeviceViewController.m
//  miataru
//
//  Created by Daniel Kirstenpfad on 31.08.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import "MIADAddADeviceViewController.h"

@interface MIADAddADeviceViewController ()

@end

@implementation MIADAddADeviceViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)CancelButtonPressed:(id)sender {
    
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)SaveButtonPressed:(id)sender {
    
    // run checks and if successful add to Devices Table...
    
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
