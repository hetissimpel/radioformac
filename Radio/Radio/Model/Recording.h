//
//  Recording.h
//  Radio
//
//  Created by Damien Glancy on 03/11/2012.
//  Copyright (c) 2012 Het is Simpel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@interface Recording : NSManagedObject

@property(nonatomic, retain) NSString *audio;
@property(nonatomic, retain) NSDate *endDate;
@property(nonatomic, retain) NSDate *startDate;
@property(nonatomic, retain) NSString *channelName;
@property(nonatomic, retain) NSString *durationString;

@end