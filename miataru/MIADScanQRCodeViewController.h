//
//  MIADScanQRCodeViewController.h
//  Miataru
//
//  Created by Daniel Kirstenpfad on 29.10.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@interface MIADScanQRCodeViewController : UIViewController <AVCaptureMetadataOutputObjectsDelegate>

@property (weak, nonatomic) IBOutlet UIView *CameraPreviewLayer;

@end
