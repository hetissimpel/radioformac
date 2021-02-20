//
//  RadioCrowdSourcingManager
//  Viscis
//
//  Created by dglancy on 07/11/2012.
//  Copyright (c) 2012 Viscis. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface RadioCrowdSourcingManager : NSObject

+ (void)sendNewStationDetailsToCrowdSourcingServiceWithName:(NSString *)name url:(NSString *)url;

@end