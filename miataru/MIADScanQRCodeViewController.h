//
//  MIADScanQRCodeViewController.h
//  Miataru
//
//  Created by Daniel Kirstenpfad on 29.10.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@protocol MIADScanQRCodeDelegate;

@interface MIADScanQRCodeViewController : UIViewController <AVCaptureMetadataOutputObjectsDelegate>

@property (weak, nonatomic) IBOutlet UIView *CameraPreviewLayer;

@property (weak) id<MIADScanQRCodeDelegate> delegate;

@end

@protocol MIADScanQRCodeDelegate <NSObject>

- (void) ScanQRCodeControllerDidFinish:(MIADScanQRCodeViewController*)inController scannedDeviceID:(NSString*)DeviceID;

@end