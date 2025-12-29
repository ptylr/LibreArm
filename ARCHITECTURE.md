# LibreArm BLE Blood Pressure Measurement Flow

## Overview

The QardioArm uses Bluetooth Low Energy (BLE) with the standard **Blood Pressure Service (UUID 0x1810)** plus a proprietary control characteristic for triggering measurements.

This document describes the complete flow from device discovery to reading blood pressure values.

---

## 1. Bluetooth Initialization

```
┌─────────────────────────────────────────────────────────────┐
│  App Launch                                                 │
│  └── BPClient.init()                         :65-68         │
│       └── Create CBCentralManager                           │
│            └── centralManagerDidUpdateState() :309-316      │
│                 └── If .poweredOn → Ready to scan           │
│                 └── Else → "Bluetooth not available"        │
└─────────────────────────────────────────────────────────────┘
```

**Source:** `Core/BPClient.swift:65-68` (init), `Core/BPClient.swift:309-316` (state callback)

---

## 2. Device Discovery

```
┌─────────────────────────────────────────────────────────────┐
│  startConnect(timeout: 30)                   :73-102        │
│  ├── Check central.state == .poweredOn       :75-78         │
│  ├── Reset all UI state flags                :80-88         │
│  ├── scanForPeripherals(withServices:[0x1810]):92           │
│  │    └── Scan ONLY for Blood Pressure Service advertisers  │
│  └── Start 30s timeout timer                 :95-101        │
│       └── If no connection → "Not connected (timeout)"      │
└─────────────────────────────────────────────────────────────┘
```

**Source:** `Core/BPClient.swift:73-102`

### BLE UUIDs

Defined at `Core/BPClient.swift:53-58`:

| UUID | Description | Line |
|------|-------------|------|
| `0x1810` | Blood Pressure Service (standard) | :54 |
| `0x2A35` | Blood Pressure Measurement characteristic (standard) | :55 |
| `583CB5B3-875D-40ED-9098-C39EB0C1983D` | QardioArm Control characteristic (proprietary) | :58 |

### Commands

Defined at `Core/BPClient.swift:61-62`:

| Bytes | Action | Line |
|-------|--------|------|
| `0xF1 0x01` | Start measurement | :61 |
| `0xF1 0x02` | Cancel measurement | :62 |

---

## 3. Connection Establishment

```
┌─────────────────────────────────────────────────────────────┐
│  didDiscover(peripheral)                     :318-328       │
│  ├── Stop scanning                           :322           │
│  ├── Cancel timeout timer                    :323           │
│  ├── Status: "Connecting…"                   :324           │
│  └── central.connect(peripheral)             :327           │
│                                                             │
│  didConnect(peripheral)                      :330-334       │
│  ├── isConnected = true                      :331           │
│  ├── Status: "Connected — discovering…"      :332           │
│  └── discoverServices([0x1810])              :333           │
│                                                             │
│  didDiscoverServices                         :352-355       │
│  └── discoverCharacteristics([0x2A35,control]):354          │
│                                                             │
│  didDiscoverCharacteristics                  :358-369       │
│  ├── Find measurementChar (0x2A35)           :360-362       │
│  │    └── setNotifyValue(true)               :362           │
│  ├── Find controlChar (proprietary)          :363-364       │
│  ├── canMeasure = (both found)               :367           │
│  └── Status: "Connected — ready"             :368           │
└─────────────────────────────────────────────────────────────┘
```

**Source:** `Core/BPClient.swift:318-369`

---

## 4. Starting Measurement

```
┌─────────────────────────────────────────────────────────────┐
│  User taps "Start Measurement"                              │
│  └── startMeasurement()                      :105-129       │
│       ├── Check canMeasure == true           :106           │
│       ├── Guard against duplicate start      :108-110       │
│       ├── sessionActive = true               :112           │
│       ├── isMeasuring = true                 :114           │
│       ├── Disable screen sleep               :115           │
│       ├── Single vs Average3 mode            :118-128       │
│       └── performSingleRunStart()            :132-136       │
│            ├── Record measurementStartTime   :134           │
│            └── Write [0xF1,0x01] to controlChar :135        │
│                 └── Cuff begins INFLATING (hardware)        │
└─────────────────────────────────────────────────────────────┘
```

**Source:** `Core/BPClient.swift:105-136`

---

## 5. During Measurement (Hardware-Controlled)

```
┌─────────────────────────────────────────────────────────────┐
│  CUFF BEHAVIOR (not software controlled):                   │
│                                                             │
│  1. Inflate to ~180 mmHg                                    │
│  2. Slowly deflate while measuring oscillations             │
│  3. Send BLE notifications with partial readings:           │
│     └── sys=X, dia=0, map=0 (measurement in progress)       │
│  4. When complete, send final reading:                      │
│     └── sys=X, dia=Y, map=Z, hr=H (all values present)      │
│  5. Fully deflate                                           │
│                                                             │
│  Total duration: ~30-45 seconds                             │
│                                                             │
│  BLE notifications received at:              :382-386       │
│  └── didUpdateValueFor(characteristic)                      │
│       └── if uuid == measurement → parseBPM() :384-385      │
└─────────────────────────────────────────────────────────────┘
```

**Source:** `Core/BPClient.swift:382-386` (notification handler)

---

## 6. Receiving & Parsing BLE Data

```
┌─────────────────────────────────────────────────────────────┐
│  parseBPM(data)                              :258-303       │
│                                                             │
│  SFLOAT parsing function:                    :259-265       │
│  └── 16-bit: 12-bit mantissa + 4-bit exponent               │
│       └── value = mantissa × 10^exponent                    │
│                                                             │
│  Extract raw bytes:                          :267-268       │
│  Parse flags:                                :270           │
│  Parse sys/dia/map:                          :271-273       │
│  Check for timestamp (skip 7 bytes if present):276          │
│  Parse heart rate if present:                :278-281       │
│  Create BPReading struct:                    :283           │
└─────────────────────────────────────────────────────────────┘
```

### Data Format (IEEE-11073 SFLOAT)

```
┌────┬────┬────┬────┬────┬────┬────┬─────────┬─────────┐
│ 0  │ 1  │ 2  │ 3  │ 4  │ 5  │ 6  │ 7-13?   │ 14-15?  │
│flag│sys │sys │dia │dia │map │map │timestamp│ heart   │
│    │ lo │ hi │ lo │ hi │ lo │ hi │(optional│  rate   │
│    │    │    │    │    │    │    │ 7 bytes)│(optional│
└────┴────┴────┴────┴────┴────┴────┴─────────┴─────────┘
```

### FLAGS byte

| Bit | Mask | Description | Line |
|-----|------|-------------|------|
| 1 | `0x02` | Timestamp present | :276 |
| 2 | `0x04` | Heart rate present | :279 |

**Source:** `Core/BPClient.swift:258-303`

---

## 7. Low Battery Detection (v1.3.1)

```
┌─────────────────────────────────────────────────────────────┐
│  Inside parseBPM(), after parsing:           :285-302       │
│                                                             │
│  Calculate elapsed time:                     :288           │
│  elapsed = now - measurementStartTime                       │
│                                                             │
│  Check for "too quick" reading:              :289           │
│  tooQuick = (dia > 0 AND elapsed < 10s)                     │
│                                                             │
│  if tooQuick:                                :291-298       │
│     ├── sessionActive = false                :292           │
│     ├── isMeasuring = false                  :293           │
│     ├── measurementStartTime = nil           :294           │
│     ├── Re-enable screen sleep               :295           │
│     ├── Status: "🪫 Measurement failed..."   :296           │
│     └── return (abort, no reading saved)     :297           │
│                                                             │
│  else (valid reading):                       :300-301       │
│     ├── lastReading = reading                :300           │
│     └── scheduleFinalize()                   :301           │
└─────────────────────────────────────────────────────────────┘
```

### Constants

| Constant | Value | Location |
|----------|-------|----------|
| `minimumMeasurementSeconds` | 10 | `Core/BPClient.swift:47` |
| `measurementStartTime` | Set on start | `Core/BPClient.swift:134` |

**Source:** `Core/BPClient.swift:285-302`

---

## 8. Finalization & Validation

```
┌─────────────────────────────────────────────────────────────┐
│  scheduleFinalize()                          :155-162       │
│  └── Debounce 1.5s before calling finalizeIfNeeded()        │
│       └── completionDebounceSeconds = 1.5    :41            │
│                                                             │
│  finalizeIfNeeded()                          :164-224       │
│  ├── Guard: sessionActive && lastReading     :166           │
│  ├── Guard: dia > 0 (complete reading)       :170           │
│  │                                                          │
│  ├── AVERAGE3 MODE:                          :173-214       │
│  │    ├── Validate with isPlausible()        :174           │
│  │    ├── Accumulate reading                 :175           │
│  │    ├── If remainingRuns > 1:              :179-201       │
│  │    │    ├── Decrement remainingRuns       :180           │
│  │    │    ├── Start countdown timer         :183,188-199   │
│  │    │    └── After delay → performSingleRunStart()  :197  │
│  │    └── If last run:                       :205-214       │
│  │         ├── Compute average()             :205           │
│  │         └── Emit onFinalReading(avg)      :211           │
│  │                                                          │
│  └── SINGLE MODE:                            :217-223       │
│       └── Emit onFinalReading(reading)       :223           │
│                                                             │
│  isPlausible(reading)                        :396-400       │
│  ├── Check sys/dia are finite                :397           │
│  ├── sys: 60-260 mmHg                        :399           │
│  └── dia: 40-160 mmHg                        :399           │
│                                                             │
│  average(of: readings)                       :228-254       │
│  ├── Filter to plausible readings only       :230           │
│  ├── Fallback if none valid                  :233-240       │
│  ├── Calculate sys/dia averages              :242-244       │
│  ├── Calculate MAP average (if present)      :247-248       │
│  └── Calculate HR average (20-220 range)     :250-251       │
└─────────────────────────────────────────────────────────────┘
```

**Source:** `Core/BPClient.swift:155-254, 396-400`

---

## 9. Cancellation

```
┌─────────────────────────────────────────────────────────────┐
│  User taps "Stop Measurement"                               │
│  └── cancelMeasurement()                     :139-151       │
│       ├── Write [0xF1,0x02] to controlChar   :141           │
│       │    └── Cuff immediately deflates                    │
│       ├── remainingRuns = 0                  :143           │
│       ├── Clear accumulatedReadings          :144           │
│       ├── sessionActive = false              :146           │
│       ├── hasFiredFinal = true               :147           │
│       ├── isMeasuring = false                :148           │
│       ├── Re-enable screen sleep             :149           │
│       └── Status: "Connected — ready"        :150           │
└─────────────────────────────────────────────────────────────┘
```

**Source:** `Core/BPClient.swift:139-151`

---

## 10. Disconnection & Error Handling

```
┌─────────────────────────────────────────────────────────────┐
│  didDisconnectPeripheral                     :343-350       │
│  ├── isConnected = false                     :344           │
│  ├── canMeasure = false                      :345           │
│  ├── isMeasuring = false                     :346           │
│  ├── Status: "Disconnected"                  :347           │
│  └── Clear characteristic references         :348-349       │
│                                                             │
│  didFailToConnect                            :336-341       │
│  └── Status: "Failed to connect"             :340           │
│                                                             │
│  didWriteValueFor (error handling)           :371-379       │
│  └── Retry with .withoutResponse if needed   :373-374       │
│                                                             │
│  didUpdateNotificationStateFor               :389-393       │
│  └── Status: "Notify error: ..."             :391           │
└─────────────────────────────────────────────────────────────┘
```

**Source:** `Core/BPClient.swift:336-393`

---

## Complete Source Reference Table

| Phase | Function | Lines |
|-------|----------|-------|
| **Constants** | UUIDs, commands | :53-62 |
| **State variables** | UI flags, timers | :14-51 |
| **Init** | `init()` | :65-68 |
| **Connect** | `startConnect()` | :73-102 |
| **Start** | `startMeasurement()` | :105-129 |
| **Run** | `performSingleRunStart()` | :132-136 |
| **Cancel** | `cancelMeasurement()` | :139-151 |
| **Debounce** | `scheduleFinalize()` | :155-162 |
| **Finalize** | `finalizeIfNeeded()` | :164-224 |
| **Average** | `average(of:)` | :228-254 |
| **Parse** | `parseBPM()` | :258-303 |
| **BT State** | `centralManagerDidUpdateState()` | :309-316 |
| **Discover** | `didDiscover()` | :318-328 |
| **Connect CB** | `didConnect()` | :330-334 |
| **Fail** | `didFailToConnect()` | :336-341 |
| **Disconnect** | `didDisconnectPeripheral()` | :343-350 |
| **Services** | `didDiscoverServices()` | :352-355 |
| **Chars** | `didDiscoverCharacteristics()` | :358-369 |
| **Write** | `didWriteValueFor()` | :371-379 |
| **Read** | `didUpdateValueFor()` | :382-386 |
| **Notify** | `didUpdateNotificationStateFor()` | :389-393 |
| **Validate** | `isPlausible()` | :396-400 |

---

## Flow Diagram

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│    SCAN      │───▶│   CONNECT    │───▶│   DISCOVER   │───▶│    READY     │
│   :73-102    │    │  :318-328    │    │  :352-369    │    │    :368      │
└──────────────┘    └──────────────┘    └──────────────┘    └──────┬───────┘
                                                                   │
                         ┌─────────────────────────────────────────┘
                         ▼
                   ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
                   │    START     │───▶│   INFLATE    │───▶│   DEFLATE    │
                   │  :105-136    │    │  (hardware)  │    │  :382-386    │
                   └──────────────┘    └──────────────┘    └──────┬───────┘
                                                                  │
             ┌────────────────────┬────────────────────────────────┤
             ▼                    ▼                                ▼
      ┌──────────────┐    ┌──────────────┐                 ┌──────────────┐
      │   TOO FAST   │    │   PARTIAL    │                 │    FINAL     │
      │  :289-298    │    │  dia=0       │                 │   dia>0      │
      │  =LOW BATTERY│    │  (continue)  │                 │  :258-303    │
      └──────────────┘    └──────────────┘                 └──────┬───────┘
             │                                                    │
             ▼                                              ┌─────┴─────┐
      ┌──────────────┐                                      ▼           ▼
      │    ABORT     │                              ┌────────────┐ ┌────────────┐
      │   No save    │                              │   SINGLE   │ │  AVERAGE   │
      └──────────────┘                              │ :217-223   │ │ :173-214   │
                                                    └─────┬──────┘ └─────┬──────┘
                                                          │              │
                                                          ▼              ▼
                                                    ┌────────────┐ ┌────────────┐
                                                    │    SAVE    │ │  3 RUNS    │
                                                    │ onFinal    │ │  + AVG     │
                                                    │   :223     │ │ :205-211   │
                                                    └────────────┘ └────────────┘
```

---

## State Machine Summary

| State | Trigger | Next State |
|-------|---------|------------|
| **Idle** | `startConnect()` | Scanning |
| **Scanning** | Device found | Connecting |
| **Scanning** | Timeout (30s) | Idle (error) |
| **Connecting** | `didConnect` | Discovering |
| **Connecting** | `didFailToConnect` | Idle (error) |
| **Discovering** | Characteristics found | Ready |
| **Ready** | `startMeasurement()` | Measuring |
| **Measuring** | Final reading (dia>0) | Finalizing |
| **Measuring** | Too quick (<10s) | Ready (battery error) |
| **Measuring** | `cancelMeasurement()` | Ready |
| **Finalizing** | Single mode | Ready (saved) |
| **Finalizing** | Average mode, runs left | Measuring (next run) |
| **Finalizing** | Average mode, complete | Ready (saved) |
| **Any** | `didDisconnect` | Idle |
