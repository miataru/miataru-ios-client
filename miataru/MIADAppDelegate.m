//
//  MIADAppDelegate.m
//  miataru
//
//  Created by Daniel Kirstenpfad on 31.08.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import "MIADAppDelegate.h"
#import "CommonCrypto/CommonDigest.h"
#import "MIADAddADeviceTableViewController.h"

@interface MIADAppDelegate ()

@property (strong) NSString *device_id;

@property (nonatomic, strong) CLLocationManager *locationManager;

@property (nonatomic) UIBackgroundTaskIdentifier bgTask;

@end

@implementation MIADAppDelegate

@synthesize bgTask;

- (void)setDefaults {
    
    //get the plist location from the settings bundle
    NSString *settingsPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"Settings.bundle"];
    NSString *plistPath = [settingsPath stringByAppendingPathComponent:@"Root.plist"];
    
    if (![self CheckDeviceID])
    {
        [self saveDeviceID];
    }
    else
    {
        [self loadDeviceID];
    }
    //get the preference specifiers array which contains the settings
    NSDictionary *settingsDictionary = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    NSArray *preferencesArray = [settingsDictionary objectForKey:@"PreferenceSpecifiers"];
    
    //use the shared defaults object
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    //for each preference item, set its default if there is no value set
    for(NSDictionary *item in preferencesArray) {
        
        //get the item key, if there is no key then we can skip it
        NSString *key = [item objectForKey:@"Key"];
        if (key) {
            
            //check to see if the value and default value are set
            //if a default value exists and the value is not set, use the default
            id value = [defaults objectForKey:key];
            id defaultValue = [item objectForKey:@"DefaultValue"];
            if(defaultValue && !value) {
                [defaults setObject:defaultValue forKey:key];
            }
        }
    }
    
    //write the changes to disk
    [defaults synchronize];
}

- (void)postLaunch {
    [self setDefaults];
    // ---------- Location
    self.locationManager = [[CLLocationManager alloc] init];
    
    // the defaults...
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    self.locationManager.distanceFilter = 100;
    self.locationManager.delegate = self;
    
    // Check for iOS 8. Without this guard the code will crash with "unknown selector" on iOS 7.
    if ([self.locationManager respondsToSelector:@selector(requestAlwaysAuthorization)]) {
        [self.locationManager requestAlwaysAuthorization];
    }
    
    // set https service.miataru.com setting...
    
    if ([[[NSUserDefaults standardUserDefaults] stringForKey:@"miataru_server_url"] isEqualToString:@"http://service.miataru.com"])
    {
        // set to https
        [[NSUserDefaults standardUserDefaults] setValue: @"https://service.miataru.com" forKey: @"miataru_server_url"]; 
    }
    
    //  BOOL value = (BOOL)[[NSUserDefaults standardUserDefaults] boolForKey:@"track_and_report_location"];
    if ( (BOOL)[[NSUserDefaults standardUserDefaults] boolForKey:@"track_and_report_location"] == 1 )
    {
        NSLog(@"Starting SignificantLocationChanges...");
        [self.locationManager startMonitoringSignificantLocationChanges];
    }
    // ---------- Location
}

- (BOOL)application:(UIApplication *)application willFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    NSLog(@"willFinishLaunchingWithOptions");
    
    //[self postLaunch];
    // Override point for customization after application launch.
    return YES;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    NSLog(@"didFinishLaunchingWithOptions");
    
    // Handle launching from a notification
    UILocalNotification *localNotif =
    [launchOptions objectForKey:UIApplicationLaunchOptionsLocalNotificationKey];
    if (localNotif) {
        NSLog(@"Received Notification %@",localNotif);
    }

    
    [self postLaunch];
    
    
    // Override point for customization after application launch.
    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    
    NSLog(@"applicationWillResignActive");
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    
    [[UIApplication sharedApplication] setIdleTimerDisabled:NO];
    
    NSLog(@"applicationDidEnterBackground");
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    self.locationManager.distanceFilter = 100;
    
    if ( (BOOL)[[NSUserDefaults standardUserDefaults] boolForKey:@"track_and_report_location"] == 1 )
    {
        [self.locationManager stopUpdatingLocation];
        [self.locationManager startMonitoringSignificantLocationChanges];
    }
    else
    {
        [self.locationManager stopUpdatingLocation];
        [self.locationManager stopMonitoringSignificantLocationChanges];
    }
    
    //[application beginBackgroundTaskWithExpirationHandler:^{}];
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    NSLog(@"applicationWillEnterForeground");
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    self.locationManager.distanceFilter = 100;
    
    if ( (BOOL)[[NSUserDefaults standardUserDefaults] boolForKey:@"disable_device_autolock_while_in_foreground"] == 1 )
    {
        [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
    }
    
    if ( (BOOL)[[NSUserDefaults standardUserDefaults] boolForKey:@"track_and_report_location"] == 1 )
    {
        [self.locationManager stopMonitoringSignificantLocationChanges];
        [self.locationManager startUpdatingLocation];
    }
    else
    {
        [self.locationManager stopMonitoringSignificantLocationChanges];
        [self.locationManager stopUpdatingLocation];
    }
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    
    NSLog(@"applicationDidBecomeActive");
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    self.locationManager.distanceFilter = 100;
    
    if ( (BOOL)[[NSUserDefaults standardUserDefaults] boolForKey:@"track_and_report_location"] == 1 )
    {
        [self.locationManager stopMonitoringSignificantLocationChanges];
        [self.locationManager startUpdatingLocation];
    }
    else
    {
        [self.locationManager stopMonitoringSignificantLocationChanges];
        [self.locationManager stopUpdatingLocation];
    }
    
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    NSLog(@"applicationWillTerminate");
    
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    self.locationManager.distanceFilter = 100;
    
    if ( (BOOL)[[NSUserDefaults standardUserDefaults] boolForKey:@"track_and_report_location"] == 1 )
    {
        [self.locationManager stopUpdatingLocation];
        [self.locationManager startMonitoringSignificantLocationChanges];
        
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        // Schedule an alarm here to warn the user that they have terminated an application and if they want to re-activate it.
        NSDate * theDate = [[NSDate date] dateByAddingTimeInterval:1]; // set a localnotificaiton for 10 seconds
        
        UIApplication* app = [UIApplication sharedApplication];
        NSArray*    oldNotifications = [app scheduledLocalNotifications];
        
        
        // Clear out the old notification before scheduling a new one.
        if ([oldNotifications count] > 0)
            [app cancelAllLocalNotifications];
        
        // Create a new notification.
        UILocalNotification* alarm = [[UILocalNotification alloc] init];
        if (alarm)
        {
            alarm.fireDate = theDate;
            alarm.timeZone = [NSTimeZone defaultTimeZone];
            alarm.repeatInterval = 0;
            alarm.soundName = @"sonar";
            alarm.alertBody =@"Miataru was closed and won't track. Tap here to restart.";
            
            [app scheduleLocalNotification:alarm];
        }

        NSLog(@"Notification...");
    }
    else
    {
        [self.locationManager stopUpdatingLocation];
        [self.locationManager stopMonitoringSignificantLocationChanges];
    }
    //[application beginBackgroundTaskWithExpirationHandler:^{}];
}

-(BOOL) application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation {
    
    NSLog(@"openURL");
    [self postLaunch];

    
    if ([[url absoluteString] hasPrefix:@"miataru://"])
    {
        //NSString *cutOff = [[url absoluteString] substringFromIndex:10];
        // todo: return value...
        
        // init the AddADeviceTableView...
        //MIADAddADeviceTableViewController *view = [[MIADAddADeviceTableViewController alloc] init];
        //[view addADeviceFromURLType:cutOff];
        //[self.window.rootViewController presentViewController:view animated:YES completion:nil];
        
        //[self.delegate ScanQRCodeControllerDidFinish:self scannedDeviceID:cutOff];
    }
    else
    {
        UIAlertView *messageAlert = [[UIAlertView alloc]
                                     initWithTitle:@"No Device QR Code" message:@"The code you scanned is not a Miataru QR device code." delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
        // Display Alert Message
        [messageAlert show];
    }
    
    
    //    if (url != nil)
    //    {
    //        // handle the miataru URL by passing it to the appropriate view controller...
    //        MIADAddADeviceTableViewController *addDeviceView = [MIADAddADeviceTableViewController alloc];
    //
    //        UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:addDeviceView];
    //        [[self window] setRootViewController:navController];
    //        //template code
    //        [self.window makeKeyAndVisible];
    //    }
    return YES;
}

// ----------------------- Location


#pragma mark - CLLocationManagerDelegate
/*
 *  locationManager:didUpdateToLocation:fromLocation:
 *
 *  Discussion:
 *    Invoked when a new location is available. oldLocation may be nil if there is no previous location
 *    available.
 *
 *    This method is deprecated. If locationManager:didUpdateLocations: is
 *    implemented, this method will not be called.
 */
- (void)locationManager:(CLLocationManager *)manager
    didUpdateToLocation:(CLLocation *)newLocation
           fromLocation:(CLLocation *)oldLocation
{
    BOOL isInBackground = NO;
    if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground)
    {
        isInBackground = YES;
    }
    
    // Handle location updates as normal, code omitted for brevity.
    // The omitted code should determine whether to reject the location update for being too
    // old, too close to the previous one, too inaccurate and so forth according to your own
    // application design.
    
    if (isInBackground)
    {
        if ( (BOOL)[[NSUserDefaults standardUserDefaults] boolForKey:@"track_and_report_location"] != 1 )
        {
            NSLog(@"Stopping Location Tracking");
            [self.locationManager stopUpdatingLocation];
            [self.locationManager stopMonitoringSignificantLocationChanges];
        }
        else
        {
            if ( (BOOL)[[NSUserDefaults standardUserDefaults] boolForKey:@"track_and_report_location"] == 1 )
            {
                // send only when enabled in the settings...
                [self sendBackgroundLocationToServer:newLocation];
            }
            else
                NSLog(@"Sending Location to Server is disabled");
        }
    }
    else
    {
        if ( (BOOL)[[NSUserDefaults standardUserDefaults] boolForKey:@"track_and_report_location"] != 1 )
        {
            NSLog(@"Stopping Location Tracking");
            [self.locationManager stopUpdatingLocation];
            [self.locationManager stopMonitoringSignificantLocationChanges];
        }
        else
        {
            if ( (BOOL)[[NSUserDefaults standardUserDefaults] boolForKey:@"track_and_report_location"] == 1 )
            {
                // send only when enabled in the settings...
                [self SendUpdateToMiataruServer:newLocation ExecuteAsyncronous:true];
            }
            else
                NSLog(@"Sending Location to Server is disabled");
        }
    }
    
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
}


#pragma mark SendUpdatesToServer

-(void) sendBackgroundLocationToServer:(CLLocation *)location
{
    // REMEMBER. We are running in the background if this is being executed.
    // We can't assume normal network access.
    // bgTask is defined as an instance variable of type UIBackgroundTaskIdentifier
    
    // Note that the expiration handler block simply ends the task. It is important that we always
    // end tasks that we have started.
    
    bgTask = [[UIApplication sharedApplication]
              beginBackgroundTaskWithExpirationHandler:
              ^{[[UIApplication sharedApplication] endBackgroundTask:bgTask];}];
    
    [self SendUpdateToMiataruServer:location ExecuteAsyncronous:false];
    
    if (bgTask != UIBackgroundTaskInvalid)
    {
    [[UIApplication sharedApplication] endBackgroundTask:bgTask];
    bgTask = UIBackgroundTaskInvalid;
    }
}

// ---------------- Send Location to Miataru Server

- (void)SendUpdateToMiataruServer:(CLLocation *)locationupdate ExecuteAsyncronous:(bool)asyncrounous
{
    // this constructs a very simple json string and POSTs it to the miataru server under
    // service.miataru.com
    /* the JSON content, according to the miataru documentation, should look like this:
     {"MiataruConfig":{"EnableLocationHistory":"False","LocationDataRetentionTime":"15"},"MiataruLocation":[{"Device":"7b8e6e0ee5296db345162dc2ef652c1350761823","Timestamp":"1376735651302","Longitude":"10.837502","Latitude":"49.828925","HorizontalAccuracy":"50.00"}]}
     */
    //[UIDevice currentDevice].identifierForVendor;
    
    // render device ID
    
    if (self.device_id != nil)
    {
        NSString *LocationHistory = @"False";
        if ( (BOOL)[[NSUserDefaults standardUserDefaults] boolForKey:@"save_location_history_on_server"] == 1 )
        {
            LocationHistory = @"True";
        }
        
        
        NSString* UpdateLocationJSONContent = [NSString stringWithFormat:@"{\"MiataruConfig\":{\"EnableLocationHistory\":\"%@\",\"LocationDataRetentionTime\":\"%@\"},\"MiataruLocation\":[{\"Device\":\"%@\",\"Timestamp\":\"%@\",\"Longitude\":\"%+.6f\",\"Latitude\":\"%+.6f\",\"HorizontalAccuracy\":\"%+.6f\"}]}",
                                               LocationHistory,
                                               [[NSUserDefaults standardUserDefaults] stringForKey:@"location_data_retention_time"],
                                               self.device_id,
                                               [NSNumber numberWithDouble: [[NSDate date] timeIntervalSince1970]],
                                               locationupdate.coordinate.longitude,
                                               locationupdate.coordinate.latitude,
                                               locationupdate.horizontalAccuracy*3.28];
        
        
        NSString* miataru_server_url = [[NSUserDefaults standardUserDefaults] stringForKey:@"miataru_server_url"];
        
        while ([miataru_server_url hasSuffix:@"/"])
        {
            if ( [miataru_server_url length] > 0)
                miataru_server_url = [miataru_server_url substringToIndex:[miataru_server_url length] - 1];
        }
        
        NSMutableURLRequest *request =
        [[NSMutableURLRequest alloc] initWithURL:
         [NSURL URLWithString:[NSString stringWithFormat:@"%@/v1/UpdateLocation", miataru_server_url]]];
        
        //NSLog(value);
        //NSLog(request.URL.absoluteString);
        
        
        [request setHTTPMethod:@"POST"];
        
        [request setValue:[NSString
                           stringWithFormat:@"%lu", (unsigned long)[UpdateLocationJSONContent length]]
       forHTTPHeaderField:@"Content-length"];
        
        [request setValue:@"application/json"
       forHTTPHeaderField:@"Content-Type"];
        
        
        [request setHTTPBody:[UpdateLocationJSONContent
                              dataUsingEncoding:NSUTF8StringEncoding]];
        
        [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
       
        if(asyncrounous)
        {
            NSLog(@"Sending Async Update to Server");
            [NSURLConnection connectionWithRequest:request delegate:self];
        }
        else
        {
            NSURLResponse* response;
            NSError* error = nil;
            NSLog(@"Sending Sync Update to Server");
            [NSURLConnection sendSynchronousRequest:request  returningResponse:&response error:&error];
        }
    }
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


- (void) saveDeviceID{
    [NSKeyedArchiver archiveRootObject:[UIDevice currentDevice].identifierForVendor.UUIDString toFile:[self pathToSavedDeviceID]];
    NSLog(@"saveDeviceID");
}


@end
