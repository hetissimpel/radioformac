//
//  RadioPrefsFavsViewController.m
//  Radio
//
//  Created by Damien Glancy on 18/08/2012.
//  Copyright (c) 2012 Het is Simpel. All rights reserved.
//

#import "RadioPrefsFavsViewController.h"
#import "RadioCrowdSourcingManager.h"
#import "RadioCloudManager.h"


@implementation RadioPrefsFavsViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        RadioAppDelegate *app = GetAppDelegate();
        _managedObjectContext = app.managedObjectContext;
    }

    return self;
}

- (void)awakeFromNib {
    NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"country" ascending:YES];
    _stationsTableView.sortDescriptors = @[sortDescriptor];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if ([tableColumn.identifier isEqualToString:@"PrefsFavsImage"]) {
        return [NSImage imageNamed:@"fav_selected"];
    } else {
        return nil;
    }
}

#pragma mark - RHPreferencesViewControllerProtocol

- (NSString *)identifier {
    return NSStringFromClass(self.class);
}

- (NSImage *)toolbarItemImage {
    return [NSImage imageNamed:@"settings_favorites"];
}

- (NSString *)toolbarItemLabel {
    return NSLocalizedString(@"Favourites", nil);
}

- (NSView *)initialKeyView {
    return nil;
}

- (IBAction)removeFavStationButtonPressed:(id)sender {
    NSArray *channels = _channelsArrayController.selectedObjects;

    if (channels && channels.count > 0) {
        Channel *channel = (Channel *)channels[0];
        channel.favourite = @NO;

        RadioAppDelegate *app = GetAppDelegate();
        [app.cloudManager unfavouriteChannelInCloud:channel];
    }

    [_managedObjectContext save:nil];

    [_stationsTableView reloadData];
}

- (IBAction)playButtonPressed:(id)sender {
    NSLog(@"Play station pressed");

    RadioAppDelegate *app = GetAppDelegate();
    NSArray *channels = _channelsArrayController.selectedObjects;

    if (channels && channels.count > 0) {
        app.radioController.selectedChannel = channels[0];
        [app playRequested:nil];
    }
}

- (IBAction)doubleClickOnFavouriteRow:(id)sender {
    [self playButtonPressed:sender];
}


@end