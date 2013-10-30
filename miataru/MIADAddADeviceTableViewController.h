//
//  MIADAddADeviceTableViewController.h
//  miataru
//
//  Created by Daniel Kirstenpfad on 08.09.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "MIADScanQRCodeViewController.h"

@class KnownDevice;

@protocol MIADAddADeviceTableViewControllerDelegate;

@interface MIADAddADeviceTableViewController : UITableViewController <UITableViewDelegate, MIADScanQRCodeDelegate>

@property (weak) id<MIADAddADeviceTableViewControllerDelegate> delegate;

- (void) addADeviceFromURLType:(NSString*)inDevice;

@end

@protocol MIADAddADeviceTableViewControllerDelegate <NSObject>

- (void) addADeviceTableViewControllerDidFinish:(MIADAddADeviceTableViewController*)inController knownDevice:(KnownDevice*)inDevice;

@end