//
//  PrefesGeneralViewController.m
//  Radio
//
//  Created by Damien Glancy on 04/08/2012.
//  Copyright (c) 2012 Het is Simpel. All rights reserved.
//

#import "RadioPrefsGeneralViewController.h"
#import "RadioCloudManager.h"

@interface RadioPrefsGeneralViewController ()

@property (nonatomic, strong) NSAlert *resetAlert;
@property (nonatomic, strong) NSAlert *startOnLoginAlert;

@end

@implementation RadioPrefsGeneralViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {

    }

    return self;
}

- (void)awakeFromNib {
    _startAtLoginController = [[StartAtLoginController alloc] initWithIdentifier:kHelperBundle];

    BOOL startOnLogin = _startAtLoginController.startAtLogin;
    
    if (startOnLogin) {
        NSLog(@"[RADIO] Start at login: yes");
        [_startOnLoginButton setState:NSOnState];
    } else {
        NSLog(@"[RADIO] Start at login: no");
        [_startOnLoginButton setState:NSOffState];
    }

    if (![[NSUserDefaults standardUserDefaults] boolForKey:kUserDefaultsUserDontNotifyOfTrackChange]) {
        [_notificationCentreEachTrackButton setState:NSOnState];
    } else {
        [_notificationCentreEachTrackButton setState:NSOffState];
    }

    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *version = [mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *build = [mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"];

    NSString *message = [NSString stringWithFormat:@""@"Copyright 2014\nV%@ Build #%@\nCreated in Dublin\nDesigned in Rotterdam", version, build];
    self.copyrightTextField.stringValue = message;
}

#pragma mark - RHPreferencesViewControllerProtocol

- (NSString *)identifier {
    return NSStringFromClass(self.class);
}

- (NSImage *)toolbarItemImage {
    return [NSImage imageNamed:@"settings_general"];
}

- (NSString *)toolbarItemLabel {
    return NSLocalizedString(@"General", @"GeneralToolbarItemLabel");
}

- (NSView *)initialKeyView {
    return nil;
}

#pragma mark - Action

- (IBAction)startOnLoginButtonClicked:(id)sender {
    BOOL startOnLogin = _startAtLoginController.startAtLogin;

    if (startOnLogin) {
        _startAtLoginController.startAtLogin = NO;
        
        [_startOnLoginButton setState:NSOffState];
    } else {
        _startOnLoginAlert = [[NSAlert alloc] init];
        [_startOnLoginAlert addButtonWithTitle:NSLocalizedString(@"OK", nil)];
        [_startOnLoginAlert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];
        [_startOnLoginAlert setMessageText:NSLocalizedString(@"Are you sure you want to launch Radio on login?", nil)];
        [_startOnLoginAlert setInformativeText:NSLocalizedString(@"It uses minimal resources and sits out of the way on your menubar.", nil)];
        [_startOnLoginAlert setAlertStyle:NSWarningAlertStyle];

        [_startOnLoginAlert beginSheetModalForWindow:[self.view window] modalDelegate:self didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:) contextInfo:nil];
    }
}

- (IBAction)notificationCentreEachTrackButtonClicked:(id)sender {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kUserDefaultsUserDontNotifyOfTrackChange]) {
        [_notificationCentreEachTrackButton setState:NSOnState];
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kUserDefaultsUserDontNotifyOfTrackChange];
    } else {
        [_notificationCentreEachTrackButton setState:NSOffState];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kUserDefaultsUserDontNotifyOfTrackChange];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (IBAction)resetCloudButtonPressed:(id)sender {
    NSLog(@"Reset Cloud Button Pressed");

    _resetAlert = [[NSAlert alloc] init];
    [_resetAlert addButtonWithTitle:NSLocalizedString(@"OK", nil)];
    [_resetAlert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];
    [_resetAlert setMessageText:NSLocalizedString(@"Reset Radio's iCloud storage?", nil)];
    [_resetAlert setInformativeText:NSLocalizedString(@"If iCloud stops syncing your custom stations, resetting Radio's iCloud storage can assist in resolving the issue. \n\nAre you sure you wish to reset Radio's iCloud storage?", nil)];
    [_resetAlert setAlertStyle:NSWarningAlertStyle];

    [_resetAlert beginSheetModalForWindow:[self.view window] modalDelegate:self didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:) contextInfo:nil];
}

- (IBAction)damoButtonPressed:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://twitter.com/dglancy"]];
}

- (IBAction)jeroenButtonPressed:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://twitter.com/JeroenHermkens"]];
}

- (IBAction)iosButtonPressed:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://search.itunes.apple.com/WebObjects/MZContentLink.woa/wa/link?path=apps%2fhetissimpel"]];
}

#pragma mark - Action Sheets Callback

- (void)alertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
    if (alert == _startOnLoginAlert) {
        if (returnCode == NSAlertFirstButtonReturn) {
            _startAtLoginController.startAtLogin = YES;
        } else {
            BOOL startOnLogin = _startAtLoginController.startAtLogin;
            if (startOnLogin) {
                [_startOnLoginButton setState:NSOnState];
            } else {
                [_startOnLoginButton setState:NSOffState];
            }
        }
    } else if (alert == _resetAlert) {
        if (returnCode == NSAlertFirstButtonReturn) {
            NSLog(@"Requesting iCloud to reset");
            [[RadioCloudManager cloudManager] reset];
        }
    }
}

@end