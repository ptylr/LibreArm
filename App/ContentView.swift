import SwiftUI

struct ContentView: View {
    @EnvironmentObject var bp: BPClient
    @EnvironmentObject var health: Health
    @State private var autoSaveToHealth = true

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("LibreArm").font(.title).bold()
                Text(bp.status).foregroundColor(.secondary)

                if let r = bp.lastReading {
                    VStack {
                        Text("\(Int(r.sys))/\(Int(r.dia)) mmHg")
                            .font(.system(size: 34, weight: .semibold))
                        if let hr = r.hr {
                            Text("HR \(Int(hr)) bpm").foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                }

                Button {
                    bp.startScanAndMeasure()
                } label: {
                    Text("Start Measurement")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)

                Toggle("Save to Apple Health", isOn: $autoSaveToHealth)

                Spacer()
            }
            .padding()
            .task {
                // Request HealthKit auth
                do { try await health.requestAuth() }
                catch { bp.status = "Health permission denied" }

                // Save ONLY the final debounced reading
                bp.onFinalReading = { reading in
                    guard autoSaveToHealth else { return }
                    Task {
                        try? await health.saveBP(
                            systolic: reading.sys,
                            diastolic: reading.dia,
                            bpm: reading.hr,
                            date: Date()
                        )
                    }
                }
            }
            .navigationTitle("Blood Pressure")
        }
    }
}
