//
//  MIADDeviceEditViewController.m
//  miataru
//
//  Created by Daniel Kirstenpfad on 16.11.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import "MIADDeviceEditViewController.h"

@interface MIADDeviceEditViewController ()

@end

@implementation MIADDeviceEditViewController

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
