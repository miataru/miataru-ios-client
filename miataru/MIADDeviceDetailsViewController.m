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


- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
    //NSLog(self.DetailDevice.DeviceID);
    [self GetLocationForDeviceFromMiataruServer:self.DetailDevice.DeviceID];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
- (IBAction)CancelButtonAction:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark MapView Delegate Methods
- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id <MKAnnotation>)annotation
{
    
    NSLog(@"here!!");
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
    
    NSDictionary* jsonArray = [NSJSONSerialization
                          JSONObjectWithData:self.responseData //1
                          options:NSJSONReadingMutableContainers
                          error:&err];
    
    NSArray* MiataruLocations = [jsonArray objectForKey:@"MiataruLocation"]; //2
    
    NSString* Lat = [MiataruLocations[0] objectForKey:@"Latitude"];
    NSString* Lon = [MiataruLocations[0] objectForKey:@"Longitude"];
    
    // now get long and lat out and add pin to mapview
    CLLocationCoordinate2D DeviceCoordinates;
    
	DeviceCoordinates.latitude = [Lat doubleValue];
	DeviceCoordinates.longitude = [Lon doubleValue];
    
	// Add the annotation to our map view
	PositionPin *newAnnotation = [[PositionPin alloc] initWithTitle:self.DetailDevice.DeviceName andCoordinate:DeviceCoordinates];
	[self.DeviceDetailMapView addAnnotation:newAnnotation];
    NSLog(@"Added Annotation...");
	//[newAnnotation release];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    // The request has failed for some reason!
    // Check the error var
    NSLog(@"Connection failed: %@",error);
}

#pragma mark - GetLocationForDeviceFromMiataruServer

- (void)GetLocationForDeviceFromMiataruServer:(NSString*)deviceID
{
    /*
        ￼{"MiataruGetLocation": [{"Device":"7b8e6e0ee5296db345162dc2ef652c1350761823"}]}
    */
    
    NSString* GetLocationJSONContent = [NSString stringWithFormat:@"{\"MiataruGetLocation\": [{\"Device\":\"%@\"}]}",deviceID];
    
    self.responseData = [NSMutableData data];
   
    NSMutableURLRequest *detailrequest = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://service.miataru.com/GetLocation"]];
        
    
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
