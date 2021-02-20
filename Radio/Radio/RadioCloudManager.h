//
//  RadioCloudManager
//  Viscis
//
//  Created by dglancy on 03/12/2012.
//  Copyright (c) 2012 Het is Simpel. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface RadioCloudManager : NSObject

@property(strong, nonatomic) NSUbiquitousKeyValueStore *keyStore;

+ (id)cloudManager;
- (void)syncWithCloud;

- (void)addChannelToCloud:(Channel *)channel;
- (void)removeChannelFromCloud:(Channel *)channel;
- (void)favouriteChannelInCloud:(Channel *)channel;
- (void)unfavouriteChannelInCloud:(Channel *)channel;
- (void)reset;

- (BOOL)isChannelMarkedFavInCloud:(Channel *)channel;
- (BOOL)isChannelInCloud:(Channel *)channel;

@end