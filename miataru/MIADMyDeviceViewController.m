//
//  MIADSecondViewController.m
//  miataru
//
//  Created by Daniel Kirstenpfad on 31.08.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import "MIADMyDeviceViewController.h"
#import <QREncoder/QREncoder.h>


//static const CGFloat kPadding = 10;

@interface MIADMyDeviceViewController ()
@property (strong) NSString *device_id;
@end

@implementation MIADMyDeviceViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self loadDeviceID];
    //NSString* deviceID = [UIDevice currentDevice].identifierForVendor.UUIDString;
    //NSString* deviceID = @"DBD02046-EAA5-40F2-8C3B-8C884893A57C-service.miataru.com";
    //NSString* deviceID = @"dbd02046-eaa5-40f2-8c3b-8c884893a57c";
	// Do any additional setup after loading the view, typically from a nib.
    NSString *deviceID = [NSString stringWithFormat:@"miataru://%@", [self.device_id lowercaseString]];
    
    UIImage* image = [QREncoder encode:deviceID size:4 correctionLevel:QRCorrectionLevelMedium scale:6];
    [self.QRCodeView layer].magnificationFilter = kCAFilterNearest;
    [self.QRCodeView setImage:image];
    
    self.DeviceIDLabel.text = self.device_id;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark Send-eMail

- (IBAction)ActionButtonPressed:(id)sender {
    if ([MFMailComposeViewController canSendMail])
    {
        MFMailComposeViewController *controller = [[MFMailComposeViewController alloc] init];
        controller.mailComposeDelegate = self;
        //[controller.navigationBar setBackgroundImage:[UIImage imageNamed:@"navigation_bg_iPhone.png"] forBarMetrics:UIBarMetricsDefault];
        //controller.navigationBar.tintColor = [UIColor colorWithRed:51.0/255.0 green:51.0/255.0 blue:51.0/255.0 alpha:1.0];
        [controller setSubject:@"my Miataru Device ID"];
        
        [controller setMessageBody:[NSString stringWithFormat:@"Hello,<br/> this is my Miataru Device ID: %@ <br><p>To view this device in any browser you may use this <a href='http://miataru.com/client/#%@'>link.</a><br>", [self.device_id uppercaseString], [self.device_id uppercaseString]] isHTML:YES];
        [controller setToRecipients:[NSArray arrayWithObjects:@"",nil]];
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        pasteboard.image = self.QRCodeView.image;
        NSData *imageData = [NSData dataWithData:UIImagePNGRepresentation(self.QRCodeView.image)];
        [controller addAttachmentData:imageData mimeType:@"image/png" fileName:@" "];
        [self presentViewController:controller animated:YES completion:NULL];
    }
    else{
        UIAlertView *alert=[[UIAlertView alloc] initWithTitle:@"sending email not possible" message:nil delegate:self cancelButtonTitle:@"ok" otherButtonTitles: nil] ;
        [alert show];
    }
}

-(void)mailComposeController:(MFMailComposeViewController*)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError*)error
{
    
//    [MailAlert show];
//    switch (result)
//    {
//        case MFMailComposeResultCancelled:
//            MailAlert.message = @"Email Cancelled";
//            break;
//        case MFMailComposeResultSaved:
//            MailAlert.message = @"Email Saved";
//            break;
//        case MFMailComposeResultSent:
//            MailAlert.message = @"Email Sent";
//            break;
//        case MFMailComposeResultFailed:
//            MailAlert.message = @"Email Failed";
//            break;
//        default:
//            MailAlert.message = @"Email Not Sent";
//            break;
//    }
    [self dismissViewControllerAnimated:YES completion:NULL];
//    [MailAlert show];
}


#pragma mark Persistent State for device ID

- (NSURL*)applicationDataDirectory {
    NSFileManager* sharedFM = [NSFileManager defaultManager];
    NSArray* possibleURLs = [sharedFM URLsForDirectory:NSApplicationSupportDirectory
                                             inDomains:NSUserDomainMask];
    NSURL* appSupportDir = nil;
    NSURL* appDirectory = nil;
    
    if ([possibleURLs count] >= 1) {
        // Use the first directory (if multiple are returned)
        appSupportDir = [possibleURLs objectAtIndex:0];
    }
    
    // If a valid app support directory exists, add the
    // app's bundle ID to it to specify the final directory.
    if (appSupportDir) {
        NSString* appBundleID = [[NSBundle mainBundle] bundleIdentifier];
        appDirectory = [appSupportDir URLByAppendingPathComponent:appBundleID];
    }
    
    return appDirectory;
}


- (NSString*) pathToSavedDeviceID{
    NSURL *applicationSupportURL = [self applicationDataDirectory];
    
    if (! [[NSFileManager defaultManager] fileExistsAtPath:[applicationSupportURL path]]){
        
        NSError *error = nil;
        
        [[NSFileManager defaultManager] createDirectoryAtPath:[applicationSupportURL path]
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:&error];
        
        if (error){
            NSLog(@"error creating app support dir: %@", error);
        }
        
    }
    NSString *path = [[applicationSupportURL path] stringByAppendingPathComponent:@"deviceID.plist"];
    
    return path;
}

- (BOOL) CheckDeviceID{
    
    NSString *path = [self pathToSavedDeviceID];
    NSLog(@"CheckDeviceID: %@", path);
    
    
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}


- (void) loadDeviceID{
    
    NSString *path = [self pathToSavedDeviceID];
    NSLog(@"LoadDeviceID: %@", path);
    
    self.device_id = [NSKeyedUnarchiver unarchiveObjectWithFile:path];
}

@end
