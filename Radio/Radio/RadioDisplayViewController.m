//
//  RadioDisplayViewController.m
//  Radio
//
//  Created by Damien Glancy on 03/08/2012.
//  Copyright (c) 2012 Het is Simpel. All rights reserved.
//

@implementation RadioDisplayViewController

- (void)awakeFromNib {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(radioTitleInfoChanged:) name:kNotificationTrackInfoChanged object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioPlayerStateChange:) name:kNotificationRadioStateChanged object:nil];

    _stationTextField.attributedStringValue = [RadioUtils convertToAttributedString:NSLocalizedString(@"No station", nil)];
    _trackTitleTextField.attributedStringValue = [RadioUtils convertToAttributedString:kBlankString];

    _recordControlButton.mouseOverImage = [NSImage imageNamed:@"controls_record_inactive_over"];
    _playControlButton.mouseOverImage = [NSImage imageNamed:@"controls_play_inactive_over"];
    _favControlButton.mouseOverImage = [NSImage imageNamed:@"controls_fav_inactive_over"];

    RadioAppDelegate *app = GetAppDelegate();
    app.radioDisplayViewController = self;
}

- (void)radioTitleInfoChanged:(NSNotification *)notification {
    if (notification.object) {
        RadioController *radioController = (RadioController *)notification.object;
        _stationTextField.attributedStringValue = [RadioUtils convertToAttributedString:radioController.radio.radioName];
        _trackTitleTextField.attributedStringValue = [RadioUtils convertToAttributedString:radioController.radio.radioTitle];

        if (_stationTextField.attributedStringValue.length == 0) {
            _stationTextField.attributedStringValue = [RadioUtils convertToAttributedString:radioController.selectedChannel.name];
        }

        if (_trackTitleTextField.attributedStringValue.length == 0) {
            _trackTitleTextField.attributedStringValue = [RadioUtils convertToAttributedString:kBlankString];
        }
    }
}

- (void)audioPlayerStateChange:(NSNotification *)notification {
    RadioAppDelegate *appDelegate = GetAppDelegate();
    NSString *status;

    if (notification.object) {
        YLRadioState state = (YLRadioState)[(NSNumber *)notification.object intValue];
        if (state == kRadioStateConnecting) {
            status = NSLocalizedString(@"connecting", nil);
            [appDelegate startMenuAnimation];
        } else if (state == kRadioStateBuffering) {
            status = NSLocalizedString(@"buffering", nil);
            [appDelegate startMenuAnimation];
        } else if (state == kRadioStatePlaying) {
            [appDelegate stopMenuAnimation];
            if ([_trackTitleTextField.stringValue isEqualToString:NSLocalizedString(@"buffering", nil)]) {
                status = NSLocalizedString(@"playing", nil);
            }
        } else if (state == kRadioStateStopped) {
            [appDelegate stopMenuAnimation];
            status = NSLocalizedString(@"stopped", nil);
        } else if (state == kRadioStateError) {
            [appDelegate stopMenuAnimation];
            status = NSLocalizedString(@"error", nil);

            YLRadioError error = [appDelegate.radioController.radio radioError];

            if (error == kRadioErrorAudioQueueBufferCreate) {
                NSLog(@"Audio buffers could not be created.");
                status = NSLocalizedString(@"error playing station (#1).", nil);
            } else if (error == kRadioErrorAudioQueueCreate) {
                NSLog(@"Audio queue could not be created.");
                status = NSLocalizedString(@"error playing station (#2).", nil);
            } else if (error == kRadioErrorAudioQueueEnqueue) {
                NSLog(@"Audio queue enqueue failed.");
                status = NSLocalizedString(@"error playing station (#3).", nil);
            } else if (error == kRadioErrorAudioQueueStart) {
                NSLog(@"Audio queue could not be started.");
                status = NSLocalizedString(@"error playing station (#4).", nil);
            } else if (error == kRadioErrorFileStreamGetProperty) {
                NSLog(@"File stream get property failed.");
                status = NSLocalizedString(@"error playing station (#5).", nil);
            } else if (error == kRadioErrorFileStreamOpen) {
                NSLog(@"File stream could not be opened.");
                status = NSLocalizedString(@"error playing station (#6).", nil);
            } else if (error == kRadioErrorPlaylistParsing) {
                NSLog(@"Playlist could not be parsed.");
                status = NSLocalizedString(@"error playing station (#7).", nil);
            } else if (error == kRadioErrorDecoding) {
                NSLog(@"Audio decoding error.");
                status = NSLocalizedString(@"error playing station (#8).", nil);
            } else if (error == kRadioErrorHostNotReachable) {
                NSLog(@"Radio host not reachable.");
                status = NSLocalizedString(@"error playing station (#9).", nil);
            } else if (error == kRadioErrorNetworkError) {
                NSLog(@"Network connection error.");
                status = NSLocalizedString(@"network connection error.", nil);
            }
        }

        if (status && status.length > 0) {
            _trackTitleTextField.attributedStringValue = [RadioUtils convertToAttributedString:status];
        }
    }

    [self updateRadioControls];
}

- (void)updateRadioControls {
    RadioAppDelegate *app = GetAppDelegate();

    if (!app.radioController.selectedChannel) {
        _recordControlButton.image = [NSImage imageNamed:@"controls_record_inactive"];
        _recordControlButton.mouseOverImage = [NSImage imageNamed:@"controls_record_inactive"];

        _playControlButton.image = _playControlButton.image = [NSImage imageNamed:@"controls_play_inactive"];
        _playControlButton.mouseOverImage = _playControlButton.image = [NSImage imageNamed:@"controls_play_inactive"];

        _favControlButton.image = [NSImage imageNamed:@"controls_fav_inactive"];
        _favControlButton.mouseOverImage = [NSImage imageNamed:@"controls_fav_inactive"];
    } else {
        if (app.radioController.recordActive) {
            _recordControlButton.image = [NSImage imageNamed:@"controls_record_active"];
            _recordControlButton.mouseOverImage = [NSImage imageNamed:@"controls_record_active_over"];
        } else {
            _recordControlButton.image = [NSImage imageNamed:@"controls_record_inactive"];
            _recordControlButton.mouseOverImage = [NSImage imageNamed:@"controls_record_inactive_over"];
        }

        if (app.radioController.playActive) {
            _playControlButton.image = [NSImage imageNamed:@"controls_play_active"];
            _playControlButton.mouseOverImage = [NSImage imageNamed:@"controls_play_active_over"];
        } else {
            _playControlButton.image = [NSImage imageNamed:@"controls_play_inactive"];
            _playControlButton.mouseOverImage = [NSImage imageNamed:@"controls_play_inactive_over"];
        }

        if (app.radioController.favouriteActive) {
            _favControlButton.image = [NSImage imageNamed:@"controls_fav_active"];
            _favControlButton.mouseOverImage = [NSImage imageNamed:@"controls_fav_active_over"];
        } else {
            _favControlButton.image = [NSImage imageNamed:@"controls_fav_inactive"];
            _favControlButton.mouseOverImage = [NSImage imageNamed:@"controls_fav_inactive_over"];
        }
    }
}

- (void)clearDisplay {
    _stationTextField.attributedStringValue = [RadioUtils convertToAttributedString:kBlankString];
    _trackTitleTextField.attributedStringValue = [RadioUtils convertToAttributedString:kBlankString];
}

#pragma mark - Actions

- (IBAction)recordControlButtonPressed:(id)sender {
    NSLog(@"Record button pressed");
    RadioAppDelegate *app = GetAppDelegate();
    [app recordingMenuItemPressed:sender];
}

- (IBAction)playControlButtonPressed:(id)sender {
    NSLog(@"Play button pressed");
    RadioAppDelegate *app = GetAppDelegate();
    if (app.radioController.radio && (app.radioController.radio.isBuffering || app.radioController.radio.isPlaying)) {
        [app stopRequested:nil];
    } else {
        [app playRequested:nil];
    }
}

- (IBAction)favControlButtonPressed:(id)sender {
    NSLog(@"Fav button pressed");
    RadioAppDelegate *app = GetAppDelegate();
    [app favouriteRequested:sender];
}

- (IBAction)volumeSliderMoved:(id)sender {
    [[NSUserDefaults standardUserDefaults] setFloat:_volumeSlider.floatValue forKey:kAudioLevels];
    [[NSUserDefaults standardUserDefaults] synchronize];

    RadioAppDelegate *app = GetAppDelegate();
    if (app.radioController.radio) {
        [app.radioController.radio setVolume:_volumeSlider.floatValue];
    }
}

- (IBAction)muteButtonPressed:(id)sender {
    NSLog(@"Mute button pressed");
    RadioAppDelegate *app = GetAppDelegate();
    app.radioController.muted ^= YES;
    if (app.radioController.muted) {
        NSLog(@"Mute is now ON");
        [app.radioController.radio setVolume:0];
    } else {
        NSLog(@"Mute is now OFF");
        [app.radioController.radio setVolume:_volumeSlider.floatValue];
    }
}

@end