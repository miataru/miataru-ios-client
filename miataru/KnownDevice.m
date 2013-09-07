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
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    if (! (self = [super init])) {
        return nil;
    }

    self.DeviceID = [aDecoder decodeObjectForKey:@"DeviceID"];
    self.DeviceName = [aDecoder decodeObjectForKey:@"DeviceName"];
    
    return self;
}


@end
