/*
 * Copyright 2013 appscape gmbh
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */

#import "RMBTTestParams.h"
#import "RMBTNews.h"

#import <Foundation/Foundation.h>
#import <AFNetworking/AFNetworking.h>

@interface RMBTControlServer : NSObject

@property (readonly, nonatomic) NSDictionary *historyFilters;
// Mapping of QoS test keys to names, e.g. "WEBSITE" => "Web page"
@property (readonly, nonatomic) NSDictionary *qosTestNames;
@property (readonly, nonatomic) NSString *openTestBaseURL;

@property (readonly, nonatomic) NSURL *mapServerURL;
@property (readonly, nonatomic) NSURL *statsURL;

+ (instancetype)sharedControlServer;

- (void)updateWithCurrentSettings;

- (void)getSettings:(RMBTBlock)success error:(RMBTErrorBlock)errorCallback;

// Retrieves news from server
- (void)getNews:(RMBTSuccessBlock)success;

// Retrieves home network (roaming) status from server. Resolved with a NSNumber representing
// a boolean value, which is true if user is out of home country.
- (void)getRoamingStatusWithParams:(NSDictionary*)params success:(RMBTSuccessBlock)success;

// Retrieves test parameters for the next test, submitting current test counter and last test status.
// If the client doesn't have an UUID yet, it first retrieves the settings to obtain the UUID
- (void)getTestParamsWithParams:(NSDictionary*)params success:(RMBTSuccessBlock)success error:(RMBTBlock)error;

- (void)getQoSParams:(RMBTSuccessBlock)success error:(RMBTErrorBlock)errorCallback;

// Retrieves list of previous test results.
// If the client doesn't have an UUID yet, it first retrieves the settings to obtain the UUID
- (void)getHistoryWithFilters:(NSDictionary*)filters length:(NSUInteger)length offset:(NSUInteger)offset success:(RMBTSuccessBlock)success error:(RMBTErrorBlock)errorCallback;

- (void)getHistoryResultWithUUID:(NSString*)uuid fullDetails:(BOOL)fullDetails success:(RMBTSuccessBlock)success error:(RMBTErrorBlock)errorCallback;
- (void)getHistoryQoSResultWithUUID:(NSString*)uuid success:(RMBTSuccessBlock)success error:(RMBTErrorBlock)errorCallback;
- (void)getHistoryOpenDataResultWithUUID:(NSString*)openUuid success:(RMBTSuccessBlock)success error:(RMBTErrorBlock)errorCallback;

- (void)getSyncCode:(RMBTSuccessBlock)success error:(RMBTErrorBlock)errorCallback;
- (void)syncWithCode:(NSString*)code success:(RMBTBlock)success error:(RMBTErrorBlock)errorCallback;

// Submits test results. Same call is used to submit both regular test result (endpoint nil) and qos test result (endpoint contains the URL string)
- (void)submitResult:(NSDictionary*)result endpoint:(NSString*)endpoint success:(RMBTSuccessBlock)success error:(RMBTBlock)error;

- (NSString *)uuid;
- (NSURL *)baseURL;

- (NSDictionary *)capabilities;

- (void)performWithUUID:(RMBTBlock)callback error:(RMBTErrorBlock)errorCallback;
- (void)cancelAllRequests;

@end
