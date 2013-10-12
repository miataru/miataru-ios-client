//
//  PassedTimeDateFormatter.m
//  miataru
//
//  Created by Daniel Kirstenpfad on 12.10.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import "PassedTimeDateFormatter.h"

@implementation PassedTimeDateFormatter

+ (NSString*)dateToStringInterval:(NSDate*)pastDate
{
    // Get the system calendar
    NSCalendar *sysCalendar = [NSCalendar currentCalendar];
    
    // Create the current date
    NSDate *currentDate = [[NSDate alloc] init];
    
    // Get conversion to months, days, hours, minutes
    unsigned int unitFlags = NSHourCalendarUnit | NSMinuteCalendarUnit | NSDayCalendarUnit | NSMonthCalendarUnit;
    
    NSDateComponents *breakdownInfo = [sysCalendar components:unitFlags fromDate:currentDate  toDate:pastDate  options:0];
    
    NSString *intervalString;
    if ([breakdownInfo month]) {
        if (-[breakdownInfo month] > 1)
            intervalString = [NSString stringWithFormat:@"%d months ago", -[breakdownInfo month]];
        else
            intervalString = @"1 month ago";
    }
    else if ([breakdownInfo day]) {
        if (-[breakdownInfo day] > 1)
            intervalString = [NSString stringWithFormat:@"%d days ago", -[breakdownInfo day]];
        else
            intervalString = @"1 day ago";
    }
    else if ([breakdownInfo hour]) {
        if (-[breakdownInfo hour] > 1)
            intervalString = [NSString stringWithFormat:@"%d hours ago", -[breakdownInfo hour]];
        else
            intervalString = @"1 hour ago";
    }
    else {
        if (-[breakdownInfo minute] > 1)
            intervalString = [NSString stringWithFormat:@"%d minutes ago", -[breakdownInfo minute]];
        else
            intervalString = @"just now";
    }
    
    return intervalString;
}


@end
