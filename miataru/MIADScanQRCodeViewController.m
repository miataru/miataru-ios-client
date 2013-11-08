//
//  MIADScanQRCodeViewController.m
//  Miataru
//
//  Created by Daniel Kirstenpfad on 29.10.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import "MIADScanQRCodeViewController.h"
#import <AVFoundation/AVFoundation.h>

@interface MIADScanQRCodeViewController ()

@property (strong) AVCaptureSession *capture_session;

@property (strong) AVCaptureVideoPreviewLayer *VideoPreviewLayer;

@end

@implementation MIADScanQRCodeViewController

@synthesize VideoPreviewLayer;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self capture];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)CancelButtonPressed:(id)sender {

    [self dismissViewControllerAnimated:true completion:nil];
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    if (VideoPreviewLayer != nil)
    {
        if (VideoPreviewLayer.connection.supportsVideoOrientation)
        {
            [self setRightInterfaceOrientation:toInterfaceOrientation];
        }
    }
    
}

- (void)setRightInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
{
    if (VideoPreviewLayer != nil)
    {
        switch (toInterfaceOrientation)
            {
                case UIInterfaceOrientationPortrait:
                {
                    VideoPreviewLayer.connection.videoOrientation = AVCaptureVideoOrientationPortrait;
                    
                    CGRect layerRect = [[[self view] layer] bounds];
                    [VideoPreviewLayer setBounds:layerRect];
                    [VideoPreviewLayer setPosition:CGPointMake(CGRectGetMidX(layerRect),CGRectGetMidY(layerRect))];
                    VideoPreviewLayer.affineTransform = CGAffineTransformMakeRotation(0.0);

                    break;
                }
                case UIInterfaceOrientationPortraitUpsideDown:
                {
                    VideoPreviewLayer.connection.videoOrientation = AVCaptureVideoOrientationPortraitUpsideDown;
                    break;
                }
                case UIInterfaceOrientationLandscapeLeft:
                {
                    VideoPreviewLayer.connection.videoOrientation = AVCaptureVideoOrientationLandscapeLeft;
                    break;
                }
                case UIInterfaceOrientationLandscapeRight:
                {
                    VideoPreviewLayer.connection.videoOrientation = AVCaptureVideoOrientationLandscapeRight;
                    break;
                }
            }
    }
}

#pragma mark Capture

- (void)capture
{
    _capture_session = [[AVCaptureSession alloc] init];
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    NSError *error = nil;
    
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device
                                                                        error:&error];
    if (!input)
    {
        NSLog(@"Error: %@", error);
        return;
    }
    
    [_capture_session addInput:input];
    
    //Turn on point autofocus for middle of view
    [device lockForConfiguration:&error];
    CGPoint point = CGPointMake(0.5,0.5);
    [device setFocusPointOfInterest:point];
    [device setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
    [device unlockForConfiguration];
    
    //Add the metadata output device
    AVCaptureMetadataOutput *output = [[AVCaptureMetadataOutput alloc] init];
    [output setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
    [_capture_session addOutput:output];
    
    //You should check here to see if the session supports these types, if they aren't support you'll get an exception
    output.metadataObjectTypes = @[AVMetadataObjectTypeQRCode];
    output.rectOfInterest = self.CameraPreviewLayer.bounds;
    
    
    VideoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:_capture_session];
    VideoPreviewLayer.frame = self.CameraPreviewLayer.bounds;
    VideoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    
    [self.CameraPreviewLayer.layer insertSublayer:VideoPreviewLayer above:self.CameraPreviewLayer.layer];
   
    [self setRightInterfaceOrientation:[UIApplication sharedApplication].statusBarOrientation];
    
    [_capture_session startRunning];
}

#pragma mark AVCaptureMetadataOutputObjectsDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects fromConnection:(AVCaptureConnection *)connection
{
    for(AVMetadataObject *metadataObject in metadataObjects)
    {
        AVMetadataMachineReadableCodeObject *readableObject = (AVMetadataMachineReadableCodeObject *)metadataObject;
        if([metadataObject.type isEqualToString:AVMetadataObjectTypeQRCode])
        {
            NSLog(@"QR Code = %@", readableObject.stringValue);
            
            if ([readableObject.stringValue hasPrefix:@"miataru://"])
            {
                NSString *cutOff = [readableObject.stringValue substringFromIndex:10];
                
                // todo: return value...
                //[self.DeviceIDTextField setText:[cutOff uppercaseString]];
                [self.delegate ScanQRCodeControllerDidFinish:self scannedDeviceID:cutOff];
            }
            else
            {
                UIAlertView *messageAlert = [[UIAlertView alloc]
                                             initWithTitle:@"No Device QR Code" message:@"The code you scanned is not a Miataru QR device code." delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
                // Display Alert Message
                [messageAlert show];
            }
        }
    }
    
    [_capture_session stopRunning];
    [self dismissViewControllerAnimated:true completion:nil];
}



@end
