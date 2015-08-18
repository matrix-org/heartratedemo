/*
    Copyright (C) 2014 Apple Inc. All Rights Reserved.
    See LICENSE.txt for this sample’s licensing information
    
    Abstract:
    
                The main application delegate.
            
*/

#import "AAPLAppDelegate.h"
#import "AAPLProfileViewController.h"
#import "AAPLJournalViewController.h"
#import "AAPLEnergyViewController.h"
@import HealthKit;

@interface AAPLAppDelegate()

@property (nonatomic) HKHealthStore *healthStore;

@end


@implementation AAPLAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.healthStore = [[HKHealthStore alloc] init];

    [self setUpHealthStoreForTabBarControllers];
    
    HKQuantityType *heartRateType = [HKObjectType quantityTypeForIdentifier:HKQuantityTypeIdentifierHeartRate];
    
    HKObserverQuery *query = [[HKObserverQuery alloc] initWithSampleType:heartRateType predicate:nil updateHandler:^(HKObserverQuery * _Nonnull query, HKObserverQueryCompletionHandler  _Nonnull completionHandler, NSError * _Nullable error) {
        if (error) {
            NSLog(@"Failed to set up observer query");
        }
        
        NSSortDescriptor *timeSortDescriptor = [[NSSortDescriptor alloc] initWithKey:HKSampleSortIdentifierStartDate ascending:YES];
        
        NSDate *lastSample = [[NSUserDefaults standardUserDefaults] objectForKey:@"lastTsUploaded"];
        if (!lastSample) {
            lastSample = [NSDate dateWithTimeIntervalSinceNow:-24 * 60 * 60];
        }
        
        NSDate *lowerBound = [lastSample dateByAddingTimeInterval:1]; // crappy
        
        NSPredicate *pred = [HKQuery predicateForSamplesWithStartDate:lowerBound endDate:nil options:HKQueryOptionStrictStartDate];
        
        HKSampleQuery *sampleQuery = [[HKSampleQuery alloc] initWithSampleType:heartRateType predicate:pred limit:10 sortDescriptors:@[timeSortDescriptor] resultsHandler:^(HKSampleQuery *query, NSArray *results, NSError *error) {
            if (!results) {
                NSLog(@"An error occured fetching the user's tracked food. In your app, try to handle this gracefully. The error was: %@.", error);
                return;
            }
            
            [self uploadSamples:results fromElement:0 then:completionHandler];
        }];
        [self.healthStore executeQuery:sampleQuery];
    }];
    
    [self.healthStore executeQuery:query];
    
    [self.healthStore enableBackgroundDeliveryForType:heartRateType frequency:HKUpdateFrequencyImmediate withCompletion:^(BOOL success, NSError * _Nullable error) {
        if (!success) {
            NSLog(@"failed to enable background delivery");
        }
    }];

    return YES;
}

- (void)uploadSamples:(NSArray *)samples fromElement:(int)i then:(HKObserverQueryCompletionHandler)completionHandler {
    if (samples.count == i) return;
    
    HKQuantitySample *sample = samples[i];
    
    NSLog(@"uploading sample at %@", sample.startDate);
    
    NSMutableURLRequest * req = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"https://matrix.org/_matrix/client/api/v1/rooms/!eoChQgeszuxcSBgfzR:matrix.org/send/org.matrix.demo.health?access_token=--token--"]];
    req.HTTPMethod = @"POST";
    
    HKUnit *bpmUnit = [[HKUnit countUnit] unitDividedByUnit:[HKUnit minuteUnit]];
    
    double bpmDouble = [[sample quantity] doubleValueForUnit:bpmUnit];
    
    NSNumber *val = [NSNumber numberWithDouble:bpmDouble];
    
    NSDictionary *body = @{
                            @"type": @"heartrate",
                            @"bpm": val,
                            @"ts": [NSNumber numberWithInt:[sample.startDate timeIntervalSince1970]]
                           };
    
    NSError *error;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&error];
    
    req.HTTPBody = bodyData;
    
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        
        if (error) {
            NSLog(@"couldn't upload sample: %@", error);
            completionHandler();
            return;
        }
        
        NSString *resp = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSLog(@"%@", resp);
        
        [[NSUserDefaults standardUserDefaults] setObject:sample.startDate forKey:@"lastTsUploaded"];
        
        if (i == samples.count - 1) {
            completionHandler();
        } else {
            [self uploadSamples:samples fromElement:i+1 then:completionHandler];
        }
    }];
    
    [task resume];
}


#pragma mark - Convenience

// Set the healthStore property on each view controller that will be presented to the user. The root view controller is a tab
// bar controller. Each tab of the root view controller is a navigation controller which contains its root view controller—
// these are the subclasses of the view controller that present HealthKit information to the user.
- (void)setUpHealthStoreForTabBarControllers {
    UITabBarController *tabBarController = (UITabBarController *)[self.window rootViewController];

    for (UINavigationController *navigationController in tabBarController.viewControllers) {
        id viewController = navigationController.topViewController;
        
        if ([viewController respondsToSelector:@selector(setHealthStore:)]) {
            [viewController setHealthStore:self.healthStore];
        }
    }
}

@end
