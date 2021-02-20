//
//  RadioAppDelegate.h
//  Radio
//
//  Created by Damien Glancy on 01/08/2012.
//  Copyright (c) 2012 Het is Simpel. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "RHPreferences.h"
#import "RadioDisplayViewController.h"

#import "RadioController.h"

#import "Channel.h"
#import "Recording.h"

@class RadioCloudManager;

@interface RadioAppDelegate : NSObject<NSApplicationDelegate, NSMenuDelegate>

@property (readonly, strong, nonatomic) NSPersistentStoreCoordinator *persistentStoreCoordinator;
@property (readonly, strong, nonatomic) NSManagedObjectModel *managedObjectModel;
@property (readonly, strong, nonatomic) NSManagedObjectContext *managedObjectContext;

@property(nonatomic, strong) NSDate *lastSync;
@property(nonatomic, strong) NSTimer *syncTimer;

@property(strong) NSTimer *menuAnimationTimer;
@property(assign) NSUInteger currentImageFrame;

@property(strong, nonatomic) RadioController *radioController;

@property(strong) NSStatusItem *statusItem;
@property(weak) IBOutlet NSMenu *statusMenu;
@property (weak) IBOutlet NSMenu *statusLibraryUpdatingMenu;
@property (weak) IBOutlet NSMenuItem *statusLibraryUpdatingMenuItem;


@property(strong) RHPreferencesWindowController *preferencesWindowController;
@property(strong, nonatomic) RadioDisplayViewController *radioDisplayViewController;

@property(nonatomic, strong) NSMutableArray *dynamicMenuItems;

@property(nonatomic, strong) NSURL *musicURL;

@property(nonatomic, strong) RadioCloudManager *cloudManager;

- (void)startMenuAnimation;

- (void)stopMenuAnimation;

- (void)recalculateMenuItems;

- (void)playRequested:(NSMenuItem *)menuItem;

- (void)stopRequested:(id)sender;

- (void)favouriteRequested:(id)sender;

- (void)recordingMenuItemPressed:(id)sender;

- (IBAction)preferencesMenuItemPressed:(id)sender;

- (IBAction)allStationsMenuItemPressed:(id)sender;

- (IBAction)quitMenuItemPressed:(id)sender;

@end