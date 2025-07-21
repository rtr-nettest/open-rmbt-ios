# iOS Unit Testing Best Practices Guide

**Modern iOS testing has evolved significantly with Apple's introduction of Swift Testing and enhanced SwiftUI capabilities.** This comprehensive guide provides actionable testing strategies specifically designed for iOS developers building personal finance applications, drawing from industry best practices and real-world examples from successful financial apps.

## Testing behavior creates resilient, maintainable code

The fundamental principle of effective iOS testing is **focusing on behavior rather than implementation details**. This approach ensures tests remain valuable through refactoring and code changes.


## Helper methods transform test maintainability

The `makeSUT` (System Under Test) pattern has become the gold standard for iOS testing, providing a clean factory method that creates test subjects while encapsulating dependencies.

The purpose of `makeSUT` method is to hide implementation details of how SUT is constructed and exposes only business-related inputs needed to accomplish business-related logic.

Ideally, the `makeSUT` should receive only simple, context-agnostic values in it's arguments - e.g. `Int`, `String`, `Result<String, Error>`, etc. It contructs SUT and related Stubs, Spyes if needed and returns then in a tuple.

In less-frequent cases its also possible to pass Stubs, Spyes into `makeSUT` arguments directly.

### The makeSUT pattern with production-ready principles

**Basic makeSUT with input data parameters**:
```swift
class PaymentServiceTests: XCTestCase {
    func makeSUT(
        initialBalance: Decimal = 1000.0,
        apiClient: FinancialAPIProtocol = MockFinancialAPI(),
        validator: PaymentValidator? = PaymentValidator()
    ) -> PaymentService {
        let mockAPI = apiClient
        let mockValidator = validator
        let sut = PaymentService(
            initialBalance: initialBalance,
            apiClient: mockAPI, 
            validator: mockValidator
        )
        trackForMemoryLeaks(sut)
        return sut
    }
}
```

**Advanced makeSUT returning tuples with spies/stubs**:
```swift
class NetworkCoverageServiceTests: XCTestCase {
    func makeSUT(
        coverage: Double = 0.85,
        signalStrength: Int = -60,
        networkType: NetworkType = .wifi
    ) -> (sut: NetworkCoverageService, networkSpy: NetworkManagerSpy, locationSpy: LocationManagerSpy) {
        let networkSpy = NetworkManagerSpy()
        let locationSpy = LocationManagerSpy()
        
        // Configure spies with input data
        networkSpy.stubCoverage = coverage
        networkSpy.stubSignalStrength = signalStrength
        networkSpy.stubNetworkType = networkType
        
        let sut = NetworkCoverageService(
            networkManager: networkSpy,
            locationManager: locationSpy
        )
        
        trackForMemoryLeaks(sut)
        trackForMemoryLeaks(networkSpy)
        trackForMemoryLeaks(locationSpy)
        
        return (sut, networkSpy, locationSpy)
    }
}

### Business-value factory methods hide implementation details

These factory method should hide concrete types from test cases so that the test cases only expose simple-value inputs, outpusts without knowledge of concrete return types etc.

**Factory methods that accept raw data values**:
```swift
// Factory methods take primitive values, hide object construction
func makeNetworkMeasurement(
    downloadSpeed: Double = 50.0,
    uploadSpeed: Double = 25.0,
    latency: TimeInterval = 0.020,
    packetLoss: Double = 0.01
) -> NetworkMeasurement {
    return NetworkMeasurement(
        id: UUID(),
        downloadSpeedMbps: downloadSpeed,
        uploadSpeedMbps: uploadSpeed,
        latencySeconds: latency,
        packetLossPercentage: packetLoss,
        timestamp: Date(),
        serverLocation: "Test Server"
    )
}

func makeCoverageArea(
    latitude: Double = 48.2082,
    longitude: Double = 16.3738,
    radius: Double = 1000.0,
    quality: CoverageQuality = .good
) -> CoverageArea {
    return CoverageArea(
        center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
        radiusMeters: radius,
        quality: quality,
        provider: "Test Provider",
        lastUpdated: Date()
    )
}

func makeFinancialAccount(
    balance: Decimal = 1000.0,
    currency: String = "USD",
    type: AccountType = .savings
) -> FinancialAccount {
    return FinancialAccount(
        id: UUID(),
        balance: balance,
        currency: currency,
        accountType: type,
        createdAt: Date().addingTimeInterval(-86400)
    )
}
```

**Test cases focus only on business values**:
```swift
@Test("Coverage calculation with multiple measurement points")
func testCoverageCalculation_withMultipleMeasurements_returnsCorrectCoverage() {
    let (sut, networkSpy, _) = makeSUT(coverage: 0.92, signalStrength: -45)
    
    let measurement1 = makeNetworkMeasurement(downloadSpeed: 100.0, uploadSpeed: 50.0)
    let measurement2 = makeNetworkMeasurement(downloadSpeed: 80.0, uploadSpeed: 40.0)
    let measurement3 = makeNetworkMeasurement(downloadSpeed: 120.0, uploadSpeed: 60.0)
    
    let result = sut.calculateCoverage(measurements: [measurement1, measurement2, measurement3])
    
    // Test compares only business-relevant values
    #expect(result.overallCoverage == 0.92)
    #expect(result.averageDownloadSpeed == 100.0)
    #expect(result.averageUploadSpeed == 50.0)
    #expect(networkSpy.calculateCoverageCallCount == 1)
}

@Test("Budget calculation with multiple expenses")  
func testBudgetCalculation_withMultipleExpenses_returnsCorrectRemaining() {
    let sut = makeSUT(initialBalance: 1000.0)
    
    let expense1 = makeExpense(amount: 200.0, category: .food)
    let expense2 = makeExpense(amount: 150.0, category: .transport)
    let expense3 = makeExpense(amount: 100.0, category: .entertainment)
    
    let result = sut.calculateRemainingBudget(expenses: [expense1, expense2, expense3])
    
    // Focus on business logic, not implementation
    #expect(result.remaining == 550.0)
    #expect(result.totalSpent == 450.0)
    #expect(result.categorizedSpending[.food] == 200.0)
}
```

### Test builder pattern for complex scenarios

```swift
class ExpenseTestBuilder {
    private var amount: Decimal = 0
    private var category: ExpenseCategory = .miscellaneous
    private var date: Date = Date()
    
    func withAmount(_ amount: Decimal) -> ExpenseTestBuilder {
        self.amount = amount
        return self
    }
    
    func withCategory(_ category: ExpenseCategory) -> ExpenseTestBuilder {
        self.category = category
        return self
    }
    
    func build() -> Expense {
        return Expense(amount: amount, category: category, date: date)
    }
}

// Usage
let expense = ExpenseTestBuilder()
    .withAmount(100)
    .withCategory(.food)
    .build()
```

## iOS-specific testing patterns require specialized approaches

Modern iOS development demands testing strategies that account for SwiftUI, Core Data, async operations, and Apple's ecosystem frameworks.


### Swift Data testing with in-memory stores

For financial apps using Core Data, **in-memory stores** provide fast, isolated testing:

```swift
func makeSUT(
    testUUID: String?,
    sendResults: [Result<Void, Error>] = [.success(())],
    previouslyPersistedFences: [PersistentFence] = [],
    maxResendAge: TimeInterval = Date().timeIntervalSince1970 * 1000,
    dateNow: @escaping () -> Date = Date.init
) -> (sut: SUT, persistence: PersistenceLayerSpy, sendService: SendCoverageResultsServiceFactory) {
    // Creating in-memory model context, separate for each `makeSUT` instance
    let configuration = ModelConfiguration(for: PersistentFence.self, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: PersistentFence.self, configurations: configuration)
    let modelContext = ModelContext(container)
    let persistence = PersistenceLayerSpy(modelContext: modelContext)
    let sendServiceFactory = SendCoverageResultsServiceFactory(sendResults: sendResults)

    // Insert prefilled fences into modelContext
    for fence in previouslyPersistedFences {
        modelContext.insert(fence)
    }
    try! modelContext.save()

    let sut = NetworkCoverageModel(modelContext: modelContext)

    return (sut, persistence, sendServiceFactory)
}
```

### Async/await testing patterns

Swift's modern concurrency features require updated testing approaches:

```swift
@Test("Async budget calculation completes successfully")
func testAsyncBudgetCalculation() async throws {
    let calculator = BudgetCalculator()
    let expenses = [makeExpense(amount: 100), makeExpense(amount: 200)]
    
    let result = try await calculator.calculateBudgetSummary(for: expenses)
    
    #expect(result.totalExpenses == 300)
    #expect(result.remainingBudget > 0)
}
```

### StoreKit testing for subscription features

Financial apps with premium features need comprehensive StoreKit testing:

```swift
@Test("Premium subscription purchase flow")
func testPremiumSubscription() async throws {
    let productId = "com.savemo.premium_monthly"
    let products = try await Product.products(for: [productId])
    
    guard let product = products.first else {
        throw TestError.productNotFound
    }
    
    let result = try await product.purchase()
    
    switch result {
    case .success(let transaction):
        #expect(transaction.productID == productId)
        #expect(transaction.revocationDate == nil)
    case .userCancelled:
        Issue.record("User cancelled purchase")
    case .pending:
        Issue.record("Purchase pending")
    @unknown default:
        Issue.record("Unknown purchase result")
    }
}
```

## Production-proven testing patterns for iOS finance apps

Drawing from real-world implementations like the RTR-NetTest open-source project, modern iOS testing emphasizes **separation of concerns** between test infrastructure and business logic validation.

### Core principles from production codebases

**1. makeSUT accepts input data parameters, not mock objects**
```swift
// ✅ Good: Data-driven SUT creation
func makeSUT(
    accountBalance: Decimal = 1000.0,
    monthlyIncome: Decimal = 5000.0,
    savingsGoal: Decimal = 10000.0
) -> (sut: SavingsCalculator, accountSpy: AccountRepositorySpy) {
    let accountSpy = AccountRepositorySpy()
    accountSpy.stubBalance = accountBalance
    accountSpy.stubMonthlyIncome = monthlyIncome
    
    let sut = SavingsCalculator(accountRepository: accountSpy)
    trackForMemoryLeaks(sut)
    return (sut, accountSpy)
}

// ❌ Avoid: Passing pre-configured mocks
func makeSUT(accountRepo: AccountRepository = MockAccountRepository()) -> SavingsCalculator {
    // Forces test setup outside makeSUT, harder to understand
}
```

**2. Test cases compare only business values**
```swift
@Test("Monthly savings calculation with varying income")
func testMonthlySavings_withFluctuatingIncome_calculatesCorrectAmount() {
    let (sut, accountSpy) = makeSUT(
        accountBalance: 5000.0,
        monthlyIncome: 4500.0,
        savingsGoal: 20000.0
    )
    
    let result = sut.calculateMonthlySavingsNeeded()
    
    // Only business-relevant assertions
    #expect(result.monthlyAmount == 1250.0)
    #expect(result.timeToGoalMonths == 12)
    #expect(accountSpy.balanceAccessCount == 1)
}
```

**3. Factory methods abstract object construction complexity**
```swift
func makeExpenseEvent(
    amount: Decimal = 100.0,
    dueDate: Date = Date().addingTimeInterval(86400 * 30), // 30 days
    category: ExpenseCategory = .miscellaneous
) -> ExpenseEvent {
    return ExpenseEvent(
        id: UUID(),
        amount: amount,
        dueDate: dueDate,
        category: category,
        createdAt: Date(),
        isRecurring: false
    )
}

func makeSavingsAccount(
    balance: Decimal = 1000.0,
    interestRate: Double = 0.02,
    compoundingFrequency: CompoundingFrequency = .monthly
) -> SavingsAccount {
    return SavingsAccount(
        id: UUID(),
        balance: balance,
        interestRate: interestRate,
        compounding: compoundingFrequency,
        openedDate: Date().addingTimeInterval(-86400 * 30)
    )
}
```

## Advanced patterns that make tests production-ready

Your NetworkCoverage tests demonstrate several sophisticated patterns that elevate test quality beyond typical examples:

### 1. **Comprehensive scenario modeling with timing precision**

```swift
@Test func whenReceivedPingsWithTimeBeforeFenceChanged_thenTheyAreAssignedToPreviousFence() async throws {
    let sut = makeSUT(updates: [
        makeLocationUpdate  (at: 0, lat: 1, lon: 1),
        makePingUpdate      (at: 1, ms: 10),
        makeLocationUpdate  (at: 5, lat: 2, lon: 2),
        makePingUpdate      (at: 2, ms: 2000),  // Late-arriving ping
        makePingUpdate      (at: 3, ms: 3000),  // Another late ping
        makeLocationUpdate  (at: 10, lat: 3, lon: 3),
        // ... complex timing scenarios
    ])
    await sut.startTest()

    #expect(sut.fenceItems
        .map(\.id)
        .map {
            sut.selectedFenceID = $0
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
}
```

**What makes this exceptional:**
- ✅ **Real-world complexity**: Models network timing issues (late-arriving pings)
- ✅ **Precise timing control**: Uses exact timestamps to test edge cases
- ✅ **Business logic verification**: Verifies pings are assigned to correct time windows
- ✅ **Readable assertions**: Clear expected outcomes with time range comments

### 2. **Nested test organization with shared context**

```swift
@MainActor @Suite("WHEN Received Location Updates With Bad Accuracy")
struct WhenReceivedLocationUpdatesWithBadAccuracy {
    @Test func goodLocationUpdatesAreInsideSameFence_thenNoNewFenceIsCreated() async throws {
        let minAccuracy = CLLocationDistance(100)
        let sut = makeSUT(minimumLocationAccuracy: minAccuracy, updates: [
            makeLocationUpdate(at: 0, lat: 1.0000000001, lon: 1.0000000002, accuracy: minAccuracy / 2),
            makeLocationUpdate(at: 2, lat: 2, lon: 2, accuracy: minAccuracy * 2), // Bad accuracy
            makeLocationUpdate(at: 5, lat: 1.0, lon: 1.0000000001, accuracy: minAccuracy / 3),
            // ...
        ])
        await sut.startTest()

        #expect(sut.fenceItems.count == 1)
        #expect(sut.fenceItems.first?.coordinate.latitude == 1.0000000001)
    }
}
```

**What makes this exceptional:**
- ✅ **Clear test context**: Suite name describes the scenario being tested
- ✅ **Precision testing**: Tests GPS accuracy edge cases with exact coordinates
- ✅ **Realistic scenarios**: Models real location services behavior
- ✅ **Focused verification**: Each test in suite focuses on one aspect of accuracy handling

### 3. **Multi-dependency coordination in makeSUT**

```swift
private func makeSUT(
    testUUID: String?,
    sendResults: [Result<Void, Error>] = [.success(())],
    previouslyPersistedFences: [PersistentFence] = [],
    maxResendAge: TimeInterval = Date().timeIntervalSince1970 * 1000,
    dateNow: @escaping () -> Date = Date.init
) -> (sut: SUT, persistence: PersistenceLayerSpy, sendService: SendCoverageResultsServiceFactory) {
    let database = UserDatabase(useInMemoryStore: true)
    let persistence = PersistenceLayerSpy(modelContext: database.modelContext)
    let sendServiceFactory = SendCoverageResultsServiceFactory(sendResults: sendResults)

    // Insert prefilled fences into modelContext
    for fence in previouslyPersistedFences {
        database.modelContext.insert(fence)
    }
    try! database.modelContext.save()

    let services = NetworkCoverageFactory(database: database, maxResendAge: maxResendAge)
        .services(testUUID: testUUID, startDate: Date(timeIntervalSinceReferenceDate: 0), dateNow: dateNow) { testUUID, _ in
            sendServiceFactory.createService(for: testUUID)
        }
    
    return (services.0, persistence, sendServiceFactory)
}
```

**What makes this exceptional:**
- ✅ **Real database integration**: Uses actual Core Data with in-memory store
- ✅ **Pre-populated state**: Inserts test data before test execution
- ✅ **Factory coordination**: Multiple service factories work together
- ✅ **Complete isolation**: Each test gets fresh database state

### 4. **Advanced async sequence testing with timing verification**

```swift
func expect(
    _ sut: some PingsAsyncSequence,
    receive expectedElements: [(at: Double, PingResult)],
    after totalDuration: Duration,
    with clock: TestClock<Duration>
) async throws {
    var capturedElements: [PingResult] = []
    var capturedInstants: [TestClock<Duration>.Instant] = []
    
    await confirmation(expectedCount: expectedElements.count) { confirmation in
        Task {
            for try await element in sut {
                capturedInstants.append(clock.now)
                capturedElements.append(element)
                confirmation.confirm()
            }
        }
        await clock.advance(by: totalDuration)
    }

    #expect(capturedElements == expectedElements.map(\.1))
    #expect(capturedInstants.isEqual(to: expectedElements.map { TestClock.Instant(offset: Duration.seconds($0.0)) }))
}
```

**What makes this exceptional:**
- ✅ **Async sequence testing**: Tests Swift's modern async iteration
- ✅ **Timing precision**: Verifies exact timing of async events
- ✅ **Controlled clock**: Uses TestClock for deterministic timing
- ✅ **Confirmation patterns**: Uses Swift Testing's confirmation API

### 5. **Sophisticated spy composition patterns**

```swift
private final class SendCoverageResultsServiceFactory {
    private(set) var capturedSendCalls: [SendCall] = []
    private var sendResults: [Result<Void, Error>]

    func createService(for testUUID: String) -> SendCoverageResultsServiceWrapper {
        let service = SendCoverageResultsServiceSpyLocal(sendResult: sendResults.removeFirst())
        
        return SendCoverageResultsServiceWrapper(
            testUUID: testUUID,
            originalService: service,
            onSend: { [weak self] fences in
                self?.capturedSendCalls.append(SendCall(testUUID: testUUID, fences: fences))
            }
        )
    }
}
```

**What makes this exceptional:**
- ✅ **Factory pattern for spies**: Creates contextual spies per test UUID
- ✅ **Composition over inheritance**: Wraps spies rather than subclassing
- ✅ **Behavior tracking**: Captures all interactions across multiple services
- ✅ **Weak references**: Proper memory management in test closures

## Key takeaways from production patterns

These patterns demonstrate testing maturity that goes far beyond typical unit testing:

1. **Precision over approximation**: Tests model exact timing, coordinates, and edge cases rather than simplified scenarios
2. **Real complexity modeling**: Tests handle out-of-order events, timing issues, and multi-dependency coordination
3. **Infrastructure investment**: Significant effort in test helpers pays off in maintainable, reliable tests
4. **Business focus**: Despite complex infrastructure, assertions remain focused on business outcomes
5. **Modern Swift features**: Leverages async/await, Swift Testing, and advanced language features effectively

```swift
class SavingsAccountTests: XCTestCase {
    
    // makeSUT accepts raw data values, returns tuple with SUT and spies
    func makeSUT(
        initialBalance: Decimal = 1000.0,
        monthlyContribution: Decimal = 200.0,
        interestRate: Double = 0.025,
        targetAmount: Decimal = 5000.0
    ) -> (sut: SavingsService, accountSpy: AccountRepositorySpy, calculatorSpy: InterestCalculatorSpy) {
        
        let accountSpy = AccountRepositorySpy()
        let calculatorSpy = InterestCalculatorSpy()
        
        // Configure spies with input data
        accountSpy.stubBalance = initialBalance
        accountSpy.stubMonthlyContribution = monthlyContribution
        calculatorSpy.stubInterestRate = interestRate
        
        let sut = SavingsService(
            accountRepository: accountSpy,
            interestCalculator: calculatorSpy
        )
        
        trackForMemoryLeaks(sut)
        trackForMemoryLeaks(accountSpy)
        trackForMemoryLeaks(calculatorSpy)
        
        return (sut, accountSpy, calculatorSpy)
    }
    
    // Factory methods hide complex object creation
    func makeExpenseEvent(
        amount: Decimal = 500.0,
        dueDate: Date = Calendar.current.date(byAdding: .month, value: 6, to: Date())!,
        priority: ExpensePriority = .medium
    ) -> ExpenseEvent {
        return ExpenseEvent(
            id: UUID(),
            amount: amount,
            dueDate: dueDate,
            priority: priority,
            category: .plannedExpense,
            createdAt: Date()
        )
    }
    
    func makeRecurringExpense(
        monthlyAmount: Decimal = 100.0,
        frequency: RecurrenceFrequency = .monthly,
        startDate: Date = Date()
    ) -> RecurringExpense {
        return RecurringExpense(
            id: UUID(),
            amount: monthlyAmount,
            frequency: frequency,
            startDate: startDate,
            category: .subscription
        )
    }
    
    // Test cases focus on business behavior, not implementation
    @Test("Savings goal calculation with future expenses")
    func testSavingsGoal_withFutureExpenses_calculatesCorrectMonthlyAmount() {
        let (sut, accountSpy, calculatorSpy) = makeSUT(
            initialBalance: 2000.0,
            monthlyContribution: 300.0,
            targetAmount: 10000.0
        )
        
        let vacation = makeExpenseEvent(amount: 3000.0, dueDate: Date().addingTimeInterval(86400 * 180))
        let carRepair = makeExpenseEvent(amount: 1500.0, dueDate: Date().addingTimeInterval(86400 * 90))
        
        let result = sut.calculateSavingsStrategy(
            targetAmount: 10000.0,
            futureExpenses: [vacation, carRepair]
        )
        
        // Business values comparison only
        #expect(result.requiredMonthlySavings == 425.0)
        #expect(result.timeToGoalMonths == 18)
        #expect(result.totalExpenseImpact == 4500.0)
        
        // Verify spy interactions (behavioral verification)
        #expect(accountSpy.balanceRequestCount == 1)
        #expect(calculatorSpy.compoundInterestCalculationCount == 1)
    }
    
    @Test("Interest calculation with varying contribution amounts")
    func testInterestCalculation_withVariableContributions_returnsAccurateProjection() {
        let (sut, _, calculatorSpy) = makeSUT(
            initialBalance: 5000.0,
            interestRate: 0.04
        )
        
        let result = sut.projectBalance(
            timeHorizonMonths: 24,
            monthlyContributions: [400.0, 450.0, 500.0, 350.0]
        )
        
        #expect(result.finalBalance > 5000.0)
        #expect(result.totalInterestEarned > 0)
        #expect(result.averageMonthlyGrowth > 0)
        #expect(calculatorSpy.variableContributionCalculationCount == 1)
    }
}

// Spy implementations that focus on behavior verification
class AccountRepositorySpy: AccountRepository {
    var stubBalance: Decimal = 0
    var stubMonthlyContribution: Decimal = 0
    var balanceRequestCount = 0
    
    func getCurrentBalance() -> Decimal {
        balanceRequestCount += 1
        return stubBalance
    }
    
    func getMonthlyContribution() -> Decimal {
        return stubMonthlyContribution
    }
}

class InterestCalculatorSpy: InterestCalculator {
    var stubInterestRate: Double = 0
    var compoundInterestCalculationCount = 0
    var variableContributionCalculationCount = 0
    
    func calculateCompoundInterest(
        principal: Decimal,
        rate: Double,
        time: Int,
        monthlyContribution: Decimal
    ) -> Decimal {
        compoundInterestCalculationCount += 1
        return principal * Decimal(1 + rate)
    }
    
    func calculateWithVariableContributions(
        principal: Decimal,
        rate: Double,
        contributions: [Decimal]
    ) -> InterestProjection {
        variableContributionCalculationCount += 1
        return InterestProjection(
            finalBalance: principal + contributions.reduce(0, +),
            totalInterest: principal * Decimal(rate),
            monthlyBreakdown: []
        )
    }
}
```

This example demonstrates all the key principles:
- **makeSUT accepts raw data parameters** (balance, contribution amounts, rates)
- **makeSUT returns tuple** with SUT and all necessary spies
- **Factory methods hide object construction** (makeExpenseEvent, makeRecurringExpense)
- **Tests compare business values only** (savings amounts, time horizons, growth rates)
- **Spies track behavior** without coupling to implementation details

## Applying these patterns to Savemo app testing

Based on your core testing values, here's how to structure tests for the Savemo personal finance app:

### Account Management Tests
```swift
class AccountManagementTests: XCTestCase {
    
    func makeSUT(
        initialBalance: Decimal = 1000.0,
        currency: String = "USD",
        accountType: AccountType = .savings
    ) -> (sut: AccountService, repositorySpy: AccountRepositorySpy, validatorSpy: InputValidatorSpy) {
        
        let repositorySpy = AccountRepositorySpy()
        let validatorSpy = InputValidatorSpy()
        
        repositorySpy.stubBalance = initialBalance
        repositorySpy.stubCurrency = currency
        validatorSpy.stubIsValid = true
        
        let sut = AccountService(
            repository: repositorySpy,
            validator: validatorSpy
        )
        
        return (sut, repositorySpy, validatorSpy)
    }
    
    func makeExpense(
        amount: Decimal = 100.0,
        dueDate: Date = Date().addingTimeInterval(86400 * 30),
        label: String = "Test Expense"
    ) -> Expense {
        return Expense(
            label: label,
            amount: amount,
            dueDate: dueDate,
            createdDate: Date()
        )
    }
    
    @Test("Monthly savings calculation with multiple expenses")
    func testMonthlySavings_withMultipleExpenses_returnsCorrectAmount() {
        let (sut, repositorySpy, _) = makeSUT(initialBalance: 2000.0)
        
        let vacation = makeExpense(amount: 1500.0, dueDate: Date().addingTimeInterval(86400 * 90))
        let carMaintenance = makeExpense(amount: 800.0, dueDate: Date().addingTimeInterval(86400 * 60))
        
        let result = sut.calculateMonthlySavingsNeeded(expenses: [vacation, carMaintenance])
        
        #expect(result.totalRequired == 2300.0)
        #expect(result.monthlyAmount == 767.0) // Approximately
        #expect(repositorySpy.balanceAccessCount == 1)
    }
}
```

### Balance Calculation Tests
```swift
class BalanceCalculationTests: XCTestCase {
    
    func makeSUT(
        lastKnownBalance: Decimal = 1000.0,
        lastBalanceDate: Date = Date().addingTimeInterval(-86400 * 30),
        monthlyContribution: Decimal = 200.0
    ) -> (sut: BalanceCalculator, timeSpy: TimeProviderSpy) {
        
        let timeSpy = TimeProviderSpy()
        timeSpy.stubCurrentDate = Date()
        
        let sut = BalanceCalculator(timeProvider: timeSpy)
        
        return (sut, timeSpy)
    }
    
    func makeBalanceEntry(
        amount: Decimal = 1000.0,
        date: Date = Date(),
        type: BalanceType = .userEntered
    ) -> Balance {
        return Balance(
            date: date,
            amount: amount,
            type: type
        )
    }
    
    @Test("Current balance projection from last entry")
    func testCurrentBalance_withMonthsSinceLastEntry_projectsCorrectly() {
        let thirtyDaysAgo = Date().addingTimeInterval(-86400 * 30)
        let (sut, timeSpy) = makeSUT(
            lastKnownBalance: 1000.0,
            lastBalanceDate: thirtyDaysAgo,
            monthlyContribution: 300.0
        )
        
        let lastBalance = makeBalanceEntry(amount: 1000.0, date: thirtyDaysAgo)
        let currentBalance = sut.calculateCurrentBalance(
            from: lastBalance,
            monthlySavings: 300.0
        )
        
        #expect(currentBalance == 1300.0) // 1000 + (1 month * 300)
        #expect(timeSpy.currentDateAccessCount == 1)
    }
}
```

### Expense Management Tests
```swift
class ExpenseManagementTests: XCTestCase {
    
    func makeSUT(
        accountBalance: Decimal = 2000.0,
        calculationStrategy: CalculationStrategy = .evenMonthly
    ) -> (sut: ExpenseManager, calculatorSpy: SavingsCalculatorSpy) {
        
        let calculatorSpy = SavingsCalculatorSpy()
        calculatorSpy.stubStrategy = calculationStrategy
        calculatorSpy.stubMonthlySavings = 150.0
        
        let sut = ExpenseManager(calculator: calculatorSpy)
        
        return (sut, calculatorSpy)
    }
    
    func makeRecurringExpense(
        amount: Decimal = 50.0,
        frequency: RecurrenceFrequency = .monthly,
        startDate: Date = Date()
    ) -> RecurringExpense {
        return RecurringExpense(
            amount: amount,
            frequency: frequency,
            startDate: startDate,
            category: .subscription
        )
    }
    
    @Test("Expense addition updates monthly savings requirement")
    func testAddExpense_updatesMonthlyRequired() {
        let (sut, calculatorSpy) = makeSUT(accountBalance: 5000.0)
        
        let newExpense = makeExpense(amount: 2000.0, dueDate: Date().addingTimeInterval(86400 * 120))
        sut.addExpense(newExpense)
        
        #expect(calculatorSpy.calculateMonthlySavingsCallCount == 1)
        #expect(calculatorSpy.lastCalculationInput?.totalExpenseAmount == 2000.0)
    }
}
```

This approach ensures your Savemo tests follow the principles you value:
- **Clear separation** between test infrastructure (makeSUT, factory methods) and business logic validation
- **Data-driven test setup** where makeSUT accepts business values, not pre-configured mocks
- **Business value focus** in assertions, testing what the system should do rather than how it does it
- **Comprehensive spy verification** to ensure proper interaction patterns without implementation coupling

### File structure and naming conventions

By default, Unit tests folder structure replicates production files fodler structure. Including similar file namess, just appending `Tests` into file name.

E.g. BalanceService.swift (production code) -> BalanceServiceSwiftTests.swift (test cases for BalanceService class)

### Test method naming patterns

In general, be mindful about GIVEN - WHEN - THEN approach.
In may cases it's okay to use WHEN [describe initial configuration] THEN [describe expected result]

✅ Examples of good test names:
```swift
@Test func whenInitializedWithNoPrefilledFences_thenFenceItemsAreEmpty() async throws { ... }
@Test func whenReceivingMultiplePingsForOneLocation_thenCombinesPingTotalValue() async throws { ... }
@Test func whenAttemptToSendPreviouslyPersistedFencesFails_thenKeepsThoseFencesPersisted() async throws { ... }

```

❌ Examples of bad test names:
```swift
@Test func test_validateResponse() { ... }
@Test func networkRequestShouldReturnResponse() { ... }

``` 


### Swift Testing organization with suites

```swift
@Suite("Budget Management")
struct BudgetManagementTests {
    @Test("Budget creation and validation")
    func budgetCreation() { /* ... */ }
    
    @Test("Budget limit enforcement")
    func budgetLimitEnforcement() { /* ... */ }
}

@Suite("Expense Tracking", .tags(.core))
struct ExpenseTrackingTests {
    @Test("Expense categorization")
    func expenseCategorization() { /* ... */ }
    
    @Test("Expense validation")
    func expenseValidation() { /* ... */ }
}
```

## Mocking and dependency injection enable isolated testing

Effective mocking strategies balance test isolation with realistic behavior, avoiding the pitfalls of over-mocking while maintaining test reliability.


### Protocol-based testing doubles

```swift
protocol FinancialAPIProtocol {
    func fetchTransactions() async throws -> [Transaction]
    func submitPayment(_ payment: Payment) async throws -> PaymentResult
}

class FinancialAPIMock: FinancialAPIProtocol {
    var fetchTransactionsResult: Result<[Transaction], Error>?
    var submitPaymentResult: Result<PaymentResult, Error>?
    
    func fetchTransactions() async throws -> [Transaction] {
        switch fetchTransactionsResult {
        case .success(let transactions):
            return transactions
        case .failure(let error):
            throw error
        case .none:
            return []
        }
    }
    
    func submitPayment(_ payment: Payment) async throws -> PaymentResult {
        switch submitPaymentResult {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        case .none:
            return PaymentResult.success
        }
    }
}
```

### Spy vs Stub: Quick Reference

**Stub** = Controls **inputs** to your system under test  
**Spy** = Captures **outputs** and interactions from your system under test

#### Stub

```swift
final class NetworkServiceStub: NetworkService {
    init(fetchDataResponse: Result<Data, Error> = .success(Data())) {
        self.fetchDataResponse = stubResponse
    }
    
    private var fetchDataResponse: Result<Data, Error>
    
    func fetchData() async throws -> Data {
        return try fetchDataResponse.get() // ✅ Controls what SUT receives
    }
}
```

**Purpose**: Provide predictable responses to SUT  
**Focus**: What the SUT gets as input

#### Spy

```swift
final class NetworkServiceSpy: NetworkService {
    private(set) var fetchDataCallCount = 0
    private(set) var capturedRequests: [URLRequest] = []\
    private var fetchDataResponse: Result<Data, Error>
    
    init(fetchDataResponse: Result<Data, Error> = .success(Data())) {
        self.fetchDataResponse = stubResponse
    }
    
    
    
    func fetchData() async throws -> Data {
        fetchDataCallCount += 1 // ✅ Captures SUT behavior
        return try fetchDataResponse.get()
    }
}
```

**Purpose**: Record and verify SUT's behavior  
**Focus**: What the SUT does (calls, parameters, frequency)

#### Real-world example from production code

```swift
final class FencePersistenceServiceSpy: FencePersistenceService {
    private(set) var capturedSavedFences: [Fence] = [] // ✅ SPY: Captures what was saved
    
    func save(_ fence: Fence) throws {
        capturedSavedFences.append(fence) // Records SUT behavior
    }
}
```

#### When to use which

- **Stub**: When SUT needs specific inputs to test business logic
- **Spy**: When you need to verify SUT called dependencies correctly  
- **Both**: Often combined in same test double for complete control and verification

#### Memory Aid

- **Stub** = "What goes IN" (stub out dependencies)
- **Spy** = "What comes OUT" (spy on behavior)

### Avoiding over-mocking with integration tests

```swift
@Test("End-to-end financial transaction flow")
func testFinancialTransactionFlow() async throws {
    let sut = FinancialService(
        apiClient: RealAPIClient(), // Real implementation
        validator: TransactionValidator(), // Real implementation
        logger: MockLogger() // Only mock non-essential dependencies
    )
    
    let transaction = makeValidTransaction()
    let result = try await sut.processTransaction(transaction)
    
    #expect(result.isSuccess)
}
```

## Conclusion

Modern iOS unit testing requires a sophisticated approach that balances behavior-focused testing, clean architecture patterns, and iOS-specific considerations. The combination of Swift Testing's modern syntax, established patterns like makeSUT, and comprehensive dependency injection creates a robust foundation for testing personal finance applications.

**Key implementation priorities** include adopting Swift Testing for new projects, implementing ViewInspector for SwiftUI testing, creating comprehensive helper methods and factories, and establishing clear testing architecture from the project's inception. Financial applications particularly benefit from rigorous testing of calculations, security measures, and data persistence patterns.

The evolution from XCTest to Swift Testing represents a significant improvement in developer experience, with better error messages, parallel execution, and native async/await support. Combined with proven patterns from successful financial apps and open-source projects, these practices enable confident development and maintenance of complex iOS applications.
