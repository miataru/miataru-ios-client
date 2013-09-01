//
//  UpdateLocation.h
//  miataru
//
//  Created by Daniel Kirstenpfad on 01.09.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MiataruConfig : NSObject

@property (nonatomic, copy) NSString* enableLocationHistory;
@property (nonatomic) unsigned int locationDataRetentionTime;

@end

@interface MiataruLocation : NSObject

@property (nonatomic, copy) NSString* deviceID;
@property (nonatomic) unsigned int timestamp;
@property (nonatomic) double longitude;
@property (nonatomic) double latitude;
@property (nonatomic) double horizontalaccuracy;

@end

@interface UpdateLocation : NSObject

@property (nonatomic, strong) MiataruConfig* MiataruConfig;
@property (nonatomic, strong) MiataruLocation* MiataruLocation;

@end
