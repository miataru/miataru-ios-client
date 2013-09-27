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

//@interface MIADDeviceDetailsViewController ()
//
//@end

@implementation MIADDeviceDetailsViewController

@synthesize DeviceDetailMapView;


//- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
//{
//    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
//    if (self) {
//        // Custom initialization
//
//    }
//    return self;
//}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
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
    NSLog(@"Detail View appears...");
    // initialize the timer... it should start it's life now
    self.map_update_timer_should_stop = false;
    [NSTimer scheduledTimerWithTimeInterval:0 target:self selector:@selector(myTimerTick:) userInfo:nil repeats:false];
}


- (void)myTimerTick:(NSTimer *)timer
{
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
- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id <MKAnnotation>)annotation
{
    
    NSLog(@"viewForAnnotation");
//    static NSString *identifier = @"MyLocation";
//    if ([annotation isKindOfClass:[PositionPin class]]) {
//        
//        MKPinAnnotationView *annotationView = (MKPinAnnotationView *) [DeviceDetailMapView dequeueReusableAnnotationViewWithIdentifier:identifier];
//        if (annotationView == nil) {
//            annotationView = [[MKPinAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:identifier];
//        } else {
//            annotationView.annotation = annotation;
//        }
//        
//        annotationView.enabled = YES;
//        annotationView.canShowCallout = YES;
//        //annotationView.image=[UIImage imageNamed:@"Icon.png"];//here we use a nice image instead of the default pins
//        
//        return annotationView;
//    }
    
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
    
    // NSMutableData in _responseData to json parsed...
    NSError *err = nil;
    //NSArray *jsonArray = [NSJSONSerialization JSONObjectWithData: self.responseData options: NSJSONReadingMutableContainers error: &err];
    
    //NSLog(@"%@",self.responseData);
    
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
        
            if (Lat != nil && Lon != nil && [Lat class] != [NSNull class] && [Lon class] != [NSNull class])
            {
                // now get long and lat out and add pin to mapview
                CLLocationCoordinate2D DeviceCoordinates;
            
                DeviceCoordinates.latitude = [Lat doubleValue];
                DeviceCoordinates.longitude = [Lon doubleValue];
                if (DeviceCoordinates.latitude != 0.0 && DeviceCoordinates.longitude != 0.0)
                {
                    if (self.LastLatitude != DeviceCoordinates.latitude && self.LastLongitude != DeviceCoordinates.longitude)
                    {
                        self.LastLatitude = DeviceCoordinates.latitude;
                        self.LastLongitude = DeviceCoordinates.longitude;
                        // clear all others...
                        [self.DeviceDetailMapView removeAnnotations:self.DeviceDetailMapView.annotations];
                        
                        //NSString* PinTitle = @"%@",self.DetailDevice.DeviceName;
                        // Add the annotation to our map view
                        PositionPin *newAnnotation = [[PositionPin alloc] initWithTitle:self.DetailDevice.DeviceName andCoordinate:DeviceCoordinates];
                        [self.DeviceDetailMapView addAnnotation:newAnnotation];
                        NSLog(@"Added Annotation...");
                        //[newAnnotation release];
                    
                        return;
                    }
                    else
                    {
                        NSLog(@"We already have that pin");
                        return;
                    }
                }
            }
        }
    }
    self.map_update_timer_should_stop = true;
    // if we end up here, there has been an error...
    NSString *message = [NSString stringWithFormat:@"Could not find Data for Device %@ - Maybe you need to enable Reporting to Server?", self.DetailDevice.DeviceName];
    
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error"
                                                    message:message
                                                   delegate:nil
                                          cancelButtonTitle:@"OK"
                                          otherButtonTitles:nil];
    [alert show];
    // TODO: transition back
    //[self.navigationController popToRootViewControllerAnimated:YES];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    // The request has failed for some reason!
    // Check the error var
    NSLog(@"Connection failed: %@",error);
    self.map_update_timer_should_stop = true;
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
}

#pragma mark - GetLocationForDeviceFromMiataruServer

- (void)GetLocationForDeviceFromMiataruServer:(NSString*)deviceID
{
    [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    /*
        ￼{"MiataruGetLocation": [{"Device":"7b8e6e0ee5296db345162dc2ef652c1350761823"}]}
    */
    
    NSString* GetLocationJSONContent = [NSString stringWithFormat:@"{\"MiataruGetLocation\": [{\"Device\":\"%@\"}]}",deviceID];
    
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
