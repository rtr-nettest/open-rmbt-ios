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

#import "RMBTHistoryResult.h"
#import "RMBT-Swift.h"

@implementation RMBTHistoryResultItem
- (instancetype)initWithResponse:(NSDictionary*)response {
    if (self = [super init]) {
        _title = response[@"title"];
        _value = [response[@"value"] description];
        NSParameterAssert(_title);
        NSParameterAssert(_value);
        _classification = -1;
        if (response[@"classification"]) {
            _classification = [response[@"classification"] unsignedIntegerValue];
        }
    }
    return self;
}

- (instancetype)initWithTitle:(NSString*)title value:(NSString*)value classification:(NSUInteger)classification hasDetails:(BOOL)hasDetails {
    if (self = [super init]) {
        _title = title;
        _value = value;
        _classification = classification;
        _hasDetails = hasDetails;
    }
    return self;
}

+ (NSInteger)classification:(double)percent {
    if (percent < 0.25) {
        return 1;
    } else if (percent < 0.5) {
        return 2;
    } else if (percent < 0.75) {
        return 3;
    } else if (percent <= 1) {
        return 4;
    } else {
        return -1;
    }
}
@end

@implementation RMBTHistoryQOEResultItem
- (instancetype)initWithResponse:(NSDictionary*)response {
    if (self = [super init]) {
        _category = response[@"category"];
        _quality = [response[@"quality"] description];
        NSParameterAssert(_category);
        NSParameterAssert(_quality);
        _classification = -1;
        if (response[@"classification"]) {
            _classification = [response[@"classification"] unsignedIntegerValue];
        }
    }
    return self;
}

- (instancetype)initWithCategory:(NSString*)category quality:(NSString*)quality value:(NSString*)value classification:(NSInteger)classification {
    if (self = [super init]) {
        _category = category;
        _value = value;
        _quality = quality;
        _classification = classification;
    }
    return self;
}
@end

@interface RMBTHistoryResult() {
    NSMutableArray *_netItems, *_measurementItems, *_fullDetailsItems;
    NSMutableArray *_qoeClassificationItems;
}
@end

@implementation RMBTHistoryResult

- (instancetype)initWithResponse:(NSDictionary*)response {
    if (self = [super init]) {
        _downloadSpeedMbpsString = response[@"speed_download"];
        _uploadSpeedMbpsString = response[@"speed_upload"];
        _shortestPingMillisString = response[@"ping_shortest"];
        // Note: here network_type is a string with full description (i.e. "WLAN") and in the basic details response
        // it's a numeric code
        _networkTypeServerDescription = response[@"network_type"];
        _uuid = response[@"test_uuid"];
        _loopUuid = response[@"loop_uuid"];
        _deviceModel = response[@"model"];
        _timeString = response[@"time_string"];
        
        NSTimeInterval t = [((NSNumber*)response[@"time"]) doubleValue] / 1000.0;
        _timestamp = [NSDate dateWithTimeIntervalSince1970:t];
        _coordinate = kCLLocationCoordinate2DInvalid;

        _dataState = RMBTHistoryResultDataStateIndex;
    }
    return self;
}

- (NSString*)formattedTimestamp {
    static NSDateFormatter *currentYearFormatter = nil;
    static NSDateFormatter *previousYearFormatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        currentYearFormatter = [[NSDateFormatter alloc] init];
        [currentYearFormatter setDateFormat:@"MMM dd\nHH:mm"];
        
        previousYearFormatter = [[NSDateFormatter alloc] init];
        [previousYearFormatter setDateFormat:@"MMM dd\nYYYY"];
    });

    NSDateComponents *historyDateComponents = [[NSCalendar currentCalendar] components:NSCalendarUnitYear
                                                                              fromDate:_timestamp];
    NSDateComponents *currentDateComponents = [[NSCalendar currentCalendar] components:NSCalendarUnitYear
                                                                              fromDate:[NSDate date]];
    NSString *result;

    if (currentDateComponents.year == historyDateComponents.year) {
        result = [currentYearFormatter stringFromDate:_timestamp];
    } else {
        result = [previousYearFormatter stringFromDate:_timestamp];
    }

    // For some reason MMM on iOS7 returns "Aug." with a trailing dot, let's strip the dot manually
    return [result stringByReplacingOccurrencesOfString:@"." withString:@""];
}

- (void)ensureBasicDetails:(RMBTBlock)success {
    if (self.dataState != RMBTHistoryResultDataStateIndex) {
        success();
    } else {
        dispatch_group_t allDone = dispatch_group_create();

        dispatch_group_enter(allDone);
        [[RMBTControlServer sharedControlServer] getHistoryQoSResultWithUUID:self.uuid success:^(QosMeasurementResultResponse *response) {
            NSArray *results = [RMBTHistoryQoSGroupResult resultsWithResponse:[response json]];
            if (results.count > 0) {
                _qosResults = results;
            }
            dispatch_group_leave(allDone);
        } error:^(NSError *error) {
            RMBTLog(@"Error fetching QoS test results: %@.", error);
            dispatch_group_leave(allDone);
        }];

        dispatch_group_enter(allDone);
        [[RMBTControlServer sharedControlServer] getHistoryResultWithUUID:self.uuid fullDetails:NO success:^(HistoryMeasurementResponse *r) {
            NSDictionary *response = [r.measurements.firstObject json];
            if (response[@"network_type"]) {
                _networkType = RMBTNetworkTypeMake([response[@"network_type"] integerValue]);
            }

            _openTestUuid = response[@"open_test_uuid"];

            _shareURL = nil;
            _shareText = response[@"share_text"];
            if (_shareText) {
                NSDataDetector *linkDetector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:nil];
                NSArray *matches = [linkDetector matchesInString:_shareText options:0 range:NSMakeRange(0, [_shareText length])];

                if (matches.count > 0) {
                    NSTextCheckingResult *r = [matches lastObject];
                    NSAssert(r.resultType == NSTextCheckingTypeLink, @"Invalid match type");
                    _shareText = [_shareText stringByReplacingCharactersInRange:r.range withString:@""];
                    _shareURL = [[matches lastObject] URL];
                }
            }
            
            _netItems = [NSMutableArray array];
            for (NSDictionary *r in response[@"net"]) {
                [_netItems addObject:[[RMBTHistoryResultItem alloc] initWithResponse:r]];
            }

            _measurementItems = [NSMutableArray array];
            for (NSDictionary *r in response[@"measurement"]) {
                [_measurementItems addObject:[[RMBTHistoryResultItem alloc] initWithResponse:r]];
            }

            _qoeClassificationItems = [NSMutableArray array];
            for (NSDictionary *r in response[@"qoe_classification"]) {
                [_qoeClassificationItems addObject:[[RMBTHistoryQOEResultItem alloc] initWithResponse:r]];
            }
            
            if (response[@"geo_lat"] && response[@"geo_long"]) {
                _coordinate = CLLocationCoordinate2DMake([response[@"geo_lat"] doubleValue], [response[@"geo_long"] doubleValue]);
            }
            
            if (response[@"measurement_result"]) {
                NSDictionary *measurementResult = response[@"measurement_result"];
                if (measurementResult[@"download_kbit"]) {
                    _downloadSpeedMbpsString = RMBTSpeedMbpsStringWithSuffix([measurementResult[@"download_kbit"] intValue], false);
                }
                if (measurementResult[@"upload_kbit"]) {
                    _uploadSpeedMbpsString = RMBTSpeedMbpsStringWithSuffix([measurementResult[@"upload_kbit"] intValue], false);
                }
                if (measurementResult[@"ping_ms"]) {
                    _shortestPingMillisString = [NSString stringWithFormat:@"%@", measurementResult[@"ping_ms"]];
                }
            }

            _dataState = RMBTHistoryResultDataStateBasic;
            dispatch_group_leave(allDone);
        } error:^(NSError *error) {
            RMBTLog(@"Error fetching test results: %@. Info: %@", error);
            dispatch_group_leave(allDone);
        }];

        dispatch_group_notify(allDone, dispatch_get_main_queue(),^{
            if (_dataState == RMBTHistoryResultDataStateBasic) {
                success();
            }
        });
    }
}

- (void)ensureFullDetails:(RMBTBlock)success {
    if (self.dataState == RMBTHistoryResultDataStateFull) {
        success();
    } else {
        // Fetch data
        [[RMBTControlServer sharedControlServer] getFullDetailsHistoryResultWithUUID:self.uuid success:^(FullMapMeasurementResponse *response) {
            self->_fullDetailsItems = [NSMutableArray array];
            NSArray *responseDictionary = [response json][@"testresultdetail"];
            for (NSDictionary *r in responseDictionary) {
                [self->_fullDetailsItems addObject:[[RMBTHistoryResultItem alloc] initWithResponse:r]];
            }
            self->_dataState = RMBTHistoryResultDataStateFull;
            success();
        } error:^(NSError *error) {
            // TODO: propagate error here
        }];
    }
}

- (void)ensureSpeedGraph:(RMBTBlock)success {
    NSParameterAssert(_openTestUuid);
    [[RMBTControlServer sharedControlServer] getHistoryOpenDataResultWithUUID:_openTestUuid success:^(RMBTOpenDataResponse *r) {
        NSDictionary *response = [r json];
        _downloadGraph = [[RMBTHistorySpeedGraph alloc] initWithResponse:response[@"speed_curve"][@"download"]];
        _uploadGraph = [[RMBTHistorySpeedGraph alloc] initWithResponse:response[@"speed_curve"][@"upload"]];
        success();
    } error:^(NSError *error, NSDictionary *info) {
        // TODO
    }];
}
@end
