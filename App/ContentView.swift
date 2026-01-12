import SwiftUI

struct ContentView: View {
    @EnvironmentObject var bp: BPClient
    @EnvironmentObject var health: Health
    @AppStorage("autoSaveToHealth") private var autoSaveToHealth = true
    @AppStorage("measurementMode") private var measurementModeString = "single"
    @AppStorage("delayBetweenRuns") private var delayBetweenRuns: Double = 30.0

    private var delaySecondsText: String {
        "\(Int(delayBetweenRuns))s"
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // Top bar - LibreArm on left, Blood Pressure on right
                HStack {
                    Text("LibreArm")
                        .font(.title2)
                        .bold()
                    Spacer()
                    Text("Blood Pressure")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                // Status line (Connection and Battery)
                HStack {
                    Text(bp.status)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(bp.batteryStatusLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)

                // Reading card with embedded graph - always visible
                VStack(spacing: 8) {
                    if let r = bp.lastReading {
                        // BP reading and stats on same line
                        HStack(spacing: 12) {
                            Text("\(Int(r.sys))/\(Int(r.dia)) mmHg")
                                .font(.system(size: 24, weight: .semibold))
                            if let map = r.map {
                                Label("\(Int(map)) MAP", systemImage: "gauge")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if let hr = r.hr {
                                Label("\(Int(hr)) bpm", systemImage: "heart.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Embedded graph with actual reading
                        HypertensionGraphView(systolic: r.sys, diastolic: r.dia)
                            .frame(height: 280)
                            .padding(.top, 4)
                    } else {
                        // Placeholder when no reading exists yet
                        Text("No reading yet")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.secondary)

                        // Empty graph with default values
                        HypertensionGraphView(systolic: 120, diastolic: 80)
                            .frame(height: 280)
                            .padding(.top, 4)
                            .opacity(0.3)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

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
                        set: { newValue in
                            bp.measurementMode = newValue ? .average3 : .single
                            measurementModeString = newValue ? "average3" : "single"
                        }
                    ))
                    .labelsHidden()
                    .disabled(bp.isMeasuring)
                }

                // Delay Slider (always visible, disabled when not in Average mode)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Delay between readings (seconds)")
                        Spacer()
                        Text(delaySecondsText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $delayBetweenRuns,
                        in: 15...60,
                        step: 15,
                        onEditingChanged: { editing in
                            if !editing {
                                // Snap to nearest of [15, 30, 45, 60]
                                let options: [Double] = [15, 30, 45, 60]
                                let v = delayBetweenRuns
                                let snapped = options.min(by: { abs($0 - v) < abs($1 - v) }) ?? 30
                                delayBetweenRuns = snapped
                                bp.delayBetweenRuns = snapped
                            }
                        }
                    )
                    .disabled(bp.isMeasuring || bp.measurementMode != .average3)
                }
                .padding(.horizontal)

                Spacer(minLength: 8)

                // Retry button
                if !bp.isConnected {
                    Button("Retry Connect") { bp.startConnect(timeout: 30) }
                        .buttonStyle(.bordered)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // Footer - Credits
                VStack(spacing: 4) {
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
            .navigationBarHidden(true)
            .task {
                // Restore settings from UserDefaults
                bp.measurementMode = (measurementModeString == "average3") ? .average3 : .single
                bp.delayBetweenRuns = delayBetweenRuns

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
