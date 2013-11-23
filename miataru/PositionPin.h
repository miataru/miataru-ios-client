//
//  PositionPin.h
//  miataru
//
//  Created by Daniel Kirstenpfad on 14.09.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <MapKit/MapKit.h>
#import "ZSPinAnnotation.h"

@interface PositionPin : NSObject <MKAnnotation>
    
/// The coordinate for the annotation
@property (nonatomic, readonly) CLLocationCoordinate2D coordinate;

/// The title for the annotation
@property (nonatomic, copy) NSString *title;

/// The subtitle for the annotation
@property (nonatomic, copy) NSString *subtitle;
    
/// The color of the annotation
@property (nonatomic, strong) UIColor *color;
    
/// The type of annotation to draw
@property (nonatomic) ZSPinAnnotationType type;

- (id)initWithTitle:(NSString *)ttl andCoordinate:(CLLocationCoordinate2D)c2d andColor:(UIColor*)PinColor;

@end
