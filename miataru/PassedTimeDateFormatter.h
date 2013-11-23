//
//  PassedTimeDateFormatter.h
//  miataru
//
//  Created by Daniel Kirstenpfad on 12.10.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface PassedTimeDateFormatter : NSObject

+ (NSString*)dateToStringInterval:(NSDate*)pastDate;
+ (bool)isWithinDayRange:(NSDate*)PastDate DayRange:(long)dayRange;

@end
