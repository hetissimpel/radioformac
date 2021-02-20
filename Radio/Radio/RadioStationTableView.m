//
//  RadioStationTableView.m
//  Radio
//
//  Created by Damien Glancy on 03/12/2012.
//  Copyright (c) 2012 Het is Simpel. All rights reserved.
//

#import "RadioStationTableView.h"

@implementation RadioStationTableView

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    return self;
}

- (void)keyDown:(NSEvent *)theEvent {
    if ([theEvent type] == NSKeyDown) {
        NSString *characters = [theEvent characters];
        if (([characters length] > 0) && (([characters characterAtIndex:0] == NSCarriageReturnCharacter) || ([characters characterAtIndex:0] == NSEnterCharacter))) {
            if ([_keyboardDelegate respondsToSelector:@selector(enterKeyWasPressed)]) {
                [_keyboardDelegate enterKeyWasPressed];
            }
        }
    }
    [super keyDown:theEvent];
}

- (BOOL)performKeyEquivalent:(NSEvent *)theEvent {
    if ([theEvent type] == NSKeyDown) {
        NSString *characters = [theEvent characters];
        if (([characters length] > 0) && (([characters characterAtIndex:0] == NSCarriageReturnCharacter) || ([characters characterAtIndex:0] == NSEnterCharacter))) {
            return YES;
        }
    }
    return [super performKeyEquivalent:theEvent];
}

@end