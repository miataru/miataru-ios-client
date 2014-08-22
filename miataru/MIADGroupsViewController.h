//
//  MIADMapViewController.h
//  Miataru
//
//  Created by Daniel Kirstenpfad on 15.08.14.
//  Copyright (c) 2014 Miataru. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>
#import "LXMapScaleView.h"

@class KnownDevice;

@interface MIADGroupsViewController : UIViewController<NSURLConnectionDelegate,MKMapViewDelegate>

@property (strong) NSMutableData *responseData;

@property (weak, nonatomic) IBOutlet MKMapView *DevicesMapView;
@property LXMapScaleView* mapScaleView;
@property (strong) NSMutableArray *known_devices;
@property (weak) KnownDevice *last_known_device;
@property BOOL zoom_to_fit;
@property NSMutableArray *ToBeRemovedPins;
@property NSInteger ToRenderDevices;
@property NSInteger RenderedDevices;

@property BOOL map_update_timer_should_stop;

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id <MKAnnotation>)annotation;

- (void)mapView:(MKMapView *)mapView didAddAnnotationViews:(NSArray *)views;

@end
