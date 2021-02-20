//
//  RadioUtils.h
//  Radio
//
//  Created by Damien Glancy on 04/08/2012.
//  Copyright (c) 2012 Het is Simpel. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "Channel.h"

@interface RadioUtils : NSObject

+ (void)sendNotificationWithTitle:(NSString *)title subtitle:(NSString *)subtitle informativeText:(NSString *)informativeText;

+ (NSAttributedString *)convertToAttributedString:(NSString *)string;

@end