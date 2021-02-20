//
//  RadioPrefsStationsViewController.m
//  Radio
//
//  Created by Damien Glancy on 04/08/2012.
//  Copyright (c) 2012 Het is Simpel. All rights reserved.
//

#import "RadioPrefsStationsViewController.h"
#import "RadioCrowdSourcingManager.h"
#import "RadioCloudManager.h"

@implementation RadioPrefsStationsViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        RadioAppDelegate *app = GetAppDelegate();
        self.managedObjectContext = app.managedObjectContext;
        self.predicate = [NSPredicate predicateWithFormat:@"(name contains[cd] $searchString) or (desc contains[cd] $searchString) or (keywords contains[cd] $searchString) or (city contains[cd] $searchString) or (country contains[cd] $searchString)"];
    }

    return self;
}

- (void)awakeFromNib {
    self.channelsTableView.keyboardDelegate = self;
    NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"country" ascending:YES];
    self.channelsTableView.sortDescriptors = @[sortDescriptor];
}

- (void)viewWillAppear {
    [self tableViewSelectionDidChange:nil]; //HACK
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSArray *selectedItems = self.channelsArrayController.selectedObjects;
    if (selectedItems && selectedItems.count > 0) {
        Channel *selectedChannel = (Channel *)selectedItems[0];
        if ([selectedChannel.guid hasPrefix:@"USR"]) {
            [self.deleteButton setEnabled:YES];
            [self.editButton setEnabled:YES];
        } else {
            [self.deleteButton setEnabled:NO];
            [self.editButton setEnabled:NO];
        }
        if (selectedChannel.favourite.boolValue) {
            [self.favButton setEnabled:NO];
        } else {
            [self.favButton setEnabled:YES];
        }
    }
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if ([tableColumn.identifier isEqualToString:@"PrefsStationsImage"]) {
        Channel *channel = self.channelsArrayController.arrangedObjects[(NSUInteger)row];
        if (channel.favourite.boolValue) {
            return [NSImage imageNamed:@"favself.selected"];
        }
    }

    return [NSImage imageNamed:@"favself.unselected"];
}

- (BOOL)tableView:(NSTableView *)tableView shouldEditTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    return NO;
}

- (IBAction)updateFilterAction:(id)sender {
    NSPredicate *p;
    
    NSString *searchString = self.searchField.stringValue;
    if (![searchString isEqualToString:kBlankString]) {
        NSMutableDictionary *bindVariables = [[NSMutableDictionary alloc] init];
        [bindVariables setObject:searchString forKey:@"searchString"];
        p = [self.predicate predicateWithSubstitutionVariables:bindVariables];
    }
    
    self.channelsArrayController.filterPredicate = p;
}

//** WORK IN PROGRESS
//- (IBAction)updateFilterAction:(id)sender {
//    NSManagedObjectContext *backgroundContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
//    backgroundContext.parentContext = self.managedObjectContext;
//    backgroundContext.undoManager = nil;
//    
//    [backgroundContext performBlock:^{
//        NSPredicate *p;
//        
//        NSString *searchString = self.searchField.stringValue;
//        if (![searchString isEqualToString:kBlankString]) {
//            NSMutableDictionary *bindVariables = [[NSMutableDictionary alloc] init];
//            [bindVariables setObject:searchString forKey:@"searchString"];
//            p = [self.predicate predicateWithSubstitutionVariables:bindVariables];
//        }
//        
//        NSFetchRequest *request = [[NSFetchRequest alloc] init];
//        request.entity = [NSEntityDescription entityForName:@"Channel" inManagedObjectContext:backgroundContext];
//        request.predicate = p;
//        
//        NSArray *results = [backgroundContext executeFetchRequest:request error:nil];
//        NSMutableArray *resultsObjectIDs = [[NSMutableArray alloc] initWithCapacity:results.count];
//        for (NSManagedObject *object in results) {
//            [resultsObjectIDs addObject:object.objectID];
//        }
//
//        [self.managedObjectContext performBlock:^{
//            NSMutableArray *array = [[NSMutableArray alloc] initWithCapacity:resultsObjectIDs.count];
//            for (NSManagedObjectID *objectID in resultsObjectIDs) {
//                [array addObject:[self.managedObjectContext objectWithID:objectID]];
//            }
//            
//            self.channelsArrayController.content = array;
//        }];
//    }];
//}

#pragma mark - RHPreferencesViewControllerProtocol

- (NSString *)identifier {
    return NSStringFromClass(self.class);
}

- (NSImage *)toolbarItemImage {
    return [NSImage imageNamed:@"settings_stations"];
}

- (NSString *)toolbarItemLabel {
    return NSLocalizedString(@"Stations", @"StationsToolbarItemLabel");
}

- (NSView *)initialKeyView {
    return nil;
}

#pragma mark - Actions

- (IBAction)addToFavsButtonPressed:(id)sender {
    NSArray *channels = self.channelsArrayController.selectedObjects;

    RadioAppDelegate *app = GetAppDelegate();
    for (Channel *channel in channels) {
        channel.favourite = @YES;
        [app.cloudManager favouriteChannelInCloud:channel];
    }

    NSError *error;
    [self.managedObjectContext save:&error];
    
    [self.channelsTableView reloadData];
}

- (IBAction)addNewStationButtonPressed:(id)sender {
    if (!self.detailSheet) {
        [[NSBundle mainBundle] loadNibNamed:@"RadioPrefsStationDetailSheet" owner:self topLevelObjects:nil];
    }

    self.detailChannel = nil;
    self.detailSheetURLTextField.stringValue = kBlankString;
    self.detailSheetStationNameTextField.stringValue = kBlankString;
    [self.detailSheetURLTextField becomeFirstResponder];

    [NSApp beginSheet:self.detailSheet modalForWindow:self.view.window modalDelegate:self didEndSelector:@selector(didEndSheet:returnCode:contextInfo:) contextInfo:nil];
}

- (IBAction)doubleClickOnStationRow:(id)sender {
    [self playButtonPressed:sender];
}

- (void)didEndSheet:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
    [sheet orderOut:self];
}

- (IBAction)detailSheetOkButtonPressed:(id)sender {
    if (self.detailSheetStationNameTextField.stringValue.length == 0 || self.detailSheetURLTextField.stringValue.length == 0) {
        return;
    }

    RadioAppDelegate *app = GetAppDelegate();
    BOOL addingNewChannel = NO;

    if (!self.detailChannel) {
        NSLog(@"Adding a new channel");
        self.detailChannel = [NSEntityDescription insertNewObjectForEntityForName:@"Channel" inManagedObjectContext:self.managedObjectContext];
        addingNewChannel = YES;
    }

    self.detailChannel.guid = [NSString stringWithFormat:@"USR-%@", [NSProcessInfo processInfo].globallyUniqueString];
    self.detailChannel.name = self.detailSheetStationNameTextField.stringValue;
    self.detailChannel.desc = [self.detailSheetStationDescriptionTextField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    self.detailChannel.country = [self.detailSheetStationCountryTextField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    NSString *trimmedUrlString = [self.detailSheetURLTextField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    if ([trimmedUrlString hasPrefix:@"http"]) {
        self.detailChannel.url = trimmedUrlString;
    } else if ([trimmedUrlString hasPrefix:@"mms"]) {
        self.detailChannel.url = trimmedUrlString;
    } else {
        NSLog(@"Adding http:// prefix to user supplied URL");
        self.detailChannel.url = [NSString stringWithFormat:@"http://%@", trimmedUrlString];
    }
    
    if (addingNewChannel) {
        self.detailChannel.favourite = @YES;
        [app.cloudManager favouriteChannelInCloud:self.detailChannel];
    }

    [RadioCrowdSourcingManager sendNewStationDetailsToCrowdSourcingServiceWithName:self.detailChannel.name url:self.detailChannel.url];

    [app.cloudManager addChannelToCloud:self.detailChannel];

    NSError *error = nil;
    [self.managedObjectContext save:&error];
    
    if (error) {
        NSLog(@"error: %@", error);
    }

    [NSApp endSheet:self.detailSheet];
}

- (IBAction)detailSheetCancelButtonPressed:(id)sender {
    [NSApp endSheet:self.detailSheet];
}

- (IBAction)playButtonPressed:(id)sender {
    NSLog(@"Play station pressed");

    RadioAppDelegate *app = GetAppDelegate();
    NSArray *channels = self.channelsArrayController.selectedObjects;

    if (channels && channels.count > 0) {
        app.radioController.selectedChannel = channels[0];
        [app playRequested:nil];
    }
}

- (IBAction)deleteButtonPressed:(id)sender {
    NSArray *selectedItems = self.channelsArrayController.selectedObjects;
    if (selectedItems && selectedItems.count > 0) {
        Channel *selectedChannel = (Channel *)selectedItems[0];

        NSAlert *alert = [[NSAlert alloc] init];
        [alert addButtonWithTitle:NSLocalizedString(@"OK", nil)];
        [alert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];
        [alert setMessageText:[NSString stringWithFormat:@"%@ %@?", NSLocalizedString(@"Delete", nil), selectedChannel.name]];
        [alert setInformativeText:NSLocalizedString(@"Are you sure you wish to delete this station?", nil)];
        [alert setAlertStyle:NSWarningAlertStyle];

        [alert beginSheetModalForWindow:[self.view window] modalDelegate:self didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:) contextInfo:nil];
    }
}

- (IBAction)editButtonPressed:(id)sender {
    if (!self.detailSheet) {
        [[NSBundle mainBundle] loadNibNamed:@"RadioPrefsStationDetailSheet" owner:self topLevelObjects:nil];
    }

    self.detailChannel = (Channel *)self.channelsArrayController.selectedObjects[0];

    self.detailSheetURLTextField.stringValue = self.detailChannel.url;
    self.detailSheetStationNameTextField.stringValue = self.detailChannel.name;

    [self.detailSheetURLTextField becomeFirstResponder];

    [NSApp beginSheet:self.detailSheet modalForWindow:self.view.window modalDelegate:self didEndSelector:@selector(didEndSheet:returnCode:contextInfo:) contextInfo:nil];
}

#pragma mark - Action Sheets Callback

- (void)alertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
    if (returnCode == NSAlertFirstButtonReturn) {
        NSArray *selectedItems = self.channelsArrayController.selectedObjects;
        if (selectedItems && selectedItems.count > 0) {
            Channel *selectedChannel = (Channel *)selectedItems[0];

            [self.managedObjectContext deleteObject:selectedChannel];
            RadioAppDelegate *app = GetAppDelegate();
            [app.cloudManager removeChannelFromCloud:selectedChannel];
        }

        [self.managedObjectContext save:nil];

        [self.searchField setStringValue:@""];
        [[[self.searchField cell] cancelButtonCell] performClick:self];
    }
}

#pragma mark - Table View Keyboard Delegate

- (void)enterKeyWasPressed {
    [self playButtonPressed:nil];
}

@end