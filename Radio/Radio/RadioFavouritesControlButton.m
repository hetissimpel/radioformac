//
//  RadioFavouritesControlButton.m
//  Radio
//
//  Created by Damien Glancy on 22/10/2012.
//  Copyright (c) 2012 Het is Simpel. All rights reserved.
//

#import "RadioFavouritesControlButton.h"

@implementation RadioFavouritesControlButton

- (void)awakeFromNib {
    [self createTrackingArea];
}

- (void)mouseDown:(NSEvent *)event {
}

- (void)mouseUp:(NSEvent *)event {
    [NSApp sendAction:self.action to:self.target from:self];
}

- (void)mouseEntered:(NSEvent *)event {
    [self setNeedsDisplay];
}

- (void)mouseExited:(NSEvent *)event {
    [self setNeedsDisplay];
}

- (void)createTrackingArea {
    NSTrackingAreaOptions focusTrackingAreaOptions = NSTrackingActiveInActiveApp;
    focusTrackingAreaOptions |= NSTrackingMouseEnteredAndExited;
    focusTrackingAreaOptions |= NSTrackingAssumeInside;
    focusTrackingAreaOptions |= NSTrackingInVisibleRect;

    NSTrackingArea *focusTrackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                                     options:focusTrackingAreaOptions owner:self userInfo:nil];
    [self addTrackingArea:focusTrackingArea];
}

@end