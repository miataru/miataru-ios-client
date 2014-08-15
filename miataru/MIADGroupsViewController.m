//
//  MIADMapViewController.m
//  Miataru
//
//  Created by Daniel Kirstenpfad on 15.08.14.
//  Copyright (c) 2014 Miataru. All rights reserved.
//

#import "MIADGroupsViewController.h"
#import "KnownDevice.h"
#import "PositionPin.h"
#import "PassedTimeDateFormatter.h"

@implementation MIADGroupsViewController

@synthesize DevicesMapView;
@synthesize mapScaleView;

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
    NSInteger map_type = [[NSUserDefaults standardUserDefaults] integerForKey:@"map_type"];
    
    switch (map_type)
    {
        case 1:
            [DevicesMapView setMapType:MKMapTypeStandard];
            break;
        case 2:
            [DevicesMapView setMapType:MKMapTypeHybrid];
            break;
        case 3:
            [DevicesMapView setMapType:MKMapTypeSatellite];
            break;
        default:
            [DevicesMapView setMapType:MKMapTypeStandard];
            break;
    }
    // here comes the interesting part
	// get a handle to the map scale view of our mapView (by eventually installing one first)
	mapScaleView = [LXMapScaleView mapScaleForMapView:DevicesMapView];
    mapScaleView.position = kLXMapScalePositionBottomRight;
	mapScaleView.style = kLXMapScaleStyleBar;
    mapScaleView.alpha = 0.7;
    mapScaleView.maxWidth = 150;
    
    [mapScaleView update];
}

- (void)viewDidAppear:(BOOL)animated
{
    NSLog(@"Map did appear");
    
    if ( (BOOL)[[NSUserDefaults standardUserDefaults] boolForKey:@"disable_device_autolock_while_in_foreground"] == 1 )
    {
        [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
    }
    else
    {
        [[UIApplication sharedApplication] setIdleTimerDisabled:NO];
    }
    
    [self loadKnownDevices];
    
    NSInteger map_type = [[NSUserDefaults standardUserDefaults] integerForKey:@"map_type"];
    
    switch (map_type)
    {
        case 1:
            [DevicesMapView setMapType:MKMapTypeStandard];
            break;
        case 2:
            [DevicesMapView setMapType:MKMapTypeHybrid];
            break;
        case 3:
            [DevicesMapView setMapType:MKMapTypeSatellite];
            break;
        default:
            [DevicesMapView setMapType:MKMapTypeStandard];
            break;
    }

    
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
    
    // zoom to fit all map annotations...
    [DevicesMapView showAnnotations:DevicesMapView.annotations animated:NO];
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
    id userLocation = [DevicesMapView userLocation];
    NSMutableArray *pins = [[NSMutableArray alloc] initWithArray:[DevicesMapView annotations]];
    if ( userLocation != nil ) {
        [pins removeObject:userLocation]; // avoid removing user location off the map
    }
    
    [DevicesMapView removeAnnotations:pins];
    //[pins release];
    pins = nil;
}

#pragma mark MapView Delegate Methods
- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id <MKAnnotation>)annotation
{
    NSLog(@"viewForAnnotation");
    
    // Don't mess with user location
	if(![annotation isKindOfClass:[PositionPin class]])
        return nil;
    
    PositionPin *a = (PositionPin *)annotation;
    static NSString *defaultPinID = @"StandardIdentifier";
    
    // Create the ZSPinAnnotation object and reuse it
    ZSPinAnnotation *pinView = (ZSPinAnnotation *)[mapView dequeueReusableAnnotationViewWithIdentifier:defaultPinID];
    if (pinView == nil){
        pinView = [[ZSPinAnnotation alloc] initWithAnnotation:annotation reuseIdentifier:defaultPinID];
    }
    
    // Set the type of pin to draw and the color
    pinView.annotationType = a.type;
    pinView.annotationColor = a.color;
    pinView.canShowCallout = YES;
    
    return pinView;
}

- (void)mapView:(MKMapView *)mapView didAddAnnotationViews:(NSArray *)views
{
    NSLog(@"didaddannotation");
//    MKAnnotationView *annotationView = [views objectAtIndex:0];
//    id <MKAnnotation> mp = [annotationView annotation];
//    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance([mp coordinate], 1000,1000);
//    [mapView setRegion:region animated:YES];
    
}

#pragma mark MapScale
- (void)mapView:(MKMapView*)aMapView regionDidChangeAnimated:(BOOL)aAnimated
{
    NSLog(@"regionchanged");
	// the map scale will retrieve the current state of the mapView it is attached to
	// and update itself accordingly
	[mapScaleView update];
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
            NSString* Timestamp = [MiataruLocations[0] objectForKey:@"Timestamp"];
            NSString* DeviceID = [MiataruLocations[0] objectForKey:@"Device"];
            NSString* DeviceName = @"MiataruDevice";
            UIColor* DeviceColor;
            
            // get the device name from the known_devices list...
            for(KnownDevice *kDevice in self.known_devices)
            {
                if([kDevice.DeviceID isEqualToString:DeviceID])
                {
                    DeviceName = kDevice.DeviceName;
                    DeviceColor = kDevice.DeviceColor;
                    break;
                }
            }
            
            
            NSString *TimeString = [PassedTimeDateFormatter dateToStringInterval:[NSDate dateWithTimeIntervalSince1970:[Timestamp doubleValue]]];
            
            NSString* UseThisDeviceName = [NSString stringWithFormat:@"%@ - %@",DeviceName,TimeString];
            
            if (Lat != nil && Lon != nil && [Lat class] != [NSNull class] && [Lon class] != [NSNull class])
            {
                // now get long and lat out and add pin to mapview
                CLLocationCoordinate2D DeviceCoordinates;
                
                DeviceCoordinates.latitude = [Lat doubleValue];
                DeviceCoordinates.longitude = [Lon doubleValue];
                if (DeviceCoordinates.latitude != 0.0 && DeviceCoordinates.longitude != 0.0)
                {
                    // Add the annotation to our map view
                    PositionPin *newAnnotation = [[PositionPin alloc] initWithTitle:UseThisDeviceName andCoordinate:DeviceCoordinates andColor:DeviceColor];
                    [DevicesMapView addAnnotation:newAnnotation];
                    NSLog(@"Added Annotation...");
                    //[newAnnotation release];
                    
                    // Zoom to fit...
                    
//                    MKMapRect zoomRect = MKMapRectNull;
//                    for (id <MKAnnotation> annotation in DevicesMapView.annotations)
//                    {
//                        MKMapPoint annotationPoint = MKMapPointForCoordinate(annotation.coordinate);
//                        MKMapRect pointRect = MKMapRectMake(annotationPoint.x+50, annotationPoint.y+50, 0.5, 0.5);
//                        zoomRect = MKMapRectUnion(zoomRect, pointRect);
//                    }
                    //[DevicesMapView setVisibleMapRect:zoomRect animated:NO];
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
     [NSURL URLWithString:[NSString stringWithFormat:@"%@/v1/GetLocation", miataru_server_url]]];
    
    
    [detailrequest setHTTPMethod:@"POST"];
    
    [detailrequest setValue:[NSString
                             stringWithFormat:@"%lu", (unsigned long)[GetLocationJSONContent length]]
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
