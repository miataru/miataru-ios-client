//
//  MIADAddADeviceTableViewController.h
//  miataru
//
//  Created by Daniel Kirstenpfad on 08.09.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@class KnownDevice;

@protocol MIADAddADeviceTableViewControllerDelegate;

@interface MIADAddADeviceTableViewController : UITableViewController <UITableViewDelegate, AVCaptureMetadataOutputObjectsDelegate>

@property (weak) id<MIADAddADeviceTableViewControllerDelegate> delegate;

@end

@protocol MIADAddADeviceTableViewControllerDelegate <NSObject>

- (void) addADeviceTableViewControllerDidFinish:(MIADAddADeviceTableViewController*)inController knownDevice:(KnownDevice*)inDevice;

@end