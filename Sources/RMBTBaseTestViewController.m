/*
 * Copyright 2017 appscape gmbh
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

#import "RMBTBaseTestViewController.h"
#import "CLLocation+RMBTFormat.h"
#import "RMBTTestRunner.h"
#import "RMBT-Swift.h"

@interface RMBTBaseTestViewController ()<RMBTTestRunnerDelegate> {
    NSUInteger _finishedPercentage;
    NSUInteger _finishedGaugePercentage;
    RMBTTestRunner *_testRunner;
    BOOL _qosPerformed;
    BOOL _qosWillPerformed;
}
@end

// The RMBTBaseTestViewControllerSubclass protocol, which subclasses should implement
// and this define let us emulate this being an "abstract" class. We get warning
// in subclasses about unimplemented methods, and don't need to implement them in the base class:
#define subself ((RMBTBaseTestViewController<RMBTBaseTestViewControllerSubclass>*)self)

@implementation RMBTBaseTestViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    _qosWillPerformed = !([RMBTSettings sharedSettings].skipQoS);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[UIApplication sharedApplication] setIdleTimerDisabled:YES]; // Disallow turning off the screen
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    // Allow turning off the screen again.
    // Note that enabling the idle timer won't reset it, so if the device has alredy been idle the screen will dim
    // immediately. To prevent this, we delay enabling by 5s.
    [[UIApplication sharedApplication] bk_performBlock:^(id sender) {
        [[UIApplication sharedApplication] setIdleTimerDisabled:NO];
    } afterDelay:5.0];
}

- (NSUInteger)percentageAfterPhase:(RMBTTestRunnerPhase)phase {
    switch (phase) {
        case RMBTTestRunnerPhaseNone:
            return 0;
        case RMBTTestRunnerPhaseFetchingTestParams:
        case RMBTTestRunnerPhaseWait:
            return 4;
        case RMBTTestRunnerPhaseInit:
            return 20;
        case RMBTTestRunnerPhaseLatency:
            return 40;
        case RMBTTestRunnerPhaseDown:
        case RMBTTestRunnerPhaseInitUp:  // no visualization for init up
            return 70;
        case RMBTTestRunnerPhaseUp:
            return 100;
        case RMBTTestRunnerPhaseQoS:
            return 100;
        case RMBTTestRunnerPhaseSubmittingTestResult:
            return 100; // also no visualization for submission
      }
}

- (NSUInteger)percentageAfterPhaseWithQos:(RMBTTestRunnerPhase)phase {
    switch (phase) {
        case RMBTTestRunnerPhaseNone:
            return 0;
        case RMBTTestRunnerPhaseFetchingTestParams:
        case RMBTTestRunnerPhaseWait:
            return 4;
        case RMBTTestRunnerPhaseInit:
            return 15;
        case RMBTTestRunnerPhaseLatency:
            return 30;
        case RMBTTestRunnerPhaseDown:
        case RMBTTestRunnerPhaseInitUp:  // no visualization for init up
            return 50;
        case RMBTTestRunnerPhaseUp:
            return 75;
        case RMBTTestRunnerPhaseQoS:
            return 100;
        case RMBTTestRunnerPhaseSubmittingTestResult:
            return 100; // also no visualization for submission
      }
}

- (NSUInteger)gaugePercentageAfterPhase:(RMBTTestRunnerPhase)phase {
    switch (phase) {
        case RMBTTestRunnerPhaseNone:
            return 0;
        case RMBTTestRunnerPhaseFetchingTestParams:
        case RMBTTestRunnerPhaseWait:
            return 4;
        case RMBTTestRunnerPhaseInit:
            return 10;
        case RMBTTestRunnerPhaseLatency:
            return 23;
        case RMBTTestRunnerPhaseDown:
        case RMBTTestRunnerPhaseInitUp:  // no visualization for init up
            return 49;
        case RMBTTestRunnerPhaseUp:
            return 74;
        case RMBTTestRunnerPhaseQoS:
            return 100;
        case RMBTTestRunnerPhaseSubmittingTestResult:
            return 100; // also no visualization for submission
      }
}

- (NSUInteger)percentageForPhase:(RMBTTestRunnerPhase)phase {
    switch (phase) {
        case RMBTTestRunnerPhaseWait:    return 4 /* waiting phase, visualized as init */;
        case RMBTTestRunnerPhaseInit:    return 16 /* waiting phase, visualized as init */;
        case RMBTTestRunnerPhaseLatency: return 20;
        case RMBTTestRunnerPhaseDown:    return 30;
        case RMBTTestRunnerPhaseUp:      return 30;
        case RMBTTestRunnerPhaseQoS:     return 30;
        default: return 0;
    }
}

- (NSUInteger)gaugePercentageForPhase:(RMBTTestRunnerPhase)phase {
    switch (phase) {
        case RMBTTestRunnerPhaseWait:    return 4 /* waiting phase, visualized as init */;
        case RMBTTestRunnerPhaseInit:    return 6 /* waiting phase, visualized as init */;
        case RMBTTestRunnerPhaseLatency: return 13;
        case RMBTTestRunnerPhaseDown:    return 26;
        case RMBTTestRunnerPhaseUp:      return 25;
        default: return 0;
    }
}

- (NSUInteger)gaugePercentageForPhaseWithQos:(RMBTTestRunnerPhase)phase {
    switch (phase) {
        case RMBTTestRunnerPhaseWait:    return 4 /* waiting phase, visualized as init */;
        case RMBTTestRunnerPhaseInit:    return 6 /* waiting phase, visualized as init */;
        case RMBTTestRunnerPhaseLatency: return 13;
        case RMBTTestRunnerPhaseDown:    return 26;
        case RMBTTestRunnerPhaseUp:      return 25;
        case RMBTTestRunnerPhaseQoS:      return 26;
        default: return 0;
    }
}

- (NSUInteger)percentageForPhaseWithQos:(RMBTTestRunnerPhase)phase {
    switch (phase) {
        case RMBTTestRunnerPhaseWait:    return 4;
        case RMBTTestRunnerPhaseInit:    return 11; /* waiting phase, visualized as init */;
        case RMBTTestRunnerPhaseLatency: return 15;
        case RMBTTestRunnerPhaseDown:    return 20;
        case RMBTTestRunnerPhaseUp:      return 25;
        case RMBTTestRunnerPhaseQoS:     return 25;
        default: return 0;
    }
}

- (NSString*)statusStringForPhase:(RMBTTestRunnerPhase)phase {
    switch(phase) {
        case RMBTTestRunnerPhaseNone:
        case RMBTTestRunnerPhaseFetchingTestParams:
            return NSLocalizedString(@"Fetching test parameters", @"Phase status label");
        case RMBTTestRunnerPhaseWait:
            return NSLocalizedString(@"Waiting for test server", @"Phase status label");
        case RMBTTestRunnerPhaseInit:
            return NSLocalizedString(@"Initializing", @"Phase status label");
        case RMBTTestRunnerPhaseLatency:
            return NSLocalizedString(@"Pinging", @"Phase status label");
        case RMBTTestRunnerPhaseDown:
            return NSLocalizedString(@"Download", @"Phase status label");
        case RMBTTestRunnerPhaseInitUp:
            return NSLocalizedString(@"Initializing Upload", @"Phase status label");
        case RMBTTestRunnerPhaseUp:
            return NSLocalizedString(@"Upload", @"Phase status label");
        case RMBTTestRunnerPhaseQoS:
            return NSLocalizedString(@"measurement_qos", @"Phase status label");
        case RMBTTestRunnerPhaseSubmittingTestResult:
            return NSLocalizedString(@"Finalizing", @"Phase status label");
    }
}

- (void)startTestWithExtraParams:(NSDictionary*)extraParams {
    _finishedPercentage = 0;
    _finishedGaugePercentage = 0;
    _qosPerformed = NO;
    [subself onTestUpdatedTotalProgress:0 gaugeProgress:0];
    [subself onTestUpdatedServerName:@"-"];
    [subself onTestUpdatedStatus:@"-"];
    _testRunner = [[RMBTTestRunner alloc] initWithDelegate:self];
    [_testRunner startWithExtraParams:extraParams];
}

- (void)cancelTest {
    [[RMBTControlServer sharedControlServer] cancelAllRequests];
    [_testRunner cancel]; // TODO: move control server to runner
}

- (void)testRunnerDidDetectConnectivity:(RMBTConnectivity*)connectivity {
    [subself onTestUpdatedConnectivity:connectivity];
}

- (void)testRunnerDidDetectLocation:(CLLocation*)location {
    [subself onTestUpdatedLocation:location];
}

- (void)testRunnerDidStartPhase:(RMBTTestRunnerPhase)phase {
    if (phase == RMBTTestRunnerPhaseInit || phase == RMBTTestRunnerPhaseWait) {
        [subself onTestUpdatedServerName:_testRunner.testParams.serverName];
    }
    [subself onTestUpdatedStatus:[self statusStringForPhase:phase]];
    [subself onTestStartedPhase:phase];
}

- (void)testRunnerDidFinishPhase:(RMBTTestRunnerPhase)phase {
    if (_qosWillPerformed) {
        _finishedPercentage = [self percentageAfterPhaseWithQos:phase];
    } else {
        _finishedPercentage = [self percentageAfterPhase:phase];
    }
    _finishedGaugePercentage = [self gaugePercentageAfterPhase:phase];
    
    NSAssert(_finishedPercentage <= 100, @"Invalid percentage");
    [subself onTestUpdatedTotalProgress:_finishedPercentage gaugeProgress:_finishedGaugePercentage];

    if (phase == RMBTTestRunnerPhaseLatency) {
        [subself onTestMeasuredLatency:_testRunner.testResult.medianPingNanos];
    } else if (phase == RMBTTestRunnerPhaseDown) {
        [subself onTestMeasuredDownloadSpeed:_testRunner.testResult.totalDownloadHistory.totalThroughput.kilobitsPerSecond];
    } else if (phase == RMBTTestRunnerPhaseUp) {
        [subself onTestMeasuredUploadSpeed:_testRunner.testResult.totalUploadHistory.totalThroughput.kilobitsPerSecond];
    } else if (phase == RMBTTestRunnerPhaseQoS) {
        _qosPerformed = YES;
    }

    [subself onTestFinishedPhase:phase];
}

- (void)testRunnerDidUpdateProgress:(float)progress inPhase:(RMBTTestRunnerPhase)phase {
    NSUInteger totalPercentage = _finishedPercentage;
    NSUInteger totalGaugePercentage = _finishedGaugePercentage;
    if (_qosWillPerformed) {
        totalPercentage += [self percentageForPhaseWithQos:phase] * progress;
        totalGaugePercentage += [self gaugePercentageForPhaseWithQos:phase] * progress;
    } else {
        totalPercentage += [self percentageForPhase:phase] * progress;
        totalGaugePercentage += [self gaugePercentageForPhase:phase] * progress;
    }
    NSAssert(totalPercentage <= 100, @"Invalid percentage");
    [subself onTestUpdatedTotalProgress:totalPercentage gaugeProgress:totalGaugePercentage];
}

- (void)testRunnerDidMeasureThroughputs:(NSArray*)throughputs inPhase:(RMBTTestRunnerPhase)phase {
    [subself onTestMeasuredTroughputs:throughputs inPhase:phase];
}

- (void)testRunnerDidCompleteWithResult:(RMBTHistoryResult*)result {
    [subself onTestCompletedWithResult:result qos:_qosPerformed];
}

- (void)testRunnerDidCancelTestWithReason:(RMBTTestRunnerCancelReason)cancelReason {
    [subself onTestUpdatedStatus:NSLocalizedString(@"Aborted", @"Test status")];
    [subself onTestCancelledWithReason:cancelReason];
}

- (void)testRunnerQoSDidStartWithGroups:(NSArray*)groups {
    [subself onTestStartedQoSWithGroups:groups];
}

- (void)testRunnerQoSGroup:(RMBTQoSTestGroup*)group didUpdateProgress:(float)progress {
    [subself onTestUpdatedProgress:progress inQoSGroup:group];
}

@end
