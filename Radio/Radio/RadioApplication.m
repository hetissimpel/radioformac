//
//  RadioApplication.m
//  Radio
//
//  Created by Damien Glancy on 05/11/2012.
//  Copyright (c) 2012 Het is Simpel. All rights reserved.
//

#import "RadioApplication.h"

@implementation RadioApplication

- (void)sendEvent:(NSEvent *)event {
    if ([event type] == NSKeyDown) {
        if (([event modifierFlags] & NSDeviceIndependentModifierFlagsMask) == NSCommandKeyMask) {
            if ([[event charactersIgnoringModifiers] isEqualToString:@"x"]) {
                if ([self sendAction:@selector(cut:) to:nil from:self]) {
                    return;
                }
            } else if ([[event charactersIgnoringModifiers] isEqualToString:@"c"]) {
                if ([self sendAction:@selector(copy:) to:nil from:self]) {
                    return;
                }
            } else if ([[event charactersIgnoringModifiers] isEqualToString:@"v"]) {
                if ([self sendAction:@selector(paste:) to:nil from:self]) {
                    return;
                }
            } else if ([[event charactersIgnoringModifiers] isEqualToString:@"a"]) {
                if ([self sendAction:@selector(selectAll:) to:nil from:self]) {
                    return;
                }
            }
        }
    }
    [super sendEvent:event];
}

@end