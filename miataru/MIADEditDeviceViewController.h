//
//  MIADEditDeviceViewController.h
//  miataru
//   kmklmlkm
//  Created by Daniel Kirstenpfad on 20.11.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "KnownDevice.h"
#import "NEOColorPickerViewController.h"

@protocol MIADEditADeviceTableViewControllerDelegate;

@interface MIADEditDeviceViewController : UITableViewController <NEOColorPickerViewControllerDelegate>

@property (strong) KnownDevice *EditDevice;
@property (weak, nonatomic) IBOutlet UITextField *DeviceNameTextfield;
@property (weak, nonatomic) IBOutlet UITextField *DeviceIDTextField;

@property (weak) id<MIADEditADeviceTableViewControllerDelegate> delegate;
@property (weak, nonatomic) IBOutlet UITextField *test;

@property (weak, nonatomic) IBOutlet UITableViewCell *ColorPickerTableCell;

@end


@protocol MIADEditADeviceTableViewControllerDelegate <NSObject>

- (void) editADeviceTableViewControllerDidFinish:(MIADEditDeviceViewController*)inController knownDevice:(KnownDevice*)inDevice;

@end
