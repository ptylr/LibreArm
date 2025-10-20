import CoreBluetooth
import Foundation
import UIKit

enum MeasurementMode {
    case single
    case average3
}

struct BPReading { let sys: Double; let dia: Double; let map: Double?; let hr: Double? }

final class BPClient: NSObject, ObservableObject {
    // UI state
    @Published var status = "Searching for device…"
    @Published var lastReading: BPReading?
    @Published var isConnected = false
    @Published var canMeasure = false
    @Published var isMeasuring = false
    @Published var delayBetweenRuns: Double = 15

    // Measurement mode
    @Published var measurementMode: MeasurementMode = .single

    // Averaging session state (used only when measurementMode == .average3)
    private var remainingRuns: Int = 0
    private var accumulatedReadings: [BPReading] = []
    private let interRunDelaySeconds: TimeInterval = 15


    /// Fires once per measurement session when the cuff stops sending updates.
    var onFinalReading: ((BPReading) -> Void)?

    // BLE
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var measurementChar: CBCharacteristic?
    private var controlChar: CBCharacteristic?

    // Debounce/Session
    private var completionWorkItem: DispatchWorkItem?
    private let completionDebounceSeconds: TimeInterval = 1.5
    private var sessionActive = false
    private var hasFiredFinal = false

    // Connect timeout
    private var connectTimeoutWorkItem: DispatchWorkItem?
    private var connectTimeoutSeconds: TimeInterval = 30

    // Standard Blood Pressure Service + Measurement char
    private let bpsService  = CBUUID(string: "1810")
    private let measurement = CBUUID(string: "2A35")

    // QardioArm control ("feature") characteristic lives inside 0x1810
    private let control = CBUUID(string: "583CB5B3-875D-40ED-9098-C39EB0C1983D")

    // Commands (little-endian on the wire)
    private let startCommand  = Data([0xF1, 0x01])
    private let cancelCommand = Data([0xF1, 0x02])

    // MARK: - Lifecycle
    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Public API

    /// Begin scanning/connecting to the cuff. Call on app start or when user taps Retry.
    func startConnect(timeout: TimeInterval = 30) {
        connectTimeoutSeconds = timeout
        guard central.state == .poweredOn else {
            status = "Bluetooth unavailable"
            return
        }

        // reset UI/flags
        isConnected = false
        canMeasure = false
        isMeasuring = false
        lastReading = nil
        sessionActive = false
        hasFiredFinal = false
        completionWorkItem?.cancel()
        connectTimeoutWorkItem?.cancel()

        status = "Searching for device…"
        central.stopScan()
        central.scanForPeripherals(withServices: [bpsService], options: nil)

        // 30s timeout → mark not connected
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, !self.isConnected else { return }
            self.central.stopScan()
            self.status = "Not connected (timeout). Check power & Bluetooth."
        }
        connectTimeoutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    }

    /// Start measurement (enabled when `canMeasure` is true).
    func startMeasurement() {
        guard let _ = peripheral, let _ = controlChar, canMeasure else { return }

        if measurementMode == .average3 && sessionActive {
            return
        }
        status = (measurementMode == .average3) ? "Measuring (run 1 of 3)…" : "Measuring…"
        sessionActive = true
        hasFiredFinal = false
        isMeasuring = true
        UIApplication.shared.isIdleTimerDisabled = true
        completionWorkItem?.cancel()

        if measurementMode == .single {
            // One-and-done
            accumulatedReadings.removeAll()
            remainingRuns = 0
            performSingleRunStart()
        } else {
            // Average over 3 runs spaced by 10s
            accumulatedReadings.removeAll()
            remainingRuns = 3
            performSingleRunStart()
        }
    }

    /// Internal: send the start command to the cuff (assumes BLE characteristics are ready)
    private func performSingleRunStart() {
        guard let p = peripheral, let c = controlChar else { return }
        p.writeValue(startCommand, for: c, type: .withResponse)
    }

    /// Stop the current measurement without saving a reading.
    func cancelMeasurement() {
        guard let p = peripheral, let c = controlChar else { return }
        p.writeValue(cancelCommand, for: c, type: .withResponse)
        // Cancel any averaging session
        remainingRuns = 0
        accumulatedReadings.removeAll()
        // Do not call finalize (which would save); just reset state.
        sessionActive = false
        hasFiredFinal = true
        isMeasuring = false
        UIApplication.shared.isIdleTimerDisabled = false
        status = "Connected — ready"
    }

    // MARK: - Helpers

    private func scheduleFinalize() {
        completionWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.finalizeIfNeeded()
        }
        completionWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + completionDebounceSeconds, execute: work)
    }

    private func finalizeIfNeeded() {
        // Must be in-session, not already finalized, and have a latest reading
        guard sessionActive, let reading = lastReading else { return }

        // Only finalize when the measurement sequence has finished.
        // We use the presence of diastolic (>0) as the completion guard.
        guard reading.dia > 0 else { return }

        // For average3 mode, accumulate and schedule subsequent runs
        if measurementMode == .average3 {
            if isPlausible(reading) {
                accumulatedReadings.append(reading)
            }

            // If we still have more runs to do, schedule the next one
            if remainingRuns > 1 {
                remainingRuns -= 1

                // Use the user-selected delay (from slider)
                var countdown = Int(self.delayBetweenRuns)
                status = "Measured run \(3 - remainingRuns) of 3 — next in \(countdown)s…"
                isMeasuring = true

                // Countdown timer updates every second
                Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                    guard let self = self else { timer.invalidate(); return }
                    countdown -= 1
                    if countdown > 0 {
                        self.status = "Measured run \(3 - self.remainingRuns) of 3 — next in \(countdown)s…"
                    } else {
                        timer.invalidate()
                        self.status = "Measuring (run \(4 - self.remainingRuns) of 3)…"
                        self.isMeasuring = true
                        self.performSingleRunStart()
                    }
                }

                return
            }

            // This was the last run → compute average and emit once
            let avg = average(of: accumulatedReadings)
            hasFiredFinal = true
            sessionActive = false
            isMeasuring = false
            UIApplication.shared.isIdleTimerDisabled = false
            status = "Connected — ready"
            onFinalReading?(avg)
            remainingRuns = 0
            accumulatedReadings.removeAll()
            return
        }

        // Single mode → emit immediately
        hasFiredFinal = true
        sessionActive = false
        isMeasuring = false
        UIApplication.shared.isIdleTimerDisabled = false
        status = "Connected — ready"
        onFinalReading?(reading)
    }

    /// Returns the arithmetic mean of valid readings only.
    /// Falls back to the last valid reading if none pass plausibility checks.
    private func average(of readings: [BPReading]) -> BPReading {
        // Keep only plausible, finite values
        let valid = readings.filter { isPlausible($0) }

        // If none valid, try a sensible fallback
        if valid.isEmpty {
            if let r = lastReading, isPlausible(r) {
                return r
            } else {
                // Upstream guards should prevent saving 0/0
                return BPReading(sys: 0, dia: 0, map: nil, hr: nil)
            }
        }

        let n = Double(valid.count)
        let sysAvg = valid.map { $0.sys }.reduce(0, +) / n
        let diaAvg = valid.map { $0.dia }.reduce(0, +) / n

        // Optional fields averaged only when present and plausible
        let mapVals = valid.compactMap { $0.map }.filter { $0.isFinite }
        let mapAvg = mapVals.isEmpty ? nil : (mapVals.reduce(0, +) / Double(mapVals.count))

        let hrVals = valid.compactMap { $0.hr }.filter { $0.isFinite && $0 >= 20 && $0 <= 220 }
        let hrAvg = hrVals.isEmpty ? nil : (hrVals.reduce(0, +) / Double(hrVals.count))

        return BPReading(sys: sysAvg, dia: diaAvg, map: mapAvg, hr: hrAvg)
    }

    // MARK: - Parser

    private func parseBPM(_ data: Data) {
        func sfloat(_ lo: UInt8, _ hi: UInt8) -> Double {
            let raw = UInt16(hi) << 8 | UInt16(lo)
            let mantissa = Int16(raw & 0x0FFF)
            let exponent = Int8(Int16(raw) >> 12)
            let m = (mantissa >= 0x0800) ? Int32(mantissa) - 0x1000 : Int32(mantissa)
            return Double(m) * pow(10.0, Double(exponent))
        }

        let b = [UInt8](data)
        guard b.count >= 7 else { return }

        let flags = b[0]
        let sys = sfloat(b[1], b[2])
        let dia = sfloat(b[3], b[4])
        let map = sfloat(b[5], b[6])

        var idx = 7
        if (flags & 0x02) != 0 { idx += 7 } // timestamp present

        var hr: Double?
        if (flags & 0x04) != 0, b.count >= idx + 2 {
            hr = sfloat(b[idx], b[idx + 1])
        }

        let reading = BPReading(sys: sys, dia: dia, map: map, hr: hr)


        DispatchQueue.main.async {
            self.lastReading = reading
            self.scheduleFinalize()
        }
    }
}

// MARK: - CoreBluetooth

extension BPClient: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            status = "Bluetooth not available"
            isConnected = false
            canMeasure = false
            isMeasuring = false
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover p: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        central.stopScan()
        connectTimeoutWorkItem?.cancel()
        status = "Connecting…"
        self.peripheral = p
        p.delegate = self
        central.connect(p, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        isConnected = true
        status = "Connected — discovering…"
        p.discoverServices([bpsService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        isConnected = false
        canMeasure = false
        isMeasuring = false
        status = "Failed to connect"
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        isConnected = false
        canMeasure = false
        isMeasuring = false
        status = "Disconnected"
        measurementChar = nil
        controlChar = nil
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] where s.uuid == bpsService {
            p.discoverCharacteristics([measurement, control], for: s)
        }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] {
            if ch.uuid == measurement {
                measurementChar = ch
                p.setNotifyValue(true, for: ch)
            } else if ch.uuid == control {
                controlChar = ch
            }
        }
        canMeasure = (measurementChar != nil && controlChar != nil)
        if canMeasure { status = "Connected — ready" }
    }

    func peripheral(_ p: CBPeripheral, didWriteValueFor ch: CBCharacteristic, error: Error?) {
        if let error = error, ch.uuid == control {
            if ch.properties.contains(.writeWithoutResponse) {
                p.writeValue(startCommand, for: ch, type: .withoutResponse)
            } else {
                status = "Write error: \(error.localizedDescription)"
                isMeasuring = false
            }
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard error == nil else { status = "Read error"; return }
        if ch.uuid == measurement, let data = ch.value {
            parseBPM(data)
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        if let error = error {
            status = "Notify error: \(error.localizedDescription)"
        }
    }
    
    /// Filters out frames that are partial/invalid (e.g. IEEE-11073 SFLOAT NaN -> 0x07FF => 2047)
    private func isPlausible(_ r: BPReading) -> Bool {
        guard r.sys.isFinite, r.dia.isFinite else { return false }
        // Adult plausible range (tune if you support other populations)
        return (r.sys >= 60 && r.sys <= 260) && (r.dia >= 40 && r.dia <= 160)
    }
}
