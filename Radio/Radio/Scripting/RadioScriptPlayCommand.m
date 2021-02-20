//
//  RadioScriptQuitCommand.m
//  Radio
//
//  Created by Damien Glancy on 22/06/2013.
//  Copyright (c) 2013 Het is Simpel. All rights reserved.
//

#import "RadioScriptPlayCommand.h"
#import "RadioController.h"

@implementation RadioScriptPlayCommand

- (id)performDefaultImplementation {
    NSLog(@"[RADIO] Script command: toggleplay");
    
    RadioAppDelegate *app = GetAppDelegate();
    RadioController *controller = app.radioController;
    if (app.radioController.playActive) {
        [app stopRequested:nil];
    } else if (controller.selectedChannel) {
        [app playRequested:nil];
    }
    
    return nil;
}

@end
