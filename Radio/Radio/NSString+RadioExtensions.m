//
//  NSString_+RadioExtensions.m
//  Radio
//
//  Created by Damien Glancy on 04/11/2012.
//  Copyright (c) 2012 Het is Simpel. All rights reserved.
//

#import "NSString+RadioExtensions.h"

@implementation NSString (RadioExtensions)

- (BOOL)containsString:(NSString *)string options:(NSStringCompareOptions)options {
    NSRange rng = [self rangeOfString:string options:options];
    return rng.location != NSNotFound;
}

@end