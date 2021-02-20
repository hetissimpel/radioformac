//
//  RadioAppDelegate.m
//  Radio
//
//  Created by Damien Glancy on 01/08/2012.
//  Copyright (c) 2012 Het is Simpel. All rights reserved.
//

#import "RadioPrefsGeneralViewController.h"
#import "RadioPrefsStationsViewController.h"
#import "RadioPrefsRecordingViewController.h"
#import "RadioPrefsFavsViewController.h"
#import "RadioCloudManager.h"

@interface RadioAppDelegate ()

@property (assign) BOOL libraryUpdating;

@end

@implementation RadioAppDelegate

@synthesize persistentStoreCoordinator = _persistentStoreCoordinator;
@synthesize managedObjectModel = _managedObjectModel;
@synthesize managedObjectContext = _managedObjectContext;

#pragma mark - App Lifecycle

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    NSLog(@"[RADIO] Starting.");
    
    NSArray *apps = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"nl.hetissimpel.Radio"];
    if (apps.count > 1) {
        NSLog(@"Radio is already running, standing down this instance.");
        [NSApp terminate:self];
    }
    
    // Dynamic menus
    _dynamicMenuItems = [[NSMutableArray alloc] init];
    
    // ~/Music/Radio
    NSURL *url = [[NSFileManager defaultManager] URLForDirectory:NSMusicDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:nil];
    _musicURL = [url URLByAppendingPathComponent:@"Radio"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:_musicURL.path]) {
        NSLog(@"Creating ~/Music/Radio");
        [[NSFileManager defaultManager] createDirectoryAtURL:_musicURL withIntermediateDirectories:NO attributes:nil error:nil];
    }
    
    // Volume
    id volumeObj = [[NSUserDefaults standardUserDefaults] objectForKey:kAudioLevels];
    if (!volumeObj) {
        NSLog(@"Setting default volume level to 50%%");
        [[NSUserDefaults standardUserDefaults] setFloat:0.5f forKey:kAudioLevels];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    
    //Prefs
    if (!_preferencesWindowController) {
        RadioPrefsGeneralViewController *general = [[RadioPrefsGeneralViewController alloc] initWithNibName:@"RadioPrefsGeneralViewController" bundle:nil];
        RadioPrefsStationsViewController *stations = [[RadioPrefsStationsViewController alloc] initWithNibName:@"RadioPrefsStationsViewController" bundle:nil];
        RadioPrefsRecordingViewController *recordings = [[RadioPrefsRecordingViewController alloc] initWithNibName:@"RadioPrefsRecordingViewController" bundle:nil];
        RadioPrefsFavsViewController *favs = [[RadioPrefsFavsViewController alloc] initWithNibName:@"RadioPrefsFavsViewController" bundle:nil];
        
        NSArray *controllers = @[general, stations, favs, recordings];
        _preferencesWindowController = [[RHPreferencesWindowController alloc] initWithViewControllers:controllers andTitle:NSLocalizedString(@"Preferences", @"Preferences window title")];
    }
    
    // Scan Recordings
    [self performSelector:@selector(scanRecordings) withObject:nil afterDelay:0.1];
    
    // Radio Controller
    _radioController = [[RadioController alloc] init];
    
    // iCloud
    _cloudManager = [RadioCloudManager cloudManager];
    //[_cloudManager performSelector:@selector(syncWithCloud) withObject:nil afterDelay:1.0];
    
    // Schedule Radio Library Syncs
    [self performSelector:@selector(sync) withObject:nil afterDelay:0.1];
    
    // Register for wake events
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(receiveWakeNotification:) name:NSWorkspaceDidWakeNotification object:NULL];
    
    NSLog(@"[RADIO] Started.");
}

- (void)awakeFromNib {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioPlayerStateChange:) name:kNotificationRadioStateChanged object:nil];
    _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    _statusItem.menu = _statusMenu;
    _statusItem.image = [NSImage imageNamed:@"menubar_icon_default"];
    _statusItem.alternateImage = [NSImage imageNamed:@"menubar_icon_rollover"];
    [_statusItem.image setTemplate:YES];
    [_statusItem.alternateImage setTemplate:YES];
    _statusItem.highlightMode = YES;
    _statusMenu.delegate = self;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    [_managedObjectContext save:nil];
    
    NSLog(@"[RADIO] Terminated.");
    return NSTerminateNow;
}

#pragma mark - Menu Management

- (void)menuWillOpen:(NSMenu *)menu {
    if (!_libraryUpdating) {
        _statusItem.menu = _statusMenu;
        [self scanRecordings];
        [self recalculateMenuItems];
        
        // *** volume
        NSNumber *volumeObj = [[NSUserDefaults standardUserDefaults] objectForKey:kAudioLevels];
        _radioDisplayViewController.volumeSlider.floatValue = volumeObj.floatValue;
    }
}

- (void)recalculateMenuItems {
    [_statusMenu setMenuChangedMessagesEnabled:NO];
    
    NSUInteger count = 1; // 1 allows for display of radio player on top of menu
    
    // *** favourites
    for (NSMenuItem *menuItem in _dynamicMenuItems) {
        [_statusMenu removeItem:menuItem];
    }
    
    [_dynamicMenuItems removeAllObjects];
    
    NSFetchRequest *channelRequest = [[NSFetchRequest alloc] init];
    channelRequest.entity = [NSEntityDescription entityForName:@"Channel" inManagedObjectContext:_managedObjectContext];
    channelRequest.predicate = [NSPredicate predicateWithFormat:@"favourite == YES"];
    channelRequest.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"guid" ascending:NO]];
    
    NSArray *favourites = [_managedObjectContext executeFetchRequest:channelRequest error:nil];
    
    if (favourites.count == 0) {
        NSMenuItem *item = [_statusMenu insertItemWithTitle:NSLocalizedString(@"No favourites", nil) action:nil keyEquivalent:@"" atIndex:count];
        [_dynamicMenuItems addObject:item];
        count++;
    } else {
        for (Channel *channel in favourites) {
            NSString *displayChannelName = channel.name;
            if (displayChannelName.length > 23) {
                NSRange stringRange = {
                    0, MIN(displayChannelName.length, 23)
                };
                stringRange = [displayChannelName rangeOfComposedCharacterSequencesForRange:stringRange];
                displayChannelName = [displayChannelName substringWithRange:stringRange];
                displayChannelName = [NSString stringWithFormat:@"%@...", displayChannelName];
            }
            
            NSMenuItem *item = [_statusMenu insertItemWithTitle:displayChannelName action:@selector(playRequested:) keyEquivalent:@"" atIndex:count];
            item.image = [NSImage imageNamed:@"favorite-icon"];
            [item.offStateImage setTemplate:YES];
            [item setRepresentedObject:channel];
            [_dynamicMenuItems addObject:item];
            count++;
        }
    }
    
    // *** recordings
    NSFetchRequest *recordingRequest = [[NSFetchRequest alloc] init];
    recordingRequest.entity = [NSEntityDescription entityForName:@"Recording" inManagedObjectContext:_managedObjectContext];
    recordingRequest.predicate = [NSPredicate predicateWithFormat:@"endDate != nil"];
    NSSortDescriptor *sort = [[NSSortDescriptor alloc] initWithKey:@"startDate" ascending:NO];
    recordingRequest.sortDescriptors = [NSArray arrayWithObject:sort];
    
    NSArray *recordings = [_managedObjectContext executeFetchRequest:recordingRequest error:nil];
    
    if (recordings.count > 0) {
        NSMenuItem *seperatorItem = [NSMenuItem separatorItem];
        [_dynamicMenuItems addObject:seperatorItem];
        [_statusMenu insertItem:seperatorItem atIndex:count];
        count++;
        
        NSUInteger numberOfRecordingsToDisplay = MIN(recordings.count, 3);
        
        for (NSUInteger i = 0; i < numberOfRecordingsToDisplay; i++) {
            Recording *recording = (Recording *)recordings[i];
            
            NSDateComponents *components = [[NSCalendar currentCalendar] components:NSDayCalendarUnit | NSMonthCalendarUnit | NSHourCalendarUnit | NSMinuteCalendarUnit fromDate:recording.startDate];
            NSString *recordingDisplayTitle = [NSString stringWithFormat:@"%02d/%02d %02d:%02d %@", (int)components.day, (int)components.month, (int)components.hour, (int)components.minute, recording.channelName];
            if (recordingDisplayTitle.length > 25) {
                recordingDisplayTitle = [recordingDisplayTitle substringToIndex:25];
                recordingDisplayTitle = [NSString stringWithFormat:@"%@...", recordingDisplayTitle];
            }
            NSMenuItem *item = [_statusMenu insertItemWithTitle:recordingDisplayTitle action:@selector(playRecording:) keyEquivalent:@"" atIndex:count];
            item.image = [NSImage imageNamed:@"recorded-icon"];
            [item.offStateImage setTemplate:YES];
            [item setRepresentedObject:recording];
            [_dynamicMenuItems addObject:item];
            count++;
        }
        
        if (recordings.count > 3) {
            NSMenuItem *item = [_statusMenu insertItemWithTitle:NSLocalizedString(@"More recordings ...", nil) action:@selector(moreRecordingsMenuItemPressed:) keyEquivalent:@"" atIndex:count];
            [_dynamicMenuItems addObject:item];
        }
    }
    
    [_statusMenu setMenuChangedMessagesEnabled:YES];
    [_radioDisplayViewController updateRadioControls];
}

- (void)startMenuAnimation {
    if (_menuAnimationTimer && _menuAnimationTimer.isValid) {
        return;
    }
    
    NSLog(@"Start Menu Animation");
    _currentImageFrame = 1;
    _menuAnimationTimer = [NSTimer timerWithTimeInterval:0.5 target:self selector:@selector(updateMenuImage:) userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:_menuAnimationTimer forMode:NSRunLoopCommonModes];
}

- (void)stopMenuAnimation {
    NSLog(@"Stop Menu Animation");
    [_menuAnimationTimer invalidate];
    _statusItem.image = [NSImage imageNamed:@"menubar_icon_default"];
    _statusItem.alternateImage = [NSImage imageNamed:@"menubar_icon_rollover"];
    [_statusItem.image setTemplate:YES];
    [_statusItem.alternateImage setTemplate:YES];

}

- (void)updateMenuImage:(NSTimer *)timer {
    if (_currentImageFrame == 4) {
        _currentImageFrame = 1;
    }
    
    _statusItem.image = [NSImage imageNamed:[NSString stringWithFormat:@"menubar_icon_default_anim0%d", (int)_currentImageFrame]];
    _statusItem.alternateImage = [NSImage imageNamed:[NSString stringWithFormat:@"menubar_icon_rollover_anim0%d", (int)_currentImageFrame]];
    [_statusItem.image setTemplate:YES];
    [_statusItem.alternateImage setTemplate:YES];

    _currentImageFrame++;
}

// //////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Actions
// //////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)playRequested:(NSMenuItem *)menuItem {
    if (!menuItem && !_radioController.selectedChannel) {
        [_radioDisplayViewController updateRadioControls];
        return;
    }
    
    [_radioDisplayViewController clearDisplay];
    
    if (menuItem) {
        Channel *channel = (Channel *)menuItem.representedObject;
        _radioDisplayViewController.stationTextField.attributedStringValue = [RadioUtils convertToAttributedString:channel.name];
        [_radioController playChannel:channel];
    } else {
        _radioDisplayViewController.stationTextField.attributedStringValue = [RadioUtils convertToAttributedString:_radioController.selectedChannel.name];
        [_radioController playChannel:nil]; // play existing channel (if any)
    }
    
    [self recalculateMenuItems];
    [_radioDisplayViewController updateRadioControls];
}

- (void)playRecording:(NSMenuItem *)menuItem {
    Recording *recording = (Recording *)menuItem.representedObject;
    if (recording) {
        [_radioController stop];
        NSURL *audioURL = [NSURL URLWithString:recording.audio];
        [[NSWorkspace sharedWorkspace] openFile:audioURL.path withApplication:@"QuickTime Player"];
    }
}

- (void)recordingMenuItemPressed:(id)sender {
    if (!_radioController.selectedChannel) {
        [_radioDisplayViewController updateRadioControls];
        return;
    }
    
    if (_radioController.radio.isRecording) {
        [_radioController stopRecording:nil];
    } else {
        [_radioController startRecording:nil];
    }
    
    [self recalculateMenuItems];
    [_radioDisplayViewController updateRadioControls];
}

- (void)stopRequested:(id)sender {
    [_radioController stop];
    [self recalculateMenuItems];
    [_radioDisplayViewController updateRadioControls];
}

- (void)favouriteRequested:(id)sender {
    if (!_radioController.selectedChannel) {
        [_radioDisplayViewController updateRadioControls];
        return;
    }
    
    BOOL favourite = _radioController.selectedChannel.favourite.boolValue;
    
    if (favourite) {
        _radioController.selectedChannel.favourite = @NO;
        _radioController.favouriteActive = NO;
        [_cloudManager unfavouriteChannelInCloud:_radioController.selectedChannel];
    } else {
        _radioController.selectedChannel.favourite = @YES;
        _radioController.favouriteActive = YES;
        [_cloudManager favouriteChannelInCloud:_radioController.selectedChannel];
    }
    
    [_managedObjectContext save:nil];
    
    [_radioDisplayViewController updateRadioControls];
    [self recalculateMenuItems];
}

- (void)moreRecordingsMenuItemPressed:(id)sender {
    _preferencesWindowController.selectedIndex = 3;
    [_preferencesWindowController showWindow:self];
    [_preferencesWindowController.window orderFrontRegardless];
}

- (IBAction)allStationsMenuItemPressed:(id)sender {
    _preferencesWindowController.selectedIndex = 1;
    [_preferencesWindowController showWindow:self];
    [_preferencesWindowController.window orderFrontRegardless];
}

- (IBAction)preferencesMenuItemPressed:(id)sender {
    [_preferencesWindowController showWindow:self];
    [_preferencesWindowController.window orderFrontRegardless];
}

- (IBAction)quitMenuItemPressed:(id)sender {
    [_radioController stopRecording:^{
        NSLog(@"[RADIO] Exited.");
        [NSApp terminate:self];
    }];
}

// //////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Apple Events
// //////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)receiveWakeNotification:(NSNotification *)notification {
    NSLog(@"[RADIO] receiveWakeNotification: %@", notification.name);
    NSDate *now = [NSDate date];
    
    NSTimeInterval secondsBetween = [now timeIntervalSinceDate:_lastSync];
    if (secondsBetween >= kOneDay) {
        NSLog(@"Just woke up and syncing because more than a day has passed since last library sync");
        [self sync];
    }
}

// //////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Radio State
// //////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)audioPlayerStateChange:(NSNotification *)notification {
    [_radioDisplayViewController updateRadioControls];
}


// //////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - iCloud
// //////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)incomingUpdatesFromCloud:(NSNotification *)notification {
    NSLog(@"[RADIO] Updates from iCloud");
    
    [self recalculateMenuItems];
}

// //////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Library Sync
// //////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define kLibraryDesc    @"desc"
#define kLibraryGuid    @"guid"
#define kLibraryName    @"name"
#define kLibraryUrl     @"url"
#define kLibraryWebsite @"website"
#define kLibraryCity    @"city"
#define kLibraryCountry @"country"
#define kLibraryDisable @"disable"

#define kBatchSize      100

- (void)sync {
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
    dispatch_async(queue, ^{
        NSURL *url = [NSURL URLWithString:kLibraryPlistUrl];
        
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:10.0];
        NSURLResponse *response;
        NSError *error;
        
        [request setHTTPMethod:@"HEAD"];
        [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
        
        NSDictionary *headers = [(NSHTTPURLResponse *)response allHeaderFields];
        NSString *lastModifiedString = headers[@"Last-Modified"];
        
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.dateFormat = @"EEE, dd MMM yyyy HH:mm:ss z";
        df.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        df.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];

        NSDate *latestLastModifiedDateForRadioLibrary = [[NSUserDefaults standardUserDefaults] objectForKey:@"latestLastModifiedDateForRadioLibrary"];
        NSDate *lastModifiedDate = [df dateFromString:lastModifiedString];
    
        if (!latestLastModifiedDateForRadioLibrary || [lastModifiedDate timeIntervalSinceDate:latestLastModifiedDateForRadioLibrary]>0) {
            [self syncFromInternetWithLastModifiedDate:lastModifiedDate];
        }
    });    
}

- (void)syncFromInternetWithLastModifiedDate:(NSDate *)lastModifiedDate {
        NSLog(@"[RADIO] Starting library sync");
        _libraryUpdating = YES;
        _statusItem.menu = _statusLibraryUpdatingMenu;
    
        NSURL *url = [NSURL URLWithString:kLibraryPlistUrl];
        NSDictionary *library = [[NSDictionary alloc] initWithContentsOfURL:url];
    
        NSArray *keys = [library allKeys];
        
        NSManagedObjectContext *backgroundContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        backgroundContext.parentContext = _managedObjectContext;
        backgroundContext.undoManager = nil;
        
        [backgroundContext performBlock: ^{
            NSUInteger count = 0;
            NSUInteger batchCount = 0;
            NSUInteger batchTotalCount = 0;
            
            for (NSString *key in keys) {
                @autoreleasepool {
                    count++;
                    batchCount++;
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        _statusLibraryUpdatingMenuItem.title = [NSString stringWithFormat:@"Library updating (%ld of %ld)", count, keys.count];
                    });
                    
                    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"guid == $GUID"];
                    
                    NSDictionary *libraryChannel = [library objectForKey:key];
                    NSString *guid = (NSString *)[libraryChannel objectForKey:kLibraryGuid];
                    
                    if (guid) {
                        NSFetchRequest *request = [[NSFetchRequest alloc] init];
                        request.entity = [NSEntityDescription entityForName:@"Channel" inManagedObjectContext:backgroundContext];
                        request.predicate = [predicate predicateWithSubstitutionVariables:@{ @"GUID": guid }];
                        
                        Channel *channel;
                        
                        NSArray *channels = [backgroundContext executeFetchRequest:request error:nil];
                        if (!channels || channels.count != 1) {
                            channel = [NSEntityDescription insertNewObjectForEntityForName:@"Channel" inManagedObjectContext:backgroundContext];
                            channel.guid = guid;
                        } else {
                            channel = (Channel *)channels[0];
                        }
                        
                        BOOL disable = ((NSNumber *)[libraryChannel objectForKey:kLibraryDisable]).boolValue;
                        if (disable) {
                            [backgroundContext deleteObject:channel];
                        }
                        
                        NSString *libraryName = (NSString *)[libraryChannel objectForKey:kLibraryName];
                        if (libraryName && ![libraryName isEqualToString:channel.name]) {
                            channel.name = libraryName;
                        }
                        
                        NSString *libraryDesc = (NSString *)[libraryChannel objectForKey:kLibraryDesc];
                        if (libraryDesc && ![libraryDesc isEqualToString:channel.desc]) {
                            channel.desc = libraryDesc;
                        }
                        
                        NSString *libraryUrl = (NSString *)[libraryChannel objectForKey:kLibraryUrl];
                        if (libraryUrl && ![libraryUrl isEqualToString:channel.url]) {
                            channel.url = libraryUrl;
                        }
                        
                        NSString *libraryWebsite = (NSString *)[libraryChannel objectForKey:kLibraryWebsite];
                        if (libraryWebsite && ![libraryWebsite isEqualToString:channel.website]) {
                            channel.website = libraryWebsite;
                        }
                        
                        NSString *libraryCity = (NSString *)[libraryChannel objectForKey:kLibraryCity];
                        if (libraryCity && ![libraryCity isEqualToString:channel.city]) {
                            channel.city = libraryCity;
                        }
                        
                        NSString *libraryCountry = (NSString *)[libraryChannel objectForKey:kLibraryCountry];
                        if (libraryCountry && ![libraryCountry isEqualToString:channel.country]) {
                            channel.country = libraryCountry;
                        }
                    }
                    
                    if (batchCount >= kBatchSize) {
                        [backgroundContext save:nil];
                        [_managedObjectContext performBlock: ^{
                            [_managedObjectContext save:nil];
                        }];
                        
                        NSLog(@"Processing station %ld of %ld (Batch: #%ld)", count, keys.count, batchTotalCount);
                        batchCount = 0;
                        batchTotalCount++;
                    }
                }
            }
            
            // one last save, to catch last batch (likely less than batch size)
            [backgroundContext save:nil];
            [_managedObjectContext performBlock: ^{
                [_managedObjectContext save:nil];
            }];
            
            [[NSUserDefaults standardUserDefaults] setObject:lastModifiedDate forKey:@"latestLastModifiedDateForRadioLibrary"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            
            _lastSync = [NSDate date];
            [_syncTimer invalidate];
            _syncTimer = [NSTimer scheduledTimerWithTimeInterval:kOneDay target:self selector:@selector(sync) userInfo:nil repeats:YES];
            
            _statusItem.menu = _statusMenu;
            _libraryUpdating = NO;
            NSLog(@"Ended library sync");
        }];
}

- (void)scanRecordings {
    NSLog(@"[RADIO] Scan recordings");
    
    NSFileManager *fm = [NSFileManager defaultManager];
    
    NSFetchRequest *request = [[NSFetchRequest alloc] init];
    request.entity = [NSEntityDescription entityForName:@"Recording" inManagedObjectContext:_managedObjectContext];
    
    NSArray *recordings = [_managedObjectContext executeFetchRequest:request error:nil];
    for (Recording *recording in recordings) {
        NSURL *audioURL = [NSURL URLWithString:recording.audio];
        if (![fm fileExistsAtPath:audioURL.path]) {
            NSLog(@"[RADIO] Recording at %@ is missing, removing entity", recording.audio);
            [_managedObjectContext deleteObject:recording];
        }
    }
    
    [_managedObjectContext save:nil];
    NSLog(@"[RADIO] Scan recordings ended");
}

// //////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Core Data Stack
// //////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSURL *)applicationFilesDirectory {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *appSupportURL = [[fileManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] lastObject];
    return [appSupportURL URLByAppendingPathComponent:@"nl.hetissimpel.radio"];
}

- (NSManagedObjectModel *)managedObjectModel {
    if (_managedObjectModel) {
        return _managedObjectModel;
    }
    
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"Radio" withExtension:@"momd"];
    _managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    return _managedObjectModel;
}

- (NSPersistentStoreCoordinator *)persistentStoreCoordinator {
    if (_persistentStoreCoordinator) {
        return _persistentStoreCoordinator;
    }
    
    NSManagedObjectModel *mom = [self managedObjectModel];
    if (!mom) {
        NSLog(@"%@:%@ No model to generate a store from", [self class], NSStringFromSelector(_cmd));
        return nil;
    }
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *applicationFilesDirectory = [self applicationFilesDirectory];
    NSError *error = nil;
    
    NSDictionary *properties = [applicationFilesDirectory resourceValuesForKeys:@[NSURLIsDirectoryKey] error:&error];
    
    if (!properties) {
        BOOL ok = NO;
        if ([error code] == NSFileReadNoSuchFileError) {
            ok = [fileManager createDirectoryAtPath:[applicationFilesDirectory path] withIntermediateDirectories:YES attributes:nil error:&error];
        }
        if (!ok) {
            [[NSApplication sharedApplication] presentError:error];
            return nil;
        }
    } else {
        if (![properties[NSURLIsDirectoryKey] boolValue]) {
            // Customize and localize this error.
            NSString *failureDescription = [NSString stringWithFormat:@"Expected a folder to store application data, found a file (%@).", [applicationFilesDirectory path]];
            
            NSMutableDictionary *dict = [NSMutableDictionary dictionary];
            [dict setValue:failureDescription forKey:NSLocalizedDescriptionKey];
            error = [NSError errorWithDomain:@"nl.hetissimpel.radio" code:101 userInfo:dict];
            
            [[NSApplication sharedApplication] presentError:error];
            return nil;
        }
    }
    
    NSURL *url = [applicationFilesDirectory URLByAppendingPathComponent:@"radio.sqlite"];
    if (![fileManager fileExistsAtPath:url.path]) {
        NSLog(@"Moving seed database into place");
        NSURL *defaultStoreURL = [[NSBundle mainBundle] URLForResource:@"radio" withExtension:@"sqlite"];
        [fileManager copyItemAtURL:defaultStoreURL toURL:url error:nil];
    }
    
    NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:mom];
    if (![coordinator addPersistentStoreWithType:NSXMLStoreType configuration:nil URL:url options:nil error:&error]) {
        [[NSApplication sharedApplication] presentError:error];
        return nil;
    }
    _persistentStoreCoordinator = coordinator;
    
    return _persistentStoreCoordinator;
}

- (NSManagedObjectContext *)managedObjectContext {
    if (_managedObjectContext) {
        return _managedObjectContext;
    }
    
    NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
    if (!coordinator) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        [dict setValue:@"Failed to initialize the store" forKey:NSLocalizedDescriptionKey];
        [dict setValue:@"There was an error building up the data file." forKey:NSLocalizedFailureReasonErrorKey];
        NSError *error = [NSError errorWithDomain:@"nl.hetissimpel.radio" code:9999 userInfo:dict];
        [[NSApplication sharedApplication] presentError:error];
        return nil;
    }
    _managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    [_managedObjectContext setPersistentStoreCoordinator:coordinator];
    
    return _managedObjectContext;
}

@end