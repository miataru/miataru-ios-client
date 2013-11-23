//
//  PositionPin.m
//  miataru
//
//  Created by Daniel Kirstenpfad on 14.09.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import "PositionPin.h"

@implementation PositionPin

@synthesize title, coordinate;

- (id)initWithTitle:(NSString *)ttl andCoordinate:(CLLocationCoordinate2D)c2d
{
	title = ttl;
	coordinate = c2d;
	return self;
}

@end
