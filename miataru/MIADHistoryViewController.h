//
//  MIADHistoryViewController.h
//  miataru
//
//  Created by Daniel Kirstenpfad on 08.11.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "KnownDevice.h"
#import "LXMapScaleView.h"

@interface MIADHistoryViewController : UIViewController<NSURLConnectionDelegate,MKMapViewDelegate>

@property (strong) KnownDevice *HistoryDevice;
@property (weak, nonatomic) IBOutlet MKMapView *HistoryMapView;
@property LXMapScaleView* mapScaleView;

@property (strong) NSMutableData *responseData;

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id <MKAnnotation>)annotation;

- (void)mapView:(MKMapView *)mapView didAddAnnotationViews:(NSArray *)views;

@end
