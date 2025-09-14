import CoreBluetooth
import Foundation

struct BPReading { let sys: Double; let dia: Double; let map: Double?; let hr: Double? }

final class BPClient: NSObject, ObservableObject {
    @Published var status = "Ready"
    @Published var lastReading: BPReading?

    /// Fires once per measurement session when the cuff stops sending updates.
    var onFinalReading: ((BPReading) -> Void)?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var measurementChar: CBCharacteristic?
    private var controlChar: CBCharacteristic?

    // Debounce/Session
    private var completionWorkItem: DispatchWorkItem?
    private let completionDebounceSeconds: TimeInterval = 1.5
    private var sessionActive = false
    private var hasFiredFinal = false

    // Standard Blood Pressure Service + Measurement char
    private let bpsService  = CBUUID(string: "1810")
    private let measurement = CBUUID(string: "2A35")

    // QardioArm control ("feature") characteristic lives inside 0x1810
    private let control = CBUUID(string: "583CB5B3-875D-40ED-9098-C39EB0C1983D")

    // Commands (little-endian on the wire)
    private let startCommand  = Data([0xF1, 0x01])
    private let cancelCommand = Data([0xF1, 0x02])

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Public API

    func startScanAndMeasure() {
        guard central.state == .poweredOn else {
            status = "Bluetooth unavailable"
            return
        }
        status = "Scanning…"
        sessionActive = false
        hasFiredFinal = false
        completionWorkItem?.cancel()
        central.scanForPeripherals(withServices: [bpsService], options: nil)
    }

    func cancelMeasurement() {
        guard let p = peripheral, let c = controlChar else { return }
        p.writeValue(cancelCommand, for: c, type: .withResponse)
        finalizeIfNeeded()
    }

    // MARK: - Helpers

    private func scheduleFinalize() {
        // Debounce: if another packet arrives, we’ll cancel and reschedule
        completionWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.finalizeIfNeeded()
        }
        completionWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + completionDebounceSeconds, execute: work)
    }

    private func finalizeIfNeeded() {
        guard sessionActive, !hasFiredFinal, let reading = lastReading else { return }
        hasFiredFinal = true
        sessionActive = false
        status = "Done"
        onFinalReading?(reading)
        // Optional: disconnect to save battery
        if let p = peripheral {
            central.stopScan()
            central.cancelPeripheralConnection(p)
        }
    }

    // MARK: - Parser

    private func parseBPM(_ data: Data) {
        // 0x2A35 layout: Flags (1), SYS (SFLOAT), DIA (SFLOAT), MAP (SFLOAT), [Timestamp 7], [Pulse SFLOAT], [...]
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

        // Treat any update as "still measuring"; we’ll debounce to detect the end.
        DispatchQueue.main.async {
            self.sessionActive = true
            self.status = "Measuring…"
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
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover p: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        status = "Connecting…"
        self.peripheral = p
        central.stopScan()
        p.delegate = self
        central.connect(p, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        status = "Discovering…"
        p.discoverServices([bpsService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        status = "Failed to connect"
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        // Reset session state on disconnect
        completionWorkItem?.cancel()
        sessionActive = false
        controlChar = nil
        measurementChar = nil
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

        // Kick off once both are ready
        if let c = controlChar, measurementChar != nil {
            status = "Measuring…"
            p.writeValue(startCommand, for: c, type: .withResponse)
        }
    }

    func peripheral(_ p: CBPeripheral, didWriteValueFor ch: CBCharacteristic, error: Error?) {
        if let error = error, ch.uuid == control {
            // Fallback to withoutResponse if withResponse fails
            if ch.properties.contains(.writeWithoutResponse) {
                p.writeValue(startCommand, for: ch, type: .withoutResponse)
            } else {
                status = "Write error: \(error.localizedDescription)"
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
}
