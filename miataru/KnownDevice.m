//
//  KnownDevice.m
//  miataru
//
//  Created by Daniel Kirstenpfad on 07.09.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import "KnownDevice.h"

//#define RGB(r, g, b) [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1]

@implementation KnownDevice

+ (id) DeviceWithName:(NSString*)inName DeviceID:(NSString*)inDeviceID;
{
    KnownDevice *device = [[KnownDevice alloc] init];

    device.DeviceName = inName;
    device.DeviceID = inDeviceID;
    device.DeviceColor = [UIColor redColor];
   
    return device;
}

-(void)setUpdateTime:(NSDate*)NewUpdateDateTime
{
    self.LastUpdate = NewUpdateDateTime;
}

-(void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:self.DeviceName forKey:@"DeviceName"];
    [aCoder encodeObject:self.DeviceID forKey:@"DeviceID"];
    [aCoder encodeObject:self.LastUpdate forKey:@"LastUpdate"];
    [aCoder encodeObject:self.DeviceColor forKey:@"DeviceColor"];
    [aCoder encodeBool:self.DeviceIsInGroup forKey:@"DeviceIsInGroup"];
    
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
    self.DeviceColor = [aDecoder decodeObjectForKey:@"DeviceColor"];
    self.DeviceIsInGroup = [aDecoder decodeBoolForKey:@"DeviceIsInGroup"];
    
    NSString *hash = [aDecoder decodeObjectForKey:@"LastKnownLocation"];
    
    if (hash)
    {
        GHArea *area = [GeoHash areaForHash:hash];
        self.LastKnownLocation = CLLocationCoordinate2DMake(area.latitude.min.doubleValue, area.longitude.min.doubleValue);
    }
    return self;
}


@end
