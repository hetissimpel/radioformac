//
//  RadioCloudManager
//  Viscis
//
//  Created by dglancy on 03/12/2012.
//  Copyright (c) 2012 Het is Simpel. All rights reserved.
//

#import "RadioCloudManager.h"

#define kCloudChannels @"CloudChannels"
#define kCloudFavourites @"CloudFavourites"

#define kName @"name"
#define kGuid @"guid"
#define kUrl @"url"
#define kDesc @"desc"

@implementation RadioCloudManager

+ (id)cloudManager {
    static dispatch_once_t onceQueue;
    static RadioCloudManager *radioCloudManager = nil;
    
    dispatch_once(&onceQueue, ^{
        radioCloudManager = [[self alloc] init];
        
        dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
        dispatch_async(queue, ^{
            radioCloudManager.keyStore = [NSUbiquitousKeyValueStore defaultStore];
            
            if (radioCloudManager.keyStore) {
                NSLog(@"[RADIO CLOUD MANAGER] Registering for incoming updates from iCloud");
                [[NSNotificationCenter defaultCenter] addObserver:radioCloudManager selector:@selector(incomingUpdatesFromCloud:) name:NSUbiquitousKeyValueStoreDidChangeExternallyNotification object:radioCloudManager.keyStore];
                [radioCloudManager.keyStore synchronize];
            }
        });
    });
    
    return radioCloudManager;
}

- (void)addChannelToCloud:(Channel *)channel {
    if ([self isChannelInCloud:channel]) {
        NSLog(@"[RADIO CLOUD MANAGER] %@ is already stored in iCloud", channel.url);
        return;
    }

    NSLog(@"[RADIO CLOUD MANAGER] Adding channel %@ to iCloud", channel.url);
    NSDictionary *cloudChannel = [[NSMutableDictionary alloc] init];
    [cloudChannel setValue:channel.name forKey:kName];
    [cloudChannel setValue:channel.guid forKey:kGuid];
    [cloudChannel setValue:channel.url forKey:kUrl];
    [cloudChannel setValue:channel.desc forKey:kDesc];

    NSMutableArray *array = [NSMutableArray arrayWithArray:[_keyStore objectForKey:kCloudChannels]];
    [array addObject:cloudChannel];
    [_keyStore setObject:array forKey:kCloudChannels];
}

- (void)removeChannelFromCloud:(Channel *)channel {
    NSMutableArray *array = [NSMutableArray arrayWithArray:[_keyStore objectForKey:kCloudChannels]];

    for (NSUInteger i = 0; i < array.count; i++) {
        NSDictionary *cloudChannel = array[i];
        NSString *guid = [cloudChannel objectForKey:kGuid];
        if ([guid isEqualToString:channel.guid]) {
            NSLog(@"[RADIO CLOUD MANAGER] Removing channel %@ from iCloud", channel.url);
            [array removeObjectAtIndex:i];
            break;
        }
    }
    [_keyStore setObject:array forKey:kCloudChannels];
}

- (void)favouriteChannelInCloud:(Channel *)channel {
    if ([self isChannelMarkedFavInCloud:channel]) {
        NSLog(@"[RADIO CLOUD MANAGER] %@ is already a favourite in iCloud", channel.url);
        return;
    }

    NSLog(@"[RADIO CLOUD MANAGER] Marking %@ as favourite in iCloud", channel.url);

    NSMutableArray *array = [NSMutableArray arrayWithArray:[_keyStore objectForKey:kCloudFavourites]];
    [array addObject:channel.guid];
    [_keyStore setObject:array forKey:kCloudFavourites];
}

- (void)unfavouriteChannelInCloud:(Channel *)channel {
    NSLog(@"[RADIO CLOUD MANAGER] Unmarking %@ as favourite in iCloud", channel.url);

    NSMutableArray *array = [NSMutableArray arrayWithArray:[_keyStore objectForKey:kCloudFavourites]];
    [array removeObject:channel.guid];
    [_keyStore setObject:array forKey:kCloudFavourites];
}

- (void)incomingUpdatesFromCloud:(id)sender {
    NSLog(@"[RADIO CLOUD MANAGER] Incoming updates from iCloud");
    [self syncWithCloud];
}

- (void)syncWithCloud {
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
    dispatch_async(queue, ^{
        RadioAppDelegate *app = GetAppDelegate();

        NSManagedObjectContext *backgroundContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        backgroundContext.parentContext = app.managedObjectContext;
        backgroundContext.undoManager = nil;

        // *** Channels ***
        NSMutableArray *arrayChannels = [NSMutableArray arrayWithArray:[_keyStore objectForKey:kCloudChannels]];

        NSMutableArray *userStationGuids = [[NSMutableArray alloc] init];
        for (NSDictionary *cloudChannel in arrayChannels) {
            Channel *channel;

            NSFetchRequest *request = [[NSFetchRequest alloc] init];
            request.entity = [NSEntityDescription entityForName:@"Channel" inManagedObjectContext:backgroundContext];
            request.predicate = [NSPredicate predicateWithFormat:@"guid == %@", [cloudChannel objectForKey:kGuid]];
            
            NSArray *results = [backgroundContext executeFetchRequest:request error:nil];
            if (!results || results.count == 0) {
                NSLog(@"[RADIO CLOUD MANAGER] Adding new channel from cloud: %@", [cloudChannel objectForKey:kUrl]);
                channel = [NSEntityDescription insertNewObjectForEntityForName:@"Channel" inManagedObjectContext:backgroundContext];
            } else {
                channel = (Channel *)results[0];
            }

            channel.guid = [cloudChannel objectForKey:kGuid];
            channel.name = [cloudChannel objectForKey:kName];
            channel.url = [cloudChannel objectForKey:kUrl];
            channel.desc = [cloudChannel objectForKey:kDesc];

            [userStationGuids addObject:[cloudChannel objectForKey:kGuid]];
        }

        // *** Prune Channels
        NSFetchRequest *allCustomChannelsRequest = [[NSFetchRequest alloc] init];
        allCustomChannelsRequest.entity = [NSEntityDescription entityForName:@"Channel" inManagedObjectContext:backgroundContext];
        allCustomChannelsRequest.predicate = [NSPredicate predicateWithFormat:@"guid BEGINSWITH 'USR'"];
        NSArray *allCustomChannels = [backgroundContext executeFetchRequest:allCustomChannelsRequest error:nil];

        for (Channel *channel in allCustomChannels) {
            if (![userStationGuids containsObject:channel.guid]) {
                NSLog(@"[RADIO CLOUD MANAGER] Removing custom station %@", channel.url);
                [backgroundContext deleteObject:channel];
            }
        }

        // *** Favs ***
        NSMutableArray *arrayFavourites = [NSMutableArray arrayWithArray:[_keyStore objectForKey:kCloudFavourites]];
        NSFetchRequest *allFavouriteChannelsRequest = [[NSFetchRequest alloc] init];
        allFavouriteChannelsRequest.entity = [NSEntityDescription entityForName:@"Channel" inManagedObjectContext:backgroundContext];
        allFavouriteChannelsRequest.predicate = [NSPredicate predicateWithFormat:@"favourite == 1"];
        NSArray *allFavouriteChannels = [backgroundContext executeFetchRequest:allFavouriteChannelsRequest error:nil];

        for (Channel *channel in allFavouriteChannels) {
            if (![arrayFavourites containsObject:channel.guid]) {
                channel.favourite = @NO;
            }
        }

        for (NSString *guid in arrayFavourites) {
            NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
            fetchRequest.entity = [NSEntityDescription entityForName:@"Channel" inManagedObjectContext:backgroundContext];
            fetchRequest.predicate = [NSPredicate predicateWithFormat:@"guid == %@ && favourite == 0", guid];

            NSArray *result = [backgroundContext executeFetchRequest:fetchRequest error:nil];
            if (result.count >= 1) {
                Channel *channel = (Channel *) result[0];
                if (channel)
                    channel.favourite = @YES;
            }
        }

        [backgroundContext save:nil];

        dispatch_async(dispatch_get_main_queue(), ^{
            [app recalculateMenuItems];
        });
    });
}

- (void)reset {
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
    dispatch_async(queue, ^{
        RadioAppDelegate *app = GetAppDelegate();

        NSManagedObjectContext *backgroundContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        backgroundContext.parentContext = app.managedObjectContext;
        backgroundContext.undoManager = nil;

        NSLog(@"[RADIO CLOUD MANAGER] Starting reset");
        [self clear];

        // Channels
        NSFetchRequest *allUserChannelsRequest = [[NSFetchRequest alloc] init];
        allUserChannelsRequest.entity = [NSEntityDescription entityForName:@"Channel" inManagedObjectContext:backgroundContext];
        allUserChannelsRequest.predicate = [NSPredicate predicateWithFormat:@"guid BEGINSWITH 'USR'"];
        NSArray *allUserChannels = [backgroundContext executeFetchRequest:allUserChannelsRequest error:nil];

        for (Channel *channel in allUserChannels) {
            [self addChannelToCloud:channel];
        }

        // Favourites
        NSFetchRequest *allFavouriteChannelsRequest = [[NSFetchRequest alloc] init];
        allFavouriteChannelsRequest.entity = [NSEntityDescription entityForName:@"Channel" inManagedObjectContext:backgroundContext];
        allFavouriteChannelsRequest.predicate = [NSPredicate predicateWithFormat:@"favourite == 1"];
        NSArray *allFavouriteChannels = [backgroundContext executeFetchRequest:allFavouriteChannelsRequest error:nil];

        for (Channel *channel in allFavouriteChannels) {
            [self favouriteChannelInCloud:channel];
        }

        [backgroundContext save:nil];

        NSLog(@"[RADIO CLOUD MANAGER] Finished reset");
    });
}

- (void)clear {
    [_keyStore setObject:nil forKey:kCloudChannels];
    [_keyStore setObject:nil forKey:kCloudFavourites];
}

- (BOOL)isChannelMarkedFavInCloud:(Channel *)channel {
    BOOL result = NO;
    NSArray *array = [_keyStore objectForKey:kCloudFavourites];
    for (NSString *guid in array) {
        if ([channel.guid isEqualToString:guid]) {
            result = YES;
            break;
        }
    }

    return result;
}

- (BOOL)isChannelInCloud:(Channel *)channel {
    BOOL result = NO;
    NSArray *array = [_keyStore objectForKey:kCloudChannels];
    for (NSDictionary *cloudChannel in array) {
        NSString *guid = [cloudChannel objectForKey:kGuid];
        if ([channel.guid isEqualToString:guid]) {
            result = YES;
            break;
        }
    }

    return result;
}

@end