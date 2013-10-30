//
//  PassedTimeDateFormatter.h
//  miataru
//
//  Created by Daniel Kirstenpfad on 12.10.13.
//  Copyright (c) 2013 Miataru. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface PassedTimeDateFormatter : NSObject<NSURLConnectionDelegate>

+ (NSString*)dateToStringInterval:(NSDate*)pastDate;

@end
