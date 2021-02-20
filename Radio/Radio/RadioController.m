//
//  RadioController
//  Het is Simpel
//
//  Created by dglancy on 04/11/2012.
//  Copyright (c) 2012 Het is Simpel. All rights reserved.
//

@implementation RadioController


- (void)playChannel:(Channel *)channel {
    [self stop];

    if (channel) {
        _selectedChannel = channel;
    }

    NSLog(@"Raw Audio URL is: %@", _selectedChannel.url);

    if ([_selectedChannel.url hasPrefix:@"mms"]) {
        _radio = [[YLMMSRadio alloc] initWithURL:[NSURL URLWithString:_selectedChannel.url]];
    } else {
        _radio = [[YLHTTPRadio alloc] initWithURL:[NSURL URLWithString:_selectedChannel.url]];
    }

    if (_radio) {
        [_radio setDelegate:self];
        _radio.channelObjectID = _selectedChannel.objectID;
        float volume = [[NSUserDefaults standardUserDefaults] floatForKey:kAudioLevels];
        [_radio setVolume:volume];
        [_radio play];
    }

    if (_selectedChannel.favourite.boolValue) {
        _favouriteActive = YES;
    } else {
        _favouriteActive = NO;
    }

    _playActive = YES;
}

- (void)startRecording:(void (^)(void))completionBlock {
    if (!_radio.isPlaying) {
        NSLog(@"Radio is not playing, therefore start recording fails.");
        _recordActive = NO;
        return;
    }

    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
    dispatch_async(queue, ^{
        RadioAppDelegate *app = GetAppDelegate();

        NSManagedObjectContext *backgroundContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        backgroundContext.parentContext = app.managedObjectContext;
        backgroundContext.undoManager = nil;

        Recording *recording = (Recording *)[NSEntityDescription insertNewObjectForEntityForName:@"Recording" inManagedObjectContext:backgroundContext];
        recording.startDate = [NSDate date];
        recording.channelName = _selectedChannel.name;

        NSString *extn = @"mp3";
        if ([_radio isKindOfClass:[YLMMSRadio class]]) {
            extn = @"mp4";
        }

        NSDateFormatter *format = [[NSDateFormatter alloc] init];
        [format setDateFormat:@"yyyy-MM-dd HH.mm.ss"];

        NSURL *audioURL = [app.musicURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@ - %@.%@", [format stringFromDate:recording.startDate], recording.channelName, extn]];
        if (audioURL) {
            recording.audio = audioURL.absoluteString;
        }

        [backgroundContext obtainPermanentIDsForObjects:@[recording] error:nil];
        _radio.recordingObjectID = recording.objectID;

        [backgroundContext save:nil];

        dispatch_async(dispatch_get_main_queue(), ^{
            [_radio startRecordingWithDestination:audioURL.path];
            NSLog(@"Recording started");
            if (completionBlock)
                completionBlock();
        });
    });
}

- (void)stopRecording:(void (^)(void))completionBlock {
    if (!_radio.isRecording) {
        if (completionBlock)
            completionBlock();
        return;
    }

    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
    dispatch_async(queue, ^{
        RadioAppDelegate *app = GetAppDelegate();

        NSManagedObjectContext *backgroundContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        backgroundContext.parentContext = app.managedObjectContext;
        backgroundContext.undoManager = nil;

        Recording *recording = (Recording *)[backgroundContext existingObjectWithID:_radio.recordingObjectID error:nil];
        if (recording) {
            recording.endDate = [NSDate date];
            [backgroundContext save:nil];
        }

        app.statusItem.image = [NSImage imageNamed:@"menubar_icon_default"];
        app.statusItem.alternateImage = [NSImage imageNamed:@"menubar_icon_rollover"];

        [_radio stopRecording];
        _recordActive = NO;

        dispatch_async(dispatch_get_main_queue(), ^{
            [app recalculateMenuItems];
            NSLog(@"Recording ended");
            if (completionBlock)
                completionBlock();
        });
    });
}

- (void)stop {
    [self stopRecording:nil];

    [_radio shutdown];

    _recordActive = NO;
    _playActive = NO;
    _radio = nil;
}

#pragma mark - Radio Callbacks

- (void)radio:(YLRadio *)radio didStartRecordingWithDestination:(NSString *)path {
    _recordActive = YES;
    RadioAppDelegate *app = GetAppDelegate();
    app.statusItem.image = [NSImage imageNamed:@"menubar_icon_default_recording"];
    app.statusItem.alternateImage = [NSImage imageNamed:@"menubar_icon_rollover_recording"];
    [app.radioDisplayViewController updateRadioControls];
}

- (void)radio:(YLRadio *)radio didStopRecordingWithDestination:(NSString *)path {
    _recordActive = NO;
}

- (void)radio:(YLRadio *)radio recordingFailedWithError:(NSError *)error {
    _recordActive = NO;
}

- (void)radioStateChanged:(YLRadio *)radio {
    YLRadioState state = [radio radioState];
    
    if(state == kRadioStateError)  {
        YLRadioError error = _radio.radioError;
        if (error == kRadioErrorPlaylistMMSStreamDetected) {
            // Special handling for ASX playlist which is parsed by YLHTTPRadio. We need to switch over to
            // YLMMSRadio if the parsed URL is a valid mms URL.
            NSURL *url = [_radio.url copy];
            [_radio shutdown];
            
            _radio = [[YLMMSRadio alloc] initWithURL:url];
            if (_radio) {
                [_radio setDelegate:self];
                [_radio play];
            }
        }
        
        return;
    }

    // determine if radio has stopped and set status correctly.
    if (state == kRadioStateStopped || state == kRadioStateError) {
        _recordActive = NO;
        _playActive = NO;
    } else if (state == kRadioStatePlaying) {
        _playActive = YES;
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationRadioStateChanged object:[NSNumber numberWithInt:state]];
}

- (void)radioMetadataReady:(YLRadio *)radio {
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationTrackInfoChanged object:self];

    NSString *radioName = [radio radioName];
    NSString *radioGenre = [radio radioGenre];

    if (radioName && radioName.length > 0 && _selectedChannel.name && _selectedChannel.name.length <= 0) {
        DLog(@"Radio name: %@", radioName);
        _selectedChannel.name = radioName;
    }

    if (radioGenre && radioGenre.length > 0) {
        DLog(@"Radio genre: %@", radioGenre);
        _selectedChannel.desc = radioGenre;
    }
}

- (void)radioTitleChanged:(YLRadio *)radio {
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationTrackInfoChanged object:self];
    if (![[NSUserDefaults standardUserDefaults] boolForKey:kUserDefaultsUserDontNotifyOfTrackChange]) {
        NSString *radioTitle = radio.radioTitle;
        NSString *radioName = radio.radioName;

        if (radioTitle.length == 0 && radioName.length == 0) {
            RadioAppDelegate *app = GetAppDelegate();
            Channel *channel = (Channel *)[app.managedObjectContext existingObjectWithID:radio.channelObjectID error:nil];
            if (channel) {
                radioTitle = channel.name;
            }
        }

        [RadioUtils sendNotificationWithTitle:@"Radio" subtitle:radioTitle informativeText:radioName ? [NSString stringWithFormat:@"On \"%@\"", radioName]:nil];
    }
}

@end