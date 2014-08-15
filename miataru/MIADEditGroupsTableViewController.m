//
//  MIADEditGroupsTableViewController.m
//  miataru
//
//  Created by Daniel Kirstenpfad on 15.08.14.
//  Copyright (c) 2014 Miataru. All rights reserved.
//

#import "MIADEditGroupsTableViewController.h"
#import "KnownDevice.h"

@interface MIADEditGroupsTableViewController ()

@property (strong) NSMutableArray *known_devices;

@end

@implementation MIADEditGroupsTableViewController

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
    [self loadKnownDevices];

    [super viewDidLoad];
    
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
    // Return the number of sections.
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    // Return the number of rows in the section.
    return [self.known_devices count];;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = nil;
    
    if([tableView respondsToSelector:@selector(dequeueReusableCellWithIdentifier:forIndexPath:)])
    {
        cell = [tableView dequeueReusableCellWithIdentifier:@"KnownGroupDeviceCell" forIndexPath:indexPath];
        
    }
    else
    {
        cell = [tableView dequeueReusableCellWithIdentifier:@"KnownGroupDeviceCell"];
        
    }
    
    //    USVFeed *feed = [self.feeds objectAtIndex:indexPath.row];
    KnownDevice *knowndevice = self.known_devices[indexPath.row];
    
    cell.textLabel.text = knowndevice.DeviceName;
    cell.detailTextLabel.text = knowndevice.DeviceID;
    
    return cell;
    
}

NSIndexPath* lastIndexPath; // This as an ivar

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell* newCell = [tableView cellForRowAtIndexPath:indexPath];
    NSInteger newRow = [indexPath row];
    NSInteger oldRow = (lastIndexPath != nil) ? [lastIndexPath row] : -1;
    
    if(newRow != oldRow)
    {
        if (newCell.accessoryType == UITableViewCellAccessoryCheckmark)
        {
            newCell.accessoryType = UITableViewCellAccessoryNone;
            
            KnownDevice *editDevice = self.known_devices[indexPath.row];
            editDevice.DeviceIsInGroup = FALSE;
            [self saveKnownDevices];
        }
        else
        {
            newCell.accessoryType = UITableViewCellAccessoryCheckmark;
            KnownDevice *editDevice = self.known_devices[indexPath.row];
            editDevice.DeviceIsInGroup = TRUE;
            [self saveKnownDevices];
        }

        lastIndexPath = indexPath;
    }
}



// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Return NO if you do not want the specified item to be editable.
    return NO;
}


- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
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

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/


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
    NSLog(@"saveKnownDevices");
}


@end
