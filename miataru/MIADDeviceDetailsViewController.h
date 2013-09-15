//
//  MIADDeviceDetailsViewController.h
//  miataru
//
//  Created by Daniel Kirstenpfad on 08.09.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>

@class KnownDevice;

@interface MIADDeviceDetailsViewController : UIViewController<NSURLConnectionDelegate,MKMapViewDelegate>

@property (strong) KnownDevice *DetailDevice;
@property (strong) NSMutableData *responseData;
@property (weak, nonatomic) IBOutlet MKMapView *DeviceDetailMapView;

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id <MKAnnotation>)annotation;

- (void)mapView:(MKMapView *)mapView didAddAnnotationViews:(NSArray *)views;
@end
