//
//  KnownDevice.m
//  miataru
//
//  Created by Daniel Kirstenpfad on 07.09.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import "KnownDevice.h"

@implementation KnownDevice

+ (id) DeviceWithName:(NSString*)inName DeviceID:(NSString*)inDeviceID;
{
    KnownDevice *device = [[KnownDevice alloc] init];

    device.DeviceName = inName;
    device.DeviceID = inDeviceID;
   
    return device;
}

-(void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:self.DeviceName forKey:@"DeviceName"];
    [aCoder encodeObject:self.DeviceID forKey:@"DeviceID"];
    [aCoder encodeObject:self.LastUpdate forKey:@"LastUpdate"];
    
    if (CLLocationCoordinate2DIsValid(self.LastKnownLocation))
    {
        NSString *hash = [GeoHash hashForLatitude: self.LastKnownLocation.latitude
                                    longitude: self.LastKnownLocation.longitude
                                       length: 13];
        // geohash encode the location...
        [aCoder encodeObject:hash forKey:@"LastKnownLocation"];
    }
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    if (! (self = [super init])) {
        return nil;
    }

    self.DeviceID = [aDecoder decodeObjectForKey:@"DeviceID"];
    self.DeviceName = [aDecoder decodeObjectForKey:@"DeviceName"];
    self.LastUpdate = [aDecoder decodeObjectForKey:@"LastUpdate"];
   
    NSString *hash = [aDecoder decodeObjectForKey:@"LastKnownLocation"];
    
    if (hash)
    {
        GHArea *area = [GeoHash areaForHash:hash];
        self.LastKnownLocation = CLLocationCoordinate2DMake(area.latitude.min.doubleValue, area.longitude.min.doubleValue);
    }
    return self;
}


@end
