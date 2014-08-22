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
@synthesize ToBeRemovedPins;
@synthesize RenderedDevices;
@synthesize ToRenderDevices;

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

- (void)viewWillDisappear:(BOOL)animated
{
    NSLog(@"Detail View goes away...");
    // here we will stop the timer...
    self.map_update_timer_should_stop = true;
}

- (void)viewDidAppear:(BOOL)animated
{
    NSLog(@"Group Map did appear");
    
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
    
    self.map_update_timer_should_stop = false;
    self.zoom_to_fit = true;
    
    [NSTimer scheduledTimerWithTimeInterval:0 target:self selector:@selector(myTimerTick:) userInfo:nil repeats:false];

}

- (void)myTimerTick:(NSTimer *)timer
{
    if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground)
    {
        self.map_update_timer_should_stop = true;
    }
    
    
    if (self.map_update_timer_should_stop == true)
    {
        NSLog(@"Stopping Timer Updates");
    }
    else
    {
        [self removeAllPinsButUserLocation];
        ToRenderDevices = 0;
        RenderedDevices = 0;
        
        // go through self.known_devices and get all known_device objects out of that...
        for(KnownDevice *kDevice in self.known_devices)
        {
            // here we go - get the location and pin for this device but only if this device is marked in the "device is in group" list
            if (kDevice.DeviceIsInGroup)
            {
                [self GetLocationForDeviceFromMiataruServer:kDevice];
                self.last_known_device = kDevice;
                ToRenderDevices++;
            }
        }

        [NSTimer scheduledTimerWithTimeInterval:[[NSUserDefaults standardUserDefaults] integerForKey:@"map_update_interval"] target:self selector:@selector(myTimerTick:) userInfo:nil repeats:false];
    }
    
    //[timer invalidate]; //to stop and invalidate the timer.
}

- (IBAction)ZoomToFitButton:(id)sender {

    [self zoomToFitMapAnnotations:DevicesMapView];
}

-(MKOverlayView *)mapView:(MKMapView *)mapView viewForOverlay:(id)overlay
{
    MKCircleView *circleView = [[MKCircleView alloc] initWithOverlay:overlay];
    //    circleView.strokeColor = [UIColor redColor];
    //    circleView.lineWidth = 2;
    circleView.fillColor = [UIColor blueColor];
    circleView.opaque = true;
    circleView.alpha = 0.1;
    return circleView;
}

- (void)zoomToFitMapAnnotations:(MKMapView *)mapView2 {
    
    NSLog(@"Zoom To Fit");
    if ([mapView2.annotations count] == 0) return;
    
    CLLocationCoordinate2D topLeftCoord;
    topLeftCoord.latitude = -90;
    topLeftCoord.longitude = 180;
    
    CLLocationCoordinate2D bottomRightCoord;
    bottomRightCoord.latitude = 90;
    bottomRightCoord.longitude = -180;
    
    for(id<MKAnnotation> annotation in mapView2.annotations) {
        topLeftCoord.longitude = fmin(topLeftCoord.longitude, annotation.coordinate.longitude);
        topLeftCoord.latitude = fmax(topLeftCoord.latitude, annotation.coordinate.latitude);
        bottomRightCoord.longitude = fmax(bottomRightCoord.longitude, annotation.coordinate.longitude);
        bottomRightCoord.latitude = fmin(bottomRightCoord.latitude, annotation.coordinate.latitude);
    }
    
    MKCoordinateRegion region;
    //MKCoordinateRegion region;
    region.center.latitude = topLeftCoord.latitude - (topLeftCoord.latitude - bottomRightCoord.latitude) * 0.5;
    region.center.longitude = topLeftCoord.longitude + (bottomRightCoord.longitude - topLeftCoord.longitude) * 0.5;
    
    // Adding edge map
    region.span.latitudeDelta = fabs(topLeftCoord.latitude - bottomRightCoord.latitude) * 1.5;
    region.span.longitudeDelta = fabs(bottomRightCoord.longitude - topLeftCoord.longitude) * 1.5;
    
    region = [mapView2 regionThatFits:region];
    [mapView2 setRegion:region animated:NO];
    
}



- (void)viewDidDisappear:(BOOL)animated
{
    NSLog(@"Group Map disappeared");
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
    if (ToBeRemovedPins == nil)
    {
        id userLocation = [DevicesMapView userLocation];
        ToBeRemovedPins = [[NSMutableArray alloc] initWithArray:[DevicesMapView annotations]];
        if ( userLocation != nil ) {
            [ToBeRemovedPins removeObject:userLocation]; // avoid removing user location off the map
        }
    }
    else{
        [DevicesMapView removeOverlays:[DevicesMapView overlays]];
        [DevicesMapView removeAnnotations:ToBeRemovedPins];
        ToBeRemovedPins = nil;
    }
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
            NSString* Accuracy = [MiataruLocations[0] objectForKey:@"HorizontalAccuracy"];
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
            
            double DeviceAccuracy = 5;
            
            if (Accuracy != nil && [Accuracy class] != [NSNull class])
            {
                DeviceAccuracy = [Accuracy doubleValue];
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
                    if ( (BOOL)[[NSUserDefaults standardUserDefaults] boolForKey:@"indicate_accuracy_on_map"] == 1 )
                    {
                        NSLog(@"Drawing Overlay...");
                        MKCircle *circle = [MKCircle circleWithCenterCoordinate:DeviceCoordinates radius:DeviceAccuracy];
                        [self.DevicesMapView addOverlay:circle];
                    }
                    
                    RenderedDevices++;
                    if (RenderedDevices == ToRenderDevices)
                    {
                        // this must be the last one to be rendered...
                        NSLog(@"this was the last Annotation for this run");
                        // do the zoom thing once...
                        if (self.zoom_to_fit)
                        {
                            [self zoomToFitMapAnnotations:DevicesMapView];
                            
                            if ( (BOOL)[[NSUserDefaults standardUserDefaults] boolForKey:@"groups_zoom_to_fit"] == 1 )
                            {
                                self.zoom_to_fit = true;
                            }
                            else
                            {
                                self.zoom_to_fit = false;
                            }
                        }
                        
                        // remove the old pins, if there are any...
                        [self removeAllPinsButUserLocation];
                    }
                    
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
