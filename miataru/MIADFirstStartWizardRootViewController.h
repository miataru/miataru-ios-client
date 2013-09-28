//
//  MIADFirstStartWizardRootViewController.h
//  Miataru
//
//  Created by Daniel Kirstenpfad on 28.09.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface MIADFirstStartWizardRootViewController : UIViewController<UIPageViewControllerDelegate>

@property (strong, nonatomic) UIPageViewController *pageViewController;

@property (weak, nonatomic) IBOutlet UISwitch *ReportLocationToServerUISwitch;
@property (weak, nonatomic) IBOutlet UISwitch *StoreLocationHistoryUISwitch;

@end
