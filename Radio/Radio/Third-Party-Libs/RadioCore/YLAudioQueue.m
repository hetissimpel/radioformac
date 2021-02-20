//
//  AudioQueue.m
//  RadioTunes
//
//  Copyright 2011 Yakamoz Labs. All rights reserved.
//

#import "YLAudioQueue.h"
#import "YLAudioPacket.h"

@interface YLAudioQueue () {
    NSMutableArray *_audioPackets;
}

@end

@implementation YLAudioQueue

- (id)init {
    self = [super init];
    if(self) {
        _audioPackets = [[NSMutableArray alloc] init];
    }
    
    return self;
}

- (void)dealloc {
    [_audioPackets release];
    [super dealloc];
}

- (YLAudioPacket *)pop {
    YLAudioPacket *packet = nil;
    packet = [_audioPackets lastObject];
    if(packet) {
        [packet retain];
        [_audioPackets removeLastObject];
    }
    
    return packet;
}

- (YLAudioPacket *)peak {
    return [_audioPackets lastObject];
}

- (void)addPacket:(YLAudioPacket *)packet {
    [_audioPackets insertObject:packet atIndex:0];
}

- (void)removeAllPackets {
    [_audioPackets removeAllObjects];
}

- (NSUInteger)count {
    return [_audioPackets count];
}

@end
