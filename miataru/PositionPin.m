//
//  PositionPin.m
//  miataru
//
//  Created by Daniel Kirstenpfad on 14.09.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import "PositionPin.h"

@implementation PositionPin

@synthesize coordinate;

- (NSString *)subtitle{
    return nil;
}

- (NSString *)title{
    return nil;
}

-(id)initWithCoordinate:(CLLocationCoordinate2D) c{
    coordinate=c;
    return self;
}

@end