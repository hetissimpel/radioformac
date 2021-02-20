//
//  RadioPrefsRecordingViewController.h
//  Radio
//
//  Created by Damien Glancy on 06/08/2012.
//  Copyright (c) 2012 Het is Simpel. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "RHPreferences.h"

@interface RadioPrefsRecordingViewController : NSViewController<RHPreferencesViewControllerProtocol, NSTableViewDelegate>

@property(weak) IBOutlet NSManagedObjectContext *managedObjectContext;
@property(strong) IBOutlet NSArrayController *recordingArrayController;
@property(weak) IBOutlet NSTableView *recordingTableView;
@property(weak) IBOutlet NSButton *playButton;

- (IBAction)playButtonPressed:(id)sender;

- (IBAction)deleteButtonPressed:(id)sender;

- (IBAction)showInFinderButtonPressed:(id)sender;

@end