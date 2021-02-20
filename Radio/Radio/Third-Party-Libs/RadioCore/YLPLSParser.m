//
//  PLSParser.m
//  RadioTunes
//
//  Copyright 2011 Yakamoz Labs. All rights reserved.
//

#import "YLPLSParser.h"

@implementation YLPLSParser

- (id)init {
    self = [super init];
    if(self) {
        
    }
    
    return self;
}

- (void)dealloc {
    [super dealloc];
}

- (NSString *)parseStreamUrl:(NSData *)httpData {
    NSString *document = [[[NSString alloc] initWithBytes:[httpData bytes] length:[httpData length] encoding:NSUTF8StringEncoding] autorelease];
    if(document == nil) {
        document = [[[NSString alloc] initWithBytes:[httpData bytes] length:[httpData length] encoding:NSASCIIStringEncoding] autorelease];
    }
    NSArray *lines = [document componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    if(lines && [lines count] > 0) {
        for(NSString *line in lines) {
            if([line hasPrefix:@"File"]) {
                NSRange r = [line rangeOfString:@"="];
                if(r.location != NSNotFound) {
                    NSString *streamUrl = [line substringFromIndex:(r.location+1)];
                    return streamUrl;
                }
            }
        }
    }
    
    return nil;
}

@end
