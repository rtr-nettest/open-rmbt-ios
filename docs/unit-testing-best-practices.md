# Unit Testing Best Practices

This document outlines the testing strategies and patterns used in the TruU project for writing clean, maintainable, and focused unit tests.

## Test Method Naming Convention

We use the **WHEN-THEN** naming pattern with snake_case to clearly express test scenarios:

```swift
func whenLocationDisabled_thenAvailableNetworksDeliversLocationError()
func whenLocationEnabled_thenAvailableNetworksDeliversNetworksUpdates()
func whenLocationEnabledAfterDisabled_thenAvailableNetworksDeliversNetworksUpdates()
```

**Benefits:**
- **Clear intent**: Immediately understand the scenario and expected outcome
- **Consistent format**: `test_when[Condition]_then[ExpectedBehavior]`
- **Business-focused**: Describes behavior from user/business perspective
- **Easy scanning**: Quickly identify test coverage gaps

## Helper Methods Strategy

### Purpose: Hide Implementation, Expose Business Logic

The core principle is to **hide complex implementation details** and make test cases focus purely on **business logic and behavior verification**.

### Key Helper Methods

#### `makeSUT()` - System Under Test Factory
```swift
func makeSUT() -> (SUT, MockLocationServicesUseCase, MockWiFiConnectionUseCase) {
    let locationUseCase = MockLocationServicesUseCase()
    let wifiUseCase = MockWiFiConnectionUseCase()
    let useCase = LocationAwareWiFiConnectionUseCase(
        locationUseCase: locationUseCase,
        decoratedUseCase: wifiUseCase
    )
    return (useCase, locationUseCase, wifiUseCase)
}
```

**Purpose:**
- Centralizes object creation and dependency injection
- Hides complex setup logic from test methods
- Provides ready-to-use system under test with dependencies
- Ensures consistent setup across all tests

#### `expectAvailableNetworks()` - Behavior Verification
```swift
func expectAvailableNetworks(
    _ expectedResults: [AvailableWifiNetworksElement<MockNetwork>],
    of sut: SUT,
    locationUseCase: MockLocationServicesUseCase,
    wifiUseCase: MockWiFiConnectionUseCase,
    after action: () async throws -> Void,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws
```

**Purpose:**
- Encapsulates complex async sequence testing logic
- Handles result collection, timing coordination, and cleanup
- Provides simple assertion interface for business behavior
- Manages test lifecycle (setup → execute → verify → cleanup)
- Passes source location for accurate test failure reporting

#### `makeNetwork()` - Test Data Factory
```swift
func makeNetwork(
    id: String = UUID().uuidString,
    name: String = UUID().uuidString,
    isSecure: Bool = Bool.random(),
    signalStrength: WiFiSignalStrength = .allCases.randomElement() ?? .medium
) -> MockNetwork
```

**Purpose:**
- Eliminates boilerplate test data creation
- Provides sensible random defaults
- Allows customization when specific values matter
- Keeps tests focused on behavior, not data setup

#### `makeError()` - Error Factory with Smart Defaults
```swift
func makeError(
    domain: String = UUID().uuidString,
    code: Int = Int.random(in: 1...9999),
    userInfo: [String: Any]? = nil
) -> NSError {
    return NSError(domain: domain, code: code, userInfo: userInfo)
}

// Specific error factory for cases where domain/code matter
func makeAuthError() -> NSError {
    return NSError(domain: "com.apple.wifi.apple80211API.error", code: -3900, userInfo: nil)
}
```

**Purpose:**
- Can be used if we use untyped throws
- Centralizes error creation in test doubles and test scenarios
- Uses random values for irrelevant error properties (domain, code)
- Provides specific factories only when error details are verified in tests
- Eliminates hardcoded error values scattered throughout test code

**Usage Patterns:**
```swift
// Generic errors for failure injection (most common case)
wifiClientSpy.startMonitoringResult = .failure(makeError())
interfaceSpy.scanForNetworksResult = .failure(makeError())

// Specific errors when domain/code are checked in test logic
interfaceSpy.associateResult = .failure(makeAuthError())

// Test verifies specific error details
do {
    try await sut.connect(to: network, password: "wrong")
    Issue.record("Expected authentication error")
} catch WifiConnectionError.incorrectCredentials(let networkName) {
    #expect(networkName == "TestNetwork") // Only then we need specific error
}
```

**Benefits:**
- **Reduced Coupling**: Tests don't depend on irrelevant error properties
- **Better Isolation**: Random errors ensure tests fail only for intended reasons  
- **Focused Specificity**: Specific error factories only where error content is validated
- **Easier Maintenance**: Single location for error creation logic
- **Cleaner Test Code**: Less boilerplate error construction in test methods

### Benefits of Helper Method Strategy

1. **Business Logic Focus**: Test methods read like business requirements
2. **Implementation Independence**: Tests don't break when internal implementation changes
3. **Reduced Duplication**: Common setup/teardown logic centralized
4. **Easier Maintenance**: Changes to test infrastructure isolated to helper methods
5. **Improved Readability**: Tests tell a clear story without technical noise

### Naming Helpers and Fixtures for Readability

When tests describe geospatial behaviour (e.g. map rendering), raw literals such as `0.0015` or `MKCoordinateRegion(center: ..., span: ...)` make scenarios hard to parse. Pair helper methods with **named fixtures** so the test body reads like prose.

- **Prefer descriptive constants** for coordinates or values that encode intent. Example:
  ```swift
  private let viennaCoordinate = CLLocationCoordinate2D(latitude: 48.2082, longitude: 16.3738)
  private let equatorWideRegion = MKCoordinateRegion(
      center: .init(latitude: 0.0015, longitude: 0.0),
      span: .init(latitudeDelta: 0.05, longitudeDelta: 0.05)
  )
  ```
  Test readers immediately understand the city/region without decoding raw doubles.

- **Wrap value creation in helpers** when multiple tests share the same pattern. Example:
  ```swift
  private func expectFenceItems(
      _ items: [FenceItem],
      match fences: [Fence],
      SourceLocation location: SourceLocation = #_sourceLocation
  ) {
      // Compares identifiers, coordinates, and technologies – not just count
  }
  ```
  This keeps assertions focused on behaviour (“the same fences are visible”) and enforces richer checks than `.count` comparisons.

- **Use `SourceLocation = #_sourceLocation`** in helpers that wrap expectations so failures still point to the calling test line. This mirrors `Testing`’s preferred style and avoids sprinkling `file:line:` parameters.

- **Explain intent in naming**: e.g. `farRegion` vs. `nearRegion`, `broadRegion`, `zeroSpanRegion`. The actual values can change, but the behaviour under test remains obvious.

Consistently applying these patterns makes scenario set-up self-documenting and reduces the mental load when maintaining complex suites (map rendering, network coverage, etc.).

## Test Doubles Strategy

### Spy Implementation Patterns

We use **Spy objects** that allow inspection of method calls and controlled behavior simulation. Spies follow specific patterns for tracking interactions and injecting responses.

#### Core Spy Patterns

##### 1. **Call Count Tracking**
Use `<methodName>CallCount: Int` properties to track how many times methods are called:

```swift
final class WiFiConnectionUseCaseSpy: WiFiConnectionUseCase {
    // Track method call counts
    var availableNetworksCallCount = 0
    var disconnectCallCount = 0
    
    func availableNetworks() throws -> AsyncStream<AvailableWifiNetworksElement<TestNetwork>> {
        availableNetworksCallCount += 1
        // Implementation
    }
    
    func disconnect() async throws(WifiDisconnectionError) {
        disconnectCallCount += 1
        // Implementation
    }
}
```

##### 2. **Parameter Capture with Arrays**
Use `captured<ParameterName>` arrays to track parameters passed to methods. Always use arrays to track both values and call frequency:

```swift
final class WiFiConnectionUseCaseSpy: WiFiConnectionUseCase {
    struct ConnectParameters: Equatable {
        let network: TestNetwork
        let password: String?
    }
    
    // Capture method parameters in arrays
    var capturedConnectParameters: [ConnectParameters] = []
    
    func connect(to network: TestNetwork, password: String?) async throws(WifiConnectionError) {
        capturedConnectParameters.append(.init(network: network, password: password))
        // Process injected result
        try connectionResult.get()
    }
}
```

**Important**: If you're capturing parameters for a method, you don't need a separate `callCount` property since `capturedParameters.count` provides the same information.

##### 3. **Result Injection with simulate Methods**
Use `func simulate<ActionName>()` methods to control returned values and trigger async events:

```swift
final class WiFiConnectionUseCaseSpy: WiFiConnectionUseCase {
    private var continuations: [AsyncStream<AvailableWifiNetworksElement<TestNetwork>>.Continuation] = []
    
    // Simulation methods for controlled behavior
    func simulateNetworkUpdate(with networks: [TestNetwork]) async {
        for continuation in continuations {
            continuation.yield(.networks(Set(networks)))
        }
        await Task.yield() // Coordination
    }
    
    func simulateScanningIssue(_ issue: WiFiScanningIssue) async {
        for continuation in continuations {
            continuation.yield(.scaningIssue(issue))
        }
        await Task.yield() // Coordination
    }
}
```

##### 4. **Result Type for Success/Failure Injection**
Use `Result` types with `try result.get()` pattern to inject both success and failure scenarios:

```swift
final class WiFiConnectionUseCaseSpy: WiFiConnectionUseCase {
    // Injectable results for testing different scenarios
    var connectionResult: ActionResult<Void, WifiConnectionError> = .success(())
    var disconnectionResult: ActionResult<Void, WifiDisconnectionError> = .success(())
    
    func connect(to network: TestNetwork, password: String?) async throws(WifiConnectionError) {
        capturedConnectParameters.append(.init(network: network, password: password))
        connectionResult.onProgress() // Execute any progress callbacks
        try connectionResult.get() // Throw or return based on injected result
    }
}

// Usage in tests
useCase.connectionResult = .success(())
await sut.onConnect() // Will succeed

useCase.connectionResult = .failure(.incorrectCredentials(networkName: "TestWiFi"))
await sut.onConnect() // Will throw the specified error
```

##### 5. **Continuation Storage for Async Streams**
Store continuation objects to enable controlled yielding of values through simulate methods:

```swift
final class WiFiConnectionUseCaseSpy: WiFiConnectionUseCase {
    private var continuations: [AsyncStream<AvailableWifiNetworksElement<TestNetwork>>.Continuation] = []
    
    func availableNetworks() throws -> AsyncStream<AvailableWifiNetworksElement<TestNetwork>> {
        availableNetworksCallCount += 1
        return AsyncStream<AvailableWifiNetworksElement<TestNetwork>> { continuation in
            self.continuations.append(continuation)
        }
    }
    
    // Use stored continuations to yield values
    func simulateNetworkUpdate(with networks: [TestNetwork]) async {
        for continuation in continuations {
            continuation.yield(.networks(Set(networks)))
        }
        await Task.yield()
    }
}
```

#### Complete Spy Example

```swift
final class WiFiConnectionUseCaseSpy: WiFiConnectionUseCase {
    struct ConnectParameters: Equatable {
        let network: TestNetwork
        let password: String?
    }

    // Call count tracking (only for methods without parameter capture)
    var availableNetworksCallCount = 0
    var disconnectCallCount = 0
    
    // Parameter capture arrays
    var capturedConnectParameters: [ConnectParameters] = []
    
    // Result injection
    var connectionResult: ActionResult<Void, WifiConnectionError> = .success(())
    var disconnectionResult: ActionResult<Void, WifiDisconnectionError> = .success(())
    
    // Async stream control
    private var continuations: [AsyncStream<AvailableWifiNetworksElement<TestNetwork>>.Continuation] = []
    
    // Property simulation
    var currentNetworkName: String?

    func availableNetworks() throws -> AsyncStream<AvailableWifiNetworksElement<TestNetwork>> {
        availableNetworksCallCount += 1
        return AsyncStream<AvailableWifiNetworksElement<TestNetwork>> { continuation in
            self.continuations.append(continuation)
        }
    }

    func connect(to network: TestNetwork, password: String?) async throws(WifiConnectionError) {
        capturedConnectParameters.append(.init(network: network, password: password))
        connectionResult.onProgress()
        try connectionResult.get()
    }

    func disconnect() async throws(WifiDisconnectionError) {
        disconnectCallCount += 1
        disconnectionResult.onProgress()
        try disconnectionResult.get()
    }
    
    // Simulation methods
    func simulateNetworkUpdate(with networks: [TestNetwork]) async {
        for continuation in continuations {
            continuation.yield(.networks(Set(networks)))
        }
        await Task.yield()
    }

    func simulateScanningIssue(_ issue: WiFiScanningIssue) async {
        for continuation in continuations {
            continuation.yield(.scaningIssue(issue))
        }
        await Task.yield()
    }
}
```

#### Usage in Tests

```swift
@Test("When user connects to network then connection parameters are captured")
func whenConnectToNetwork_thenConnectionParametersAreCaptured() async throws {
    let network = makeNetwork(ssid: "TestWiFi", isSecure: true)
    let password = "password123"
    let (sut, useCase) = makeSUT()
    
    // Inject success result
    useCase.connectionResult = .success(())
    
    await sut.connect(to: network, password: password)
    
    // Verify method was called with correct parameters
    #expect(useCase.capturedConnectParameters == [
        .init(network: network.domain, password: password)
    ])
}

@Test("When connection fails then error is propagated")
func whenConnectionFails_thenErrorIsPropagated() async throws {
    let (sut, useCase) = makeSUT()
    
    // Inject failure result
    useCase.connectionResult = .failure(.incorrectCredentials(networkName: "TestWiFi"))
    
    do {
        try await sut.connect(to: network, password: "wrong")
        Issue.record("Expected connection to fail")
    } catch WifiConnectionError.incorrectCredentials(let name) {
        #expect(name == "TestWiFi")
    }
}

@Test("When multiple network updates occur then all are delivered")
func whenMultipleNetworkUpdates_thenAllAreDelivered() async throws {
    let networks1 = [makeNetwork(ssid: "WiFi1")]
    let networks2 = [makeNetwork(ssid: "WiFi2")]
    let (sut, useCase) = makeSUT()
    
    await sut.startScanning()
    
    // Simulate multiple updates
    await useCase.simulateNetworkUpdate(with: networks1)
    await useCase.simulateNetworkUpdate(with: networks2)
    
    #expect(sut.availableNetworks.count == 1)
    #expect(sut.availableNetworks.first?.ssid == "WiFi2")
}
```

### Mock Objects with Controlled Behavior (Alternative Pattern)

For simpler scenarios where you only need controlled responses without call inspection, use **mock objects**:

```swift
class MockLocationServicesUseCase: LocationServicesAuthorizationStatusUseCase {
    func simulateLocationAuthorizationChanged(to status: LocationAuthorizationStatus) async throws {
        // Controlled simulation of location status changes
    }
}
```

### Key Principles

#### 1. **Deterministic Event Ordering**
- Controlled timing with minimal coordination
- Predictable async sequence behavior
- Reliable test execution

#### 2. **Business-Focused Interface**
- Methods named for business actions (`simulateLocationAuthorizationChanged`)
- Hide technical implementation details
- Express test scenarios in domain language

#### 3. **Complete Call Inspection**
- Track all method calls with call counts or parameter capture
- Verify exact interactions between components
- Assert both that methods were called and with correct parameters

#### 4. **Flexible Result Injection**
- Support both success and failure scenarios
- Allow dynamic result changes during test execution
- Enable testing of error handling paths

### Test Double Benefits

1. **Isolation**: Tests run independently without external dependencies
2. **Speed**: No real network calls or system interactions
3. **Reliability**: Deterministic behavior eliminates flaky tests
4. **Control**: Precise simulation of edge cases and error conditions
5. **Clarity**: Business-focused mock methods improve test readability
6. **Verification**: Complete inspection of component interactions
7. **Flexibility**: Dynamic behavior injection for comprehensive testing

## Example: Complete Test Structure

```swift
func whenLocationReEnabledAfterDisabled_thenAvailableNetworksDeliversNetworkUpdatesAgain() async throws {
    // Arrange: Simple test data creation
    let networks1 = Set([makeNetwork()])
    let networks2 = Set([makeNetwork(), makeNetwork()])
    let (sut, locationUseCase, wifiUseCase) = makeSUT()

    // Act & Assert: Business behavior verification
    try await expectAvailableNetworks(
        [
            .networks(networks1),
            .scaningIssue(.locationServicesNotAvailable),
            .networks(networks2)
        ],
        of: sut,
        locationUseCase: locationUseCase,
        wifiUseCase: wifiUseCase
    ) {
        // Business scenario execution
        try await locationUseCase.simulateLocationAuthorizationChanged(to: .enabled)
        try await wifiUseCase.simulateAvailableNewtworksUpdated(with: networks1)
        try await locationUseCase.simulateLocationAuthorizationChanged(to: .disabled)
        try await locationUseCase.simulateLocationAuthorizationChanged(to: .enabled)
        try await wifiUseCase.simulateAvailableNewtworksUpdated(with: networks2)
    }
}
```

## Test File Structure and Organization

All unit test files must follow this standardized structure for consistency and maintainability:

### 1. Test Suites with Test Cases (Top Section)

#### Organizing Tests into Logical Suites

Group related tests into separate inner suites instead of using MARK comments. This provides better organization, clearer test reporting, and logical separation of concerns:

```swift
// MARK: - Test Suites

@Suite("MyComponent Tests")
struct MyComponentTests {
    @Suite("Initial State Tests")
    struct InitialStateTests {
        @Test("When component is initialized then initial state is correct")
        func whenComponentIsInitialized_thenInitialStateIsCorrect() async throws {
            let (sut, dependency) = makeSUT()
            // Test implementation
        }
        
        @Test("When initialized with custom config then config is applied")
        func whenInitializedWithCustomConfig_thenConfigIsApplied() async throws {
            let (sut, dependency) = makeSUT(config: makeCustomConfig())
            // Test implementation
        }
    }
    
    @Suite("State Change Tests")
    struct StateChangeTests {
        @Test("When state changes then observers are notified")
        func whenStateChanges_thenObserversAreNotified() async throws {
            let (sut, dependency) = makeSUT()
            // Test implementation
        }
        
        @Test("When multiple state changes occur then all changes are processed")
        func whenMultipleStateChangesOccur_thenAllChangesAreProcessed() async throws {
            let (sut, dependency) = makeSUT()
            // Test implementation
        }
    }
    
    @Suite("Error Handling Tests")
    struct ErrorHandlingTests {
        @Test("When error occurs then error is handled gracefully")
        func whenErrorOccurs_thenErrorIsHandledGracefully() async throws {
            let (sut, dependency) = makeSUT()
            // Test implementation
        }
    }
}
```

#### Benefits of Inner Suite Organization

1. **Better Test Reporting**: Test runners display results organized by suite, making it easier to understand which categories of functionality are passing or failing
2. **Logical Grouping**: Related tests are explicitly grouped together, improving code organization
3. **Clear Intent**: Suite names communicate the specific aspect of functionality being tested
4. **Easier Navigation**: Developers can quickly find tests related to specific features or scenarios
5. **Scalability**: Large test files remain manageable as functionality is compartmentalized into focused suites

#### Suite Naming Guidelines

- Use descriptive names that indicate the specific aspect being tested
- Common suite categories:
  - "Initial State Tests" - Tests for component initialization and default behavior
  - "State Change Tests" - Tests for how component responds to state changes
  - "Error Handling Tests" - Tests for error conditions and edge cases  
  - "Authorization Tests" - Tests for permission-related functionality
  - "Edge Case Tests" - Tests for boundary conditions and unusual scenarios
  - "Integration Tests" - Tests for component interactions

#### When to Use Inner Suites vs. MARK Comments

✅ **Use Inner Suites When:**
- You have 3+ tests covering the same functional area
- Tests share similar setup or scenarios
- You want better test reporting organization
- The test file is growing large and needs better structure

❌ **Use MARK Comments When:**
- Separating helper methods from test code
- Marking major structural sections (Test Suites, makeSUT, Test Doubles)
- Providing high-level file organization

### 2. makeSUT and Helper Factory Methods (Middle Section)
```swift
// MARK: - makeSUT and Helper Factory Methods

private func makeSUT() -> (SystemUnderTest, DependencySpy) {
    let dependencySpy = DependencySpy()
    let sut = SystemUnderTest(dependency: dependencySpy)
    return (sut, dependencySpy)
}

private func makeTestData(
    value: String = UUID().uuidString // Use random data whenever possible
) -> TestData {
    return TestData(value: value)
}
```

### 3. Test Doubles - Stubs, Spies (Bottom Section)  
```swift
// MARK: - Test Doubles

private final class DependencyStub: DependencyProtocol {
    // Stub implementation allows only to inject expected state, does not allow to inspect the called methods
}

private final class ObserverSpy: ObserverProtocol {
    // Spy implementation allows to inspect methods calls count or passed parameters
}
```

### Key Structure Rules

1. **Private Access Control**: All makeSUT functions, factory methods, mocks, and spies must be marked as `private`
2. **Free Functions**: makeSUT and factory methods should be standalone private functions, not extension methods
3. **Clear Separation**: Use MARK comments to clearly separate the three sections
4. **Consistent Ordering**: Always maintain the same order - Test Suites, makeSUT/Factories, Test Doubles

### Benefits of This Structure

- **Predictable Layout**: Every test file follows the same organization
- **Easy Navigation**: Developers know exactly where to find different types of code
- **Proper Encapsulation**: Private access control prevents test implementation leakage
- **Maintainability**: Changes to test infrastructure are isolated to appropriate sections

## Single Focused #expect vs Multiple Separate Assertions

### ✅ Preferred: Single Focused #expect for Related Properties

When testing multiple properties that are logically related and form a cohesive assertion, use a single `#expect` statement that tests the complete behavior:

```swift
// GOOD: Single assertion that tests the complete business logic
#expect(sut.fenceItems
    .map(\.id)
    .map { fenceId in
        sut.selectedFenceItem = sut.fenceItems.first { $0.id == fenceId }
        return sut.selectedFenceDetail?.averagePing ?? "(no detail selected)"
    } == [
        "1670 ms",  // t = 0 - 5
        "",         // t = 5 - 10
        "150 ms",   // t = 10 - 20
        "3000 ms",  // t = 20 - 30
        "1100 ms",  // t = 30 = 40
        "300 ms"    // t = 40+
    ]
)
```

**Benefits:**
- **Single Point of Failure**: If the test fails, it's clear that the entire ping assignment logic is broken
- **Complete Business Logic**: Tests the full behavior as a cohesive unit
- **Atomic Verification**: Ensures all related properties are consistent with each other
- **Clear Intent**: Shows exactly what the expected end-to-end behavior should be

### ❌ Avoid: Multiple Separate #expect for Related Properties

```swift
// BAD: Multiple assertions that fragment the business logic test
#expect(sut.fenceItems.count == 6)
for (index, expectedPing) in ["1670 ms", "", "150 ms", "3000 ms", "1100 ms", "300 ms"].enumerated() {
    sut.selectedFenceItem = sut.fenceItems[index]
    #expect(sut.selectedFenceDetail?.averagePing == expectedPing)
}
```

**Why this is problematic:**
- **Fragmented Logic**: Each assertion tests only a piece of the behavior
- **Multiple Failure Points**: Test could fail at any step, making it harder to understand the root cause
- **Incomplete Picture**: Early failures prevent verification of later behavior
- **More Complex**: Loop logic makes the test harder to read and understand

### When to Use Each Pattern

#### ✅ Use Single Focused #expect When:
- Testing related properties that form a complete business behavior
- The properties are logically connected and should be verified together
- You want to verify the entire state transformation as one unit
- The expected result represents a complete business outcome

#### ✅ Use Multiple #expect Statements When:
- Testing completely independent properties or behaviors
- Each assertion represents a separate business rule or requirement
- The properties are unrelated and can fail independently
- You need granular failure information for debugging different aspects

#### Example: Independent Properties (Multiple #expect is appropriate)
```swift
// GOOD: Independent properties that should be tested separately
#expect(sut.selectedFenceItem == nil)           // Selection state
#expect(sut.selectedFenceDetail == nil)         // Detail state  
#expect(sut.fenceItems.isEmpty)                 // Collection state
```

These represent three independent aspects of the initial state and should be verified separately.

## SUT Helper Methods for Business Logic Abstraction

### Creating Business-Focused Test Extensions

To improve test readability and future-proof tests against implementation changes, create helper methods on the System Under Test (SUT) that expose business behaviors while hiding concrete implementation details.

#### ✅ Preferred: Business Logic Helper Methods

Create extension methods on your SUT that abstract away framework-specific implementation details:

```swift
@MainActor extension NetworkCoverageViewModel {
    func startTest() async {
        await toggleMeasurement()
    }

    func simulateSelectFence(_ fence: Fence) {
        selectedFenceItem = fenceItems.first { $0.id == fence.id }
    }
}
```

**Usage in tests:**
```swift
@Test("WHEN valid fence ID is selected THEN fence is marked as selected and detail is populated")
func whenValidFenceIDIsSelected_thenFenceIsMarkedAsSelectedAndDetailIsPopulated() async throws {
    let fence1 = makeFence(at: 1.0, lon: 1.0)
    let fence2 = makeFence(at: 2.0, lon: 2.0)
    let sut = makeSUT(fences: [fence1, fence2])

    sut.simulateSelectFence(fence2)
    
    #expect(sut.selectedFenceItem?.id == fence2.id)
    #expect(sut.selectedFenceDetail?.id == fence2.id)
    #expect(sut.fenceItems.map(\.isSelected) == [false, true])
}
```

#### ❌ Avoid: Framework-Specific Implementation in Tests

```swift
// BAD: Test is coupled to SwiftUI implementation details
@Test func whenFenceIsSelected_thenStateUpdates() async throws {
    let fence = makeFence(at: 1.0, lon: 1.0)
    let sut = makeSUT(fences: [fence])

    // Directly manipulating SwiftUI binding - brittle and implementation-dependent
    sut.selectedFenceItem = sut.fenceItems.first { $0.id == fence.id }
    
    #expect(sut.selectedFenceItem?.id == fence.id)
}
```

### Benefits of SUT Helper Methods

#### 1. **Business Logic Focus**
- Tests express user intentions and business behaviors
- Hide technical implementation details (SwiftUI bindings, data transformations)
- Make tests readable to non-technical stakeholders

#### 2. **Implementation Independence**
- Tests remain stable when internal implementation changes
- Easy to refactor from SwiftUI to UIKit, or change data structures
- Framework updates don't break test logic

#### 3. **Semantic Clarity**
- Method names express business actions: `simulateSelectFence`, `startTest`
- Tests read like user stories or requirement specifications
- Clear intent for future developers maintaining the code

#### 4. **Reduced Redundancy**
- Eliminates repetitive setup code across multiple tests
- Centralizes complex object lookups and transformations
- Single point of change when business logic evolves

### Guidelines for SUT Helper Methods

#### ✅ Good Helper Method Examples

```swift
// Business action helpers
func simulateUserLogin(with credentials: UserCredentials)
func simulateNetworkDisconnection()
func simulateLocationPermissionGranted()
func simulateBackgroundAppTransition()

// State query helpers
func getCurrentSelectedItems() -> [Item]
func getVisibleNotifications() -> [Notification]
func isInOfflineMode() -> Bool
```

#### ❌ Poor Helper Method Examples

```swift
// BAD: Exposes implementation details
func setSelectedFenceItemToFirstMatchingId(_ id: UUID)
func triggerViewDidAppearLifecycle()
func simulateBindingValueChange()

// BAD: Too generic, doesn't express business intent  
func setValue(_ value: Any, forKey key: String)
func updateState()
func processData()
```

### Removing Redundant Assertions

When using SUT helper methods, also eliminate redundant `#expect` calls that are already covered by other test cases:

#### ✅ Before: Focused, Non-Redundant Assertions

```swift
@Test("WHEN selection is changed to different fence THEN previous fence is deselected and new one is selected")
func whenSelectionIsChangedToDifferentFence_thenPreviousFenceIsDeselectedAndNewOneIsSelected() async throws {
    let fence1 = makeFence(at: 1.0, lon: 1.0)
    let fence2 = makeFence(at: 2.0, lon: 2.0)
    let fence3 = makeFence(at: 3.0, lon: 3.0)
    let sut = makeSUT(fences: [fence1, fence2, fence3])
    
    sut.simulateSelectFence(fence1)
    sut.simulateSelectFence(fence3)

    // Only test the specific behavior - selection state changes
    #expect(sut.fenceItems.map(\.isSelected) == [false, false, true])
}
```

#### ❌ Avoid: Redundant Assertions Already Tested Elsewhere

```swift
// BAD: Too many redundant assertions
@Test func whenSelectionChanges_thenStateUpdates() async throws {
    let fence1 = makeFence(at: 1.0, lon: 1.0)
    let fence2 = makeFence(at: 2.0, lon: 2.0)
    let sut = makeSUT(fences: [fence1, fence2])
    
    sut.simulateSelectFence(fence1)
    
    // REDUNDANT: Count is already tested in initialization tests
    #expect(sut.fenceItems.count == 2)
    
    // REDUNDANT: Individual fence data is tested in other cases
    #expect(sut.fenceItems.first?.coordinate.latitude == 1.0)
    #expect(sut.fenceItems.last?.coordinate.latitude == 2.0)
    
    // FOCUS: Only this assertion is specific to selection behavior
    #expect(sut.fenceItems.map(\.isSelected) == [true, false])
}
```

### Implementation Strategy

#### 1. **Place Helper Methods in Test File Extensions**
```swift
// At the bottom of the test file, near test doubles
@MainActor extension NetworkCoverageViewModel {
    func simulateSelectFence(_ fence: Fence) {
        selectedFenceItem = fenceItems.first { $0.id == fence.id }
    }
    
    func simulateUserAction() async {
        await performBusinessAction()
    }
}
```

#### 2. **Name Methods by Business Intent**
- Use `simulate*` prefix for user actions
- Use `trigger*` prefix for system events
- Use descriptive business terms, not technical implementation details

#### 3. **Keep Methods Simple and Focused**
- Each helper should perform one clear business action
- Avoid complex logic that might need its own testing
- Focus on hiding implementation, not adding new behavior

### Real-World Impact

**Before (brittle, implementation-coupled):**
```swift
// Test breaks if SwiftUI binding implementation changes
sut.selectedFenceItem = sut.fenceItems.first { $0.id == fence.id }
```

**After (resilient, business-focused):**
```swift
// Test survives framework changes, focuses on behavior
sut.simulateSelectFence(fence)
```

This approach makes tests more maintainable, readable, and resilient to implementation changes while clearly expressing business requirements.

## Testing Asynchronous Code with Confirmation

### Using Swift Testing's `confirmation` for Async Stream Testing

When testing asynchronous streams and async sequences, use Swift Testing's `confirmation` function instead of `Task.sleep` patterns for more reliable and deterministic tests.

#### ❌ Bad Practice: Task.sleep Pattern
```swift
// Brittle, unreliable, and timing-dependent
@Test func whenInitializedWithEnabledStatus_thenStatusesStreamYieldsEnabledImmediately() async throws {
    let (sut, factory) = makeSUT(initialAuthorizationStatus: .authorized)
    
    var receivedStatuses: [LocationAuthorizationStatus] = []
    let statusTask = Task {
        for await status in sut.statuses {
            receivedStatuses.append(status)
            if receivedStatuses.count >= 1 { break }
        }
    }
    
    // BAD: Arbitrary timing - creates flaky tests
    try await Task.sleep(for: .milliseconds(10))
    statusTask.cancel()
    
    #expect(receivedStatuses == [.enabled])
}
```

**Why Task.sleep is problematic:**
- **Timing-dependent**: Tests may fail on slower systems or under load
- **Unreliable**: No guarantee that async operations complete within sleep duration
- **Flaky**: May pass locally but fail in CI/CD environments
- **Inefficient**: Wastes time waiting when events complete faster
- **Hard to debug**: Failures are intermittent and environment-dependent

#### ✅ Preferred: Helper Functions with Confirmation

Create reusable helper functions that encapsulate confirmation patterns for clean, maintainable tests:

```swift
// Robust helper function for async stream testing
func expect<Sequence: AsyncSequence>(
    statuses statusSequence: Sequence,
    deliver expectedStatuses: [LocationAuthorizationStatus],
    after action: (() async throws -> Void)? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws where Sequence == CoreLocationServicesAuthorizationStatusUseCase.StatusSequence {
    var capturedStatuses: [LocationAuthorizationStatus] = []
    await confirmation("Status stream delivers requested statuses", expectedCount: expectedStatuses.count) { confirmation in
        Task {
            try await action?()
        }
        for await status in statusSequence {
            capturedStatuses.append(status)
            confirmation()

            // Break out of endless loop when expected count reached
            if capturedStatuses.count >= expectedStatuses.count {
                break
            }
        }
    }
    #expect(capturedStatuses == expectedStatuses, sourceLocation: sourceLocation)
}

// Specialized helper for tests that need confirmation control
func expectWithConfirmation<Sequence: AsyncSequence>(
    statuses statusSequence: Sequence,
    deliver expectedStatuses: [LocationAuthorizationStatus],
    after action: @escaping (Confirmation) async -> Void,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws where Sequence == CoreLocationServicesAuthorizationStatusUseCase.StatusSequence {
    var capturedStatuses: [LocationAuthorizationStatus] = []
    await confirmation("Status stream delivers requested statuses", expectedCount: 1) { confirmation in
        Task {
            for await status in statusSequence {
                capturedStatuses.append(status)

                if capturedStatuses.count >= expectedStatuses.count {
                    break
                }
            }
        }
        await action(confirmation)
    }
    #expect(capturedStatuses == expectedStatuses, sourceLocation: sourceLocation)
}
```

#### Test Implementation Examples

**Simple async stream verification:**
```swift
@Test("WHEN initialized with enabled status THEN statuses stream yields enabled immediately")
func whenInitializedWithEnabledStatus_thenStatusesStreamYieldsEnabledImmediately() async throws {
    let (sut, factory) = makeSUT(initialAuthorizationStatus: .authorized)

    try await expect(statuses: sut.statuses, deliver: [.enabled])
    #expect(factory.locationManager.requestWhenInUseAuthorizationCallCount == 0)
}
```

**Multiple status changes with actions:**
```swift
@Test("WHEN authorization changes multiple times THEN statuses stream yields all changes")
func whenAuthorizationChangesMultipleTimes_thenStatusesStreamYieldsAllChanges() async throws {
    let (sut, factory) = makeSUT(initialAuthorizationStatus: .authorized)

    try await expect(
        statuses: sut.statuses,
        deliver: [.enabled, .disabled, .enabled, .disabled],
        after: {
            try await Task.yield()
            factory.locationManager.simulateDelegateDidChangeAuthorization(to: .denied)
            try await Task.yield()
            factory.locationManager.simulateDelegateDidChangeAuthorization(to: .authorized)
            try await Task.yield()
            factory.locationManager.simulateDelegateDidChangeAuthorization(to: .restricted)
        }
    )
}
```

**No initial status with confirmation control:**
```swift
@Test("WHEN initialized with notDetermined status THEN requests authorization and yields no initial status")
func whenInitializedWithNotDeterminedStatus_thenRequestsAuthorizationAndYieldsNoInitialStatus() async throws {
    let (sut, factory) = makeSUT(initialAuthorizationStatus: .notDetermined)

    try await expectWithConfirmation(statuses: sut.statuses, deliver: []) { confirmation in
        confirmation()
    }

    #expect(factory.locationManager.requestWhenInUseAuthorizationCallCount == 1)
}
```

### Confirmation Best Practices

#### 1. **Use Helper Functions for Common Patterns**
- Encapsulate confirmation logic in reusable helper functions
- Provide clean, business-focused test interfaces
- Handle complex async sequence iteration internally
- Enable consistent behavior verification across tests

#### 2. **Expected Count Management**
```swift
// For exact number of events
await confirmation("Multiple status changes", expectedCount: 3) { confirmation in
    // Will complete after exactly 3 confirmations
}

// For single confirmation with manual control
await confirmation("Single event", expectedCount: 1) { confirmation in
    // Manually call confirmation() when condition is met
}
```

#### 3. **Natural Loop Termination**
```swift
// Break out of potentially infinite async sequences
for await status in statusSequence {
    capturedStatuses.append(status)
    confirmation()

    if capturedStatuses.count >= expectedStatuses.count {
        break  // Prevent hanging on endless streams
    }
}
```

### Source Location Propagation in Helper Methods

When creating helper methods with `#expect` calls, always include `sourceLocation: SourceLocation = #_sourceLocation` parameter to ensure test failures are reported at the correct line in your test code:

```swift
func expectNetworkStatus(
    _ expectedStatus: NetworkStatus,
    from stream: AsyncStream<NetworkStatus>,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    // Test logic here
    #expect(actualStatus == expectedStatus, sourceLocation: sourceLocation)
}
```

**Why Source Location Matters:**
- **Accurate Failure Reporting**: Test failures show the exact line in your test method, not inside the helper
- **Better Debugging**: Developers immediately know which test assertion failed
- **Consistent with XCTest**: Similar to `#file` and `#line` parameters in XCTest assertions

### Direct Test Failures with Issue.record

For immediate test failure without using `#expect`, use `Issue.record`:

```swift
func validatePrecondition(
    condition: Bool,
    message: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    if !condition {
        Issue.record("Precondition failed: \(message)", sourceLocation: sourceLocation)
    }
}
```

**When to Use Issue.record:**
- **Precondition Failures**: When setup conditions aren't met
- **Custom Validation**: For complex validation logic that doesn't fit `#expect`
- **Early Termination**: When test should fail immediately without continuing

### Key Benefits of Confirmation Pattern

1. **Deterministic**: Waits for actual events rather than arbitrary timeouts
2. **Reliable**: Built-in timeout prevents hanging tests
3. **Clear Intent**: Test clearly expresses what event it's waiting for
4. **Resource Efficient**: No unnecessary task cancellation in most cases
5. **Better Error Messages**: Clear failure messages when events don't occur
6. **Fast Execution**: Completes as soon as expected conditions are met
7. **CI/CD Friendly**: Consistent behavior across different environments
8. **Accurate Failure Location**: Source location propagation ensures failures point to correct test lines

## Custom Test Debug Descriptions

### Improving Test Failure Output with Custom String Representations

When test assertions fail, Swift Testing and Xcode display object descriptions to help debug the failure. By default, Swift objects show minimal information, making it difficult to understand what went wrong. Implementing custom debug descriptions significantly improves the debugging experience.

#### The Problem: Poor Default Debug Output

Without custom descriptions, test failures show uninformative output:

```swift
// Poor default output in test failures:
#expect(actualNetworks == expectedNetworks)
// Failure: NetworkModel(id: UUID, ssid: "WiFi", ...) != NetworkModel(id: UUID, ssid: "WiFi", ...)
```

This makes it nearly impossible to understand what the actual difference is between objects.

#### The Solution: CustomTestStringConvertible and CustomDebugStringConvertible

Implement both protocols to ensure custom descriptions appear in all contexts:

```swift
// MARK: - SwiftTesting Debug Support

extension NetworkModel: CustomTestStringConvertible, CustomDebugStringConvertible {
    public var debugDescription: String { testDescription }

    public var testDescription: String {
        let idPrefix = String(id.prefix(6))
        let lockIcon = isSecure ? "🔒" : ""
        let connectingStatus = isConnecting ? "connecting" : ""
        let connectedStatus = isConnected ? "connected" : ""
        let selectedStatus = isSelected ? "selected" : ""
        
        let statuses = [connectingStatus, connectedStatus, selectedStatus, lockIcon].filter { !$0.isEmpty }
        let statusString = statuses.isEmpty ? "" : " [\(statuses.joined(separator: ", "))]"
        
        return "NetworkModel(\(idPrefix), \"\(ssid)\"\(statusString))"
    }
}
```

#### Why Both Protocols Are Required

- **`CustomTestStringConvertible`**: Used by Swift Testing framework for test output
- **`CustomDebugStringConvertible`**: Used by Xcode's inline test result display and console output
- **Implementation**: Both should return the same string via a shared `testDescription` property

#### Best Practices for Test Debug Descriptions

##### 1. **Include Key Identifying Information**
```swift  
// Good: Shows the most important identifying fields
"NetworkModel(a1b2c3, "MyWiFi" [connected, selected, 🔒])"

// Bad: Too much irrelevant detail
"NetworkModel(id: a1b2c3d4-e5f6-1234-5678-9abcdef01234, ssid: MyWiFi, isSecure: true, isConnecting: false, isConnected: true, isSelected: true, signalStrength: high)"
```

##### 2. **Use Shortened IDs**
```swift
// Truncate long IDs to first 6 characters for readability
let idPrefix = String(id.prefix(6))
return "NetworkModel(\(idPrefix), \"\(ssid)\")"
```

##### 3. **Show State with Visual Indicators**
```swift
// Use emojis and concise state descriptions
let lockIcon = isSecure ? "🔒" : ""
let statuses = [connectingStatus, connectedStatus, selectedStatus, lockIcon]
    .filter { !$0.isEmpty }
let statusString = statuses.isEmpty ? "" : " [\(statuses.joined(separator: ", "))]"
```

##### 4. **Prioritize Relevant Information**
```swift
// Show only states that are true, filter out false/empty values
let statuses = [connectingStatus, connectedStatus, selectedStatus, lockIcon]
    .filter { !$0.isEmpty }  // Only include non-empty status strings
```

#### Example: Before and After

**Before (default output):**
```
Test failed: #expect(sut.availableNetworks == [network1.presentation, network2.presentation.selected])

Expected: [TruUHelpers.NetworkModel, TruUHelpers.NetworkModel]
Actual: [TruUHelpers.NetworkModel, TruUHelpers.NetworkModel]
```

**After (custom descriptions):**
```
Test failed: #expect(sut.availableNetworks == [network1.presentation, network2.presentation.selected])

Expected: [NetworkModel(a1b2c3, "AWiFi"), NetworkModel(d4e5f6, "BWiFi" [selected, 🔒])]
Actual: [NetworkModel(a1b2c3, "AWiFi"), NetworkModel(d4e5f6, "BWiFi" [🔒])]
```

The custom description immediately shows that the second network is missing the "selected" state.

#### Implementation Guidelines

##### 1. **Placement in Test Files**
Place custom debug extensions in a dedicated section at the end of test files:

```swift
// MARK: - SwiftTesting Debug Support

extension NetworkModel: CustomTestStringConvertible, CustomDebugStringConvertible {
    // Implementation here
}
```

##### 2. **Shared Implementation Pattern**
```swift
extension YourModel: CustomTestStringConvertible, CustomDebugStringConvertible {
    public var debugDescription: String { testDescription }
    
    public var testDescription: String {
        // Single implementation used by both protocols
        return "YourModel(\(key), \(importantProperty))"
    }
}
```

##### 3. **Focus on Test-Relevant Information**
- Include properties that are commonly asserted in tests
- Exclude implementation details not relevant to test verification
- Use concise, scannable format for quick visual comparison

#### Complete Example

```swift
// Model being tested
struct UserProfile {
    let id: UUID
    let username: String
    let isVerified: Bool
    let isPremium: Bool
    let lastLogin: Date?
}

// Custom debug description for testing
extension UserProfile: CustomTestStringConvertible, CustomDebugStringConvertible {
    public var debugDescription: String { testDescription }
    
    public var testDescription: String {
        let idPrefix = String(id.uuidString.prefix(6))
        let verifiedIcon = isVerified ? "✓" : ""
        let premiumIcon = isPremium ? "⭐" : ""
        let loginStatus = lastLogin != nil ? "active" : "inactive"
        
        let badges = [verifiedIcon, premiumIcon, loginStatus].filter { !$0.isEmpty }
        let badgeString = badges.isEmpty ? "" : " [\(badges.joined(separator: ", "))]"
        
        return "UserProfile(\(idPrefix), \"\(username)\"\(badgeString))"
    }
}

// Test output becomes readable:
// Expected: [UserProfile(a1b2c3, "john_doe" [✓, active])]
// Actual: [UserProfile(a1b2c3, "john_doe" [✓, ⭐, active])]
```

### Benefits of Custom Test Debug Descriptions

1. **Faster Debugging**: Immediately understand what differs between expected and actual values
2. **Better Test Maintenance**: Easier to understand test failures when refactoring
3. **Improved Team Productivity**: Other developers can quickly grasp test failure causes
4. **Reduced Investigation Time**: No need to set breakpoints just to see object state
5. **Self-Documenting Tests**: Test output clearly shows the business logic being verified

## Task.sleep vs Task.yield: When and Why

#### ❌ Avoid Task.sleep in Tests
```swift
// BAD: Arbitrary delays make tests unreliable
try await Task.sleep(for: .milliseconds(100))  // Don't do this
try await Task.sleep(nanoseconds: 1_000_000)   // Or this
```

**Why Task.sleep is problematic in tests:**
- Creates timing dependencies that vary by system performance
- Makes tests slower than necessary
- Introduces flakiness in CI/CD environments
- Doesn't guarantee that the awaited condition has actually occurred

#### ✅ Limited Use of Task.yield/Task.sleep
```swift
// ACCEPTABLE: Strategic yielding for async coordination
try await Task.yield()  // Allow other tasks to run
try await Task.sleep(for: .milliseconds(1)) // Give little time to run other tasks
```

**When Task.yield/Task.sleep is acceptable:**
- **Async coordination**: Allowing other concurrent tasks to execute their work
- **Event sequence ordering**: Ensuring delegate callbacks complete before next action
- **Resource yielding**: Giving system time to process pending async operations

**Example from current implementation:**
```swift
try await expect(
    statuses: sut.statuses,
    deliver: [.enabled, .disabled, .enabled, .disabled],
    after: {
        try await Task.sleep(for: .milliseconds(1))  // Let initial status propagate
        factory.locationManager.simulateDelegateDidChangeAuthorization(to: .denied)
        try await Task.sleep(for: .milliseconds(1))  // Let status change propagate
        factory.locationManager.simulateDelegateDidChangeAuthorization(to: .authorized)
        try await Task.sleep(for: .milliseconds(1))  // Let status change propagate
        factory.locationManager.simulateDelegateDidChangeAuthorization(to: .restricted)
    }
)
```

#### ✅ Preferred: Event-Driven Testing
```swift
// BEST: Wait for actual conditions/events
await confirmation("Event occurs") { confirmation in
    // React to actual events, not time passage
}
```

### Migration Strategy

When refactoring from `Task.sleep` to `confirmation`:

1. **Identify the expected event**: What specific condition triggers test success?
2. **Replace timing with confirmation**: Remove `Task.sleep` and `task.cancel()`
3. **Use natural completion**: Return from async loop when condition is met
4. **Add descriptive messages**: Make test intent clear in confirmation description
5. **Keep strategic Task.yield**: Only where needed for async coordination, not timing

## Advanced Patterns and Edge Cases

### Multiple Concurrent Async Streams

**Challenge**: Testing scenarios where multiple async streams run concurrently (e.g., multiple subscribers to the same service).

**❌ Problematic: Confirmation with Concurrent Streams**
```swift
// This pattern doesn't work reliably with multiple concurrent streams
try await confirmation("All subscribers receive networks", expectedCount: sequences.count) { confirmation in
    for (index, sequence) in sequences.enumerated() {
        Task {
            for try await element in sequence {
                // Coordination issues between multiple Tasks
                confirmation()
            }
        }
    }
}
```

**✅ Recommended: Traditional Task Pattern for Concurrent Streams**
```swift
@Test("When multiple subscribers request networks then each receives updates")
func test_whenMultipleSubscribersRequest_thenEachReceivesUpdates() async throws {
    let networks = Set([makeNetwork(name: "SharedNetwork")])
    let (sut, _, interfaceSpy) = makeSUT()
    interfaceSpy.stubbedNetworks = networks
    
    let sequence1 = try sut.availableNetworks()
    let sequence2 = try sut.availableNetworks()
    
    var results1: [NetworkElement] = []
    var results2: [NetworkElement] = []
    
    let task1 = Task {
        for try await element in sequence1 {
            results1.append(element)
            if results1.count >= 1 { break }
        }
    }
    
    let task2 = Task {
        for try await element in sequence2 {
            results2.append(element)
            if results2.count >= 1 { break }
        }
    }
    
    // Small delay for async coordination only
    try await Task.sleep(for: .milliseconds(10))
    try await task1.value
    try await task2.value
    
    // Verify both subscribers received expected data
    #expect(results1.count == 1)
    #expect(results2.count == 1)
}
```

**When to Use Each Pattern:**
- **Confirmation**: Single async streams, sequential operations, event-driven testing
- **Task Pattern**: Multiple concurrent streams, complex async coordination, subscriber testing

### Error Testing with Swift Testing

**✅ Preferred: Use #expect(throws:) for Thrown Error Testing**

Swift Testing provides several approaches for testing thrown errors with `#expect(throws:)` that are cleaner and more reliable than do-catch blocks:

#### 1. Testing For Specific Error Type (When Equatable)
```swift
// If your error type conforms to Equatable
await #expect(throws: WifiConnectionError.generic) {
    try await sut.connect(to: network, password: "password")
}
```

#### 2. Testing That Any Error Is Thrown
```swift
// Test that any error is thrown
await #expect(throws: (any Error).self) {
    try await sut.connect(to: network, password: "password")
}
```

#### 3. Testing With Complex Error Requirements
```swift
// Test error with custom validation logic
await #expect {
    try await sut.connect(to: network, password: "wrongPassword")
} throws: { error in
    guard case WifiConnectionError.incorrectCredentials(let networkName) = error else {
        return false
    }
    return networkName == "SecureNetwork"
}
```

#### 4. Testing That No Error Is Thrown
```swift
// Explicitly test that no error occurs
await #expect(throws: Never.self) {
    try await sut.connect(to: network, password: "correctPassword")
}
```

**❌ Avoid: Do-Catch Blocks for Error Testing**
```swift
// OLD APPROACH - Don't use this pattern
do {
    try await sut.connect(to: network, password: "password")
    Issue.record("Expected WifiConnectionError.generic to be thrown")
} catch {
    if case WifiConnectionError.generic = error {
        // Expected error type - test passes
    } else {
        Issue.record("Expected WifiConnectionError.generic, got \(error)")
    }
}
```

**Why #expect(throws:) is Better:**
- **More Concise**: Less boilerplate code than do-catch blocks
- **Clearer Intent**: Immediately obvious what error behavior is being tested
- **Better Failure Messages**: Swift Testing provides clear error descriptions
- **Type Safety**: Compile-time verification of error types when possible
- **Consistent**: Follows the same pattern as other Swift Testing expectations

**Design Recommendation**: Consider adding `Equatable` conformance to custom error types to enable the cleanest test syntax:

```swift
enum WifiConnectionError: Error, Equatable {
    case generic
    case incorrectCredentials(String)
}

// Now this works cleanly:
await #expect(throws: WifiConnectionError.generic) {
    try await sut.connect(to: network, password: "password")
}
```

### Source Location Propagation in Complex Helpers

**Challenge**: Ensuring test failures are reported at the correct line when using nested helper methods.

**✅ Proper Source Location Chain**
```swift
// Main expectation helper
private func expectAvailableNetworks(
    _ expectedElements: [NetworkElement],
    from sut: UseCase,
    after action: (() async throws -> Void)? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    // Implementation with confirmation...
    
    // Pass source location to validation helper
    try validateNetworkElements(received: receivedElements, 
                              expected: expectedElements, 
                              sourceLocation: sourceLocation)
}

// Validation helper that also propagates source location
private func validateNetworkElements(
    received: [NetworkElement],
    expected: [NetworkElement],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    #expect(received.count == expected.count, sourceLocation: sourceLocation)
    
    for (index, expectedElement) in expected.enumerated() {
        // All assertions use propagated source location
        validateElement(received[index], expected: expectedElement, 
                       at: index, sourceLocation: sourceLocation)
    }
}
```

**Key Principle**: Always propagate `sourceLocation` through the entire chain of helper methods to ensure failures point to the actual test line, not helper internals.

### Async Coordination Timing

**✅ Strategic Use of Minimal Delays**
```swift
// Acceptable: Minimal delays for async coordination
try await expectAvailableNetworks(
    [.networks(networks), .networks(updatedNetworks)],
    from: sut,
    after: {
        try await Task.sleep(for: .milliseconds(1))  // Let initial scan complete
        sut.triggerNetworkUpdate()
    }
)
```

**Guidelines for Task.sleep Usage:**
- **1ms delays**: For async coordination between operations
- **10ms+ delays**: Only for testing cleanup/deallocation scenarios
- **Never use**: Arbitrary delays as primary test synchronization mechanism

## Summary

These strategies create tests that are:
- **Business-focused**: Express requirements in domain language
- **Maintainable**: Changes isolated to helper methods
- **Reliable**: Deterministic behavior with controlled dependencies and proper async testing
- **Readable**: Clear intent without implementation noise
- **Fast**: No external dependencies or real system interactions
- **Well-Organized**: Consistent structure across all test files
- **Robust**: Proper async testing with confirmation patterns
- **Flexible**: Appropriate patterns for different async scenarios

The result is a test suite that serves as living documentation of business requirements while remaining robust to implementation changes and capable of handling complex async scenarios reliably.
