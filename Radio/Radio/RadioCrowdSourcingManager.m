//
//  RadioCrowdSourcingManager
//  Viscis
//
//  Created by dglancy on 07/11/2012.
//  Copyright (c) 2012 Viscis. All rights reserved.
//

#import "RadioCrowdSourcingManager.h"

@implementation RadioCrowdSourcingManager

+ (void)sendNewStationDetailsToCrowdSourcingServiceWithName:(NSString *)name url:(NSString *)url {
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    NSString *body = [NSString stringWithFormat:@" {  \"name\" : \"%@\", \"url\" : \"%@\" }", name, url];

    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:kCrowdSourcingUrl]];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"content-type"];
    [request setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];

    NSLog(@"Sending new station details to crowd sourcing service");

    [NSURLConnection sendAsynchronousRequest:request queue:queue completionHandler: ^(NSURLResponse *response, NSData *data, NSError *error) {
        if (error) {
            NSLog(@"Error sending station details to crowd sourcing service. %@", error);
        } else {
            NSLog(@"Success sending station details to crowd sourcing service");
        }
    }];
}

@end