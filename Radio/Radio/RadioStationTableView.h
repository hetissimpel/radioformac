//
//  RadioStationTableView.h
//  Radio
//
//  Created by Damien Glancy on 03/12/2012.
//  Copyright (c) 2012 Het is Simpel. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@protocol RadioStationTableViewKeyboardDelegate<NSObject>

@optional
- (void)enterKeyWasPressed;

@end

@interface RadioStationTableView : NSTableView

@property(weak, nonatomic) id<RadioStationTableViewKeyboardDelegate> keyboardDelegate;

@end