//
//  Channel.h
//  Radio
//
//  Created by Damien Glancy on 03/11/2012.
//  Copyright (c) 2012 Het is Simpel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>


@interface Channel : NSManagedObject

@property(nonatomic, retain) NSString *desc;
@property(nonatomic, retain) NSString *guid;
@property(nonatomic, retain) NSString *keywords;
@property(nonatomic, retain) NSString *name;
@property(nonatomic, retain) NSNumber *no;
@property(nonatomic, retain) NSNumber *type;
@property(nonatomic, retain) NSString *url;
@property(nonatomic, retain) NSString *website;
@property(nonatomic, retain) NSNumber *favourite;
@property(nonatomic, retain) NSString *languages;
@property(nonatomic, retain) NSString *country;
@property(nonatomic, retain) NSString *city;
@end