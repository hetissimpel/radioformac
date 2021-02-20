//
//  NowPlayingViewController.h
//  Radio
//
//  Created by Damien Glancy on 03/08/2012.
//  Copyright (c) 2012 Het is Simpel. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "RadioControlButton.h"
#import "RadioVolumeSlider.h"

@interface RadioDisplayViewController : NSViewController

@property(weak) IBOutlet NSTextField *trackTitleTextField;
@property(weak) IBOutlet NSTextField *stationTextField;

@property(weak) IBOutlet RadioControlButton *recordControlButton;
@property(weak) IBOutlet RadioControlButton *playControlButton;
@property(weak) IBOutlet RadioControlButton *favControlButton;

@property(weak) IBOutlet RadioVolumeSlider *volumeSlider;

- (IBAction)recordControlButtonPressed:(id)sender;

- (IBAction)playControlButtonPressed:(id)sender;

- (IBAction)favControlButtonPressed:(id)sender;

- (IBAction)volumeSliderMoved:(id)sender;

- (IBAction)muteButtonPressed:(id)sender;

- (void)updateRadioControls;

- (void)clearDisplay;

@end