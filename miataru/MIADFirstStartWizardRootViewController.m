//
//  MIADFirstStartWizardRootViewController.m
//  Miataru
//
//  Created by Daniel Kirstenpfad on 28.09.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import "MIADFirstStartWizardRootViewController.h"

@interface MIADFirstStartWizardRootViewController ()

@end

@implementation MIADFirstStartWizardRootViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}
- (IBAction)button:(id)sender {
     [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
}

- (void)viewDidAppear:(BOOL)animated
{
    //[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
