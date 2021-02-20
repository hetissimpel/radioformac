//
//  RadioVolumeSlider.m
//  Radio
//
//  Created by Damien Glancy on 18/08/2012.
//  Copyright (c) 2012 Het is Simpel. All rights reserved.
//

#import <objc/runtime.h>

@implementation RadioVolumeSlider

BOOL usesCustomTrackImage(id self, SEL _cmd) {
    return YES;
}

+ (void)initialize {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        class_addMethod([RadioVolumeSliderCell class], @selector(_usesCustomTrackImage), (IMP)usesCustomTrackImage, "c@:");
    }

                  );
}

- (void)awakeFromNib {
    NSSliderCell *oldCell = [self cell];
    RadioVolumeSliderCell *sliderCell = [[RadioVolumeSliderCell alloc] init];
    [sliderCell setSliderType:NSLinearSlider];
    [sliderCell setTag:[oldCell tag]];
    [sliderCell setTarget:[oldCell target]];
    [sliderCell setAction:[oldCell action]];
    [self setCell:sliderCell];
}

- (void)setNeedsDisplayInRect:(NSRect)invalidRect {
    [super setNeedsDisplayInRect:self.bounds];
}

@end

@interface RadioVolumeSliderCell ()

@property(strong, nonatomic) NSImage *knobImage;
@property(strong, nonatomic) NSImage *barImage;

@end

@implementation RadioVolumeSliderCell

- (BOOL)isOpaque {
    return NO;
}

- (void)drawBarInside:(NSRect)aRect flipped:(BOOL)flipped {
    if (_barImage == nil) {
        _barImage = [NSImage imageNamed:@"slider"];
    }

    [_barImage drawAtPoint:NSMakePoint(aRect.origin.x, aRect.origin.y + 3)
                  fromRect:CGRectMake(0, 0, 74, 21)
                 operation:NSCompositeSourceOver
                  fraction:1.0];
}

- (void)drawKnob:(NSRect)knobRect {
    if (_knobImage == nil) {
        _knobImage = [NSImage imageNamed:@"slider-button"];
    }

    [_knobImage drawAtPoint:NSMakePoint(knobRect.origin.x, knobRect.origin.y + _knobImage.size.height)
                   fromRect:NSZeroRect
                  operation:NSCompositeSourceOver
                   fraction:1.0];
}

@end