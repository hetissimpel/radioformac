//
//  PrefesGeneralViewController.h
//  Radio
//
//  Created by Damien Glancy on 04/08/2012.
//  Copyright (c) 2012 Het is Simpel. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "RHPreferences.h"
#import "StartAtLoginController.h"

@interface RadioPrefsGeneralViewController : NSViewController<RHPreferencesViewControllerProtocol>

@property(strong) StartAtLoginController *startAtLoginController;

@property(weak) IBOutlet NSButton *startOnLoginButton;
@property(weak) IBOutlet NSButton *notificationCentreEachTrackButton;
@property (weak) IBOutlet NSTextField *copyrightTextField;


- (IBAction)startOnLoginButtonClicked:(id)sender;

- (IBAction)notificationCentreEachTrackButtonClicked:(id)sender;

- (IBAction)resetCloudButtonPressed:(id)sender;

- (IBAction)damoButtonPressed:(id)sender;
- (IBAction)jeroenButtonPressed:(id)sender;
- (IBAction)iosButtonPressed:(id)sender;

@end