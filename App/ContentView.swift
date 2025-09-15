import SwiftUI

struct ContentView: View {
    @EnvironmentObject var bp: BPClient
    @EnvironmentObject var health: Health
    @State private var autoSaveToHealth = true

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image("LibreArmIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(radius: 8)
                        .accessibilityHidden(true)

                    Text("LibreArm").font(.title2).bold()
                    Text(bp.status).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)

                // Last reading card
                if let r = bp.lastReading {
                    VStack(spacing: 8) {
                        Text("\(Int(r.sys))/\(Int(r.dia)) mmHg")
                            .font(.system(size: 36, weight: .semibold))
                        HStack(spacing: 16) {
                            if let map = r.map { Label("\(Int(map)) MAP", systemImage: "gauge") }
                            if let hr = r.hr   { Label("\(Int(hr)) bpm", systemImage: "heart.fill") }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                // Start/Stop button
                Button {
                    if bp.isMeasuring {
                        bp.cancelMeasurement()
                    } else {
                        bp.startMeasurement()
                    }
                } label: {
                    Text(bp.isMeasuring ? "Stop Measurement" : "Start Measurement")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(bp.isMeasuring ? .red : .blue)     // 🔴 red while measuring
                .disabled(!bp.canMeasure && !bp.isMeasuring) // keep enabled to allow Stop during measuring

                // Save to Health toggle
                Toggle("Save to Apple Health", isOn: $autoSaveToHealth)

                Spacer(minLength: 12)

                if !bp.isConnected {
                    Button("Retry Connect") { bp.startConnect(timeout: 30) }
                        .buttonStyle(.bordered)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                VStack(spacing: 6) {
                    Text("Developed by Paul Taylor").font(.footnote).foregroundStyle(.secondary)
                    Link("GitHub: ptylr/LibreArm", destination: URL(string: "https://github.com/ptylr/LibreArm")!)
                        .font(.footnote)
                }
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 20)
            .navigationTitle("Blood Pressure")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                do { try await health.requestAuth() } catch { bp.status = "Health permission denied" }

                bp.onFinalReading = { reading in
                    guard autoSaveToHealth else { return }
                    Task { try? await health.saveBP(systolic: reading.sys, diastolic: reading.dia, bpm: reading.hr, date: Date()) }
                }

                bp.startConnect(timeout: 30)
            }
        }
    }
}
