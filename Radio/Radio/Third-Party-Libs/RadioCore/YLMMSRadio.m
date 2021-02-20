//
//  MMSRadio.m
//  RadioTunes
//
//  Copyright 2011 Yakamoz Labs. All rights reserved.
//

#import "YLMMSRadio.h"
#import "libavcodec/avcodec.h"
#import "libavformat/avformat.h"
#import "libswresample/swresample.h"
#import "libavutil/opt.h"
#import "YLAudioPacket.h"
#import "YLReachability.h"
#import "YLAudioConverter.h"
#import "pthread.h"

#define MAX_AUDIO_FRAME_SIZE    192000 // 1 second of 48khz 32bit audio
#define CONNECTION_TIMEOUT      10

@interface YLMMSRadio() {
    dispatch_queue_t _decodeQueue;
    
    AVFormatContext *_formatCtx;
    AVCodecContext *_codecCtx;
    SwrContext *_swrCtx;
    
    YLAudioConverter *_converter;
    
    int _audioStreamID;
    BOOL _connected;
    BOOL _decodeError;
    BOOL _dispatchQueueReady;
    BOOL _connectShouldTimeout;
	UInt16 *_decodeBuffer;
    void *_swrBuffer;
    NSUInteger _swrBufferSize;
    NSTimer *_timeoutTimer;
    
}

- (void)handlePlayCallback:(AudioQueueRef)inAudioQueue buffer:(AudioQueueBufferRef) inBuffer;
- (void)onReachabilityChanged:(NSNotification *)notification;
- (void)connect;
- (void)startDecoding;
- (void)setupQueue;
- (void)dismissQueue;
- (void)primeQueueBuffers;
- (void)startQueue;
- (void)setState:(YLRadioState) state;
- (void)cleanup;
- (void)stopRecordingWithError:(NSError *)error;
- (void)startBufferTimerWithTimeout:(NSInteger)timeout;
- (void)startReconnectTimerWithTimeout:(NSInteger)timeout;
- (void)startTimeoutTimerWithTimeout:(NSInteger)timeout;
- (void)stopBufferTimer;
- (void)stopReconnectTimer;
- (void)stopTimeoutTimer;
- (void)onBufferTimerFired:(NSTimer *)timer;
- (void)onReconnectTimerFired:(NSTimer *)timer;
- (void)onTimeoutTimerFired:(NSTimer *)timer;
- (int)connectShouldTimeout;
@end

int QuitDecoding = 0;

static void MMSPlayCallback(void *inUserData, AudioQueueRef inAudioQueue, AudioQueueBufferRef inBuffer) {
    YLMMSRadio *radio = (YLMMSRadio *)inUserData;
    [radio handlePlayCallback:inAudioQueue buffer:inBuffer];
}

static int DecodeInterruptCallback(void *data) {
    YLMMSRadio *radio = (YLMMSRadio *)data;
    if(radio.radioState == kRadioStateConnecting) {
        return [radio connectShouldTimeout];
    }

    return QuitDecoding;
}

static int LockCallback(void **mutex, enum AVLockOp op) {
    switch(op) {
        case AV_LOCK_CREATE:
            *mutex = (pthread_mutex_t *) malloc(sizeof(pthread_mutex_t));
            pthread_mutex_init((pthread_mutex_t *)(*mutex), NULL);
            break;
        case AV_LOCK_OBTAIN:
            pthread_mutex_lock((pthread_mutex_t *)(*mutex));
            break;
        case AV_LOCK_RELEASE:
            pthread_mutex_unlock((pthread_mutex_t *)(*mutex));
            break;
        case AV_LOCK_DESTROY:
            pthread_mutex_destroy((pthread_mutex_t *)(*mutex));
            free(*mutex);
            break;
    }
    
    return 0;
}

@implementation YLMMSRadio

- (id)initWithURL:(NSURL *)url {
    if(![[url scheme] isEqualToString:@"mms"] &&
       ![[url scheme] isEqualToString:@"mmsh"]) {
        return nil;
    }
    
    NSURL *newURL;
    if([[url scheme] isEqualToString:@"mmsh"]) {
        newURL = url;
    } else {
        NSString *urlString = [url description];
        urlString = [urlString stringByReplacingOccurrencesOfString:@"mms://" withString:@"mmst://"];
        newURL = [NSURL URLWithString:urlString];
    }
    
    self = [super initWithURL:newURL];
    if(self) {
        _decodeQueue = dispatch_queue_create("decodeQueue", NULL);
        
        _formatCtx = NULL;
        _codecCtx = NULL;
        _swrCtx = NULL;
        _swrBuffer = NULL;
        _swrBufferSize = 0;
        _audioStreamID = -1;
        _connected = NO;
        _decodeError = NO;
        _connectShouldTimeout = NO;
        _dispatchQueueReady = YES;
		
		_decodeBuffer = malloc(MAX_AUDIO_FRAME_SIZE);
		memset(_decodeBuffer, 0, MAX_AUDIO_FRAME_SIZE);
		
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            avformat_network_init();
            av_register_all();
            av_lockmgr_register(&LockCallback);
        });
        
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onReachabilityChanged:) name:kYLReachabilityChangedNotification object:nil];
    }
    
    return self;
}

- (void)dealloc {
    dispatch_release(_decodeQueue);
    
    
    if(_swrBuffer) {
        free(_swrBuffer);
    }
    if(_swrCtx) {
        swr_free(&_swrCtx);
    }
    if(_codecCtx) {
        avcodec_close(_codecCtx);
    }
    if(_formatCtx) {
        avformat_close_input(&_formatCtx);
    }
    
    free(_decodeBuffer);
    
    [super dealloc];
}

- (void)shutdown {
    _shutdown = YES;
    _playerState.mPlaying = NO;
    _playerState.mPaused = YES;
    
    QuitDecoding = 1;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    if(_reachability) {
        [_reachability stopNotifier];
        [_reachability release];
        _reachability = nil;
    }
    
    if(_playerState.mRecording) {
        [self stopRecording];
    }
    
    if(_playerState.mStarted) {
        _playerState.mStarted = NO;
        _playerState.mTotalBytes = 0.0;
        
        [self dismissQueue];
        
        dispatch_sync(_lockQueue, ^(void) {
            [_playerState.mAudioQueue removeAllPackets];
        });
    }
    
    [self stopTimeoutTimer];
    [self stopBufferTimer];
    [self stopReconnectTimer];
    
    [self retain];
    dispatch_async(_decodeQueue, ^{
        [self cleanup];
    });
}

- (void)play {
    if(_playerState.mPlaying || !_dispatchQueueReady) {
        return;
    }
    
    QuitDecoding = 0;
    _decodeError = NO;
    _connectionError = NO;
    _waitingForReconnection = NO;
    _connectShouldTimeout = NO;
    _buffersInUse = 0;
    
    if(!_connected) {
        [self setState:kRadioStateConnecting];
        [self connect];
    } else {
        if(_shutdown) {
            return;
        }
        
        [self setState:kRadioStateBuffering];
        _playerState.mPaused = NO;
        _playerState.mPlaying = YES;
        _dispatchQueueReady = NO;
        
        _playerState.mAudioFormat.mFormatID = kAudioFormatLinearPCM;
        _playerState.mAudioFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
        _playerState.mAudioFormat.mSampleRate = _codecCtx->sample_rate;
        _playerState.mAudioFormat.mChannelsPerFrame = _codecCtx->channels;
        _playerState.mAudioFormat.mBitsPerChannel = 16;
        _playerState.mAudioFormat.mFramesPerPacket = 1;
        _playerState.mAudioFormat.mBytesPerFrame = _playerState.mAudioFormat.mChannelsPerFrame * _playerState.mAudioFormat.mBitsPerChannel/8;
        _playerState.mAudioFormat.mBytesPerPacket = _playerState.mAudioFormat.mBytesPerFrame * _playerState.mAudioFormat.mFramesPerPacket;

        // calculate buffer size so that there is 0.5 seconds of data in one buffer
        UInt32 numPacketsForTime = _playerState.mAudioFormat.mSampleRate / _playerState.mAudioFormat.mFramesPerPacket * 0.5;
        _playerState.mBufferSize = numPacketsForTime * _playerState.mAudioFormat.mBytesPerPacket;

        if(_reachability == nil) {
            _reachability = [[YLReachability reachabilityForInternetConnection] retain];
            [_reachability startNotifier];
        }
        
        YLNetworkStatus status = [_reachability currentReachabilityStatus];
        if(status == ReachableViaWWAN) {
            _connectionType = kRadioConnectionTypeWWAN;
        } else if(status == ReachableViaWiFi) {
            _connectionType = kRadioConnectionTypeWiFi;
        }
        
        [self setupQueue];
        [self startDecoding];
    }
}

- (void)pause {
    if(_playerState.mPaused) {
        return;
    }
    
    _playerState.mPlaying = NO;
    _playerState.mPaused = YES;
    
    QuitDecoding = 1;
    
    if(_playerState.mRecording) {
        [self stopRecording];
    }
    
    if(_playerState.mStarted) {
        [self dismissQueue];
        _playerState.mStarted = NO;
        _playerState.mTotalBytes = 0.0;
        
        dispatch_sync(_lockQueue, ^(void) {
            [_playerState.mAudioQueue removeAllPackets];
        });
    }
    
    [self stopTimeoutTimer];
    [self stopBufferTimer];
    [self stopReconnectTimer];
    
    if(_reachability) {
        [_reachability stopNotifier];
        [_reachability release];
        _reachability = nil;
    }
    
    if(_decodeError) {
        _radioError = kRadioErrorDecoding;
        [self setState:kRadioStateError];
    } else if(_connectionError) {
        if(!_waitingForReconnection) {
            // start reconnect timer and wait 60 seconds for new connection notification from reachability
            // if we can't establish a new connection within 60 seconds we'll enter the error state
            // and inform the UI about the network connection error.
            _waitingForReconnection = YES;
            [self setState:kRadioStateBuffering];
            
            [self startReconnectTimerWithTimeout:60];
            if(_reachability == nil) {
                _reachability = [[YLReachability reachabilityForInternetConnection] retain];
                [_reachability startNotifier];
            }
            
            YLNetworkStatus status = [_reachability currentReachabilityStatus];
            if(status == ReachableViaWiFi || status == ReachableViaWWAN) {
                [self stopReconnectTimer];
                DLog(@"Reconnecting to radio stream");
                // allow FFmpeg to clean up and start playing again after 1 second
                [self performSelector:@selector(play) withObject:nil afterDelay:1.0];
            }
        } else {
            _radioError = kRadioErrorNetworkError;
            [self setState:kRadioStateError];
        }
    } else {
        [self setState:kRadioStateStopped];
    }
}

- (void)startRecordingWithDestination:(NSString *)filePath {
    if(_playerState.mRecording) {
        DLog(@"Error: Cannot start recording while previous recording session is still running!");
        return;
    }
    
    BOOL notifyDelegate = NO;
    if(_delegate && [_delegate respondsToSelector:@selector(radio:recordingFailedWithError:)]) {
        notifyDelegate = YES;
    }
    
    if(!_playerState.mPlaying) {
        DLog(@"Error: Cannot start recording before playback starts!");
        if(notifyDelegate) {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"Radio playback has not started yet."
                                                                 forKey:NSLocalizedDescriptionKey];
            NSError *error = [NSError errorWithDomain:YLRadioTunesErrorDomain code:kRadioRecordingInitializationError userInfo:userInfo];
            [_delegate radio:self recordingFailedWithError:error];
        }
        
        return;
    }
    
    if(filePath == nil || [filePath isEqualToString:@""]) {
        DLog(@"Error: Invalid filename for recording!");
        if(notifyDelegate) {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"Invalid filename for recording."
                                                                 forKey:NSLocalizedDescriptionKey];
            NSError *error = [NSError errorWithDomain:YLRadioTunesErrorDomain code:kRadioRecordingInitializationError userInfo:userInfo];
            [_delegate radio:self recordingFailedWithError:error];
        }
        
        return;
    }
    
    if(![YLAudioConverter AudioConverterAvailable]) {
        DLog(@"Error: Audio encoder not available!");
        if(notifyDelegate) {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"Audio encoder not available."
                                                                 forKey:NSLocalizedDescriptionKey];
            NSError *error = [NSError errorWithDomain:YLRadioTunesErrorDomain code:kRadioRecordingInitializationError userInfo:userInfo];
            [_delegate radio:self recordingFailedWithError:error];
        }
        
        return;
    }
    
    _converter = [[YLAudioConverter alloc] initWithAudioFormat:_playerState.mAudioFormat bufferSize:_playerState.mBufferSize];
    NSError *error;
    if(![_converter startWithDestination:filePath error:&error]) {
        DLog(@"Error: Recording could not be started: %@", error);
        if(notifyDelegate) {
            [_delegate radio:self recordingFailedWithError:error];
        }
        
        return;
    }
    
    if(_filePath) {
        [_filePath release];
        _filePath = nil;
    }
    _filePath = [filePath retain];
    
    _playerState.mRecording = YES;
    if(_delegate && [_delegate respondsToSelector:@selector(radio:didStartRecordingWithDestination:)]) {
        [_delegate radio:self didStartRecordingWithDestination:_filePath];
    }
}

- (void)stopRecording {
    if(!_playerState.mRecording) {
        DLog(@"Warning: There's no active recording session.");
        return;
    }
    
    _playerState.mRecording = NO;
    [_converter finish];
    [_converter release];
    
    if(_delegate && [_delegate respondsToSelector:@selector(radio:didStopRecordingWithDestination:)]) {
        [_delegate radio:self didStopRecordingWithDestination:_filePath];
    }
}

- (NSString *)fileExtensionHint {
    return @"m4a";
}


#pragma mark -
#pragma mark Private Methods
- (void)handlePlayCallback:(AudioQueueRef)inAudioQueue buffer:(AudioQueueBufferRef)inBuffer {
    if(_playerState.mPaused) {
        return;
    }
    
    if(_playerState.mRecording && inBuffer->mAudioDataByteSize > 0) {
        NSError *error;
        BOOL written = NO;
        memcpy(_converter.audioBuffer, inBuffer->mAudioData, inBuffer->mAudioDataByteSize);
        written = [_converter writeBytesWithLength:inBuffer->mAudioDataByteSize error:&error];
        if(!written && error) {
            [self stopRecordingWithError:error];
        }
    }
    
    __block int maxBytes = inBuffer->mAudioDataBytesCapacity;
    __block int dataWritten = 0;
    inBuffer->mAudioDataByteSize = 0;
    
    dispatch_sync(_lockQueue, ^(void) {
        @autoreleasepool {
            YLAudioPacket *audioPacket = [_playerState.mAudioQueue peak];
            while(audioPacket) {
                if((dataWritten + [audioPacket remainingLength]) > maxBytes) {
                    int dataNeeded = (maxBytes - dataWritten);
                    if(_playerState.mRecording) {
                        [audioPacket copyToBuffer:(inBuffer->mAudioData+dataWritten) buffer:(_converter.audioBuffer+dataWritten) size:dataNeeded];
                    } else {
                        [audioPacket copyToBuffer:(inBuffer->mAudioData+dataWritten) size:dataNeeded];
                    }
                    dataWritten += dataNeeded;
                    break;
                } else {
                    NSInteger dataNeeded = [audioPacket remainingLength];
                    if(_playerState.mRecording) {
                        [audioPacket copyToBuffer:(inBuffer->mAudioData+dataWritten) buffer:(_converter.audioBuffer+dataWritten) size:dataNeeded];
                    } else {
                        [audioPacket copyToBuffer:(inBuffer->mAudioData+dataWritten) size:dataNeeded];
                    }
                    audioPacket = [_playerState.mAudioQueue pop];
                    [audioPacket release];
                    dataWritten += dataNeeded;
                    audioPacket = [_playerState.mAudioQueue peak];
                }
            }
            
            // buffer was used previously
            _buffersInUse--;
            
            inBuffer->mAudioDataByteSize = dataWritten;
            if(inBuffer->mAudioDataByteSize > 0) {
                OSStatus result = AudioQueueEnqueueBuffer(inAudioQueue, inBuffer, 0, NULL);
                if(result != noErr) {
                    DLog(@"could not enqueue buffer");
                    
                    _radioError = kRadioErrorAudioQueueEnqueue;
                    [self setState:kRadioStateError];
                } else {
                    _buffersInUse++;
                    if(_playerState.mBuffering && (_buffersInUse >= (NUM_AQ_BUFS - 1))) {
                        DLog(@"start playback again, buffers filled up again and ready to go");
                        _playerState.mBuffering = NO;
                        
                        [self stopBufferTimer];
                        [self primeQueueBuffers];
                        [self startQueue];
                    }
                }
            }
            
            
            if(_buffersInUse == 0 && !_playerState.mBuffering) {
                DLog(@"all buffers empty, buffering");
                AudioQueuePause(inAudioQueue);
                
                _playerState.mTotalBytes = 0.0;
                _playerState.mBuffering = YES;
                [self setState:kRadioStateBuffering];
                
                [self startBufferTimerWithTimeout:10];
            }
        }
    });
}

- (void)onReachabilityChanged:(NSNotification *)notification {
    if(_reachability) {
        
        if([_reachability isReachable]) {
            if(_waitingForReconnection) {
                [self stopReconnectTimer];
                DLog(@"Reconnecting to radio stream");
                [self play];
            } else if(_playerState.mPlaying && _connectionType == kRadioConnectionTypeWWAN) {
                // Check if we are now connected via WiFi and change to WiFi if so
                YLNetworkStatus status = [_reachability currentReachabilityStatus];
                if(status == ReachableViaWiFi) {
                    DLog(@"Switching back to WiFi");
                    _connectionError = YES;
                    [self pause];
                }
            }
        }
    }
}

- (void)connect {
    if(_connected) {
        return;
    }
    
    dispatch_async(_decodeQueue, ^(void) {
        @autoreleasepool {
            _formatCtx = avformat_alloc_context();
            _formatCtx->interrupt_callback.callback = DecodeInterruptCallback;
            _formatCtx->interrupt_callback.opaque = self;
            
            const char *url = [[_url description] cStringUsingEncoding:NSUTF8StringEncoding];
            [self startTimeoutTimerWithTimeout:CONNECTION_TIMEOUT];
            if(avformat_open_input(&_formatCtx, url, NULL, NULL) != 0) {
                [self stopTimeoutTimer];
                // if current scheme is mmst then try again with scheme mmsh (will use port 80)
                if([[_url scheme] isEqualToString:@"mmst"]) {
                    DLog(@"Trying again with scheme mmsh (port 80)");
                    NSString *urlString = [_url description];
                    urlString = [urlString stringByReplacingOccurrencesOfString:@"mmst://" withString:@"mmsh://"];
                    NSURL *newURL = [NSURL URLWithString:urlString];
                    [_url release];
                    _url = [newURL retain];
                    
                    url = [[newURL description] cStringUsingEncoding:NSUTF8StringEncoding];
                    [self startTimeoutTimerWithTimeout:CONNECTION_TIMEOUT];
                    if(avformat_open_input(&_formatCtx, url, NULL, NULL) != 0) {
                        [self stopTimeoutTimer];
                        DLog(@"FFMPEG cannot open stream");
                        _radioError = kRadioErrorFileStreamOpen;
                        [self setState:kRadioStateError];
                        return;
                    }
                } else {
                    DLog(@"FFMPEG cannot open stream");
                    _radioError = kRadioErrorFileStreamOpen;
                    [self setState:kRadioStateError];
                    return;
                }
            }
            
            [self stopTimeoutTimer];
            DLog(@"FFMPEG connected to stream: %@", [_url scheme]);
            if(avformat_find_stream_info(_formatCtx, NULL) < 0) {
                DLog(@"Cannot find stream info");
                _radioError = kRadioErrorFileStreamOpen;
                [self setState:kRadioStateError];
                return;
            }
            
            for(int i = 0; i < _formatCtx->nb_streams; i++ ) {
                if(_formatCtx->streams[i]->codec->codec_type == AVMEDIA_TYPE_AUDIO) {
                    _audioStreamID = i;
                    break;
                }
            }
            
            if(_audioStreamID == -1) {
                DLog(@"Audio stream not found");
                _radioError = kRadioErrorFileStreamOpen;
                [self setState:kRadioStateError];
                return;
            }
            
            _codecCtx = _formatCtx->streams[_audioStreamID]->codec;
            AVCodec *codec = avcodec_find_decoder(_codecCtx->codec_id);
            if(!codec) {
                DLog(@"Cannot find codec");
                _radioError = kRadioErrorFileStreamOpen;
                [self setState:kRadioStateError];
                return;
            }
            
            int s = avcodec_open2(_codecCtx, codec, NULL);
            if(s < 0) {
                DLog(@"Cannot open codec");
                _radioError = kRadioErrorFileStreamOpen;
                [self setState:kRadioStateError];
                return;
            }
            
            if(_codecCtx->sample_fmt != AV_SAMPLE_FMT_S16) {
                _swrCtx = swr_alloc_set_opts(NULL,
                                             av_get_default_channel_layout(_codecCtx->channels),
                                             AV_SAMPLE_FMT_S16,
                                             _codecCtx->sample_rate,
                                             av_get_default_channel_layout(_codecCtx->channels),
                                             _codecCtx->sample_fmt,
                                             _codecCtx->sample_rate,
                                             0,
                                             NULL);
                if(!_swrCtx || swr_init(_swrCtx)) {
                    if(_swrCtx) {
                        swr_free(&_swrCtx);
                        _swrCtx = NULL;
                    }
                    avcodec_close(_codecCtx);
                    
                    DLog(@"Cannot initialize audio resampler.");
                    _radioError = kRadioErrorFileStreamOpen;
                    [self setState:kRadioStateError];
                    return;
                }
            }
            
            _connected = YES;
            
            DLog(@"Codec opened: %@ - %@", [NSString stringWithUTF8String:codec->name], [NSString stringWithUTF8String:codec->long_name]);
            DLog(@"sample rate: %d", _codecCtx->sample_rate);
            DLog(@"channels: %d", _codecCtx->channels);
            
            dispatch_async(dispatch_get_main_queue(), ^(void) {
                [self play];
            });
        }
    });
}

- (void)startDecoding {
    dispatch_async(_decodeQueue, ^(void) {
        @autoreleasepool {
            AVPacket packet;
            int last_packet = 0;
            int decodeErrorCount = 0;
            
            if(_shutdown) {
                DLog(@"we're shutting down");
                return;
            }
            
            do {
                do {
                    if(av_read_frame(_formatCtx, &packet) < 0) {
                        last_packet = 1;
                    }
                    
                    if(packet.stream_index != _audioStreamID) {
                        av_free_packet(&packet);
                    }
                } while (packet.stream_index != _audioStreamID && !last_packet);
                
                // do not try to decode the last packet if it's not from this stream
                if(last_packet && (packet.stream_index != _audioStreamID)) {
                    break;
                }
                
                UInt8 *packetPtr = packet.data;
                int bytes_remaining = packet.size;
                int dataSize;
                int decodedSize;
                
                while(bytes_remaining > 0 && !_playerState.mPaused) {
                    int got_frame = 0;
                    AVFrame decoded_frame;

                    decodedSize = avcodec_decode_audio4(_codecCtx, &decoded_frame, &got_frame, &packet);
                    
                    if(decodedSize < 0) {
                        packet.size = 0;
                        decodeErrorCount++;
                        if(decodeErrorCount > 4) {
                            _decodeError = YES;
                            [self pause];
                        }
                        
                        break;
                    }
                    
                    bytes_remaining -= decodedSize;
                    packetPtr += decodedSize;
                    
                    if(got_frame == 0) {
                        continue;
                    }
                    
                    if(_swrCtx) {
                        dataSize = av_samples_get_buffer_size(NULL, _codecCtx->channels, decoded_frame.nb_samples, AV_SAMPLE_FMT_S16, 1);
                        if(!_swrBuffer || _swrBufferSize < dataSize) {
                            _swrBufferSize = dataSize;
                            _swrBuffer = realloc(_swrBuffer, _swrBufferSize);
                        }
                        
                        Byte *outbuf[2] = {_swrBuffer, 0};
                        swr_convert(_swrCtx, outbuf, decoded_frame.nb_samples, (const uint8_t **)decoded_frame.data, decoded_frame.nb_samples);
                        memcpy(_decodeBuffer, _swrBuffer, _swrBufferSize);
                    } else {
                        int plane_size;
                        dataSize = av_samples_get_buffer_size(&plane_size, _codecCtx->channels, decoded_frame.nb_samples, _codecCtx->sample_fmt, 1);
                        memcpy(_decodeBuffer, decoded_frame.extended_data[0], plane_size);
                    }
                    
                    _playerState.mTotalBytes += dataSize;
                    
                    dispatch_sync(_lockQueue, ^(void) {
                        NSData *data = [[NSData alloc] initWithBytes:_decodeBuffer length:dataSize];
                        YLAudioPacket *audioPacket = [[YLAudioPacket alloc] initWithData:data];
                        [_playerState.mAudioQueue addPacket:audioPacket];
                        [data release];
                        [audioPacket release];
                    });
                    
                    if(!_playerState.mStarted && 
                       !_playerState.mPaused &&
                       !_shutdown &&
                       _playerState.mTotalBytes > (_playerState.mBufferInSeconds * _playerState.mBufferSize)) {
                        DLog(@"starting playback");
                        DLog(@"total bytes for playback start: %llu", _playerState.mTotalBytes);
                        _playerState.mBuffering = NO;
                        
                        [self primeQueueBuffers];
                        [self startQueue];
                    }
                    
                    // enqueue audio buffers again after buffering
                    if(_playerState.mStarted &&
                       !_playerState.mPaused &&
                       _playerState.mBuffering &&
                       !_shutdown &&
                       _playerState.mTotalBytes > (_playerState.mBufferInSeconds * _playerState.mBufferSize)) {
                        DLog(@"starting playback again");
                        _playerState.mBuffering = NO;
                        
                        [self stopBufferTimer];
                        [self primeQueueBuffers];
                        [self startQueue];
                    }
                }
                
                if(packet.data) {
                    av_free_packet(&packet);
                }
            } while (!last_packet && !_playerState.mPaused && !QuitDecoding);
            
            dispatch_async(dispatch_get_main_queue(), ^(void) {
                DLog(@"connection dropped");
                _connected = NO;
                
                if(_swrBuffer) {
                    free(_swrBuffer);
                    _swrBuffer = NULL;
                    _swrBufferSize = 0;
                }
                
                if(_swrCtx) {
                    swr_free(&_swrCtx);
                    _swrCtx = NULL;
                }
                
                if(_codecCtx) {
                    avcodec_close(_codecCtx);
                    _codecCtx = NULL;
                }
                
                if(_formatCtx) {
                    avformat_close_input(&_formatCtx);
                    _formatCtx = NULL;
                }
                
                _dispatchQueueReady = YES;
            });
        }
    });
}

- (void)setupQueue {
    if(_playerState.mQueue == NULL) {
        // create audio queue
        OSStatus err = AudioQueueNewOutput(&_playerState.mAudioFormat, MMSPlayCallback, self, NULL, kCFRunLoopCommonModes, 0, &_playerState.mQueue);
        if(err != noErr) {
            DLog(@"audio queue could not be created");
            _radioError = kRadioErrorAudioQueueCreate;
            [self setState:kRadioStateError];
            return;
        }
        
        // create audio buffers
        for(int t = 0; t < NUM_AQ_BUFS; ++t) {
            err = AudioQueueAllocateBuffer(_playerState.mQueue, _playerState.mBufferSize, &_playerState.mQueueBuffers[t]->mQueueBuffer);
            if(err) {
                DLog(@"Error: AudioQueueAllocateBuffer %d", (int)err);
                _radioError = kRadioErrorAudioQueueBufferCreate;
                [self setState:kRadioStateError];
                return;
            }
        }
    }
}

- (void)dismissQueue {
    if(_playerState.mQueue) {
        if(_playerState.mPlaying) {
            AudioQueueStop(_playerState.mQueue, YES);
            _playerState.mPlaying = NO;
        }
        
        AudioQueueDispose(_playerState.mQueue, YES);
        _playerState.mQueue = NULL;
    }
}

- (void)primeQueueBuffers {
    _buffersInUse = NUM_AQ_BUFS;
    for(int t = 0; t < NUM_AQ_BUFS; ++t) {
        MMSPlayCallback(self, _playerState.mQueue, _playerState.mQueueBuffers[t]->mQueueBuffer);
	}
}

- (void)startQueue {
    AudioQueueSetParameter(_playerState.mQueue, kAudioQueueParam_Volume, _playerState.mGain);
    OSStatus result = AudioQueueStart(_playerState.mQueue, NULL);
    if(result == noErr) {
        _playerState.mStarted = YES;
        _playerState.mPlaying = YES;
        
        [self setState:kRadioStatePlaying];
    } else {
        _radioError = kRadioErrorAudioQueueStart;
        [self setState:kRadioStateError];
    }
}
         
 - (void)setState:(YLRadioState)state {
     if(state == _radioState) {
         return;
     }
     
     _radioState = state;
     if(_radioState == kRadioStateError) {
         _playerState.mPlaying = NO;
         _playerState.mPaused = NO;
         _playerState.mBuffering = NO;
         _playerState.mStarted = NO;
         _playerState.mTotalBytes = 0.0;
         
         if(_playerState.mQueue) {
             if(_playerState.mPlaying) {
                 AudioQueueStop(_playerState.mQueue, YES);
                 _playerState.mPlaying = NO;
             }
             
             AudioQueueDispose(_playerState.mQueue, YES);
             _playerState.mQueue = NULL;
         }
         
         if(_swrBuffer) {
             free(_swrBuffer);
             _swrBuffer = NULL;
             _swrBufferSize = 0;
         }
         
         if(_swrCtx) {
             swr_free(&_swrCtx);
             _swrCtx = NULL;
         }
         
         if(_codecCtx) {
             avcodec_close(_codecCtx);
             _codecCtx = NULL;
         }
         
         if(_formatCtx) {
             avformat_close_input(&_formatCtx);
             _formatCtx = NULL;
         }
     }
     
     dispatch_async(dispatch_get_main_queue(), ^(void) {
         [_delegate radioStateChanged:self];
     });
 }

- (void)cleanup {
    [self release];
}

- (void)stopRecordingWithError:(NSError *)error {
    if(!_playerState.mRecording) {
        DLog(@"Warning: There's no active recording session.");
        return;
    }
    
    _playerState.mRecording = NO;
    [_converter finish];
    [_converter release];
    
    if(_delegate && [_delegate respondsToSelector:@selector(radio:recordingFailedWithError:)]) {
        [_delegate radio:self recordingFailedWithError:error];
    }
}

- (void)startBufferTimerWithTimeout:(NSInteger)timeout {
    [self stopBufferTimer];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        DLog(@"Starting buffer timer with timeout: %ld", (long)timeout);
        _bufferTimer = [[NSTimer scheduledTimerWithTimeInterval:timeout
                                                         target:self
                                                       selector:@selector(onBufferTimerFired:)
                                                       userInfo:nil
                                                        repeats:NO] retain];
    });
}

- (void)startReconnectTimerWithTimeout:(NSInteger)timeout {
    [self stopReconnectTimer];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        DLog(@"Starting reconnect timer with timeout: %ld", (long)timeout);
        _reconnectTimer = [[NSTimer scheduledTimerWithTimeInterval:timeout
                                                            target:self
                                                          selector:@selector(onReconnectTimerFired:)
                                                          userInfo:nil
                                                           repeats:NO] retain];
    });
}

- (void)startTimeoutTimerWithTimeout:(NSInteger)timeout {
    [self stopTimeoutTimer];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        _connectShouldTimeout = NO;
        _timeoutTimer = [[NSTimer scheduledTimerWithTimeInterval:timeout
                                                          target:self
                                                        selector:@selector(onTimeoutTimerFired:)
                                                        userInfo:nil
                                                         repeats:NO] retain];
    });
}

- (void)stopBufferTimer {
    if(_bufferTimer) {
        dispatch_async(dispatch_get_main_queue(), ^{
            DLog(@"Stopping buffer timer");
            [_bufferTimer invalidate];
            [_bufferTimer release];
            _bufferTimer = nil;
        });
    }
}

- (void)stopReconnectTimer {
    if(_reconnectTimer) {
        dispatch_async(dispatch_get_main_queue(), ^{
            DLog(@"Stopping reconnect timer");
            [_reconnectTimer invalidate];
            [_reconnectTimer release];
            _reconnectTimer = nil;
        });
    }
}

- (void)stopTimeoutTimer {
    if(_timeoutTimer) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [_timeoutTimer invalidate];
            [_timeoutTimer release];
            _timeoutTimer = nil;
        });
    }
}

- (void)onBufferTimerFired:(NSTimer *)timer {
    [_bufferTimer release];
    _bufferTimer = nil;
    
    if(_reachability == nil) {
        _reachability = [[YLReachability reachabilityForInternetConnection] retain];
        [_reachability startNotifier];
    }
    
    _connectionError = YES;
    [self pause];
}

- (void)onReconnectTimerFired:(NSTimer *)timer {
    [_reconnectTimer release];
    _reconnectTimer = nil;
    
    _connectionError = YES;
    [self pause];
}

- (void)onTimeoutTimerFired:(NSTimer *)timer {
    [_timeoutTimer release];
    _timeoutTimer = nil;
    
    _connectShouldTimeout = YES;
}

- (int)connectShouldTimeout {
    if(_radioState != kRadioStateConnecting) {
        return 0;
    }
    
    if(_connectShouldTimeout) {
        return 1;
    } else {
        return 0;
    }
}

@end
