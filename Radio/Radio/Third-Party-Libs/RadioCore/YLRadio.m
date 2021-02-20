//
//  Radio.m
//  Radio
//
//  Copyright 2011 Yakamoz Labs. All rights reserved.
//

#import "YLRadio.h"
#import "YLReachability.h"

NSString *YLRadioTunesErrorDomain = @"com.yakamozlabs.RadioTunes";

@interface YLRadio()
@property (nonatomic, readwrite) YLRadioState radioState;
@end

@implementation YLRadio

@synthesize url = _url;
@synthesize radioState = _radioState;
@synthesize radioError = _radioError;
@synthesize radioTitle = _radioTitle;
@synthesize radioName = _radioName;
@synthesize radioGenre = _radioGenre;
@synthesize radioUrl = _radioUrl;
@synthesize delegate = _delegate;

- (id)initWithURL:(NSURL *)url {
    self = [super init];
    if(self) {
        _url = [url retain];
        _delegate = nil;
        
        _radioTitle = nil;
        _radioName = nil;
        _radioGenre = nil;
        _radioUrl = nil;
        
        _playerState.mStarted = NO;
        _playerState.mPlaying = NO;
        _playerState.mPaused = NO;
        _playerState.mGain = 0.5;
        _playerState.mTotalBytes = 0;
        _playerState.mBufferInSeconds = 4; // 2 seconds buffering
        _playerState.mAudioQueue = [[YLAudioQueue alloc] init];
        _playerState.mQueue = NULL;
        for(int i = 0; i < NUM_AQ_BUFS; ++i) {
            _playerState.mQueueBuffers[i] = (YLQueueBufferRef)malloc(sizeof(YLQueueBuffer));
            _playerState.mQueueBuffers[i]->mQueueBuffer = NULL;
            _playerState.mQueueBuffers[i]->mPacketDescriptions = NULL;
            _playerState.mQueueBuffers[i]->mPacketDescriptionCount = 0;
        }
        
        _lockQueue = dispatch_queue_create("lockQueue", NULL);
        
        _radioState = kRadioStateStopped;
        _radioError = kRadioErrorNone;
        
        _shutdown = NO;
        _waitingForReconnection = NO;
        _connectionError = NO;
        _buffersInUse = 0;
        
        _bufferTimer = nil;
        _reconnectTimer = nil;
        _reachability = nil;
        _connectionType = kRadioConnectionTypeNone;
    }
    
    return self;
}

- (void)dealloc {
    _delegate = nil;
    [_url release];
    [_filePath release];
    
    [_radioTitle release];
    [_radioName release];
    [_radioGenre release];
    [_radioUrl release];
    
    for(int i = 0; i < NUM_AQ_BUFS; ++i) {
        YLQueueBufferRef buffer = _playerState.mQueueBuffers[i];
        if(buffer && buffer->mPacketDescriptions) {
            free(buffer->mPacketDescriptions);
        }
        free(buffer);
    }
    [_playerState.mAudioQueue release];
    dispatch_release(_lockQueue);
    
    if(_bufferTimer) {
        [_bufferTimer invalidate];
        [_bufferTimer release];
        _bufferTimer = nil;
    }
    
    if(_reconnectTimer) {
        [_reconnectTimer invalidate];
        [_reconnectTimer release];
        _reconnectTimer = nil;
    }
    
    if(_reachability) {
        [_reachability stopNotifier];
        [_reachability release];
        _reachability = nil;
    }
    
    [super dealloc];
}


#pragma mark -
#pragma mark Instance Methods
- (void)shutdown {
    // implemented in subclass
}

- (void)play {
    // implemented in subclass
}

- (void)pause {
    // implemented in sublass
}

- (void)startRecordingWithDestination:(NSString *)filePath {
    // implemented in sublass
}

- (void)stopRecording {
    // implemented in sublass
}

- (NSString *)fileExtensionHint {
    // implemented in sublass
    return @"";
}

- (BOOL)isPlaying {
    return _playerState.mPlaying;
}

- (BOOL)isPaused {
    return _playerState.mPaused;
}

- (BOOL)isBuffering {
    return _playerState.mBuffering;
}

- (BOOL)isRecording {
    return _playerState.mRecording;
}

- (void)setBufferInSeconds:(NSUInteger)seconds {
    if(seconds > 30) {
        seconds = 30;
    }
    if(seconds < 1) {
        seconds = 1;
    }
    
    // buffers contain 0.5 seconds of data
    _playerState.mBufferInSeconds = seconds * 2;
}

- (void)setVolume:(float)volume {
    if(volume < 0) {
        volume = 0;
    }
    
    if(volume > 1.0) {
        volume = 1.0;
    }
    
    _playerState.mGain = volume;
    
    if(_playerState.mQueue == nil) {
        return;
    }
    AudioQueueSetParameter(_playerState.mQueue, kAudioQueueParam_Volume, _playerState.mGain);
}

- (NSInteger)enableLevelMetering:(NSError **)error {
    if(_radioState != kRadioStatePlaying) {
        if(error != NULL) {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"Radio is not in playing state."
                                                                 forKey:NSLocalizedDescriptionKey];
            *error = [NSError errorWithDomain:YLRadioTunesErrorDomain code:kRadioMeteringStateError userInfo:userInfo];
        }
        
        return -1;
    }
    
    UInt32 enable = 1;
    OSStatus err = AudioQueueSetProperty(_playerState.mQueue, kAudioQueueProperty_EnableLevelMetering, &enable, sizeof(UInt32));
    if(err) {
        if(error != NULL) {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"Could not enable level metering."
                                                                 forKey:NSLocalizedDescriptionKey];
            *error = [NSError errorWithDomain:YLRadioTunesErrorDomain code:kRadioMeteringInitializationError userInfo:userInfo];
        }
        
        return -1;
    }
    
    return _playerState.mAudioFormat.mChannelsPerFrame;
}

- (void)currentLevelMeterDB:(AudioQueueLevelMeterState *)levels error:(NSError **)error {
    if(_radioState != kRadioStatePlaying || levels == NULL) {
        return;
    }
    
    UInt32 dataSize = sizeof(AudioQueueLevelMeterState) * _playerState.mAudioFormat.mChannelsPerFrame;
    OSStatus err = AudioQueueGetProperty(_playerState.mQueue, kAudioQueueProperty_CurrentLevelMeterDB, levels, &dataSize);
    if(err) {
        if(error != NULL) {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"Could not query level metering."
                                                                 forKey:NSLocalizedDescriptionKey];
            *error = [NSError errorWithDomain:YLRadioTunesErrorDomain code:kRadioMeteringQueryError userInfo:userInfo];
        }
    }
}


@end
