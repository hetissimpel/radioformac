//
//  RadioController
//  Het is Simpel
//
//  Created by dglancy on 04/11/2012.
//  Copyright (c) 2012 Het is Simpel. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "Channel.h"
#import "Recording.h"

#import "YLRadio.h"
#import "YLHTTPRadio.h"
#import "YLMMSRadio.h"

@interface RadioController : NSObject<YLRadioDelegate>

@property(strong) YLRadio *radio;
@property(strong, nonatomic) Channel *selectedChannel;

@property(assign, nonatomic) BOOL recordActive;
@property(assign, nonatomic) BOOL playActive;
@property(assign, nonatomic) BOOL favouriteActive;
@property(assign, nonatomic) BOOL muted;

- (void)playChannel:(Channel *)channel;
- (void)startRecording:(void (^)(void))completionBlock;
- (void)stopRecording:(void (^)(void))completionBlock;
- (void)stop;

@end