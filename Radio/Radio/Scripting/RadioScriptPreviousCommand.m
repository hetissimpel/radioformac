//
//  RadioScriptPreviousCommand.m
//  Radio
//
//  Created by Damien Glancy on 22/06/2013.
//  Copyright (c) 2013 Het is Simpel. All rights reserved.
//

#import "RadioScriptPreviousCommand.h"

@implementation RadioScriptPreviousCommand

- (id)performDefaultImplementation {
    NSLog(@"[RADIO] Script command: previous");
    
    RadioAppDelegate *app = GetAppDelegate();
    if (app.radioController.selectedChannel) {
        NSFetchRequest *channelRequest = [[NSFetchRequest alloc] init];
        channelRequest.entity = [NSEntityDescription entityForName:@"Channel" inManagedObjectContext:app.managedObjectContext];
        channelRequest.predicate = [NSPredicate predicateWithFormat:@"favourite == YES"];
        
        NSArray *favourites = [app.managedObjectContext executeFetchRequest:channelRequest error:nil];
        if (favourites && favourites.count>0) {
            NSUInteger idx = [favourites indexOfObject:app.radioController.selectedChannel];
            
            Channel *targetChannel;
            if (idx != 0) {
                targetChannel = (Channel *)[favourites objectAtIndex:idx-1];
            } else {
                targetChannel = (Channel *)[favourites objectAtIndex:favourites.count-1];
            }
            
            if (targetChannel) {
                app.radioController.selectedChannel = targetChannel;
                [app playRequested:nil];
            }
        } else {
            NSLog(@"[RADIO] No favourite channels");
        }
        
    } else {
        NSLog(@"[RADIO] No selected channel");
    }
    
    return nil;
}

@end
