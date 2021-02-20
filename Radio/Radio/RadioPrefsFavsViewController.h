//
//  RadioPrefsFavsViewController.h
//  Radio
//
//  Created by Damien Glancy on 18/08/2012.
//  Copyright (c) 2012 Het is Simpel. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "RHPreferences.h"

@interface RadioPrefsFavsViewController : NSViewController<RHPreferencesViewControllerProtocol, NSTableViewDelegate, NSTableViewDataSource>

@property(weak) IBOutlet NSManagedObjectContext *managedObjectContext;
@property(weak) IBOutlet NSTableView *stationsTableView;
@property(strong) IBOutlet NSArrayController *channelsArrayController;

- (IBAction)removeFavStationButtonPressed:(id)sender;
- (IBAction)playButtonPressed:(id)sender;

@end