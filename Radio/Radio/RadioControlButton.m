//
//  RadioControlButton.m
//  Radio
//
//  Created by Damien Glancy on 17/08/2012.
//  Copyright (c) 2012 Het is Simpel. All rights reserved.
//

@interface RadioControlButton ()

@property(nonatomic, strong) NSImage *cacheImage;

@end

@implementation RadioControlButton

- (void)awakeFromNib {
    [self createTrackingArea];
}

- (void)mouseDown:(NSEvent *)event {
    _cacheImage = nil;
}

- (void)mouseUp:(NSEvent *)event {
    [NSApp sendAction:self.action to:self.target from:self];
}

- (void)mouseEntered:(NSEvent *)event {
    _cacheImage = self.image;
    self.image = _mouseOverImage;
    [self setNeedsDisplay];
}

- (void)mouseExited:(NSEvent *)event {
    if (_cacheImage) {
        self.image = _cacheImage;
    }
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