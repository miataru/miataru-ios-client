//
//  MIADFirstViewController.h
//  miataru
//
//  Created by Daniel Kirstenpfad on 31.08.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>

@interface MIADDevicesViewController : UIViewController <CLLocationManagerDelegate>

@property (strong, nonatomic) IBOutlet UISwitch *switchEnabled;

- (IBAction)accuracyChanged:(id)sender;
- (IBAction)enabledStateChanged:(id)sender;


@end
