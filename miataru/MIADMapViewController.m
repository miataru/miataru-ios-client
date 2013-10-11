//
//  MIADMapViewController.m
//  Miataru
//
//  Created by Daniel Kirstenpfad on 27.09.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import "MIADMapViewController.h"
#import "KnownDevice.h"
#import "PositionPin.h"


@interface MIADMapViewController ()

@property (strong) NSMutableArray *known_devices;

@end

@implementation MIADMapViewController

//- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
//{
//    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
//    if (self) {
//        // Custom initialization
//    }
//    return self;
//}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
}

- (void)viewDidAppear:(BOOL)animated
{
    NSLog(@"Map did appear");
    [self loadKnownDevices];
    
    //[self GetLocationForDeviceFromMiataruServer:@"24F47362-2B49-47F7-A1E4-0AC15117CD65"];
    
    // go through self.known_devices and get all known_device objects out of that...
    for(KnownDevice *kDevice in self.known_devices)
    {
        // here we go - get the location and pin for this device...
        [self GetLocationForDeviceFromMiataruServer:kDevice];
//      if ([kDevice isKindOfClass:[KnownDevice class]])
//      {
//      }
    }
}

- (void)viewDidDisappear:(BOOL)animated
{
    NSLog(@"Map disappeared");
    [self removeAllPinsButUserLocation];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
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

#pragma mark MapView Annotation Clear
// to remove all pins but the users location...
- (void)removeAllPinsButUserLocation
{
    id userLocation = [self.AllDevicesMapView userLocation];
    NSMutableArray *pins = [[NSMutableArray alloc] initWithArray:[self.AllDevicesMapView annotations]];
    if ( userLocation != nil ) {
        [pins removeObject:userLocation]; // avoid removing user location off the map
    }
    
    [self.AllDevicesMapView removeAnnotations:pins];
    //[pins release];
    pins = nil;
}

#pragma mark MapView Delegate Methods
- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id <MKAnnotation>)annotation
{
    NSLog(@"viewForAnnotation");
    
    return nil;
}

- (void)mapView:(MKMapView *)mapView didAddAnnotationViews:(NSArray *)views
{
    NSLog(@"didaddannotation");
    MKAnnotationView *annotationView = [views objectAtIndex:0];
    id <MKAnnotation> mp = [annotationView annotation];
    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance([mp coordinate], 1000,1000);
    [mapView setRegion:region animated:YES];
}

#pragma mark NSURLConnection Delegate Methods

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    // A response has been received, this is where we initialize the instance var you created
    // so that we can append data to it in the didReceiveData method
    // Furthermore, this method is called each time there is a redirect so reinitializing it
    // also serves to clear it
    self.responseData = [[NSMutableData alloc] init];
    //[self.responseData setLength:0];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    // Append the new data to the instance variable you declared
    [self.responseData appendData:data];
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection
                  willCacheResponse:(NSCachedURLResponse*)cachedResponse {
    // Return nil to indicate not necessary to store a cached response for this connection
    return nil;
}


- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    // The request is complete and data has been received
    // You can parse the stuff in your instance variable now
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
    NSError *err = nil;
    NSDictionary* jsonArray = [NSJSONSerialization
                               JSONObjectWithData:self.responseData //1
                               options:NSJSONReadingMutableContainers
                               error:&err];
    
    NSArray* MiataruLocations = [jsonArray objectForKey:@"MiataruLocation"]; //2
    
    if (MiataruLocations != nil && [MiataruLocations class] != [NSNull class])
    {
        if (MiataruLocations[0] != nil && [MiataruLocations[0] class] != [NSNull class])
        {
            NSString* Lat = [MiataruLocations[0] objectForKey:@"Latitude"];
            NSString* Lon = [MiataruLocations[0] objectForKey:@"Longitude"];
            NSString* DeviceID = [MiataruLocations[0] objectForKey:@"Device"];
            NSString* DeviceName = @"MiataruDevice";
            
            // get the device name from the known_devices list...
            for(KnownDevice *kDevice in self.known_devices)
            {
                if([kDevice.DeviceID isEqualToString:DeviceID])
                {
                    DeviceName = kDevice.DeviceName;
                    break;
                }
            }
            
            if (Lat != nil && Lon != nil && [Lat class] != [NSNull class] && [Lon class] != [NSNull class])
            {
                // now get long and lat out and add pin to mapview
                CLLocationCoordinate2D DeviceCoordinates;
                
                DeviceCoordinates.latitude = [Lat doubleValue];
                DeviceCoordinates.longitude = [Lon doubleValue];
                if (DeviceCoordinates.latitude != 0.0 && DeviceCoordinates.longitude != 0.0)
                {
                    // Add the annotation to our map view
                    PositionPin *newAnnotation = [[PositionPin alloc] initWithTitle:DeviceName andCoordinate:DeviceCoordinates];
                    [self.AllDevicesMapView addAnnotation:newAnnotation];
                    NSLog(@"Added Annotation...");
                    //[newAnnotation release];
                    
                    return;
                }
            }
        }
    }
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    // The request has failed for some reason!
    // Check the error var
    NSLog(@"Connection failed: %@",error);
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
}

#pragma mark - GetLocationForDeviceFromMiataruServer

- (void)GetLocationForDeviceFromMiataruServer:(KnownDevice*)device
{
    /*
     ￼{"MiataruGetLocation": [{"Device":"7b8e6e0ee5296db345162dc2ef652c1350761823"}]}
     */
    
    NSString* GetLocationJSONContent = [NSString stringWithFormat:@"{\"MiataruGetLocation\": [{\"Device\":\"%@\"}]}",device.DeviceID];
    
    self.responseData = [NSMutableData data];
    
    NSString* miataru_server_url = [[NSUserDefaults standardUserDefaults] stringForKey:@"miataru_server_url"];
    
    while ([miataru_server_url hasSuffix:@"/"])
    {
        if ( [miataru_server_url length] > 0)
            miataru_server_url = [miataru_server_url substringToIndex:[miataru_server_url length] - 1];
    }
    
    NSMutableURLRequest *detailrequest =
    [[NSMutableURLRequest alloc] initWithURL:
     [NSURL URLWithString:[NSString stringWithFormat:@"%@/GetLocation", miataru_server_url]]];
    
    
    [detailrequest setHTTPMethod:@"POST"];
    
    [detailrequest setValue:[NSString
                             stringWithFormat:@"%d", [GetLocationJSONContent length]]
         forHTTPHeaderField:@"Content-length"];
    
    [detailrequest setValue:@"application/json"
         forHTTPHeaderField:@"Content-Type"];
    
    
    [detailrequest setHTTPBody:[GetLocationJSONContent dataUsingEncoding:NSUTF8StringEncoding]];
    
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
    
    [NSURLConnection connectionWithRequest:detailrequest delegate:self];
    
    //NSLog(@"%@", GetLocationJSONContent);
    
    NSLog(@"Getting Update from to Miataru Service...");
}


@end
