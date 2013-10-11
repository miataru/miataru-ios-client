//
//  MIADAddADeviceTableViewController.m
//  miataru
//
//  Created by Daniel Kirstenpfad on 08.09.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import "MIADAddADeviceTableViewController.h"
#import "KnownDevice.h"
#import "MultiFormatReader.h"

@interface MIADAddADeviceTableViewController ()

@property (weak, nonatomic) IBOutlet UITextField *DeviceNameTextField;

@property (weak, nonatomic) IBOutlet UITextField *DeviceIDTextField;

@end

@implementation MIADAddADeviceTableViewController

- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)CancelButtonAction:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
    //[self.delegate addADeviceTableViewControllerDidFinish:self knownDevice:nil];
    
}
- (IBAction)SaveButtonAction:(id)sender
{
    KnownDevice *newDevice = nil;
    
    if ([self.DeviceNameTextField.text length] && [self.DeviceIDTextField.text length])
    {
        newDevice = [KnownDevice DeviceWithName:self.DeviceNameTextField.text DeviceID:self.DeviceIDTextField.text];
        [self.delegate addADeviceTableViewControllerDidFinish:self knownDevice:newDevice];
        [self dismissViewControllerAnimated:YES completion:nil];
    }

}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    //NSLog(@"%i-%i",indexPath.row,indexPath.section);
    
    if (indexPath.row == 0 && indexPath.section == 1)
    {
        ZXingWidgetController *widController =
        [[ZXingWidgetController alloc] initWithDelegate:self showCancel:YES OneDMode:NO];

        NSBundle *mainBundle = [NSBundle mainBundle];
/*        widController.soundToPlay =
        [NSURL fileURLWithPath:[mainBundle pathForResource:@"beep-beep" ofType:@"aiff"] isDirectory:NO];
*/
        NSMutableSet *readers = [[NSMutableSet alloc ] init];
        
        MultiFormatReader* reader = [[MultiFormatReader alloc] init];
        [readers addObject:reader];

        widController.readers = readers;
        
        [self presentViewController:widController animated:NO completion:nil];
    }
}

- (void)zxingController:(ZXingWidgetController*)controller didScanResult:(NSString *)result
{
    //NSLog(@"%@",result);
   if ([result hasPrefix:@"miataru://"])
   {
       NSString *cutOff = [result substringFromIndex:10];
       [self.DeviceIDTextField setText:[cutOff uppercaseString]];
   }
   else
   {
       UIAlertView *messageAlert = [[UIAlertView alloc]
                                    initWithTitle:@"No Device QR Code" message:@"The code you scanned is not a Miataru QR device code." delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
       
       // Display Alert Message
       [messageAlert show];
   }
   [self dismissViewControllerAnimated:NO completion:nil];
}

- (void)zxingControllerDidCancel:(ZXingWidgetController*)controller {
   [self dismissViewControllerAnimated:NO completion:nil];
}

@end
