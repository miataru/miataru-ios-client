//
//  MIADMapViewController.h
//  Miataru
//
//  Created by Daniel Kirstenpfad on 27.09.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>

@interface MIADMapViewController : UIViewController <NSURLConnectionDelegate,MKMapViewDelegate>

@property (strong) NSMutableData *responseData;

@end
