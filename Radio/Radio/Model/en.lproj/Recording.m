//
//  Recording.m
//  Radio
//
//  Created by Damien Glancy on 03/11/2012.
//  Copyright (c) 2012 Het is Simpel. All rights reserved.
//


@implementation Recording

@dynamic audio;
@dynamic audioMimeType;
@dynamic duration;
@dynamic endDate;
@dynamic keep;
@dynamic startDate;
@dynamic channel;
@dynamic tracks;
@synthesize durationString;

- (NSString *)durationString {
    if (!self.endDate) {
        return @"Rec";
    } else {
        unsigned int unitFlags = NSHourCalendarUnit | NSMinuteCalendarUnit;
        NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
        NSDateComponents *conversionInfo = [calendar components:unitFlags fromDate:self.startDate toDate:self.endDate options:0];

        NSInteger hours = conversionInfo.hour;
        NSInteger minutes = conversionInfo.minute;

        return [NSString stringWithFormat:@"%02d:%02d", (int)hours, (int)minutes];
    }
}

@end