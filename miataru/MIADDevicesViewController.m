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
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    self.locationManager.delegate = self;
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

- (IBAction)accuracyChanged:(id)sender
{
    /*const CLLocationAccuracy accuracyValues[] = {
        kCLLocationAccuracyBestForNavigation,
        kCLLocationAccuracyBest,
        kCLLocationAccuracyNearestTenMeters,
        kCLLocationAccuracyHundredMeters,
        kCLLocationAccuracyKilometer,
        kCLLocationAccuracyThreeKilometers};
    */
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
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
/*        // determine the region the points span so we can update our map's zoom.
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
        NSLog(@"App is foregrounded. New location is %@", newLocation);
    }
    else
    {
        NSLog(@"App is backgrounded. New location is %@", newLocation);
    }
}

@end
