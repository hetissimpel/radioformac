//
//  AudioConverter.m
//  RadioTunes
//
//  Copyright (c) 2013 Yakamoz Labs. All rights reserved.
//

#import "YLAudioConverter.h"
#import "YLRadio.h"
#import <AudioToolbox/AudioToolbox.h>

@interface YLAudioConverter () {
    char *_audioBuffer;
    int _bufferSize;
    SInt64 _frameOffset;
    
    BOOL _processing;
    
    ExtAudioFileRef _destinationFile;
    AudioStreamBasicDescription _audioFormat;
}

@end

@implementation YLAudioConverter

@synthesize audioBuffer = _audioBuffer;

+ (BOOL)AudioConverterAvailable {
    return YES;
}

- (id)initWithAudioFormat:(AudioStreamBasicDescription)audioFormat
               bufferSize:(int)bufferSize {
    self = [super init];
    if(self) {
        _audioFormat = audioFormat;
        _bufferSize = bufferSize;
        _frameOffset = 0;
        _processing = NO;
        _audioBuffer = (char *)malloc(_bufferSize * sizeof(char));
    }
    
    return self;
}

- (void)dealloc {
    [self finish];
    if(_audioBuffer != NULL) {
        free(_audioBuffer);
    }
    
    [super dealloc];
}

- (BOOL)startWithDestination:(NSString *)destination
                       error:(NSError **)error {
    AudioStreamBasicDescription destinationFormat;
    memset(&destinationFormat, 0, sizeof(destinationFormat));
    destinationFormat.mChannelsPerFrame = _audioFormat.mChannelsPerFrame;
    destinationFormat.mFormatID = kAudioFormatMPEG4AAC;
    
    UInt32 size = sizeof(destinationFormat);
    OSStatus err = AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, &destinationFormat);
    if(err) {
        DLog(@"Error: get property kAudioFormatProperty_FormatInfo failed: %d", (int)err);
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"Destination format could not be initialized." forKey:NSLocalizedDescriptionKey];
        if(error != NULL) {
            *error = [NSError errorWithDomain:YLRadioTunesErrorDomain code:kRadioRecordingInitializationError userInfo:userInfo];
        }
        
        return NO;
    }

    err = ExtAudioFileCreateWithURL((CFURLRef)[NSURL fileURLWithPath:destination], kAudioFileM4AType, &destinationFormat, NULL, kAudioFileFlags_EraseFile, &_destinationFile);
    if(err) {
        DLog(@"Error: ExtAudioFileCreateWithURL failed: %d", (int)err);
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"Destination file could not be created." forKey:NSLocalizedDescriptionKey];
        if(error != NULL) {
            *error = [NSError errorWithDomain:YLRadioTunesErrorDomain code:kRadioRecordingFileError userInfo:userInfo];
        }
        
        return NO;
    }
    
    size = sizeof(_audioFormat);
    err = ExtAudioFileSetProperty(_destinationFile, kExtAudioFileProperty_ClientDataFormat, size, &_audioFormat);
    if(err) {
        ExtAudioFileDispose(_destinationFile);
        DLog(@"Error: ExtAudioFileSetProperty failed: %d", (int)err);
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"Conversion format could not be initliazed." forKey:NSLocalizedDescriptionKey];
        if(error != NULL) {
            *error = [NSError errorWithDomain:YLRadioTunesErrorDomain code:kRadioRecordingFormatError userInfo:userInfo];
        }
        
        return NO;
    }
    
    _processing = YES;
    return YES;
}

- (BOOL)writeBytesWithLength:(int)length error:(NSError **)error {
    if(length == 0) {
        return NO;
    }
    
    if(!_processing) {
        return NO;
    }
    
    AudioBufferList fillBufList;
    fillBufList.mNumberBuffers = 1;
    fillBufList.mBuffers[0].mNumberChannels = _audioFormat.mChannelsPerFrame;
    fillBufList.mBuffers[0].mDataByteSize = _bufferSize;
    fillBufList.mBuffers[0].mData = _audioBuffer;
    
    UInt32 numFrames = length / _audioFormat.mBytesPerFrame;
    fillBufList.mBuffers[0].mDataByteSize = length;
    
    _frameOffset += numFrames;
    
    OSStatus err = ExtAudioFileWrite(_destinationFile, numFrames, &fillBufList);
    if(err) {
        DLog(@"Error: ExtAudioFileWrite failed: %d", (int)err);
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"Audio packets could not be written to file." forKey:NSLocalizedDescriptionKey];
        if(error != NULL) {
            *error = [NSError errorWithDomain:YLRadioTunesErrorDomain code:kRadioRecordingWriteError userInfo:userInfo];
        }
        
        return NO;
    }
    
    memset(_audioBuffer, 0, _bufferSize);
    return YES;
}

- (void)finish {
    _processing = NO;
    
    if(_destinationFile) {
        ExtAudioFileDispose(_destinationFile);
        _destinationFile = NULL;
    }
}

@end
