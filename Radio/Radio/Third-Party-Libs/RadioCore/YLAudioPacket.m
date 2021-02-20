//
//  AudioPacket.m
//  RadioTunes
//
//  Copyright 2011 Yakamoz Labs. All rights reserved.
//

#import "YLAudioPacket.h"

@interface YLAudioPacket () {    
    NSUInteger _consumedLength;
}

@end

@implementation YLAudioPacket

@synthesize data = _data;
@synthesize audioDescription = _audioDescription;

- (id)initWithData:(NSData *)data {
    self = [super init];
    if(self) {
        _data = [data retain];
        _consumedLength = 0;
    }
    
    return self;
}

- (void)dealloc {
    [_data release];
    
    [super dealloc];
}

- (NSUInteger)length {
    return [_data length];
}

- (NSUInteger)remainingLength {
    return ([_data length] - _consumedLength);
}

- (void)copyToBuffer:(void *const)buffer size:(NSInteger)size {
    NSInteger dataSize = size;
    if((_consumedLength + dataSize) > [self length]) {
        dataSize = [self length] - _consumedLength;
    }
    
    memcpy(buffer, ([_data bytes] + _consumedLength), dataSize);
    _consumedLength += dataSize;
}

- (void)copyToBuffer:(void *const)firstBuffer buffer:(void *const)secondBuffer size:(NSInteger)size {
    NSInteger dataSize = size;
    if((_consumedLength + dataSize) > [self length]) {
        dataSize = [self length] - _consumedLength;
    }
    
    memcpy(firstBuffer, ([_data bytes] + _consumedLength), dataSize);
    memcpy(secondBuffer, ([_data bytes] + _consumedLength), dataSize);
    
    _consumedLength += dataSize;
}

@end
