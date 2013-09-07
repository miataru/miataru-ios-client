//
//  KnownDevice.h
//  miataru
//
//  Created by Daniel Kirstenpfad on 07.09.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface KnownDevice : NSObject <NSCoding>

@property (strong) NSString *DeviceName;
@property (strong) NSString *DeviceID;

+ (id) DeviceWithName:(NSString*)inName DeviceID:(NSString*)inDeviceID;

@end
