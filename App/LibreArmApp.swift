import SwiftUI

@main
struct LibreArmApp: App {
    @StateObject private var health = Health()
    @StateObject private var bp = BPClient()
    @StateObject private var coffee = CoffeeSupport(observeTransactions: {
#if DEBUG
        // Unit tests own their StoreKit observers and simulated transactions.
        NSClassFromString("XCTestCase") == nil
#else
        true
#endif
    }())

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(health)
                .environmentObject(bp)
                .environmentObject(coffee)
        }
    }
}
