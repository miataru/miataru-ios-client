//
//  PositionPin.h
//  miataru
//
//  Created by Daniel Kirstenpfad on 14.09.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <MapKit/MapKit.h>

@interface PositionPin : NSObject<MKAnnotation> {
    CLLocationCoordinate2D coordinate;
}

@end
