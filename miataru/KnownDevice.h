//
//  KnownDevice.h
//  miataru
//
//  Created by Daniel Kirstenpfad on 07.09.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <MapKit/MapKit.h>
#import "GeoHash.h"

@interface KnownDevice : NSObject <NSCoding>

@property (strong) NSString *DeviceName;
@property (strong) NSString *DeviceID;

@property (strong) NSDate *LastUpdate;
@property CLLocationCoordinate2D LastKnownLocation;

+ (id) DeviceWithName:(NSString*)inName DeviceID:(NSString*)inDeviceID;

@end
