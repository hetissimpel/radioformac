//
//  RadioAppDelegate.m
//  RadioHelper
//
//  Created by Damien Glancy on 04/08/2012.
//  Copyright (c) 2012 Het is Simpel. All rights reserved.
//

#import "RadioAppDelegate.h"

@implementation RadioAppDelegate


- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    NSLog(@"Started.");
    NSArray *apps = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"nl.hetissimpel.Radio"];
    if (apps.count==0) {
        NSString *path = [[NSBundle mainBundle] bundlePath];
        NSArray *p = [path pathComponents];
        NSMutableArray *pathComponents = [NSMutableArray arrayWithArray:p];
        [pathComponents removeLastObject];
        [pathComponents removeLastObject];
        [pathComponents removeLastObject];
        [pathComponents addObject:@"MacOS"];
        [pathComponents addObject:@"Radio"];
        NSString *newPath = [NSString pathWithComponents:pathComponents];
        
        BOOL success = [[NSWorkspace sharedWorkspace] launchApplication:newPath];
        if (!success)
            NSLog(@"Radio was not launched successfully");
    } else
        NSLog(@"Radio already running. Standing down.");

    [NSApp terminate:nil];
}

@end
