//
//  MIADAppDelegate.m
//  miataru
//
//  Created by Daniel Kirstenpfad on 31.08.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import "MIADAppDelegate.h"
#import "CommonCrypto/CommonDigest.h"

@interface MIADAppDelegate ()

@property (nonatomic, strong) CLLocationManager *locationManager;

//@property (nonatomic) UIBackgroundTaskIdentifier bgTask;

@end

@implementation MIADAppDelegate

- (void)setDefaults {
    
    //get the plist location from the settings bundle
    NSString *settingsPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"Settings.bundle"];
    NSString *plistPath = [settingsPath stringByAppendingPathComponent:@"Root.plist"];
    
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

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    [self setDefaults];
    // ---------- Location
    NSLog(@"didFinishLaunchingWithOptions");
    
    self.locationManager = [[CLLocationManager alloc] init];
 
    // the defaults...
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    self.locationManager.distanceFilter = 250;
    self.locationManager.delegate = self;
    
    BOOL value = (BOOL)[[NSUserDefaults standardUserDefaults] boolForKey:@"track_location"];
    
   
    if ( value == 1 )
    {
        NSLog(@"Starting SignificantLocationChanges...");
        [self.locationManager startMonitoringSignificantLocationChanges];
    }
    // ---------- Location
    
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

    NSLog(@"applicationDidEnterBackground");
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    self.locationManager.distanceFilter = 250;

    if ( (BOOL)[[NSUserDefaults standardUserDefaults] boolForKey:@"track_location"] == 1 )
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

    if ( (BOOL)[[NSUserDefaults standardUserDefaults] boolForKey:@"track_location"] == 1 )
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

    if ( (BOOL)[[NSUserDefaults standardUserDefaults] boolForKey:@"track_location"] == 1 )
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

    if ( (BOOL)[[NSUserDefaults standardUserDefaults] boolForKey:@"track_location"] == 1 )
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

-(BOOL) application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
    if (url != nil && [url isFileURL])
    {
        // handle the miataru URL by passing it to the appropriate view controller...
    }
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
    if ( (BOOL)[[NSUserDefaults standardUserDefaults] boolForKey:@"track_location"] != 1 )
    {
        NSLog(@"Stopping Location Tracking");
        [self.locationManager stopUpdatingLocation];
        [self.locationManager stopMonitoringSignificantLocationChanges];
    }
    else
    {
        if ( (BOOL)[[NSUserDefaults standardUserDefaults] boolForKey:@"report_location_to_server"] == 1 )
        {
            // send only when enabled in the settings...
            [self SendUpdateToMiataruServer:newLocation];
        }
        else
            NSLog(@"Sending Location to Server is disabled");
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


// ---------------- Send Location to Miataru Server

- (void)SendUpdateToMiataruServer:(CLLocation *)locationupdate
{
    // this constructs a very simple json string and POSTs it to the miataru server under
    // service.miataru.com
    /* the JSON content, according to the miataru documentation, should look like this:
     {"MiataruConfig":{"EnableLocationHistory":"False","LocationDataRetentionTime":"15"},"MiataruLocation":[{"Device":"7b8e6e0ee5296db345162dc2ef652c1350761823","Timestamp":"1376735651302","Longitude":"10.837502","Latitude":"49.828925","HorizontalAccuracy":"50.00"}]}
    */
    //[UIDevice currentDevice].identifierForVendor;
    
    // render device ID
    
    if ([UIDevice currentDevice].identifierForVendor != nil)
    {
        
        NSString* deviceID = [UIDevice currentDevice].identifierForVendor.UUIDString;
        
//        unsigned char digest[CC_SHA1_DIGEST_LENGTH];
//        NSData *stringBytes = [vendor_deviceID dataUsingEncoding: NSUTF8StringEncoding]; /* or some other encoding */
//        CC_SHA1([stringBytes bytes], [stringBytes length], digest);
//        NSString* deviceID = [[NSString alloc] initWithBytes:digest length:sizeof(digest) encoding:NSASCIIStringEncoding];
//        NSString* deviceID = [NSString stringWithFormat:@"7b8e6e0ee5296db345162dc2ef652c1350761824"];

        NSString *currentLatitude = [[NSString alloc]initWithFormat:@"%+.6f", locationupdate.coordinate.latitude];
        NSString *currentLongitude = [[NSString alloc]initWithFormat:@"%+.6f", locationupdate.coordinate.longitude];
        NSString *currentHorizontalAccuracy = [[NSString alloc]initWithFormat:@"%+.6f", locationupdate.horizontalAccuracy*3.28];

        // change this to the measured date timestamp!
        NSTimeInterval timeStamp = [[NSDate date] timeIntervalSince1970];
        // NSTimeInterval is defined as double
        NSNumber *timeStampObj = [NSNumber numberWithDouble: timeStamp];

        NSString *currentTimeStamp = [[NSString alloc]initWithFormat:@"%@", timeStampObj];

        NSString *LocationHistory = @"False";
        
        if ( (BOOL)[[NSUserDefaults standardUserDefaults] boolForKey:@"save_location_history_on_server"] == 1 )
        {
            LocationHistory = @"True";
        }
        
        
        NSString* UpdateLocationJSONContent = [NSString stringWithFormat:@"{\"MiataruConfig\":{\"EnableLocationHistory\":\"%@\",\"LocationDataRetentionTime\":\"15\"},\"MiataruLocation\":[{\"Device\":\"%@\",\"Timestamp\":\"%@\",\"Longitude\":\"%@\",\"Latitude\":\"%@\",\"HorizontalAccuracy\":\"%@\"}]}",LocationHistory,deviceID,currentTimeStamp,currentLongitude,currentLatitude,currentHorizontalAccuracy];

        
        NSString* miataru_server_url = [[NSUserDefaults standardUserDefaults] stringForKey:@"miataru_server_url"];
        
        while ([miataru_server_url hasSuffix:@"/"])
        {
            if ( [miataru_server_url length] > 0)
                miataru_server_url = [miataru_server_url substringToIndex:[miataru_server_url length] - 1];
        }
       
        NSMutableURLRequest *request =
        [[NSMutableURLRequest alloc] initWithURL:
         [NSURL URLWithString:[NSString stringWithFormat:@"%@/UpdateLocation", miataru_server_url]]];

        //NSLog(value);
        //NSLog(request.URL.absoluteString);
        
        
        [request setHTTPMethod:@"POST"];

        [request setValue:[NSString
                           stringWithFormat:@"%d", [UpdateLocationJSONContent length]]
       forHTTPHeaderField:@"Content-length"];

        [request setValue:@"application/json"
       forHTTPHeaderField:@"Content-Type"];


        [request setHTTPBody:[UpdateLocationJSONContent
                              dataUsingEncoding:NSUTF8StringEncoding]];

        [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
        
        [NSURLConnection connectionWithRequest:request delegate:self];
        
        NSLog(@"Sending Update for %@",deviceID);
    }
}

@end
