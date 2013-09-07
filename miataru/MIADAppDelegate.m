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

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // ---------- Location
    NSLog(@"didFinishLaunchingWithOptions");
    
    self.locationManager = [[CLLocationManager alloc] init];
 
    // the defaults...
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    self.locationManager.distanceFilter = 500;
    self.locationManager.delegate = self;
    
    [self.locationManager startMonitoringSignificantLocationChanges];
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
    self.locationManager.distanceFilter = 500;

    [self.locationManager stopUpdatingLocation];
    [self.locationManager startMonitoringSignificantLocationChanges];

    [application beginBackgroundTaskWithExpirationHandler:^{}];
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    NSLog(@"applicationWillEnterForeground");
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    self.locationManager.distanceFilter = 100;
    
    [self.locationManager stopMonitoringSignificantLocationChanges];
    [self.locationManager startUpdatingLocation];
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    
    NSLog(@"applicationDidBecomeActive");
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    self.locationManager.distanceFilter = 100;
    
    [self.locationManager stopMonitoringSignificantLocationChanges];
    [self.locationManager startUpdatingLocation];

}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    NSLog(@"applicationWillTerminate");
    
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    self.locationManager.distanceFilter = 500;
    
    [self.locationManager stopUpdatingLocation];
    [self.locationManager startMonitoringSignificantLocationChanges];
    
    //[application beginBackgroundTaskWithExpirationHandler:^{}];

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
    [self SendUpdateToMiataruServer:newLocation];
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


        NSString* UpdateLocationJSONContent = [NSString stringWithFormat:@"{\"MiataruConfig\":{\"EnableLocationHistory\":\"True\",\"LocationDataRetentionTime\":\"15\"},\"MiataruLocation\":[{\"Device\":\"%@\",\"Timestamp\":\"%@\",\"Longitude\":\"%@\",\"Latitude\":\"%@\",\"HorizontalAccuracy\":\"%@\"}]}",deviceID,currentTimeStamp,currentLongitude,currentLatitude,currentHorizontalAccuracy];


        NSMutableURLRequest *request =
        [[NSMutableURLRequest alloc] initWithURL:
         [NSURL URLWithString:@"http://service.miataru.com/UpdateLocation"]];

        [request setHTTPMethod:@"POST"];

        [request setValue:[NSString
                           stringWithFormat:@"%d", [UpdateLocationJSONContent length]]
       forHTTPHeaderField:@"Content-length"];

        [request setValue:@"application/json"
       forHTTPHeaderField:@"Content-Type"];


        [request setHTTPBody:[UpdateLocationJSONContent
                              dataUsingEncoding:NSUTF8StringEncoding]];

        [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
        [[NSURLConnection alloc] initWithRequest:request delegate:self];
        NSLog(@"Sending Update to Miataru Service...");
    }
}

@end
