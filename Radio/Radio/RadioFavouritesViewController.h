//
//  RadioFavouritesViewController.h
//  Radio
//
//  Created by Damien Glancy on 19/08/2012.
//  Copyright (c) 2012 Het is Simpel. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class RadioAppDelegate;

@interface RadioFavouritesViewController : NSViewController

@property(strong) IBOutlet RadioAppDelegate *app;
@property(weak) IBOutlet NSArrayController *favouritesArrayController;
@property(weak) IBOutlet NSTableView *favouritesTableView;
@property(weak) IBOutlet NSScrollView *favouritesScrollView;

@end