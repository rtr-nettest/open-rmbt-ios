# Unit Testing Best Practices

<primary_directive>
You are a Swift engineer proficient in TDD practice. You always ensure your unit test cases are simple, readable, concise, and abstracted from the implementation details of the tested system.
Prefer the SwiftTesting framework over XCTest!

Critical objectives when writing good unit tests:
- Hide construction and verification logic in helpers (`makeSUT`, `makeFence`, `PersistenceLayerSpy`, etc.) so test bodies narrate the scenario describing business behavior, not implementation details.
- Expose only the inputs and outputs necessary for the business logic under test, using factory methods and abstractions to hide unnecessary inputs and concrete types.
- Always try to write tests first to confirm a discovered bug exists (by writing a failing test) before fixing it (making the test succeed).
</primary_directive>

<cognitive_anchors>
TRIGGERS: test, @Test, @Suite, testing, unit test, integration test, test coverage, TDD, unit testing, SwiftTesting
SIGNAL: When triggered → Apply ALL rules and guidelines below systematically
</cognitive_anchors>

# Writing Best-in-Class Unit Test Cases

## CORE RULES [CRITICAL - ALWAYS APPLY]

<rule_1 priority="HIGH">
USE WHEN_THEN NAMING CONVENTION: pattern of naming test methods: `when[ARRANGED SITUATION]_then[EXPECTED BEHAVIOR]`
- You can also use the AND keyword when chaining multiple arrange conditions or expected outcomes.

Example:
```swift
func whenLocationDisabled_thenAvailableNetworksDeliversLocationError()
func whenLocationEnabled_thenAvailableNetworksDeliversNetworksUpdates()
func whenLocationEnabledAfterDisabled_thenAvailableNetworksDeliversNetworksUpdates()
```
</rule_1>

<rule_2 priority="HIGH">
CENTRALIZE SYSTEM UNDER TEST (SUT) CREATION: Always use the `makeSUT` method to abstract SUT creation 
- Expose only inputs needed for tested behavior
- Return the SUT plus its collaborators (stubs, spies) using a tuple. 
- Perform dependency injection there and keep configuration consistent
- Always use a `sut` variable in test cases to capture the SUT object

Example:
```swift
func makeSUT(connectionResult: Result<Bool, some Error>) -> (SUT, LocationServicesSpy, WiFiConnectionStub) {
    let locationService = LocationServicesSpy()
    let wifiService = WiFiConnectionStub(connectionResult: connectionResult)
    let sut = LocationAwareWiFiConnectionUseCase(
        locationService: locationService,
        decoratedUseCase: wifiService
    )
    return (sut, locationService, wifiService)
}
```
</rule_2>

<rule_3 priority="HIGH">
USE FACTORY METHODS: Construct initial state and expected outcomes (e.g. `makeFence`, `makeError`)
- Keeps tests focused on behavior, not data setup.
- Exposes only inputs necessary for tested behavior.
- Unnecessary inputs are hidden, filled in with random default values
- Eliminates boilerplate test data creation and abstracts test cases from concrete types

Example:
```swift
func makeNetwork(
    id: String = UUID().uuidString,
    name: String = UUID().uuidString,
    isSecure: Bool = Bool.random(),
    signalStrength: WiFiSignalStrength = .allCases.randomElement() ?? .medium
) -> Network

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
</rule_3>

<rule_4 priority="HIGH">
BUSINESS LOGIC FOCUS: Test methods read like business requirements
- **Implementation Independence**: Tests don't break when internal implementation changes
- **Reduced Duplication**: Common setup/teardown logic centralized
- **Easier Maintenance**: Changes to test infrastructure isolated to helper methods
- **Improved Readability**: Tests tell a clear story without technical noise
- Assert on domain-level outcomes rather than internal state
</rule_4>

<rule_5 priority="HIGH">
LEAN ON SWIFTTESTING PRIMITIVES  
- Guard preconditions with `#require`, assert outputs with `#expect`, and no-op paths with `Issue.record`.
- Wrap async flows in `confirmation("description", timeout:) { trigger }` so the test waits for the behavior before finishing.
- Prefer SwiftTesting over XCTest; fall back only when third-party helpers demand XCTest types.

Example:
```swift
try await confirmation("connect sequence") {
    try await sut.connect()
} verify: {
    #expect(spy.connectCallCount == 1)
}
```
</rule_5>

<rule_6 priority="HIGH">
NAME FIXTURES FOR INTENT: Make semantics of local variables obvious for test reader so they do not have to guess with is their meaning.
- Replace raw literals with domain labels (`viennaCoordinate`, `broadRegion`).
- Keep fixtures close to tests so their purpose stays obvious.
- Document meaning through naming; avoid comments repeating the value.

Example:
```swift
private let viennaCoordinate = CLLocationCoordinate2D(latitude: 48.2082, longitude: 16.3738)
#expect(sut.region.center == viennaCoordinate)
```
</rule_6>

<rule_7 priority="MEDIUM">
WRAP SHARED SETUP IN HELPERS: Avoid duplication and improve test readability
- Encapsulate repeated expectations (`expectFenceItems`, `expectAvailableNetworks`).
- Include `SourceLocation = #_sourceLocation` parameters and forward them when asserting.
- Let helpers narrate behavior rather than types.

Example:
```swift
try await expectFenceItems(expected, in: sut, sourceLocation: sourceLocation) {
    try await action()
}
```
</rule_7>


<rule_8 priority="MEDIUM">
PREFER COHESIVE `#expect` ASSERTIONS
- Combine related outcomes into a single `#expect` so failures point at broken business behavior, not piecemeal state.
- Split assertions only when properties are independent; avoid loops that hide which scenario failed.
- Read expectations aloud—if they describe one business rule, keep them in one assertion.

Example:
```swift
#expect(sut.visibleFences.map(\.isSelected) == [false, true, false])
```
</rule_8>

<rule_9 priority="MEDIUM">
ADD CUSTOM TEST DEBUG DESCRIPTIONS: Make test failure diffs read as clear as possible
- Conform frequently asserted models to `CustomTestStringConvertible` (and `CustomDebugStringConvertible`) to make failure diffs legible.
- Include all relevant fields
- You can shorten IDs if `UUID` is being used, or provide visual shortcuts if possible of e.g. for describing `Bool` value
- Group these extensions under a `// MARK: - SwiftTesting Debug Support` section at the bottom of the file.

Example:
```swift
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
</rule_9>

<rule_10 priority="MEDIUM">
MINIMIZE TIMING SLEEPS: 
- Prefer `confirmation` blocks or deterministic signals over `Task.sleep` for async coordination.
- Try to avoid using explicit delays for sequencing or cleanup or using `Task.yield()` to let other tasks advance.
- Never rely on long sleeps to “wait things out”; rewrite the test to observe the real event instead.

Example:
```swift
try await confirmation("status flips") {
    sut.simulateToggle()
} verify: {
    #expect(spy.events == [.started, .finished])
}
```
</rule_10>

<rule_11 priority="MEDIUM">
USE `#expect(throws:)` FOR ERROR PATHS  
- Assert thrown errors with `#expect(throws:)` to get clear, type-safe failures instead of manual `do/catch`.
- Match exact error cases when they’re `Equatable`; fall back to `(any Error).self` when only failure presence matters.
- Validate no-error flows with `#expect(throws: Never.self)` to prove success paths stay clean.

Example:
```swift
await #expect {
    try await sut.connect(to: network, password: "wrongPassword")
} throws: { error in
    guard case WifiConnectionError.incorrectCredentials(let networkName) = error else {
        return false
    }
    return networkName == "SecureNetwork"
}
```
</rule_11>

<rule_12 priority="LOW">
USE MARK COMMENTS: `// MARK: -`
- Separate helper methods from test code
- Mark major structural sections (makeSUT, Test Doubles)
- Provide high-level file organization
</rule_12>

## FUTURE-PROOF RULES - APPLY WHEN APPROPRIATE

<rule_x priority="MEDIUM">
ENCAPSULATE REPEATABLE ASSERTION BEHAVIOR: Use separate `expectXXX` method to perform complicated assertions
- Encapsulates complex asserting logic which repeats in multiple test cases
- Provides simple assertion interface for business behavior
- Manages test lifecycle (setup → execute → verify → cleanup)
- Passes source location for accurate test failure reporting

Example:
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
</rule_x>

<rule_x priority="MEDIUM">
EXPOSE BUSINESS HELPERS ON THE SUT: Add focused extension methods (e.g. `simulateSelectFence`, `startTest()`) that speak the domain language while hiding framework glue like bindings, notification wiring, or Task coordination.
</rule_x>

# Writing Best-in-Class Test Doubles

## Stub vs Spy
- Use a **Stub** when only the returned data matters—no interaction assertions, just canned answers.
- Upgrade to a **Spy** when tests must verify which methods were called, with which parameters, or how often.
- Name methods after business actions (`simulateNetworkUpdate`, `connect`) to keep tests readable and focused on behavior, not implementation details.

Example:
```swift
private final class LocationServicesStub: LocationServicesUseCase {
    var status: LocationAuthorizationStatus = .enabled
    func authorizationStatus() -> LocationAuthorizationStatus { status }
}

final class WiFiConnectionSpy: WiFiConnectionUseCase {
    private(set) var connectCalls: [TestNetwork] = []
    var connectResult: Result<Void, WifiConnectionError> = .success(())

    func connect(to network: TestNetwork, password: String?) async throws {
        connectCalls.append(network)
        try connectResult.get()
    }
}
```

### Approaches to Spying on Which Methods Have Been Called

#### 1. Call Count Tracking
- Use this when spying on calls of methods with no arguments.
- Maintain variables named `<methodName>CallCount`.
- Increment counters inside the spy method before returning or throwing.

Example:
```swift
final class MonitoringSpy: CoverageMonitoring {
    private(set) var startCallCount = 0

    func start() {
        startCallCount += 1
    }
}

#expect(spy.startCallCount == 1)
```

#### 2. Parameter Capture
- Use this when spying on calls of methods with arguments.
- Maintain variables named `captured<methodName>Calls` to store method parameters in arrays so tests can assert on the order and count of values. Default to an empty array.
- Use Equatable structs named `<methodName>Parameters` to capture spied method arguments, keeping identical struct members to the method arguments.
- Use `capturedParameters.count` instead of a separate call count for that method.
- Test cases should validate against the complete content of `captured<methodName>Calls`—the whole array, instead of just the count or a mapped property.

Example:
```swift
final class WiFiConnectionUseCaseSpy: WiFiConnectionUseCase {
    struct ConnectParameters: Equatable { 
        let network: TestNetwork
        let password: String?
    }

    private(set) var capturedConnectParameters: [ConnectParameters] = []

    func connect(to network: TestNetwork, password: String?) async throws {
        capturedConnectParameters.append(.init(network: network, password: password))
        try connectionResult.get()
    }

    var connectionResult: Result<Void, WifiConnectionError> = .success(())
}

#expect(spy.capturedConnectParameters == [.init(network: network, password: "secret")])
```

#### 3. Message Calls — When You Need to Verify Multiple Spy Methods Were Called
- Verify the order of multiple method calls.
- Create an `enum CapturedMessage` containing cases that mirror method names with associated values that mirror the method parameters.
- Maintain a variable named `capturedCalls: [CapturedMessage]`, and have each spied method add an associated value representing that it was called.
- Use Equatable structs named `<methodName>Parameters` to capture spied method arguments, keeping identical struct members to the method arguments.
- Test cases should assert on the array of enum cases.

Example:
```swift
// Spy definition
final actor PersistenceServiceSpy: FencePersistenceService {
    enum CapturedMessage: Equatable {
        case save(fence: Fence)
        case sessionStarted(date: Date)
        case assign(testUUID: String, anchorDate: Date)
    }

    private(set) var capturedMessages: [CapturedMessage] = []

    func save(_ fence: Fence) throws {
        capturedMessages.append(.save(fence: fence))
    }

    func sessionStarted(at date: Date) throws {
        capturedMessages.append(.sessionStarted(date: date))
    }

    func assignTestUUIDAndAnchor(_ uuid: String, anchorNow: Date) throws {
        capturedMessages.append(.assign(testUUID: uuid, anchorDate: anchorNow))
    }
}

// Asserting inside test case
@Test func whenReceivedSessionInitialization_thenAssignsTestUUIDAsSessionID() async throws {
    // test setup, set up local variables
    let (sut, persistenceService) = makeSUT(...)

    await sut.startTest()

    #expect(persistenceService.capturedMessages == [
        .sessionStarted(date: dateNow),
        .save(fence: expectedFence1),
        .save(fence: expectedFence2),
        .assign(testUUID: sessionID, anchorDate: makeDate(offset: 6)),
    ])
}
```

### Result Injection & Simulation
- Store behavior in `Result` properties (`connectionResult`) and invoke `try result.get()` inside spy methods.
- Provide `simulate<ActionName>()` helpers to drive async updates or error paths deterministically.
- Yield from stored continuations when working with `AsyncStream`.

Example:
```swift
final class WiFiConnectionUseCaseSpy: WiFiConnectionUseCase {
    private var continuations: [AsyncStream<AvailableWifiNetworksElement<TestNetwork>>.Continuation] = []
    var availableNetworksCallCount = 0

    func availableNetworks() throws -> AsyncStream<AvailableWifiNetworksElement<TestNetwork>> {
        availableNetworksCallCount += 1
        return AsyncStream { continuation in continuations.append(continuation) }
    }

    func simulateNetworkUpdate(with networks: [TestNetwork]) async {
        for continuation in continuations {
            continuation.yield(.networks(Set(networks)))
        }
        await Task.yield()
    }
}
```

#### Result Usage in Tests
- Inject success/failure into spy properties before invoking the SUT.
- Verify captured parameters and emitted events using `#expect`.
- Wrap async verification in `confirmation` blocks to guarantee the sequence completes.

Example:
```swift
@Test("WHEN connection fails THEN error propagates")
func whenConnectionFails_thenErrorPropagates() async throws {
    let (sut, spy) = makeSUT()
    spy.connectResult = .failure(.incorrectCredentials(networkName: "TestWiFi"))

    do {
        try await sut.connect(to: makeNetwork(), password: "wrong")
        Issue.record("Expected failure")
    } catch WifiConnectionError.incorrectCredentials(let name) {
        #expect(name == "TestWiFi")
    }
}
```

### Test Double Principles
- Ensure deterministic ordering.

Example:
```swift
final class CoverageLoopSpy: CoverageLooping {
    private(set) var triggeredActions: [CoverageLoopAction] = []

    func trigger(_ action: CoverageLoopAction) {
        triggeredActions.append(action)
    }
}

#expect(loopSpy.triggeredActions == [.startMeasurement])
```

# Test File Structure and Organization

Follow a three-part layout:
1. **Test suites first** – organize behaviors with nested `@Suite` blocks instead of `MARK` comments so reports cluster by scenario (e.g. `@Suite("connect(to:)")`).
2. **Factories in the middle** – group `makeSUT` and fixture factories under `// MARK: - makeSUT & Factories`, keeping them `private` free functions.
3. **Test doubles last** – declare stubs/spies under `// MARK: - Test Doubles`, also `private`, so implementation detail stays at the bottom.

This structure gives every test file a predictable shape and keeps business-facing scenarios at the top.

## IMPLEMENTATION PATTERNS

<pattern name="Spy Skeleton">

```swift
final class WiFiConnectionUseCaseSpy: WiFiConnectionUseCase {
    struct ConnectCall: Equatable { let network: TestNetwork; let password: String? }

    var availableNetworksCallCount = 0
    private(set) var connectCalls: [ConnectCall] = []
    var connectResult: Result<Void, WifiConnectionError> = .success(())
    private var continuations: [AsyncStream<AvailableWifiNetworksElement<TestNetwork>>.Continuation] = []

    func availableNetworks() throws -> AsyncStream<AvailableWifiNetworksElement<TestNetwork>> {
        availableNetworksCallCount += 1
        return AsyncStream { continuation in continuations.append(continuation) }
    }

    func connect(to network: TestNetwork, password: String?) async throws -> Void {
        connectCalls.append(.init(network: network, password: password))
        try connectResult.get()
    }

    func simulateNetworkUpdate(_ networks: [TestNetwork]) {
        continuations.forEach { $0.yield(.networks(Set(networks))) }
    }
}
```
</pattern>

<pattern name="Nested Suites">

```swift
@Suite("NetworkCoverageViewModel")
struct NetworkCoverageViewModelTests {
    @Suite("startMeasurement") struct StartMeasurement {
        @Test func whenNetworkReady_thenBeginsMeasurement() async throws { /* ... */ }
    }
}
```
</pattern>

<pattern name="Business Helper Extension">

```swift
@MainActor extension NetworkCoverageViewModel {
    func simulateSelectFence(id: UUID) {
        selectedFenceItem = fenceItems.first { $0.id == id }
    }
}
```
Use these helpers in tests to avoid touching SwiftUI bindings directly.
</pattern>

## QUALITY GATES

<checklist>
☐ Use correct test method names: describe the tested behavior, and ensure naming matches other test methods in the suite.
☐ Use `makeSUT` for SUT creation.
☐ Ensure all business behavior is obvious from the test implementation, exposing only necessary inputs and outputs.
☐ Abstract concrete implementation details from tests using factories, helper methods, and understandable fixtures.
☐ Cover all variations and edge cases of business behavior with unit tests.
☐ Make the test setup, local variables, assertions etc. obvious so reader can immediately recognize what is going on when reading a single test case.
</checklist>

## ANTI-PATTERNS TO AVOID

<avoid>
❌ Tests named after implementation details or method names (`test_fetchData`)  
❌ Multiple disjoint `#expect` calls that slice a single behavior into fragments  
❌ Direct manipulation of framework internals (bindings, notifications) instead of business helpers  
❌ Reusing spies across tests without resetting captured state, causing cross-test leakage  
</avoid>
