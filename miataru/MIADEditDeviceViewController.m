//
//  MIADEditDeviceViewController.m
//  miataru
//
//  Created by Daniel Kirstenpfad on 20.11.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import "MIADEditDeviceViewController.h"

@interface MIADEditDeviceViewController ()

@end

@implementation MIADEditDeviceViewController

@synthesize EditDevice;
@synthesize DeviceNameTextfield;
@synthesize DeviceIDTextField;
@synthesize ColorPickerTableCell;

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

    // Uncomment the following line to preserve selection between presentations.
    // self.clearsSelectionOnViewWillAppear = NO;
 
    // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
    // self.navigationItem.rightBarButtonItem = self.editButtonItem;
}

- (void)viewWillAppear:(BOOL)animated
{
    NSLog(@"viewWillAppear");
    DeviceNameTextfield.text = EditDevice.DeviceName;
    DeviceIDTextField.text = EditDevice.DeviceID;
    if (EditDevice.DeviceColor != nil)
        ColorPickerTableCell.backgroundColor = EditDevice.DeviceColor;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table view data source

//- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
//{
//    // Return the number of sections.
//    return 1;
//}
//
//- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
//{
//    #warning Incomplete method implementation.
//    // Return the number of rows in the section.
//    return 1;
//}
//
//- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
//{
//    static NSString *CellIdentifier = @"Cell";
//    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier forIndexPath:indexPath];
//    
//    // Configure the cell...
//    
//    return cell;
//}

/*
// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Return NO if you do not want the specified item to be editable.
    return YES;
}
*/

/*
// Override to support editing the table view.
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        // Delete the row from the data source
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    }   
    else if (editingStyle == UITableViewCellEditingStyleInsert) {
        // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
    }   
}
*/

/*
// Override to support rearranging the table view.
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath
{
}
*/

/*
// Override to support conditional rearranging of the table view.
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Return NO if you do not want the item to be re-orderable.
    return YES;
}
*/

/*
#pragma mark - Navigation

// In a story board-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}

 */
- (IBAction)SaveButtonPressed:(id)sender {
    
    KnownDevice *newDevice = nil;
    
    if ([DeviceNameTextfield.text length])
    {
        newDevice = [KnownDevice DeviceWithName:DeviceNameTextfield.text DeviceID:DeviceIDTextField.text];
        newDevice.KnownDevicesTablePosition = EditDevice.KnownDevicesTablePosition;
        if (ColorPickerTableCell.backgroundColor != nil)
            newDevice.DeviceColor = ColorPickerTableCell.backgroundColor;
        
        [self.delegate editADeviceTableViewControllerDidFinish:self knownDevice:newDevice];
        [self.navigationController popViewControllerAnimated:YES];
    }
}
- (IBAction)PickColorPressed:(id)sender {
    NEOColorPickerViewController *controller = [[NEOColorPickerViewController alloc] init];
    controller.delegate = self;

    controller.selectedColor = EditDevice.DeviceColor;
    controller.title = @"Pick a color";
    
	UINavigationController* navVC = [[UINavigationController alloc] initWithRootViewController:controller];
    [self presentViewController:navVC animated:YES completion:nil];

}

#pragma mark ColorPicker Delegate
- (void)colorPickerViewController:(NEOColorPickerBaseViewController *)controller didSelectColor:(UIColor *)color {
    ColorPickerTableCell.backgroundColor = color;
    EditDevice.DeviceColor = color;
    [controller dismissViewControllerAnimated:YES completion:nil];
}

- (void)colorPickerViewControllerDidCancel:(NEOColorPickerBaseViewController *)controller {
	[controller dismissViewControllerAnimated:YES completion:nil];
}

@end
