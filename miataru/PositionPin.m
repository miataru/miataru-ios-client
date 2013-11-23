//
//  PositionPin.m
//  miataru
//
//  Created by Daniel Kirstenpfad on 14.09.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import "PositionPin.h"
#import "ZSPinAnnotation.h"

@implementation PositionPin

@synthesize title, coordinate, color, type;

- (id)initWithTitle:(NSString *)ttl andCoordinate:(CLLocationCoordinate2D)c2d andColor:(UIColor*)PinColor
{
	title = ttl;
	coordinate = c2d;
    if (PinColor == nil)
    {
        color = [UIColor redColor];
    }
    else
        color = PinColor;
    
    type = ZSPinAnnotationTypeStandard;
    
	return self;
}

@end
