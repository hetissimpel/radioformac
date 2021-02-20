//
//  HTTPRadio.m
//  Radio
//
//  Copyright 2011 Yakamoz Labs. All rights reserved.
//

#import "YLHTTPRadio.h"
#import "YLAudioPacket.h"
#import "NSHTTPURLResponse+RadioTunes.h"
#import "YLM3UParser.h"
#import "YLXSPFParser.h"
#import "YLPLSParser.h"
#import "YLASXParser.h"
#import "YLReachability.h"

#define HTTP_TIMEOUT        30

@interface YLHTTPRadio() {
    NSURLConnection *_urlConnection;
    NSMutableData *_audioData;
    NSMutableData *_playlistData;
    NSMutableData *_metaData;
    NSDictionary *_streamHeaders;
    NSString *_contentType;
    NSString *_httpUserAgent;
    NSUInteger _httpTimeout;
    
    int _metadataInterval;
    int _metadataLength;
    int _streamCount;
    int _bitrateInBytes;
    BOOL _icyStartFound;
    BOOL _icyEndFound;
    BOOL _icyHeadersParsed;
    BOOL _connectionFinished;
    BOOL _waitForEmptyBuffers;
    
    BOOL _highQualityFormat;
    AudioStreamBasicDescription _hqASBD;
    AudioFileID _recordFile;
    SInt64 _recordPacket;
    
    YLPlaylistType _playlistType;
    NSObject<YLPlaylistParserProtocol> *_playlistParser;
    
    YLHTTPState _httpState;
    
}

- (void)handlePlayCallback:(AudioQueueRef)inAudioQueue 
                    buffer:(AudioQueueBufferRef)inBuffer;
- (void)handlePropertyChange:(AudioFileStreamID)inAudioFileStream
                    property:(AudioFileStreamPropertyID)inPropertyID
                       flags:(UInt32 *)ioFlags;
- (void)handleQueuePropertyChange:(AudioQueueRef)inAudioQueue
                         property:(AudioQueuePropertyID)inPropertyID;
- (void)handlePacket:(UInt32) inNumberBytes 
     numberOfPackets:(UInt32) inNumberPackets 
           inputData:(const void *)inInputData
  packetDescriptions:(AudioStreamPacketDescription *)inPacketDescriptions;
- (void)dismissQueue;
- (void)primeQueueBuffers;
- (void)startQueue;
- (void)requestPlaylist;
- (void)requestAudioStream;
- (void)parseAudioData:(NSData *)data;
- (void)setState:(YLRadioState) state;
- (UInt32)fileTypeHint;
- (YLPlaylistType)playlistTypeForContentType:(NSString *)contentType;
- (id<YLPlaylistParserProtocol>)playlistParserForType:(YLPlaylistType)playlistType;
- (void)setupPlaylistParserForExtension:(NSString *)extension;
- (BOOL)supportedContentType:(NSString *)contentType;
- (void)cleanup;
- (void)copyEncoderCookieToFile;
- (void)stopRecordingWithError:(NSError *)error;
- (void)startBufferTimerWithTimeout:(NSInteger)timeout;
- (void)startReconnectTimerWithTimeout:(NSInteger)timeout;
- (void)stopBufferTimer;
- (void)stopReconnectTimer;
- (void)onBufferTimerFired:(NSTimer *)timer;
- (void)onReconnectTimerFired:(NSTimer *)timer;
- (void)onReachabilityChanged:(NSNotification *)notification;
@end


static void HTTPPlayCallback(void *inUserData, AudioQueueRef inAudioQueue, AudioQueueBufferRef inBuffer) {
    YLHTTPRadio *radio = (YLHTTPRadio *)inUserData;
    [radio handlePlayCallback:inAudioQueue buffer:inBuffer];
}

static void PacketsProc(void *inUserData, UInt32 inNumberBytes, UInt32 inNumberPackets, const void *inInputData, AudioStreamPacketDescription *inPacketDescriptions) {
    YLHTTPRadio *radio = (YLHTTPRadio *)inUserData;
    [radio handlePacket:inNumberBytes numberOfPackets:inNumberPackets inputData:inInputData packetDescriptions:inPacketDescriptions];
}

static void PropertyListenerProc(void *inUserData, AudioFileStreamID inAudioFileStream, AudioFileStreamPropertyID inPropertyID, UInt32 *ioFlags) {
    YLHTTPRadio *radio = (YLHTTPRadio *)inUserData;
    [radio handlePropertyChange:inAudioFileStream property:inPropertyID flags:ioFlags];
}

static void QueuePropertyListenerProc(void *inUserData, AudioQueueRef inAQ, AudioQueuePropertyID inID) {
    YLHTTPRadio *radio = (YLHTTPRadio *)inUserData;
    [radio handleQueuePropertyChange:inAQ property:inID];
}


@implementation YLHTTPRadio

@synthesize httpUserAgent = _httpUserAgent;
@synthesize httpTimeout = _httpTimeout;

- (id)initWithURL:(NSURL *)url {
    if(![[url scheme] isEqualToString:@"http"] &&
       ![[url scheme] isEqualToString:@"https"]) {
        return nil;
    }
    
    self = [super initWithURL:url];
    if(self) {
        _httpUserAgent = nil;
        _httpTimeout = HTTP_TIMEOUT;
        
        _playlistType = kPlaylistNone;
        _playlistParser = nil;
        
        NSString *urlExtension = [_url pathExtension];
        [self setupPlaylistParserForExtension:urlExtension];
        if(_playlistType == kPlaylistNone) {
            // we will immediately start parsing the audio stream
            _httpState = kHTTPStateAudioStreaming;
        } else {
            _httpState = kHTTPStatePlaylistParsing;
        }
        
        _urlConnection = nil;
        _audioData = nil;
        _playlistData = nil;
        _metaData = nil;
        _metadataLength = 0;
        _metadataInterval = 0;
        _bitrateInBytes = 0;
        _streamCount = 0;
        _contentType = nil;
        
        _icyStartFound = NO;
        _icyEndFound = NO;
        _icyHeadersParsed = NO;
        _connectionFinished = NO;
        _waitForEmptyBuffers = NO;
        
        _highQualityFormat = NO;

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onReachabilityChanged:) name:kYLReachabilityChangedNotification object:nil];
    }
    
    return self;
}

- (void)dealloc {
    [_httpUserAgent release];
    [_playlistParser release];
    
    
    [_audioData release];
    [_metaData release];
    [_playlistData release];
    [_streamHeaders release];
    [_contentType release];
    
    [super dealloc];
}

- (void)shutdown {
    _shutdown = YES;
    _playerState.mPlaying = NO;
    _playerState.mPaused = YES;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    if(_reachability) {
        [_reachability stopNotifier];
        [_reachability release];
        _reachability = nil;
    }
    
    if(_urlConnection) {
        [_urlConnection cancel];
        [_urlConnection release];
        _urlConnection = nil;
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
    
    [self stopBufferTimer];
    [self stopReconnectTimer];
    
    [self retain];
    dispatch_async(_lockQueue, ^{
        [self cleanup];
    });
}

- (void)play {
    if(_playerState.mPlaying) {
        return;
    }
    
    _playerState.mPaused = NO;
    _playerState.mPlaying = YES;
    
    _streamCount = 0;
    _metadataInterval = 0;
    _metadataLength = 0;
    _buffersInUse = 0;
    
    _icyStartFound = NO;
    _icyEndFound = NO;
    _icyHeadersParsed = NO;
    _connectionFinished = NO;
    _connectionError = NO;
    _waitingForReconnection = NO;
    _waitForEmptyBuffers = NO;
    
    if(_metaData == nil) {
        _metaData = [[NSMutableData alloc] init];
    }

    if(_audioData == nil) {
        _audioData = [[NSMutableData alloc] init];
    }
    
    if(_playlistType != kPlaylistNone && _playlistData == nil) {
        _playlistData = [[NSMutableData alloc] init];
    }
    
    // this value will be later calculated in PropertyListenerProc
    _playerState.mBufferSize = AQ_DEFAULT_BUF_SIZE;
    _playerState.mTotalBytes = 0;
    
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
    
    if([_reachability isReachable]) {
        [self setState:kRadioStateConnecting];
        
        if(_httpState == kHTTPStatePlaylistParsing) {
            [self requestPlaylist];
        } else {
            [self requestAudioStream];
        }
    } else {
        _playerState.mPlaying = NO;
        [_reachability stopNotifier];
        [_reachability release];
        _reachability = nil;
        
        _radioError = kRadioErrorNetworkError;
        [self setState:kRadioStateError];
    }
}

- (void)pause {
    if(_playerState.mPaused) {
        return;
    }
    
    if(!_waitForEmptyBuffers) {
        _playerState.mPlaying = NO;
        _playerState.mPaused = YES;
    }
    
    if(_urlConnection) {
        [_urlConnection cancel];
        [_urlConnection release];
        _urlConnection = nil;
    }
    
    if(!_waitForEmptyBuffers && _playerState.mRecording) {
        [self stopRecording];
    }
    
    if(_playerState.mStarted) {
        _playerState.mStarted = NO;
        _playerState.mTotalBytes = 0.0;
        
        [self dismissQueue];
        
        if(!_waitForEmptyBuffers) {
            dispatch_sync(_lockQueue, ^(void) {
                [_playerState.mAudioQueue removeAllPackets];
            });
        }
    }
    
    [self stopBufferTimer];
    [self stopReconnectTimer];
    
    if(_reachability) {
        [_reachability stopNotifier];
        [_reachability release];
        _reachability = nil;
    }
    
    if(_connectionError) {
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
                [self play];
            }
        } else {
            _radioError = kRadioErrorNetworkError;
            [self setState:kRadioStateError];
        }
    } else {
        if(!_waitForEmptyBuffers) {
            [self setState:kRadioStateStopped];
        }
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
    
    CFStringRef pathEscaped = CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)filePath, NULL, NULL, kCFStringEncodingUTF8);
    CFURLRef url = CFURLCreateWithString(kCFAllocatorDefault, pathEscaped, NULL);
    OSStatus err = AudioFileCreateWithURL(url, [self fileTypeHint], &_playerState.mAudioFormat, kAudioFileFlags_EraseFile, &_recordFile);
    CFRelease(url);
    CFRelease(pathEscaped);
    if(err) {
        DLog(@"Error: Destination file for recording cannot be created.");
        if(notifyDelegate) {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"Destination file for recording cannot be created."
                                                                 forKey:NSLocalizedDescriptionKey];
            NSError *error = [NSError errorWithDomain:YLRadioTunesErrorDomain code:kRadioRecordingFileError userInfo:userInfo];
            [_delegate radio:self recordingFailedWithError:error];
        }
        
        return;
    }
    
    [self copyEncoderCookieToFile];
    _recordPacket = 0;
    
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
    [self copyEncoderCookieToFile];
    AudioFileClose(_recordFile);
    if(_delegate && [_delegate respondsToSelector:@selector(radio:didStopRecordingWithDestination:)]) {
        [_delegate radio:self didStopRecordingWithDestination:_filePath];
    }
}

- (NSString *)fileExtensionHint {
    AudioFileTypeID fileType = [self fileTypeHint];
    if(fileType == kAudioFileMP3Type) {
        return @"mp3";
    } else if(fileType == kAudioFileAAC_ADTSType) {
        return @"m4a";
    } else {
        return @"m4a";
    }
}


#pragma mark -
#pragma mark Private Methods
- (void)handlePlayCallback:(AudioQueueRef)inAudioQueue buffer:(AudioQueueBufferRef)inBuffer {
    if(_playerState.mPaused) {
        return;
    }
    
    __block int maxBytes = inBuffer->mAudioDataBytesCapacity;
    __block int descriptionCount = 0;
    
    dispatch_sync(_lockQueue, ^(void) {
        @autoreleasepool {
            YLQueueBufferRef buffer = NULL;
            for(int i = 0; i < NUM_AQ_BUFS && buffer == NULL; ++i) {
                if(inBuffer == _playerState.mQueueBuffers[i]->mQueueBuffer) {
                    buffer = _playerState.mQueueBuffers[i];
                }
            }
            
            if(buffer == NULL) {
                DLog(@"Error: AudioQueue buffer mismatch, this should never happen!");
                return;
            }
            
            if(_playerState.mRecording) {
                // write packets to file
                OSStatus err = AudioFileWritePackets(_recordFile, FALSE, inBuffer->mAudioDataByteSize, buffer->mPacketDescriptions, _recordPacket,
                                                     (UInt32 *)&buffer->mPacketDescriptionCount, inBuffer->mAudioData);
                if(err) {
                    DLog(@"Error: Could not write packets: %d", (int)err);
                    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"Audio packets could not be written to file."
                                                                         forKey:NSLocalizedDescriptionKey];
                    NSError *error = [NSError errorWithDomain:YLRadioTunesErrorDomain code:kRadioRecordingWriteError userInfo:userInfo];
                    [self stopRecordingWithError:error];
                } else {
                    _recordPacket += buffer->mPacketDescriptionCount;
                }
            }
            
            inBuffer->mAudioDataByteSize = 0;
            descriptionCount = 0;
            
            // variable bit rate implementation (VBR)
            if(_playerState.mQueueBuffers[0]->mPacketDescriptions) {
                YLAudioPacket *audioPacket = [_playerState.mAudioQueue peak];
                while(audioPacket) {
                    if(([audioPacket length] + inBuffer->mAudioDataByteSize) < maxBytes) {
                        [audioPacket copyToBuffer:(inBuffer->mAudioData+inBuffer->mAudioDataByteSize) size:[audioPacket length]];
                        buffer->mPacketDescriptions[descriptionCount] = [audioPacket audioDescription];
                        buffer->mPacketDescriptions[descriptionCount].mStartOffset = inBuffer->mAudioDataByteSize;
                        inBuffer->mAudioDataByteSize += [audioPacket length];
                        
                        audioPacket = [_playerState.mAudioQueue pop];
                        [audioPacket release];
                        audioPacket = [_playerState.mAudioQueue peak];
                        descriptionCount++;
                        if(descriptionCount == AQ_MAX_PACKET_DESCS) {
                            break;
                        }
                    } else {
                        break;
                    }
                }
                
                buffer->mPacketDescriptionCount = descriptionCount;
                
            } else { // constant bit rate implementation (CBR)
                YLAudioPacket *audioPacket = [_playerState.mAudioQueue peak];
                int dataWritten = 0;
                while(audioPacket) {
                    if((dataWritten + [audioPacket remainingLength]) > maxBytes) {
                        int dataNeeded = (maxBytes - dataWritten);
                        [audioPacket copyToBuffer:(inBuffer->mAudioData+dataWritten) size:dataNeeded];
                        dataWritten += dataNeeded;
                        break;
                    } else {
                        [audioPacket copyToBuffer:(inBuffer->mAudioData+dataWritten) size:[audioPacket remainingLength]];
                        dataWritten += [audioPacket remainingLength];
                         
                         audioPacket = [_playerState.mAudioQueue pop];
                         [audioPacket release];
                         audioPacket = [_playerState.mAudioQueue peak];
                    }
                }
                inBuffer->mAudioDataByteSize = dataWritten;
            }
            
            // buffer was used previously
            _buffersInUse--;
            if(inBuffer->mAudioDataByteSize > 0) {
                // descriptionCount = 0, _playerState.packetDescriptions = NULL for CBR streams
                OSStatus result = AudioQueueEnqueueBuffer(inAudioQueue, inBuffer, buffer->mPacketDescriptionCount, buffer->mPacketDescriptions);
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
                if(_connectionFinished) {
                    // connection is closed and buffers are almost empty
                    _waitForEmptyBuffers = YES;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self pause];
                    });
                } else {
                    DLog(@"all buffers empty, buffering");
                    AudioQueuePause(inAudioQueue);
                    
                    _playerState.mTotalBytes = 0.0;
                    _playerState.mBuffering = YES;
                    [self setState:kRadioStateBuffering];
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self startBufferTimerWithTimeout:10];
                    });                
                }
            }
        }
    });
}

- (void)handlePropertyChange:(AudioFileStreamID)inAudioFileStream
                    property:(AudioFileStreamPropertyID)inPropertyID 
                       flags:(UInt32 *)ioFlags {
    OSStatus err = noErr;
    
    if(inPropertyID == kAudioFileStreamProperty_ReadyToProducePackets) {
        // the audio stream parser is now ready to produce packets
        // get the stream format
        UInt32 asbdSize = sizeof(_playerState.mAudioFormat);
        err = AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_DataFormat, &asbdSize, &_playerState.mAudioFormat);
        if(err) {
            DLog(@"Error: get kAudioFileStreamProperty_DataFormat %d", (int)err);
            _radioError = kRadioErrorFileStreamGetProperty;
            [self setState:kRadioStateError];
            return;
        }
        
        if(_highQualityFormat) {
            _playerState.mAudioFormat = _hqASBD;
        }
        
        // create the audio queue
        err = AudioQueueNewOutput(&_playerState.mAudioFormat, HTTPPlayCallback, self, NULL, NULL, 0, &_playerState.mQueue);
        if(err) {
            DLog(@"Error: AudioQueueNewOutput %d", (int)err);
            _radioError = kRadioErrorAudioQueueCreate;
            [self setState:kRadioStateError];
            return;
        }
        
        err = AudioQueueAddPropertyListener(_playerState.mQueue, kAudioQueueProperty_IsRunning, QueuePropertyListenerProc, self);
        if(err) {
            DLog(@"Error: Cannot add listener to AudioQueue for property kAudioQueueProperty_IsRunning %d", (int)err);
            _radioError = kRadioErrorAudioQueueCreate;
            [self setState:kRadioStateError];
            return;
        }
        
        static const int kDefaultBufferSize = 0x8000;   // 32K
        UInt32 maxPacketSize = 0;
        if(_playerState.mAudioFormat.mBytesPerPacket) {
            maxPacketSize = _playerState.mAudioFormat.mBytesPerPacket;
        } else {
            UInt32 propertySize = sizeof(maxPacketSize);
            err = AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_PacketSizeUpperBound, &propertySize, &maxPacketSize);
            if(err) {
                err = AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_MaximumPacketSize, &propertySize, &maxPacketSize);
                if(err || maxPacketSize == 0) {
                    maxPacketSize = 1024;
                }
            }
        }
        
        if(_playerState.mAudioFormat.mFramesPerPacket) {
            UInt32 numPacketsForTime = (int)ceil(_playerState.mAudioFormat.mSampleRate / _playerState.mAudioFormat.mFramesPerPacket * 0.5);
            _playerState.mBufferSize = numPacketsForTime * maxPacketSize;
        } else {
            _playerState.mBufferSize = kDefaultBufferSize;
        }
        
        bool isFormatVBR = (_playerState.mAudioFormat.mBytesPerPacket == 0 ||
                            _playerState.mAudioFormat.mFramesPerPacket == 0);
        
        if(isFormatVBR) {
            for(int i = 0; i < NUM_AQ_BUFS; ++i) {
                _playerState.mQueueBuffers[i]->mPacketDescriptions = (AudioStreamPacketDescription *)malloc(AQ_MAX_PACKET_DESCS * sizeof(AudioStreamPacketDescription));
            }
        } else {
            for(int i = 0; i < NUM_AQ_BUFS; ++i) {
                _playerState.mQueueBuffers[i]->mPacketDescriptions = NULL;
            }
        }
        
        // allocate the audio queue buffers
        for(int i = 0; i < NUM_AQ_BUFS; ++i) {
            err = AudioQueueAllocateBuffer(_playerState.mQueue, _playerState.mBufferSize, &_playerState.mQueueBuffers[i]->mQueueBuffer);
            if(err) {
                DLog(@"Error: AudioQueueAllocateBuffer %d", (int)err);
                _radioError = kRadioErrorAudioQueueBufferCreate;
                [self setState:kRadioStateError];
                return;
            }
        }
                
        // get the magic cookie size
        Boolean writable;
        UInt32 cookieSize;
        err = AudioFileStreamGetPropertyInfo(inAudioFileStream, kAudioFileStreamProperty_MagicCookieData, &cookieSize, &writable);
        if(err == noErr && cookieSize > 0) {
            // get the magic cookie data
            void *cookieData = calloc(1, cookieSize);
            err = AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_MagicCookieData, &cookieSize, cookieData);
            if(err == noErr) {
                // set the magic cookie on the queue
                err = AudioQueueSetProperty(_playerState.mQueue, kAudioQueueProperty_MagicCookie, cookieData, cookieSize);
                if(err) {
                    DLog(@"Warning: set kAudioQueueProperty_MagicCookie %d", (int)err);
                }
            }
            
            free(cookieData);
        }
    } else if(inPropertyID == kAudioFileStreamProperty_FormatList) {
        Boolean writable;
        UInt32 propertySize;
        err = AudioFileStreamGetPropertyInfo(inAudioFileStream, kAudioFileStreamProperty_FormatList, &propertySize, &writable);
        if(err) {
            DLog(@"Warning: info kAudioFileStreamProperty_FormatList %d", (int)err);
            return;
        }
        
        AudioFormatListItem *formatList = malloc(propertySize);
        err = AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_FormatList, &propertySize, formatList);
        if(err) {
            DLog(@"Warning: get kAudioFileStreamProperty_FormatList %d", (int)err);
            free(formatList);
            return;
        }
        
        UInt32 numFormats = propertySize / sizeof(AudioFormatListItem);
        DLog(@"This file has a %u layered data format:", (unsigned int)numFormats);
        for(unsigned int i = 0; i < numFormats; i++) {
            AudioStreamBasicDescription temp = formatList[i].mASBD;
            DLog(@"%u %f", (unsigned int)temp.mFormatID, temp.mSampleRate);
        }
        
        UInt32 itemIndex;
        UInt32 indexSize = sizeof(itemIndex);
        // get the index number of the first playable format -- this index number will be for
        // the highest quality layer the platform is capable of playing
        err = AudioFormatGetProperty(kAudioFormatProperty_FirstPlayableFormatFromList, propertySize, formatList, &indexSize, &itemIndex);
        if(err) {
            DLog(@"Warning: get kAudioFormatProperty_FirstPlayableFormatFromList %d", (int)err);
            free(formatList);
            return;
        }
        
        _highQualityFormat = YES;
        _hqASBD = formatList[itemIndex].mASBD;
        
        free(formatList);
    }
}

- (void)handleQueuePropertyChange:(AudioQueueRef)inAudioQueue
                         property:(AudioQueuePropertyID)inPropertyID {
    if(inPropertyID == kAudioQueueProperty_IsRunning) {
        if(_waitForEmptyBuffers && _playerState.mPlaying) {
            if(_playerState.mRecording) {
                [self stopRecording];
            }
            
            _playerState.mPlaying = NO;
            _playerState.mPaused = YES;
            
            _playerState.mQueue = NULL;
            
            for(int i = 0; i < NUM_AQ_BUFS; ++i) {
                free(_playerState.mQueueBuffers[i]->mPacketDescriptions);
                _playerState.mQueueBuffers[i]->mPacketDescriptions = NULL;
                _playerState.mQueueBuffers[i]->mPacketDescriptionCount = 0;
            }
            
            dispatch_sync(_lockQueue, ^(void) {
                [_playerState.mAudioQueue removeAllPackets];
            });
            
            [self setState:kRadioStateStopped];
        }
    }
}

- (void)handlePacket:(UInt32)inNumberBytes
     numberOfPackets:(UInt32)inNumberPackets
           inputData:(const void *)inInputData 
  packetDescriptions:(AudioStreamPacketDescription *)inPacketDescriptions {
    dispatch_sync(_lockQueue, ^(void) {
        @autoreleasepool {
            for(int i = 0; i < inNumberPackets; ++i) {
                AudioStreamPacketDescription description = inPacketDescriptions[i];
                
                NSData *data = [[NSData alloc] initWithBytes:((const char *)inInputData+description.mStartOffset) length:description.mDataByteSize];
                YLAudioPacket *packet = [[YLAudioPacket alloc] initWithData:data];
                [packet setAudioDescription:description];
                [_playerState.mAudioQueue addPacket:packet];
                [data release];
                [packet release];
                
                _playerState.mTotalBytes += description.mDataByteSize;
            }
        }
    });
    
    if(!_playerState.mStarted &&
       !_playerState.mPaused &&
       _playerState.mTotalBytes > (_playerState.mBufferInSeconds * _playerState.mBufferSize)) {
        DLog(@"total bytes for playback start: %llu", _playerState.mTotalBytes);
        _playerState.mBuffering = NO;
        
        [self primeQueueBuffers];
        [self startQueue];
    }
    
    // enqueue audio buffers again after buffering
    if(_playerState.mStarted &&
       !_playerState.mPaused &&
       _playerState.mBuffering &&
       _playerState.mTotalBytes > (_playerState.mBufferInSeconds * _playerState.mBufferSize)) {
        DLog(@"total bytes for playback start: %llu", _playerState.mTotalBytes);
        DLog(@"starting playback again");
        _playerState.mBuffering = NO;
        [self stopBufferTimer];
        
        [self primeQueueBuffers];
        [self startQueue];
    }
}

- (void)dismissQueue {
    if(_playerState.mQueue) {
        if(_playerState.mPlaying) {
            if(_waitForEmptyBuffers) {
                AudioQueueStop(_playerState.mQueue, NO);
            } else {
                AudioQueueStop(_playerState.mQueue, YES);
            }
        }
        
        if(!_waitForEmptyBuffers) {
            AudioQueueDispose(_playerState.mQueue, YES);
            _playerState.mQueue = NULL;
            
            for(int i = 0; i < NUM_AQ_BUFS; ++i) {
                free(_playerState.mQueueBuffers[i]->mPacketDescriptions);
                _playerState.mQueueBuffers[i]->mPacketDescriptions = NULL;
                _playerState.mQueueBuffers[i]->mPacketDescriptionCount = 0;
            }
        }
    }
}

- (void)primeQueueBuffers {
    _buffersInUse = NUM_AQ_BUFS;
    for(int i = 0; i < NUM_AQ_BUFS; ++i) {
        HTTPPlayCallback(self, _playerState.mQueue, _playerState.mQueueBuffers[i]->mQueueBuffer);
    }
}

- (void)startQueue {
    AudioQueueSetParameter(_playerState.mQueue, kAudioQueueParam_Volume, _playerState.mGain);
    OSStatus err = AudioQueueStart(_playerState.mQueue, NULL);
    if(err == noErr) {
        _playerState.mStarted = YES;
        _playerState.mPlaying = YES;
        
        [self setState:kRadioStatePlaying];
    } else {
        _radioError = kRadioErrorAudioQueueStart;
        [self setState:kRadioStateError];
    }
}

- (void)requestPlaylist {
    NSMutableURLRequest *request = [[[NSMutableURLRequest alloc] initWithURL:_url] autorelease];
    [request setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
    if(_httpUserAgent) {
        [request setValue:_httpUserAgent forHTTPHeaderField:@"User-Agent"];
    }
    [request setTimeoutInterval:_httpTimeout];
    
    if(_urlConnection) {
        [_urlConnection release];
        _urlConnection = nil;
    }
    
    _urlConnection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:NO];
    [_urlConnection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    [_urlConnection start];
}

- (void)requestAudioStream {
    NSMutableURLRequest *request = [[[NSMutableURLRequest alloc] initWithURL:_url] autorelease];
    [request setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
    // Shoutcast Metadata Protocol: http://www.smackfu.com/stuff/programming/shoutcast.html
    [request setValue:@"1" forHTTPHeaderField:@"Icy-Metadata"];
    [request setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];
    if(_httpUserAgent) {
        [request setValue:_httpUserAgent forHTTPHeaderField:@"User-Agent"];
    }
    [request setTimeoutInterval:_httpTimeout];
    
    if(_urlConnection) {
        [_urlConnection release];
        _urlConnection = nil;
    }
    
    _urlConnection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:NO];
    [_urlConnection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    [_urlConnection start];
}

- (void)parseAudioData:(NSData *)data {
    if(_playerState.mPaused) {
        return;
    }
    
    const char *bytes = [data bytes];
    NSInteger length = [data length];
    NSInteger streamStart = 0;
    
    if(_metadataInterval == 0) {
        if(!_icyStartFound) {
            NSString *icyCheck = [[[NSString alloc] initWithBytes:bytes length:10 encoding:NSUTF8StringEncoding] autorelease];
            if(icyCheck && [icyCheck caseInsensitiveCompare:@"ICY 200 OK"] == NSOrderedSame) {
                _icyStartFound = YES;
            }
        }
        
        if(_icyStartFound && !_icyEndFound) {
            NSInteger lineStart = 0;
            char c1 = '\0';
            char c2 = '\0';
            char c3 = '\0';
            char c4 = '\0';
            BOOL radioMetadataReady = NO;
            
            for(streamStart = 0; streamStart < length; streamStart++) {
                if((streamStart + 3) > length) {
                    break;
                }
                
                c1 = bytes[streamStart];
                c2 = bytes[streamStart+1];
                c3 = bytes[streamStart+2];
                c4 = bytes[streamStart+3];
                
                if(c1 == '\r' && c2 == '\n') {
                    NSString *fullString = [[[NSString alloc] initWithBytes:bytes length:streamStart encoding:NSUTF8StringEncoding] autorelease];
                    if(fullString == nil) {
                        fullString = [[[NSString alloc] initWithBytes:bytes length:streamStart encoding:NSASCIIStringEncoding] autorelease];
                    }
                    if(fullString) {
                        NSString *line = [fullString substringWithRange:NSMakeRange(lineStart, (fullString.length - lineStart))];
                        NSArray *lineItems = [line componentsSeparatedByString:@":"];
                        if([lineItems count] > 1) {
                            if([[lineItems objectAtIndex:0] caseInsensitiveCompare:@"icy-metaint"] == NSOrderedSame) {
                                _metadataInterval = [[lineItems objectAtIndex:1] intValue];
                            }
                            
                            if([[lineItems objectAtIndex:0] caseInsensitiveCompare:@"icy-br"] == NSOrderedSame) {
                                _bitrateInBytes = ([[lineItems objectAtIndex:1] intValue] * 1000) / 8;
                            }
                            
                            if([[lineItems objectAtIndex:0] caseInsensitiveCompare:@"Content-Type"] == NSOrderedSame) {
                                if(_contentType) {
                                    [_contentType release];
                                    _contentType = nil;
                                }
                                
                                _contentType = [[[lineItems objectAtIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] retain];
                            }
                            
                            if([[lineItems objectAtIndex:0] caseInsensitiveCompare:@"icy-name"] == NSOrderedSame) {
                                if(_radioName) {
                                    [_radioName release];
                                    _radioName = nil;
                                }
                                
                                _radioName = [[[lineItems objectAtIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] retain];
                                radioMetadataReady = YES;
                            }
                            
                            if([[lineItems objectAtIndex:0] caseInsensitiveCompare:@"icy-genre"] == NSOrderedSame) {
                                if(_radioGenre) {
                                    [_radioGenre release];
                                    _radioGenre = nil;
                                }
                                
                                _radioGenre = [[[lineItems objectAtIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] retain];
                                radioMetadataReady = YES;
                            }
                            
                            if([[lineItems objectAtIndex:0] caseInsensitiveCompare:@"icy-url"] == NSOrderedSame) {
                                if(_radioUrl) {
                                    [_radioUrl release];
                                    _radioUrl = nil;
                                }
                                
                                _radioUrl = [[[lineItems objectAtIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] retain];
                                radioMetadataReady = YES;
                            }
                        }
                    
                        // end of line
                        lineStart = fullString.length + 2;
                    } else { // fullString == nil
                        lineStart += 2;
                    }
                    
                    if(c3 == '\r' && c4 == '\n') {
                        _icyEndFound = YES;
                        break;
                    }
                }
                
            }
            
            if(_icyEndFound) {
                _icyHeadersParsed = YES;
                streamStart += 4;
                
                OSStatus err = AudioFileStreamOpen(self, PropertyListenerProc, PacketsProc, [self fileTypeHint], &_playerState.mStreamID);
                if(err != noErr) {
                    DLog(@"Error: AudioFileStreamOpen %d", (int)err);
                    return;
                }
            }
            
            if(radioMetadataReady) {
                if(_delegate && [_delegate respondsToSelector:@selector(radioMetadataReady:)]) {
                    dispatch_async(dispatch_get_main_queue(), ^(void) {
                        [_delegate radioMetadataReady:self];
                    });
                }
            }
        }
    }
    
    if(_metadataInterval != 0) {
        for(NSInteger i = streamStart; i < length; ++i) {
            if(_metadataLength > 0) {
                if(bytes[i] != '\0') {
                    [_metaData appendBytes:(bytes+i) length:1];
                }
                
                _metadataLength--;
                if(_metadataLength == 0) {
                    NSString *title = [[[NSString alloc] initWithBytes:[_metaData bytes] length:[_metaData length] encoding:NSUTF8StringEncoding] autorelease];
                    NSError *error = nil;
                    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^StreamTitle='([^;]*)';" options:0 error:&error];
                    if(title && error == nil) {
                        NSTextCheckingResult *match = [regex firstMatchInString:title options:0 range:NSMakeRange(0, [title length])];
                        if(match) {
                            NSRange groupOne = [match rangeAtIndex:1];
                            if(!NSEqualRanges(groupOne, NSMakeRange(NSNotFound, 0))) {
                                NSString *streamTitle = [title substringWithRange:groupOne];
                                
                                if(_radioTitle) {
                                    [_radioTitle release];
                                    _radioTitle = nil;
                                }
                                
                                _radioTitle = [streamTitle retain];
                                if(_delegate && [_delegate respondsToSelector:@selector(radioTitleChanged:)]) {
                                    dispatch_async(dispatch_get_main_queue(), ^(void) {
                                        [_delegate radioTitleChanged:self];
                                    });
                                }
                            }
                        }
                    }
                    
                    [_metaData setLength:0];
                }
                
                
                continue;
            }
            
            if(_metadataInterval > 0 && _streamCount == _metadataInterval) {
                _metadataLength = 16 * bytes[i];
                _streamCount = 0;
                
                continue;
            }
            
            _streamCount++;
            [_audioData appendBytes:(bytes+i) length:1];
            if([_audioData length] == _playerState.mBufferSize) {
                AudioFileStreamParseBytes(_playerState.mStreamID, (UInt32)[_audioData length], [_audioData bytes], 0);
                [_audioData setLength:0];
            }
        }
    } else if(_metadataInterval == 0 && (!_icyStartFound || _icyHeadersParsed)) {
        for(NSInteger i = streamStart; i < length; i++) {
            [_audioData appendBytes:(bytes+i) length:1];
            if([_audioData length] == _playerState.mBufferSize) {
                AudioFileStreamParseBytes(_playerState.mStreamID, (UInt32)[_audioData length], [_audioData bytes], 0);
                [_audioData setLength:0];
            }
        }
    }
}

- (void)setState:(YLRadioState) state {
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
        
        if(_urlConnection) {
            [_urlConnection cancel];
            [_urlConnection release];
            _urlConnection = nil;
        }
        
        [self dismissQueue];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        [_delegate radioStateChanged:self];
    });    
}

- (UInt32)fileTypeHint {
    if(_contentType == nil) {
        return 0;
    }
    
    if([_contentType caseInsensitiveCompare:@"audio/mpeg"] == NSOrderedSame) {
        return kAudioFileMP3Type;
    } else if([_contentType caseInsensitiveCompare:@"audio/aac"] == NSOrderedSame) {
        return kAudioFileAAC_ADTSType;
    } else if([_contentType caseInsensitiveCompare:@"audio/aacp"] == NSOrderedSame) {
        return kAudioFileAAC_ADTSType;
    } else {
        return 0;
    }
}

- (YLPlaylistType)playlistTypeForContentType:(NSString *)contentType {
    if(contentType == nil) {
        return kPlaylistNone;
    } else if([contentType rangeOfString:@"audio/mpegurl" options:NSCaseInsensitiveSearch].location != NSNotFound ||
              [contentType rangeOfString:@"audio/x-mpegurl" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return kPlaylistM3U;
    } else if([contentType rangeOfString:@"video/x-ms-asf" options:NSCaseInsensitiveSearch].location != NSNotFound ||
              [contentType rangeOfString:@"audio/x-ms-asf" options:NSCaseInsensitiveSearch].location != NSNotFound ||
              [contentType rangeOfString:@"audio/x-ms-wax" options:NSCaseInsensitiveSearch].location != NSNotFound ||
              [contentType rangeOfString:@"video/x-ms-wvx" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return kPlaylistASX;
    } else if([contentType rangeOfString:@"audio/x-scpls" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return kPlaylistPLS;
    } else {
        return kPlaylistNone;
    }
}

- (id<YLPlaylistParserProtocol>)playlistParserForType:(YLPlaylistType)playlistType {
    if(playlistType == kPlaylistM3U) {
        return [[[YLM3UParser alloc] init] autorelease];
    } else if(playlistType == kPlaylistPLS) {
        return [[[YLPLSParser alloc] init] autorelease];
    } else if(playlistType == kPlaylistXSPF) {
        return [[[YLXSPFParser alloc] init] autorelease];
    } else if(playlistType == kPlaylistASX) {
        return [[[YLASXParser alloc] init] autorelease];
    } else {
        return nil;
    }
}

- (void)setupPlaylistParserForExtension:(NSString *)extension {
    _playlistType = kPlaylistNone;
    if(_playlistParser) {
        [_playlistParser release];
        _playlistParser = nil;
    }
    
    if(extension == nil) {
        return;
    }
    
    if([extension compare:@"m3u" options:NSCaseInsensitiveSearch] == NSOrderedSame) {
        _playlistType = kPlaylistM3U;
        _playlistParser = [[self playlistParserForType:kPlaylistM3U] retain];
    } else if([extension compare:@"pls" options:NSCaseInsensitiveSearch] == NSOrderedSame) {
        _playlistType = kPlaylistPLS;
        _playlistParser = [[self playlistParserForType:kPlaylistPLS] retain];
    } else if([extension compare:@"xspf" options:NSCaseInsensitiveSearch] == NSOrderedSame) {
        _playlistType = kPlaylistXSPF;
        _playlistParser = [[self playlistParserForType:kPlaylistXSPF] retain];
    } else if([extension compare:@"asx" options:NSCaseInsensitiveSearch] == NSOrderedSame) {
        _playlistType = kPlaylistASX;
        _playlistParser = [[self playlistParserForType:kPlaylistASX] retain];
    }
}

- (BOOL)supportedContentType:(NSString *)contentType {
    if([contentType rangeOfString:@"application/ogg" options:NSCaseInsensitiveSearch].location != NSNotFound ||
       [contentType rangeOfString:@"audio/ogg" options:NSCaseInsensitiveSearch].location != NSNotFound ||
       [contentType rangeOfString:@"video/x-flv" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return NO;
    }
    
    return YES;
}

- (void)cleanup {
    [self release];
}

- (void)copyEncoderCookieToFile {
	Boolean writable;
    UInt32 cookieSize;
    OSStatus err = AudioFileStreamGetPropertyInfo(_playerState.mStreamID, kAudioFileStreamProperty_MagicCookieData, &cookieSize, &writable);
    if(err == noErr && cookieSize > 0) {
        // get the magic cookie data
        void *cookieData = calloc(1, cookieSize);
        err = AudioFileStreamGetProperty(_playerState.mStreamID, kAudioFileStreamProperty_MagicCookieData, &cookieSize, cookieData);
        if(err == noErr) {
            // now set the magic cookie on the output file
            UInt32 willEatTheCookie = false;
            OSStatus err = AudioFileGetPropertyInfo(_recordFile, kAudioFilePropertyMagicCookieData, NULL, &willEatTheCookie);
            if(err == noErr && willEatTheCookie) {
                err = AudioFileSetProperty(_recordFile, kAudioFilePropertyMagicCookieData, cookieSize, cookieData);
                if(err) {
                    DLog(@"Warning: set kAudioFilePropertyMargicCookieData");
                }
            }
        }
        
        free(cookieData);
    }
}

- (void)stopRecordingWithError:(NSError *)error {
    if(!_playerState.mRecording) {
        DLog(@"Warning: There's no active recording session.");
        return;
    }
    
    _playerState.mRecording = NO;
    [self copyEncoderCookieToFile];
    AudioFileClose(_recordFile);
    if(_delegate && [_delegate respondsToSelector:@selector(radio:recordingFailedWithError:)]) {
        [_delegate radio:self recordingFailedWithError:error];
    }
}

- (void)startBufferTimerWithTimeout:(NSInteger)timeout {
    [self stopBufferTimer];
    
    DLog(@"Starting buffer timer with timeout: %ld", (long)timeout);
    _bufferTimer = [[NSTimer scheduledTimerWithTimeInterval:timeout 
                                                     target:self 
                                                   selector:@selector(onBufferTimerFired:) 
                                                   userInfo:nil 
                                                    repeats:NO] retain];
}

- (void)startReconnectTimerWithTimeout:(NSInteger)timeout {
    [self stopReconnectTimer];
    
    DLog(@"Starting reconnect timer with timeout: %ld", (long)timeout);
    _reconnectTimer = [[NSTimer scheduledTimerWithTimeInterval:timeout
                                                        target:self
                                                      selector:@selector(onReconnectTimerFired:)
                                                      userInfo:nil
                                                       repeats:NO] retain];
}

- (void)stopBufferTimer {
    if(_bufferTimer) {
        DLog(@"Stopping buffer timer");
        [_bufferTimer invalidate];
        [_bufferTimer release];
        _bufferTimer = nil;
    }
}

- (void)stopReconnectTimer {
    if(_reconnectTimer) {
        DLog(@"Stopping reconnect timer");
        [_reconnectTimer invalidate];
        [_reconnectTimer release];
        _reconnectTimer = nil;
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
                    [self pause];
                    [self play];
                }
            }
        }
    }
}

#pragma mark -
#pragma mark NSURLConnectionDelegate Methods
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    if([httpResponse respondsToSelector:@selector(statusCode)]) {
        NSInteger statusCode = [httpResponse statusCode];
        if(statusCode >= 400) {
            _radioError = kRadioErrorNetworkError;
            [self setState:kRadioStateError];
            
            [connection cancel];
            return;
        }
    }
    
    if(_httpState == kHTTPStateAudioStreaming) {
        if(_streamHeaders) {
            [_streamHeaders release];
            _streamHeaders = nil;
        }
        
        _streamHeaders = [[httpResponse caseInsensitiveHTTPHeaders] retain];
        NSString *contentType = [_streamHeaders objectForKey:@"content-type"];
        if(contentType) {
            [_contentType release];
            _contentType = [contentType retain];
            
            // if we detect the content type of a playlist we switch back to playlist parsing mode
            YLPlaylistType playlistType = [self playlistTypeForContentType:_contentType];
            if(playlistType != kPlaylistNone) {
                _httpState = kHTTPStatePlaylistParsing;
                _playlistType = playlistType;
                if(_playlistParser) {
                    [_playlistParser release];
                    _playlistParser = nil;
                }
                _playlistParser = [[self playlistParserForType:playlistType] retain];
                
                if(_playlistData == nil) {
                    _playlistData = [[NSMutableData alloc] init];
                }
                [_playlistData setLength:0];
                
                return;
            }
            
            if(![self supportedContentType:_contentType]) {
                _radioError = kRadioErrorUnsupportedStreamFormat;
                [self setState:kRadioStateError];
                
                [connection cancel];
                return;
            }
        }
        
        NSString *bitrate = [_streamHeaders objectForKey:@"icy-br"];
        if(bitrate) {
            _bitrateInBytes = ([bitrate intValue] * 1000) / 8;
        }
        
        NSString *metaInt = [_streamHeaders objectForKey:@"icy-metaint"];
        if(metaInt) {
            _metadataInterval = [metaInt intValue];
            _icyHeadersParsed = YES;
        }
        
        BOOL radioMetadataReady = NO;
        NSString *radioName = [_streamHeaders objectForKey:@"icy-name"];
        if(radioName) {
            if(_radioName) {
                [_radioName release];
                _radioName = nil;
            }
            _radioName = [radioName retain];
            radioMetadataReady = YES;
        }
        
        NSString *radioGenre = [_streamHeaders objectForKey:@"icy-genre"];
        if(radioGenre) {
            if(_radioGenre) {
                [_radioGenre release];
                _radioGenre = nil;
            }
            _radioGenre = [radioGenre retain];
            radioMetadataReady = YES;
        }
        
        NSString *radioUrl = [_streamHeaders objectForKey:@"icy-url"];
        if(radioUrl) {
            if(_radioUrl) {
                [_radioUrl release];
                _radioUrl = nil;
            }
            _radioUrl = [radioUrl retain];
            radioMetadataReady = YES;
        }
        
        if(radioMetadataReady) {
            if(_delegate && [_delegate respondsToSelector:@selector(radioMetadataReady:)]) {
                dispatch_async(dispatch_get_main_queue(), ^(void) {
                    [_delegate radioMetadataReady:self];
                });
            }
        }
        
        _playerState.mBuffering = YES;
        [self setState:kRadioStateBuffering];
        
        OSStatus err = AudioFileStreamOpen(self, PropertyListenerProc, PacketsProc, [self fileTypeHint], &_playerState.mStreamID);
        if(err != noErr) {
            DLog(@"Error: AudioFileStreamOpen %d", (int)err);
            _radioError = kRadioErrorFileStreamOpen;
            [self setState:kRadioStateError];
            return;
        }
        
        [_metaData setLength:0];
        [_audioData setLength:0];
    } else {
        [_playlistData setLength:0];
    }
}

- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response {
    if(response) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if([httpResponse respondsToSelector:@selector(statusCode)]) {
            NSInteger statusCode = [httpResponse statusCode];
            
            // handle HTTP redirect response codes
            if(statusCode == 301 || statusCode == 302 || statusCode == 303 || statusCode == 307) {
                NSDictionary *responseHeaders = [httpResponse caseInsensitiveHTTPHeaders];
                NSString *location = [responseHeaders objectForKey:@"location"];
                if(location) {
                    NSURL *newUrl = [NSURL URLWithString:location];
                    if(newUrl) {
                        [connection cancel];
                        
                        [_url release];
                        _url = [newUrl retain];
                        
                        [self setupPlaylistParserForExtension:[newUrl pathExtension]];
                        if(_playlistType == kPlaylistNone) {
                            // HTTP redirect to direct stream URL
                            _httpState = kHTTPStateAudioStreaming;
                            [self requestAudioStream];
                        } else {
                            // HTTP redirect to another playlist URL
                            _httpState = kHTTPStatePlaylistParsing;
                            [self requestPlaylist];
                        }
                        
                        return nil;
                    }
                }
                
                _radioError = kRadioErrorNetworkError;
                [self setState:kRadioStateError];
                
                [connection cancel];
            }
        }
    }
    
    return request;
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    if(_httpState == kHTTPStateAudioStreaming) {
        [self parseAudioData:data];
    } else {
        [_playlistData appendData:data];
    }
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    if(_httpState == kHTTPStateAudioStreaming) {
        if(_playerState.mPlaying) {
            // check if internet is reachable, if so the radio host could be down
            // in which case there's no need to reconnect.
            if(_reachability && [_reachability isReachable]) {
                [_reachability stopNotifier];
                [_reachability release];
                _reachability = nil;
                
                _radioError = kRadioErrorHostNotReachable;
                [self setState:kRadioStateError];
            } else {
                _connectionError = YES;
                [self pause];
            }
        }
    } else {
        _radioError = kRadioErrorNetworkError;
        [self setState:kRadioStateError];
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    if(_httpState == kHTTPStateAudioStreaming) {
        _connectionFinished = YES;
        if(_playerState.mPlaying) {
            if(_playerState.mBuffering && !_playerState.mStarted) {
                // very short audio clip, the audio queue buffers are still empty and need to be filled
                // so that the audio queue can be started.
                // Parse remaining audio data
                if([_audioData length] > 0) {
                    AudioFileStreamParseBytes(_playerState.mStreamID, (UInt32)[_audioData length], [_audioData bytes], 0);
                    [_audioData setLength:0];
                }
                
                // Only start playback if the stream is ready to produce packets. We can check this by making sure
                // that the audioqueue buffers are allocated.
                if(_playerState.mQueueBuffers[0]->mQueueBuffer == NULL) {
                    [self pause];
                } else {
                    _playerState.mBuffering = NO;
                    [self primeQueueBuffers];
                    [self startQueue];
                }
            } else if(_playerState.mBuffering || _buffersInUse == 0) {
                [self pause];
            } else {
                // Parse remaining audio data
                if([_audioData length] > 0) {
                    AudioFileStreamParseBytes(_playerState.mStreamID, (UInt32)[_audioData length], [_audioData bytes], 0);
                    [_audioData setLength:0];
                }
            }
        }
    } else {
        NSString *streamUrl = [_playlistParser parseStreamUrl:_playlistData];
        NSURL *streamURL = [NSURL URLWithString:streamUrl];
        if(streamURL) {
            [_url release];
            _url = [streamURL retain];
            
            if(_playlistType == kPlaylistASX) {
                if(![[_url scheme] isEqualToString:@"mms"] &&
                   ![[_url scheme] isEqualToString:@"mmsh"]) {
                    _radioError = kRadioErrorPlaylistParsing;
                    [self setState:kRadioStateError];
                } else {
                    _radioError = kRadioErrorPlaylistMMSStreamDetected;
                    [self setState:kRadioStateError];
                }
                
                return;
            }
            
            _httpState = kHTTPStateAudioStreaming;
            [self requestAudioStream];
        } else {
            _radioError = kRadioErrorPlaylistParsing;
            [self setState:kRadioStateError];
        }
    }
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)cachedResponse {
    return nil;
}

@end
