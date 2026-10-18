import XCTest
import StoreKit
import StoreKitTest
@testable import LibreArm

@MainActor
final class CoffeeSupportTests: XCTestCase {
    func testUnavailableProductCannotBePurchasedAndCanBeRetried() async {
        let store = FakeCoffeeStore()
        store.price = nil
        let coffee = CoffeeSupport(store: store, observeTransactions: false)
        await coffee.load()
        XCTAssertFalse(coffee.canPurchase)
        await coffee.buy()
        XCTAssertEqual(store.purchaseCount, 0)
        store.price = "£5.00"
        await coffee.load()
        XCTAssertEqual(coffee.price, "£5.00")
        XCTAssertTrue(coffee.canPurchase)
    }

    func testCancellationDoesNotThankOrPreventAnotherAttempt() async {
        let store = FakeCoffeeStore()
        store.result = .cancelled
        let coffee = CoffeeSupport(store: store, observeTransactions: false)
        await coffee.load()
        await coffee.buy()
        XCTAssertEqual(coffee.state, .ready)
        XCTAssertTrue(coffee.canPurchase)
    }

    func testPendingApprovalCannotCreateAnotherPurchase() async {
        let store = FakeCoffeeStore()
        store.result = .pending
        let coffee = CoffeeSupport(store: store, observeTransactions: false)
        await coffee.load()
        await coffee.buy()
        await coffee.load()
        await coffee.buy()
        XCTAssertEqual(coffee.state, .pending)
        XCTAssertEqual(store.purchaseCount, 1)
    }

    func testUnverifiedPurchaseDoesNotShowThankYou() async {
        let store = FakeCoffeeStore()
        store.result = .unverified
        let coffee = CoffeeSupport(store: store, observeTransactions: false)
        await coffee.load()
        await coffee.buy()
        guard case .failed = coffee.state else { return XCTFail("Expected verification failure") }
    }

    func testStoreFailureDoesNotShowThankYouAndAllowsRetry() async {
        let store = FakeCoffeeStore()
        store.fails = true
        let coffee = CoffeeSupport(store: store, observeTransactions: false)
        await coffee.load()
        XCTAssertNil(coffee.price)
        store.fails = false
        await coffee.load()
        store.fails = true
        await coffee.buy()
        guard case .failed = coffee.state else { return XCTFail("Expected purchase failure") }
        XCTAssertTrue(coffee.canPurchase)
    }

    func testRepeatedTapsCannotStartConcurrentPurchases() async {
        let store = FakeCoffeeStore()
        let coffee = CoffeeSupport(store: store, observeTransactions: false)
        await coffee.load()
        store.suspendPurchase = true
        let first = Task { await coffee.buy() }
        while store.continuation == nil { await Task.yield() }
        await coffee.buy()
        XCTAssertEqual(store.purchaseCount, 1)
        store.continuation?.resume()
        await first.value
        XCTAssertEqual(coffee.state, .thankYou)
    }
}

@MainActor
private final class FakeCoffeeStore: CoffeeStore {
    var price: String? = "£5.00"
    var result: CoffeePurchaseResult = .purchased
    var fails = false
    var purchaseCount = 0
    var suspendPurchase = false
    var continuation: CheckedContinuation<Void, Never>?

    func loadPrice() async throws -> String? {
        if fails { throw StoreKitError.notAvailableInStorefront }
        return price
    }

    func purchase() async throws -> CoffeePurchaseResult {
        purchaseCount += 1
        if suspendPurchase {
            await withCheckedContinuation { continuation = $0 }
        }
        if fails { throw StoreKitError.notAvailableInStorefront }
        return result
    }
}

@MainActor
final class CoffeeStoreKitTests: XCTestCase {
    private var session: SKTestSession!

    override func setUpWithError() throws {
        session = try SKTestSession(configurationFileNamed: "2026-10-18-coffee")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
    }

    override func tearDownWithError() throws {
        session.clearTransactions()
        session.resetToDefaultState()
        session = nil
    }

    func testVerifiedCoffeeCanBeBoughtTwiceAndTransactionsAreFinished() async throws {
        let coffee = CoffeeSupport(observeTransactions: false)
        await coffee.load()
        XCTAssertNotNil(coffee.price)
        await coffee.buy()
        XCTAssertEqual(coffee.state, .thankYou)
        await coffee.buy()
        XCTAssertEqual(coffee.state, .thankYou)
        XCTAssertEqual(session.allTransactions().count, 2)
        for await result in StoreKit.Transaction.unfinished {
            if case let .verified(transaction) = result {
                XCTAssertNotEqual(transaction.productID, AppleCoffeeStore.productID)
            }
        }
    }

    func testUnverifiedCoffeeIsNotAcknowledgedOrFinished() async throws {
        _ = try await session.buyProduct(identifier: AppleCoffeeStore.productID)
        var unfinished: StoreKit.Transaction?
        for await result in StoreKit.Transaction.unfinished {
            if case let .verified(transaction) = result,
               transaction.productID == AppleCoffeeStore.productID {
                unfinished = transaction
                break
            }
        }
        let transaction = try XCTUnwrap(unfinished)
        let outcome = await AppleCoffeeStore.complete(.unverified(transaction, .invalidSignature))
        XCTAssertEqual(outcome, .unverified)
        var remainsUnfinished = false
        for await result in StoreKit.Transaction.unfinished {
            if case let .verified(candidate) = result, candidate.id == transaction.id {
                remainsUnfinished = true
            }
        }
        XCTAssertTrue(remainsUnfinished)
    }

    func testPendingApprovalCompletesThroughTransactionListener() async throws {
        session.askToBuyEnabled = true
        let coffee = CoffeeSupport()
        await coffee.load()
        await coffee.buy()
        XCTAssertEqual(coffee.state, .pending)
        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.approveAskToBuyTransaction(identifier: transaction.identifier)
        let completion = expectation(description: "Approved coffee is acknowledged")
        let observer = Task {
            while coffee.state != .thankYou {
                if Task.isCancelled { return }
                try? await Task.sleep(for: .milliseconds(20))
            }
            completion.fulfill()
        }
        await fulfillment(of: [completion], timeout: 10)
        observer.cancel()
        XCTAssertEqual(coffee.state, .thankYou)
    }

    func testUnfinishedPurchaseIsAcknowledgedAfterRestart() async throws {
        _ = try await session.buyProduct(identifier: AppleCoffeeStore.productID)
        let coffee = CoffeeSupport()
        let completion = expectation(description: "Unfinished coffee is acknowledged")
        let observer = Task {
            while coffee.state != .thankYou {
                if Task.isCancelled { return }
                try? await Task.sleep(for: .milliseconds(20))
            }
            completion.fulfill()
        }
        await fulfillment(of: [completion], timeout: 10)
        observer.cancel()
        XCTAssertEqual(coffee.state, .thankYou)
    }
}
