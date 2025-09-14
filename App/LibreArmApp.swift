import SwiftUI

@main
struct LibreArmApp: App {
    @StateObject private var health = Health()
    @StateObject private var bp = BPClient()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(health)
                .environmentObject(bp)
        }
    }
}
