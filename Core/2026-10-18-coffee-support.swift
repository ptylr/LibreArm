import StoreKit
import SwiftUI

enum CoffeePurchaseResult: Equatable {
    case purchased, cancelled, pending, unverified
}

@MainActor
protocol CoffeeStore {
    func loadPrice() async throws -> String?
    func purchase() async throws -> CoffeePurchaseResult
}

@MainActor
final class AppleCoffeeStore: CoffeeStore {
    static let productID = "com.ptylr.LibreArm.coffee"
    private var product: Product?

    func loadPrice() async throws -> String? {
        product = try await Product.products(for: [Self.productID])
            .first { $0.id == Self.productID && $0.type == .consumable }
        return product?.displayPrice
    }

    func purchase() async throws -> CoffeePurchaseResult {
        guard let product, AppStore.canMakePayments else {
            throw StoreKitError.notAvailableInStorefront
        }
        switch try await product.purchase() {
        case let .success(result):
            return await Self.complete(result) ?? .unverified
        case .userCancelled: return .cancelled
        case .pending: return .pending
        @unknown default: return .unverified
        }
    }

    // Only acknowledge verified coffee transactions; never grant an app entitlement.
    static func complete(_ result: VerificationResult<StoreKit.Transaction>) async -> CoffeePurchaseResult? {
        guard case let .verified(transaction) = result else {
            if case let .unverified(transaction, _) = result, transaction.productID == productID {
                return .unverified
            }
            return nil
        }
        guard transaction.productID == productID, transaction.productType == .consumable else { return nil }
        await transaction.finish()
        return transaction.revocationDate == nil ? .purchased : nil
    }
}

@MainActor
final class CoffeeSupport: ObservableObject {
    enum State: Equatable {
        case idle, loading, ready, purchasing, pending, thankYou, failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var price: String?
    private let store: any CoffeeStore
    private var updatesTask: Task<Void, Never>?
    private var unfinishedTask: Task<Void, Never>?

    var canPurchase: Bool {
        guard price != nil else { return false }
        switch state {
        case .loading, .purchasing, .pending: return false
        default: return true
        }
    }

    init(store: (any CoffeeStore)? = nil, observeTransactions: Bool = true) {
        self.store = store ?? AppleCoffeeStore()
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--screenshot-state=coffee") {
            price = "£5.00"
            state = .ready
            return
        }
#endif
        guard observeTransactions else { return }
        updatesTask = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard !Task.isCancelled else { return }
                if let outcome = await AppleCoffeeStore.complete(result) {
                    self?.apply(outcome)
                }
            }
        }
        unfinishedTask = Task { [weak self] in
            for await result in StoreKit.Transaction.unfinished {
                guard !Task.isCancelled else { return }
                if let outcome = await AppleCoffeeStore.complete(result) {
                    self?.apply(outcome)
                }
            }
        }
    }

    deinit {
        updatesTask?.cancel()
        unfinishedTask?.cancel()
    }

    func load() async {
        guard state != .loading, state != .purchasing else { return }
        if price != nil { return }
        state = .loading
        do {
            price = try await store.loadPrice()
            // A pending approval may complete while the product request is suspended.
            guard state == .loading else { return }
            state = price == nil
                ? .failed("Coffee purchases are unavailable right now. Please try again later.")
                : .ready
        } catch {
            guard state == .loading else { return }
            state = .failed("Couldn’t connect to the App Store. Please try again.")
        }
    }

    func buy() async {
        guard canPurchase else { return }
        state = .purchasing
        do {
            apply(try await store.purchase())
        } catch {
            state = .failed("The purchase couldn’t be completed. Please check the App Store and try again.")
        }
    }

    private func apply(_ outcome: CoffeePurchaseResult) {
        switch outcome {
        case .purchased: state = .thankYou
        case .cancelled: state = .ready
        case .pending: state = .pending
        case .unverified:
            state = .failed("The purchase couldn’t be verified. Please check your App Store purchase history before trying again.")
        }
    }
}

struct CoffeeSupportView: View {
    @ObservedObject var coffee: CoffeeSupport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("🫘")
                        .font(.largeTitle)
                        .accessibilityHidden(true)
                    Text("Buy LibreArm a coffee")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text("LibreArm will always remain free. Voluntary support helps its continued development and does not unlock features or priority.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("A one-time purchase through Apple. No subscription.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    status
                    if let price = coffee.price {
                        Button("Buy a coffee · \(price)") {
                            Task { await coffee.buy() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!coffee.canPurchase)
                        .frame(minHeight: 44)
                    } else if case .failed = coffee.state {
                        Button("Try Again") { Task { await coffee.load() } }
                            .buttonStyle(.bordered)
                            .frame(minHeight: 44)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await coffee.load() }
    }

    @ViewBuilder
    private var status: some View {
        switch coffee.state {
        case .loading: ProgressView("Loading coffee price…")
        case .purchasing: ProgressView("Waiting for Apple…")
        case .pending:
            Text("Your purchase is awaiting approval. Thank you for your support.")
                .font(.subheadline)
        case .thankYou:
            Label("Thank you for supporting LibreArm!", systemImage: "heart.fill")
                .font(.subheadline)
                .foregroundStyle(.green)
                .accessibilityAddTraits(.updatesFrequently)
        case let .failed(message):
            Text(message).font(.subheadline).foregroundStyle(.secondary)
        case .idle, .ready: EmptyView()
        }
    }
}
