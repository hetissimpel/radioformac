//
//  RadioUtils.m
//  Radio
//
//  Created by Damien Glancy on 04/08/2012.
//  Copyright (c) 2012 Het is Simpel. All rights reserved.
//

@implementation RadioUtils

+ (void)sendNotificationWithTitle:(NSString *)title subtitle:(NSString *)subtitle informativeText:(NSString *)informativeText {
    Class c = NSClassFromString(@"NSUserNotification");
    if (c) {
        NSUserNotification *notification = [[NSUserNotification alloc] init];
        notification.title = title;
        notification.subtitle = subtitle;
        notification.informativeText = informativeText;
        notification.soundName = nil;

        [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
    }
}

+ (NSAttributedString *)convertToAttributedString:(NSString *)string {
    if (!string) {
        string = kBlankString;
    }
    NSDictionary *attributesDict = [NSDictionary dictionaryWithObject:[NSNumber numberWithFloat:0.0f] forKey:(__bridge NSString *)kCTKernAttributeName];
    NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:string attributes:attributesDict];
    return attributedString;
}

@end