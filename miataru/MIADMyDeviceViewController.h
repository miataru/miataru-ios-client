//
//  MIADSecondViewController.h
//  miataru
//
//  Created by Daniel Kirstenpfad on 31.08.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <MessageUI/MFMailComposeViewController.h>

@interface MIADMyDeviceViewController : UIViewController <MFMailComposeViewControllerDelegate>

@property (weak, nonatomic) IBOutlet UIImageView *QRCodeView;

@property (weak, nonatomic) IBOutlet UILabel *DeviceIDLabel;

@end
