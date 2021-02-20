//
//  M3UParser.m
//  RadioTunes
//
//  Copyright 2011 Yakamoz Labs. All rights reserved.
//

#import "YLM3UParser.h"

@implementation YLM3UParser

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
    if(document == nil) {
        return nil;
    }
    NSArray *lines = [document componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    if(lines && [lines count] > 0) {
        for(NSString *line in lines) {
            if([line hasPrefix:@"http"]) {
                NSString *streamUrl = [line stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
                return streamUrl;
            }
        }
    }
    
    return nil;
}

@end
