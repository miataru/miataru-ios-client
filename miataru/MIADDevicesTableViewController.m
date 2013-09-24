//
//  MIADDevicesTableViewController.m
//  miataru
//
//  Created by Daniel Kirstenpfad on 07.09.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import "MIADDevicesTableViewController.h"
#import "MIADDeviceDetailsViewController.h"
#import "KnownDevice.h"

@interface MIADDevicesTableViewController ()

@property (strong) NSMutableArray *known_devices;

@end

@implementation MIADDevicesTableViewController

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

    [self loadKnownDevices];
    
    if(!self.known_devices)
    {
        self.known_devices = [NSMutableArray array];
        
        NSString *name = @"Daniels iPhone";
        NSString *id = @"DBD02046-EAA5-40F2-8C3B-8C884893A57C";
        KnownDevice *knowndevice = [KnownDevice DeviceWithName:name DeviceID:id];
        [self.known_devices addObject:knowndevice];
        
        name = @"Steffis iPhone";
        id = @"1FA18E88-2CD8-426F-94FD-69D95BFEE410";
        knowndevice = [KnownDevice DeviceWithName:name DeviceID:id];
        [self.known_devices addObject:knowndevice];
        
        [self saveKnownDevices];
    }
    self.navigationItem.leftBarButtonItem = self.editButtonItem;

    // Uncomment the following line to preserve selection between presentations.
    // self.clearsSelectionOnViewWillAppear = NO;
 
    // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
    // self.navigationItem.rightBarButtonItem = self.editButtonItem;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [self.known_devices count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = nil;
    
    if([tableView respondsToSelector:@selector(dequeueReusableCellWithIdentifier:forIndexPath:)])
    {
        cell = [tableView dequeueReusableCellWithIdentifier:@"KnownDeviceCell" forIndexPath:indexPath];
        
    }
    else
    {
        cell = [tableView dequeueReusableCellWithIdentifier:@"KnownDeviceCell"];
        
    }
    
    //    USVFeed *feed = [self.feeds objectAtIndex:indexPath.row];
    KnownDevice *knowndevice = self.known_devices[indexPath.row];
    
    cell.textLabel.text = knowndevice.DeviceName;
    cell.detailTextLabel.text = knowndevice.DeviceID;
    
    return cell;
    
}

// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Return NO if you do not want the specified item to be editable.
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete)
    {
        // delete a row...
        [self.known_devices removeObjectAtIndex:indexPath.row];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
        [self saveKnownDevices];
        
    } else if (editingStyle == UITableViewCellEditingStyleInsert) {
        // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view.
    }
}


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

#pragma mark - Segue

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.identifier isEqualToString:@"ModalToAddDevice"])
    {
        ((MIADAddADeviceTableViewController*)[[segue.destinationViewController viewControllers] objectAtIndex:0]).delegate = self;
    }
    else
    if ([segue.identifier isEqualToString:@"PushToDeviceDetails"]) {
        NSIndexPath *indexPath = [self.tableView indexPathForSelectedRow];
        //Dev
        KnownDevice *detailDevice = self.known_devices[indexPath.row];
       
        ((MIADDeviceDetailsViewController*)segue.destinationViewController).DetailDevice = detailDevice;
    }
}


#pragma mark Persistent State

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


- (NSString*) pathToSavedKnownDevices{
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
    NSString *path = [[applicationSupportURL path] stringByAppendingPathComponent:@"knownDevices.plist"];
    
    return path;
}

- (void) loadKnownDevices{
    
    NSString *path = [self pathToSavedKnownDevices];
    NSLog(@"loadKnownDevices: %@", path);
    
    self.known_devices = [NSKeyedUnarchiver unarchiveObjectWithFile:path];
}


- (void) saveKnownDevices{
    [NSKeyedArchiver archiveRootObject:self.known_devices toFile:[self pathToSavedKnownDevices]];
}


#pragma mark - Add a Device Delegate

- (void)addADeviceTableViewControllerDidFinish:(MIADAddADeviceTableViewController *)inController knownDevice:(KnownDevice *)inDevice
{
    if (inDevice)
    {
        [self.known_devices addObject:inDevice];
        [self.tableView reloadData];
        [self saveKnownDevices];
        return;
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}


@end
