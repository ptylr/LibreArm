import SwiftUI

struct ContentView: View {
    @EnvironmentObject var bp: BPClient
    @EnvironmentObject var health: Health
    @State private var autoSaveToHealth = true
    @State private var showGraph = false

    private var delaySecondsText: String {
        "\(Int(bp.delayBetweenRuns))s"
    }

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
                    Text(bp.status)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text(bp.batteryStatusLine)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
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

                        // Show graph link
                        Button {
                            showGraph = true
                        } label: {
                            Text("Show graph")
                                .font(.footnote)
                                .foregroundStyle(.blue)
                        }
                        .padding(.top, 4)
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
                .tint(bp.isMeasuring ? .red : .blue)
                .disabled((!bp.canMeasure && !bp.isMeasuring) || (bp.batteryLevelPct != nil && bp.batteryLevelPct! <= 10 && !bp.isMeasuring))

                // Save to Health toggle (disabled while measuring)
                Toggle("Save to Apple Health", isOn: $autoSaveToHealth)
                    .disabled(bp.isMeasuring)

                // Average Mode toggle (disabled while measuring)
                HStack {
                    Text("Average (3 readings)")
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { bp.measurementMode == .average3 },
                        set: { bp.measurementMode = $0 ? .average3 : .single }
                    ))
                    .labelsHidden()
                    .disabled(bp.isMeasuring)
                }

                // Delay Slider (only visible in Average mode; disabled while measuring)
                if bp.measurementMode == .average3 {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Delay between readings (seconds)")
                            Spacer()
                            Text(delaySecondsText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding<Double>(
                                get: { bp.delayBetweenRuns },
                                set: { newVal in bp.delayBetweenRuns = newVal }
                            ),
                            in: 15...60, // updated min
                            step: 15,    // updated step
                            onEditingChanged: { editing in
                                if !editing {
                                    // Snap to nearest of [15, 30, 45, 60]
                                    let options: [Double] = [15, 30, 45, 60]
                                    let v = bp.delayBetweenRuns
                                    let snapped = options.min(by: { abs($0 - v) < abs($1 - v) }) ?? 30
                                    bp.delayBetweenRuns = snapped
                                }
                            }
                        )
                        .disabled(bp.isMeasuring)
                    }
                    .padding(.horizontal)
                }

                Spacer(minLength: 12)

                // Retry button
                if !bp.isConnected {
                    Button("Retry Connect") { bp.startConnect(timeout: 30) }
                        .buttonStyle(.bordered)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // Footer
                VStack(spacing: 6) {
                    Text("Developed by Paul Taylor")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link("GitHub: ptylr/LibreArm",
                         destination: URL(string: "https://github.com/ptylr/LibreArm")!)
                        .font(.footnote)
                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                        Text("Version \(version)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 20)
            .navigationTitle("Blood Pressure")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showGraph) {
                if let r = bp.lastReading {
                    HypertensionGraphSheet(systolic: r.sys, diastolic: r.dia)
                }
            }
            .task {
                do {
                    try await health.requestAuth()
                } catch {
                    bp.status = "Health permission denied"
                }

                bp.onFinalReading = { reading in
                    // v1.4.0: Final validation guard before saving to Health
                    guard autoSaveToHealth, bp.isValidReading(reading) else { return }
                    Task {
                        try? await health.saveBP(
                            systolic: reading.sys,
                            diastolic: reading.dia,
                            bpm: reading.hr,
                            date: Date()
                        )
                    }
                }

                bp.startConnect(timeout: 30)
            }
        }
    }
}
