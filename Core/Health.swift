import HealthKit

final class Health: ObservableObject {
    let store = HKHealthStore()

    func requestAuth() async throws {
        let s = HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic)!
        let d = HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic)!
        let hr = HKObjectType.quantityType(forIdentifier: .heartRate)!
        try await store.requestAuthorization(toShare: [s, d, hr], read: [])
    }

    func saveBP(systolic: Double, diastolic: Double, bpm: Double?, date: Date) async throws {
        let mmHg = HKUnit.millimeterOfMercury()
        let sType = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic)!
        let dType = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic)!
        let sSample = HKQuantitySample(type: sType, quantity: .init(unit: mmHg, doubleValue: systolic), start: date, end: date)
        let dSample = HKQuantitySample(type: dType, quantity: .init(unit: mmHg, doubleValue: diastolic), start: date, end: date)
        let corrType = HKCorrelationType.correlationType(forIdentifier: .bloodPressure)!
        try await store.save(HKCorrelation(type: corrType, start: date, end: date, objects: [sSample, dSample]))

        if let bpm = bpm {
            let unit = HKUnit.count().unitDivided(by: .minute())
            let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
            let hrSample = HKQuantitySample(type: hrType, quantity: .init(unit: unit, doubleValue: bpm), start: date, end: date)
            try await store.save(hrSample)
        }
    }
}
