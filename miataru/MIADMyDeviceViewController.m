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

@end

@implementation MIADMyDeviceViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    //NSString* deviceID = [UIDevice currentDevice].identifierForVendor.UUIDString;
    //NSString* deviceID = @"DBD02046-EAA5-40F2-8C3B-8C884893A57C-service.miataru.com";
    //NSString* deviceID = @"dbd02046-eaa5-40f2-8c3b-8c884893a57c";
	// Do any additional setup after loading the view, typically from a nib.
    NSString *deviceID = [NSString stringWithFormat:@"miataru://%@", [[UIDevice currentDevice].identifierForVendor.UUIDString lowercaseString]];
    
    UIImage* image = [QREncoder encode:deviceID size:4 correctionLevel:QRCorrectionLevelMedium scale:6];
    [self.QRCodeView layer].magnificationFilter = kCAFilterNearest;
    [self.QRCodeView setImage:image];
    
    self.DeviceIDLabel.text = [UIDevice currentDevice].identifierForVendor.UUIDString;
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
        
        [controller setMessageBody:[NSString stringWithFormat:@"Hello,<br/> this is my Miataru Device ID: %@ <br><p>To view this device in any browser you may use this <a href='http://miataru.com/client/#%@'>link.</a><br>", [[UIDevice currentDevice].identifierForVendor.UUIDString uppercaseString], [[UIDevice currentDevice].identifierForVendor.UUIDString uppercaseString]] isHTML:YES];
        [controller setToRecipients:[NSArray arrayWithObjects:@"",nil]];
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        pasteboard.image = self.QRCodeView.image;
        NSData *imageData = [NSData dataWithData:UIImagePNGRepresentation(self.QRCodeView.image)];
        [controller addAttachmentData:imageData mimeType:@"image/png" fileName:@" "];
        [self presentViewController:controller animated:YES completion:NULL];
    }
    else{
        UIAlertView *alert=[[UIAlertView alloc] initWithTitle:@"alrt" message:nil delegate:self cancelButtonTitle:@"ok" otherButtonTitles: nil] ;
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

@end
