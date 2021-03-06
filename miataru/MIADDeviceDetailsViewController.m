//
//  MIADDeviceDetailsViewController.m
//  miataru
//
//  Created by Daniel Kirstenpfad on 08.09.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import "MIADDeviceDetailsViewController.h"
#import <CoreLocation/CoreLocation.h>
#import "KnownDevice.h"
#import "PositionPin.h"
#import "PassedTimeDateFormatter.h"
#import "MIADHistoryViewController.h"
#import "ZSPinAnnotation.h"

#define RGB(r, g, b) [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1]

@implementation MIADDeviceDetailsViewController {
}

@synthesize DeviceDetailMapView;
@synthesize DeviceDetail_UpdateDateTime;
@synthesize DeviceCoordinates;
@synthesize MapAnnotation;
@synthesize DetailDevice;
@synthesize mapScaleView;

- (void)viewDidLoad
{
    [super viewDidLoad];
    if ([self CheckDeviceID])
    {
        [self loadDeviceID];
    }

	// Do any additional setup after loading the view.
    NSInteger map_type = [[NSUserDefaults standardUserDefaults] integerForKey:@"map_type"];
    
    switch (map_type)
    {
        case 1:
            [DeviceDetailMapView setMapType:MKMapTypeStandard];
            break;
        case 2:
            [DeviceDetailMapView setMapType:MKMapTypeHybrid];
            break;
        case 3:
            [DeviceDetailMapView setMapType:MKMapTypeSatellite];
            break;
        default:
            [DeviceDetailMapView setMapType:MKMapTypeStandard];
            break;
    }
    
    // here comes the interesting part
	// get a handle to the map scale view of our mapView (by eventually installing one first)
	mapScaleView = [LXMapScaleView mapScaleForMapView:DeviceDetailMapView];
    mapScaleView.position = kLXMapScalePositionBottomRight;
	mapScaleView.style = kLXMapScaleStyleBar;
    //mapScaleView.style = kLXMapScaleStyleTapeMeasure;
    mapScaleView.alpha = 0.7;
    mapScaleView.maxWidth = 150;
    
    [mapScaleView update];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appDidEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
    
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark --- Timer related stuff here

- (void)viewWillDisappear:(BOOL)animated
{
    NSLog(@"Detail View goes away...");
    // here we will stop the timer...
    self.map_update_timer_should_stop = true;
}

- (void)viewDidAppear:(BOOL)animated
{
    if ( (BOOL)[[NSUserDefaults standardUserDefaults] boolForKey:@"disable_device_autolock_while_in_foreground"] == 1 )
    {
        [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
    }
    else
    {
        [[UIApplication sharedApplication] setIdleTimerDisabled:NO];
    }
        
    
    NSLog(@"Detail View appears...");
    // initialize the timer... it should start it's life now
    self.map_update_timer_should_stop = false;
    [NSTimer scheduledTimerWithTimeInterval:0 target:self selector:@selector(myTimerTick:) userInfo:nil repeats:false];
    
    NSInteger map_type = [[NSUserDefaults standardUserDefaults] integerForKey:@"map_type"];
    
    switch (map_type)
    {
        case 1:
            [DeviceDetailMapView setMapType:MKMapTypeStandard];
            break;
        case 2:
            [DeviceDetailMapView setMapType:MKMapTypeHybrid];
            break;
        case 3:
            [DeviceDetailMapView setMapType:MKMapTypeSatellite];
            break;
        default:
            [DeviceDetailMapView setMapType:MKMapTypeStandard];
            break;
    }    
}

- (void)appDidBecomeActive:(NSNotification *)notification {
    NSLog(@"detailview became active again");
    [self viewDidAppear:false];
}

- (void)appDidEnterForeground:(NSNotification *)notification {
    NSLog(@"detailview was sent to background");
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
        [self GetLocationForDeviceFromMiataruServer:self.DetailDevice.DeviceID];

        [NSTimer scheduledTimerWithTimeInterval:[[NSUserDefaults standardUserDefaults] integerForKey:@"map_update_interval"] target:self selector:@selector(myTimerTick:) userInfo:nil repeats:false];
    }
    
    //[timer invalidate]; //to stop and invalidate the timer.
}

#pragma mark MapView Annotation Clear
// to remove all pins but the users location...
- (void)removeAllPinsButUserLocation
{
    id userLocation = [self.DeviceDetailMapView userLocation];
    NSMutableArray *pins = [[NSMutableArray alloc] initWithArray:[self.DeviceDetailMapView annotations]];
    if ( userLocation != nil ) {
        [pins removeObject:userLocation]; // avoid removing user location off the map
    }
    
    [self.DeviceDetailMapView removeAnnotations:pins];
    //[pins release];
    pins = nil;
}

#pragma mark MapView Delegate Methods
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

- (void)zoomToFitMapAnnotations:(MKMapView *)mapView2 {
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


- (void)mapView:(MKMapView *)mapView didAddAnnotationViews:(NSArray *)views
{
    NSLog(@"didaddannotation");
    MKAnnotationView *annotationView = [views objectAtIndex:0];
    id <MKAnnotation> mp = [annotationView annotation];

    //CLLocationDistance visibleDistance = 5000;
    
    NSInteger distance_setting = [[NSUserDefaults standardUserDefaults] integerForKey:@"map_zoom_level"];

    if (distance_setting > 0)
    {
        MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance([mp coordinate],  distance_setting*1000, distance_setting*1000);
        [mapView setRegion:region animated:NO];
        [mapView selectAnnotation:mp animated:NO];
    }
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
    
    // NSMutableData in _responseData to json parsed...
    NSError *err = nil;
    //NSArray *jsonArray = [NSJSONSerialization JSONObjectWithData: self.responseData options: NSJSONReadingMutableContainers error: &err];
    
    NSString *strData = [[NSString alloc]initWithData:self.responseData encoding:NSUTF8StringEncoding];
    NSLog(@"%@",strData );
    
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
        
            if (Lat != nil && Lon != nil && [Lat class] != [NSNull class] && [Lon class] != [NSNull class])
            {
                // now get long and lat out and add pin to mapview
                DeviceCoordinates.latitude = [Lat doubleValue];
                DeviceCoordinates.longitude = [Lon doubleValue];
                
                double DeviceAccuracy = 5;
                
                if (Accuracy != nil && [Accuracy class] != [NSNull class])
                {
                    DeviceAccuracy = [Accuracy doubleValue];
                }
                
                if (DeviceCoordinates.latitude != 0.0 && DeviceCoordinates.longitude != 0.0)
                {
                    if (self.LastLatitude != DeviceCoordinates.latitude || self.LastLongitude != DeviceCoordinates.longitude || self.LastAccuracy != DeviceAccuracy)
                    {
                        self.LastLatitude = DeviceCoordinates.latitude;
                        self.LastLongitude = DeviceCoordinates.longitude;
                        self.LastAccuracy = DeviceAccuracy;
                        
                        //NSDate *startdate = [NSDate dateWithTimeIntervalSince1970:[Timestamp doubleValue]];
                        
                        DeviceDetail_UpdateDateTime = [NSDate dateWithTimeIntervalSince1970:[Timestamp doubleValue]];

                        // update the knowndevice
                        [DetailDevice setUpdateTime:DeviceDetail_UpdateDateTime];
                        
                        NSString *TimeString = [PassedTimeDateFormatter dateToStringInterval:DeviceDetail_UpdateDateTime];
                        
                        NSString* DeviceName = [NSString stringWithFormat:@"%@ - %@",self.DetailDevice.DeviceName,TimeString];
                        
                        // clear all others...
                        [self.DeviceDetailMapView removeOverlays:self.DeviceDetailMapView.overlays];
                        [self.DeviceDetailMapView removeAnnotations:self.DeviceDetailMapView.annotations];

                        //NSString* PinTitle = @"%@",self.DetailDevice.DeviceName;
                        // Add the annotation to our map view
                        MapAnnotation = [[PositionPin alloc] initWithTitle:DeviceName andCoordinate:DeviceCoordinates andColor:DetailDevice.DeviceColor];
                        
                        [self.DeviceDetailMapView addAnnotation:MapAnnotation];
                        NSLog(@"Added Annotation...");
                        
                        if ( (BOOL)[[NSUserDefaults standardUserDefaults] boolForKey:@"indicate_accuracy_on_map"] == 1 )
                        {
                            NSLog(@"Drawing Overlay...");
                            MKCircle *circle = [MKCircle circleWithCenterCoordinate:DeviceCoordinates radius:DeviceAccuracy];
                            [self.DeviceDetailMapView addOverlay:circle];
                        }
                        
                        //[newAnnotation release];
                        [self zoomToFitMapAnnotations:DeviceDetailMapView];
                        
                        return;
                    }
                    else
                    {
                        NSLog(@"We already have that pin");
                        // just update the passed time...
                        NSString *TimeString = [PassedTimeDateFormatter dateToStringInterval:DeviceDetail_UpdateDateTime];
                        
                        NSString* DeviceName = [NSString stringWithFormat:@"%@ - %@",self.DetailDevice.DeviceName,TimeString];
//                        
//                        // clear all others...
//                        [self.DeviceDetailMapView removeAnnotations:self.DeviceDetailMapView.annotations];
//                        
//                        PositionPin *newAnnotation = [[PositionPin alloc] initWithTitle:DeviceName andCoordinate:DeviceCoordinates];
//                        [self.DeviceDetailMapView addAnnotation:newAnnotation];

                        MapAnnotation.title = DeviceName;
                        
                        NSLog(@"Updated Annotation...");
                        
                        return;
                    }
                }
            }
        }
    }
    //self.map_update_timer_should_stop = true;
    // if we end up here, there has been an error...
    //NSString *message = [NSString stringWithFormat:@"Device %@ could not be found.", self.DetailDevice.DeviceName];
    
    /*UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error"
                                                    message:message
                                                   delegate:nil
                                          cancelButtonTitle:@"OK"
                                          otherButtonTitles:nil];
    [alert show];*/
    // TODO: transition back
    //[self.navigationController popToRootViewControllerAnimated:YES];
}

+(NSString*)generateRandomString:(int)num {
    NSMutableString* string = [NSMutableString stringWithCapacity:num];
    for (int i = 0; i < num; i++) {
        [string appendFormat:@"%C", (unichar)('a' + arc4random_uniform(25))];
    }
    return string;
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    // The request has failed for some reason!
    // Check the error var
    NSLog(@"Connection failed: %@",error);
    //self.map_update_timer_should_stop = true;
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
}

#pragma mark - GetLocationForDeviceFromMiataruServer

- (void)GetLocationForDeviceFromMiataruServer:(NSString*)deviceID
{
    if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground)
        return;
    
    if (deviceID == nil)
        return;
    
    [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    /*
        ￼{"MiataruGetLocation": [{"Device":"7b8e6e0ee5296db345162dc2ef652c1350761823"}]}
        [UIDevice currentDevice].identifierForVendor.UUIDString
    */
    
    NSString* GetLocationJSONContent = [NSString stringWithFormat:@"{\"MiataruConfig\":{\"RequestMiataruDeviceID\": \"%@\"},\"MiataruGetLocation\": [{\"Device\":\"%@\"}]}",self.device_id,deviceID];
    
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
    
    [detailrequest setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
   
    [detailrequest setHTTPBody:[GetLocationJSONContent dataUsingEncoding:NSUTF8StringEncoding]];
        
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
    
    [NSURLConnection connectionWithRequest:detailrequest delegate:self];
    
    NSLog(@"%@", GetLocationJSONContent);
    
    NSLog(@"Getting Update from to Miataru Service...");
}

#pragma mark Segues

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.identifier isEqualToString:@"PushToDeviceHistory"]) {
        ((MIADHistoryViewController*)segue.destinationViewController).HistoryDevice = self.DetailDevice;
    }
}

#pragma mark MapScale
- (void)mapView:(MKMapView*)aMapView regionDidChangeAnimated:(BOOL)aAnimated
{
	// the map scale will retrieve the current state of the mapView it is attached to
	// and update itself accordingly
	[mapScaleView update];
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
@end
