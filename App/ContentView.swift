import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var bp: BPClient
    @EnvironmentObject private var health: Health
    @EnvironmentObject private var coffee: CoffeeSupport
    @State private var showsCoffeeSupport = {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--screenshot-state=coffee")
#else
        false
#endif
    }()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("autoSaveToHealth") private var autoSaveToHealth = true
    @AppStorage("readingCount") private var readingCount = 1
    @AppStorage("delayBetweenRuns") private var delayBetweenRuns = 30.0
    @State private var nextMeasurementIsGuest = {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--screenshot-state=guest")
#else
        false
#endif
    }()

    var body: some View {
        NavigationStack {
            ViewThatFits(in: .vertical) {
                content
                ScrollView { content }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                footer
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await configure() }
            .sheet(isPresented: $showsCoffeeSupport) {
                CoffeeSupportView(coffee: coffee)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { bp.refreshBattery() }
            }
            .onChange(of: readingCount) { _, value in
                bp.readingCount = min(max(value, 1), 3)
            }
            .onChange(of: delayBetweenRuns) { _, value in
                bp.delayBetweenRuns = min(max(value, 15), 60)
            }
            .onChange(of: nextMeasurementIsGuest) { _, _ in
                health.resetSaveState()
            }
        }
    }

    private var content: some View {
        VStack(spacing: 12) {
            header
            status
            readingCard
            measurementControls
            settings
            healthAuthorizationStatus
            healthStatus
            recovery
        }
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("LibreArm: Blood Pressure")
                .font(.title2.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer()
            Text(bp.batteryStatusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(bp.batteryStatusLine)
        }
    }

    private var status: some View {
        Text(bp.status)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(2)
    }

    private var readingCard: some View {
        let reading = bp.lastReading ?? bp.liveReading
        return VStack(spacing: 7) {
            Text(reading.map { "\(Int($0.sys.rounded()))/\(Int($0.dia.rounded())) mmHg" } ?? "—/— mmHg")
                .font(.title2.bold())

            HStack(spacing: 8) {
                Text(reading?.map.map { "\(Int($0.rounded())) MAP" } ?? "— MAP")
                Text("|")
                Text(reading?.hr.map { "\(Int($0.rounded())) bpm" } ?? "— bpm")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)

            if let reading = bp.lastReading, reading.irregularPulseDetected {
                Label("Device-reported irregular pulse; this is not a diagnosis.", systemImage: "waveform.path.ecg")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let reading = bp.lastReading, !reading.isWithinSupportedSaveRange {
                Label("Outside LibreArm’s supported save range; visible but not saved.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HypertensionGraphView(
                systolic: reading?.sys,
                diastolic: reading?.dia,
                showsClassification: bp.lastReading != nil
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var measurementControls: some View {
        VStack(spacing: 6) {
            Button {
                if bp.isMeasuring {
                    bp.cancelMeasurement()
                } else {
                    health.resetSaveState()
                    bp.startMeasurement(guest: nextMeasurementIsGuest)
                }
            } label: {
                Label(
                    bp.isMeasuring ? "Stop Measurement" : nextMeasurementIsGuest ? "Start Guest Measurement" : "Start Measurement",
                    systemImage: bp.isMeasuring ? "stop.fill" : "play.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(bp.isMeasuring ? .red : .blue)
            .disabled((!bp.canMeasure && !bp.isMeasuring) || (bp.batteryLevelPct ?? 100) <= 10 && !bp.isMeasuring)
            .padding(.vertical, 5)

            Toggle(isOn: $nextMeasurementIsGuest) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Guest measurement")
                    Text("One run only; it will not be saved to Apple Health.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .disabled(bp.isMeasuring)
        }
    }

    private var settings: some View {
        GroupBox("Measurement settings") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Save owner readings to Apple Health", isOn: $autoSaveToHealth)

                Picker("Readings to average", selection: $readingCount) {
                    ForEach(1...3, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .pickerStyle(.segmented)

                if readingCount > 1 {
                    HStack {
                        Text("Delay")
                        Slider(value: $delayBetweenRuns, in: 15...60, step: 15)
                            .accessibilityLabel("Delay between readings")
                            .accessibilityValue("\(Int(delayBetweenRuns)) seconds")
                        Text("\(Int(delayBetweenRuns))s")
                            .monospacedDigit()
                    }
                    .font(.caption)
                }
            }
        }
        .font(.subheadline)
        .disabled(bp.isMeasuring || nextMeasurementIsGuest)
        .opacity(bp.isMeasuring || nextMeasurementIsGuest ? 0.55 : 1)
        .padding(.top, 6)
    }

    @ViewBuilder
    private var healthAuthorizationStatus: some View {
        switch health.authorizationState {
        case .notRequested, .ready:
            EmptyView()
        case .requesting:
            Label("Requesting Apple Health access…", systemImage: "heart.text.square")
                .font(.caption)
                .foregroundStyle(.secondary)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var healthStatus: some View {
        switch health.saveState {
        case .idle: EmptyView()
        case .saving: Label("Saving to Apple Health…", systemImage: "arrow.triangle.2.circlepath").font(.caption)
        case .saved: Label("Saved to Apple Health", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
        case let .partiallySaved(message), let .failed(message), let .skipped(message):
            Label(message, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var recovery: some View {
        if !bp.isConnected {
            Button("Retry Connection") { bp.startConnect(timeout: 30) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Button {
                showsCoffeeSupport = true
            } label: {
                HStack(spacing: 6) {
                    Text("🫘")
                        .accessibilityHidden(true)
                    Text("Buy LibreArm a coffee")
                }
                .font(.caption)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
            .accessibilityLabel("Buy LibreArm a coffee")
            .accessibilityHint("Shows an optional one-time Apple purchase")

            HStack(alignment: .center, spacing: 6) {
                Text("Paul Taylor")
                Text("•")
                Link("GitHub: ptylr/LibreArm", destination: URL(string: "https://github.com/ptylr/LibreArm")!)
                    .foregroundStyle(.blue)
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    Text("• v\(version)")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.bottom, 10)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func configure() async {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--screenshot-state=") }) {
            readingCount = 3
            delayBetweenRuns = 30
        }
#endif
        readingCount = min(max(readingCount, 1), 3)
        delayBetweenRuns = min(max(delayBetweenRuns, 15), 60)
        bp.readingCount = readingCount
        bp.delayBetweenRuns = delayBetweenRuns
        await health.requestAuth()
        bp.onFinalReading = { reading, wasGuest in
            Task { @MainActor in
                _ = await health.record(reading, guest: wasGuest, enabled: autoSaveToHealth)
                if wasGuest {
                    nextMeasurementIsGuest = false
                }
            }
        }
        bp.startConnect(timeout: 30)
    }
}
