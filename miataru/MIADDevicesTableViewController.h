//
//  MIADDevicesTableViewController.h
//  miataru
//
//  Created by Daniel Kirstenpfad on 07.09.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "MIADAddADeviceTableViewController.h"
#import "MIADEditDeviceViewController.h"

@interface MIADDevicesTableViewController : UITableViewController <UITableViewDelegate, UITableViewDataSource, MIADAddADeviceTableViewControllerDelegate, MIADEditADeviceTableViewControllerDelegate>

@property (strong, nonatomic) IBOutlet UITableView *KnownDevicesTableView;

@end
