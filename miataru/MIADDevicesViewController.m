      //
//  MIADFirstViewController.m
//  miataru
//
//  Created by Daniel Kirstenpfad on 31.08.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import "MIADDevicesViewController.h"

@interface MIADDevicesViewController ()

@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) NSMutableArray *locations;

@end

@implementation MIADDevicesViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
    self.locations = [[NSMutableArray alloc] init];
    self.locationManager = [[CLLocationManager alloc] init];

    // the defaults...
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    self.locationManager.distanceFilter = 5;
    self.locationManager.delegate = self;
}

- (void)LocationAppInForeground
{
    if (self.locationManager.desiredAccuracy != kCLLocationAccuracyBest) {
        NSLog(@"Switching Accuracy to Foreground Mode");
        [self.locationManager setDesiredAccuracy:kCLLocationAccuracyBest];
        [self.locationManager setDistanceFilter:5];
    }
}

- (void)LocationAppInBackground
{
    if (self.locationManager.desiredAccuracy != kCLLocationAccuracyHundredMeters) {
        NSLog(@"Switching Accuracy to Background Mode");
        [self.locationManager setDesiredAccuracy:kCLLocationAccuracyHundredMeters];
        [self.locationManager setDistanceFilter:500];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)enabledStateChanged:(id)sender
{
    if (self.switchEnabled.on)
    {
        [self.locationManager startUpdatingLocation];
    }
    else
    {
        [self.locationManager stopUpdatingLocation];
    }
}

- (void)SendUpdateToMiataruServer:(CLLocation *)locationupdate
{
    // this constructs a very simple json string and POSTs it to the miataru server under
    // service.miataru.com
    /* the JSON content, according to the miataru documentation, should look like this:
     {"MiataruConfig":{"EnableLocationHistory":"False","LocationDataRetentionTime":"15"},"MiataruLocation":[{"Device":"7b8e6e0ee5296db345162dc2ef652c1350761823","Timestamp":"1376735651302","Longitude":"10.837502","Latitude":"49.828925","HorizontalAccuracy":"50.00"}]}
    */
    //[UIDevice currentDevice].identifierForVendor;
    
    NSString* deviceID = [NSString stringWithFormat:@"7b8e6e0ee5296db345162dc2ef652c1350761824"];

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
    
    /*NSURLResponse * response = nil;
    NSError * error = nil;
    NSData * data = [NSURLConnection sendSynchronousRequest:request
                                          returningResponse:&response
                                                      error:&error];
    
    if (error == nil)
    {
        // Parse data here
    }
    */
    
  
    [[NSURLConnection alloc] initWithRequest:request delegate:self];
    NSLog(@"Sending Update to Miataru Service...");
    
}


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
    // Add another anotation to the map.
//  MKPointAnnotation *annotation = [[MKPointAnnotation alloc] init];
//  annotation.coordinate = newLocation.coordinate;
//  [self.map addAnnotation:annotation];
    
    // Also add to our map so we can remove old values later
//  [self.locations addObject:annotation];
    
    // Remove values if the array is too big
/*    while (self.locations.count > 100)
    {
        annotation = [self.locations objectAtIndex:0];
        [self.locations removeObjectAtIndex:0];
        
        // Also remove from the map
        [self.map removeAnnotation:annotation];
    }
*/
    // when active...
    if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive)
    {
/*      // determine the region the points span so we can update our map's zoom.
        double maxLat = -91;
        double minLat =  91;
        double maxLon = -181;
        double minLon =  181;
        
        for (MKPointAnnotation *annotation in self.locations)
        {
            CLLocationCoordinate2D coordinate = annotation.coordinate;
            
            if (coordinate.latitude > maxLat)
                maxLat = coordinate.latitude;
            if (coordinate.latitude < minLat)
                minLat = coordinate.latitude;
            
            if (coordinate.longitude > maxLon)
                maxLon = coordinate.longitude;
            if (coordinate.longitude < minLon)
                minLon = coordinate.longitude;
        }
        
        MKCoordinateRegion region;
        region.span.latitudeDelta  = (maxLat +  90) - (minLat +  90);
        region.span.longitudeDelta = (maxLon + 180) - (minLon + 180);
        
        // the center point is the average of the max and mins
        region.center.latitude  = minLat + region.span.latitudeDelta / 2;
        region.center.longitude = minLon + region.span.longitudeDelta / 2;
        
        // Set the region of the map.
        [self.map setRegion:region animated:YES];*/
        // this if the foreground part        
        //NSLog(@"App is foregrounded. New location is %@", newLocation);
        [self LocationAppInForeground];
        [self SendUpdateToMiataruServer:newLocation];
        
    }
    else
    {
        // this is the background part
        //NSLog(@"App is backgrounded. New location is %@", newLocation);
        [self LocationAppInBackground];
        [self SendUpdateToMiataruServer:newLocation];
    }
}

@end
