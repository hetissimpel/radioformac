//
//  RadioPrefsStationsViewController.h
//  Radio
//
//  Created by Damien Glancy on 04/08/2012.
//  Copyright (c) 2012 Het is Simpel. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "RHPreferences.h"
#import "RadioStationTableView.h"

@interface RadioPrefsStationsViewController : NSViewController<RHPreferencesViewControllerProtocol, NSTableViewDelegate, NSTableViewDataSource, RadioStationTableViewKeyboardDelegate>

@property(weak) IBOutlet NSManagedObjectContext *managedObjectContext;
@property(weak) IBOutlet NSArrayController *channelsArrayController;
@property(weak) IBOutlet RadioStationTableView *channelsTableView;

@property(weak) IBOutlet NSSearchField *searchField;
@property(strong, nonatomic) NSPredicate *predicate;

@property(weak) IBOutlet NSButton *playButton;
@property(weak) IBOutlet NSButtonCell *deleteButton;
@property(weak) IBOutlet NSButton *editButton;
@property(weak) IBOutlet NSButton *favButton;

- (IBAction)addToFavsButtonPressed:(id)sender;
- (IBAction)addNewStationButtonPressed:(id)sender;
- (IBAction)playButtonPressed:(id)sender;
- (IBAction)deleteButtonPressed:(id)sender;
- (IBAction)editButtonPressed:(id)sender;

// details sheet
@property(strong, nonatomic) Channel *detailChannel;
@property(strong, nonatomic) IBOutlet NSWindow *detailSheet;
@property(weak) IBOutlet NSTextField *detailSheetURLTextField;
@property(weak) IBOutlet NSTextField *detailSheetStationNameTextField;
@property (weak) IBOutlet NSTextField *detailSheetStationDescriptionTextField;
@property (weak) IBOutlet NSTextField *detailSheetStationCountryTextField;

- (IBAction)detailSheetOkButtonPressed:(id)sender;
- (IBAction)detailSheetCancelButtonPressed:(id)sender;

@end