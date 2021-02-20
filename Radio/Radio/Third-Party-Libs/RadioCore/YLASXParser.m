//
//  YLASXParser.m
//  RadioTunes
//
//  Copyright (c) 2013 Yakamoz Labs. All rights reserved.
//

#import "YLASXParser.h"
#import "YLXMLUtilities.h"

@implementation YLASXParser

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
    // node names are case-sensitive and this is the simplest solution to cover them all in XPath!
    NSString *query = @"//ENTRY/REF|//ENTRY/Ref|//ENTRY/ref|//Entry/REF|//Entry/Ref|//Entry/ref|//entry/REF|//entry/Ref|//entry/ref";
    NSArray *tracks = PerformXMLXPathQuery(httpData, nil, query);
    if(tracks && [tracks count] > 0) {
        for(NSDictionary *track in tracks) {
            if(track == nil) {
                continue;
            }
            
            NSArray *attributes = [track objectForKey:@"nodeAttributeArray"];
            if(attributes == nil) {
                continue;
            }
            
            for(id attrib in attributes) {
                if([attrib isKindOfClass:[NSDictionary class]]) {
                    NSString *name = [(NSDictionary *)attrib objectForKey:@"attributeName"];
                    if(name && [name compare:@"href" options:NSCaseInsensitiveSearch] == NSOrderedSame) {
                        NSString *streamUrl = [(NSDictionary *)attrib objectForKey:@"nodeContent"];
                        if(streamUrl && [streamUrl hasPrefix:@"http://"]) {
                            streamUrl = [streamUrl stringByReplacingOccurrencesOfString:@"http://" withString:@"mms://"];
                        }
                        
                        return streamUrl;
                    }
                }
            }
        }
    }
    
    return nil;
}

@end
