//
//  RadioPrefsRecordingViewController.m
//  Radio
//
//  Created by Damien Glancy on 06/08/2012.
//  Copyright (c) 2012 Het is Simpel. All rights reserved.
//

#import "RadioPrefsRecordingViewController.h"

@implementation RadioPrefsRecordingViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        RadioAppDelegate *app = GetAppDelegate();
        _managedObjectContext = app.managedObjectContext;
    }

    return self;
}

- (void)awakeFromNib {
    NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"startDate" ascending:YES];
    _recordingTableView.sortDescriptors = @[sortDescriptor];
}

#pragma mark - RHPreferencesViewControllerProtocol

- (NSString *)identifier {
    return NSStringFromClass(self.class);
}

- (NSImage *)toolbarItemImage {
    return [NSImage imageNamed:@"settings_recordings"];
}

- (NSString *)toolbarItemLabel {
    return NSLocalizedString(@"Recordings", @"Recordings Toolbar Item Label");
}

- (NSView *)initialKeyView {
    return nil;
}

- (IBAction)playButtonPressed:(id)sender {
    NSArray *selectedObjects = _recordingArrayController.selectedObjects;
    if (selectedObjects.count == 0) {
        return;
    }

    RadioAppDelegate *app = GetAppDelegate();
    [app.radioController stop];

    Recording *recording = (Recording *)selectedObjects[0];
    NSURL *audioURL = [NSURL URLWithString:recording.audio];
    [[NSWorkspace sharedWorkspace] openFile:audioURL.path withApplication:@"QuickTime Player"];
}

- (IBAction)doubleClickOnRecordingRow:(id)sender {
    [self playButtonPressed:sender];
}

- (IBAction)deleteButtonPressed:(id)sender {
    NSLog(@"Delete button pressed");

    NSAlert *alert = [[NSAlert alloc] init];
    [alert addButtonWithTitle:NSLocalizedString(@"OK", nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];
    [alert setMessageText:NSLocalizedString(@"Delete Recording", nil)];
    [alert setInformativeText:NSLocalizedString(@"Are you sure you wish to delete this recording?", nil)];
    [alert setAlertStyle:NSWarningAlertStyle];

    [alert beginSheetModalForWindow:[self.view window] modalDelegate:self didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:) contextInfo:nil];
}

- (IBAction)showInFinderButtonPressed:(id)sender {
    NSLog(@"Show in finder button pressed");

    RadioAppDelegate *app = GetAppDelegate();
    [[NSWorkspace sharedWorkspace] openFile:app.musicURL.path withApplication:@"Finder"];
}

#pragma mark - Action Sheets Callback

- (void)alertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
    if (returnCode == NSAlertFirstButtonReturn) {
        NSArray *selectedObjects = _recordingArrayController.selectedObjects;
        if (selectedObjects.count == 0) {
            return;
        }

        Recording *selectedRecording = selectedObjects[0];
        
        NSURL *file = [NSURL URLWithString:selectedRecording.audio];
        [[NSFileManager defaultManager] removeItemAtURL:file error:nil];

        [_managedObjectContext deleteObject:selectedRecording];
        [_managedObjectContext save:nil];
    }
}

@end