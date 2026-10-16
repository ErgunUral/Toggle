//
//  MyAppTests.swift
//  MyAppTests
//
//  Created by Ergün Ural on 16.10.2026.
//

import Foundation
import Testing
@testable import MyApp

// MARK: - Yardımcılar

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func point(
    _ minutes: Double,
    odo: Double?,
    battery: Double? = nil,
    temp: Double? = nil
) -> HistoryPoint {
    HistoryPoint(
        date: t0.addingTimeInterval(minutes * 60),
        battery: battery,
        rangeKm: nil,
        odometerKm: odo,
        outsideTemp: temp,
        isCharging: nil
    )
}

// MARK: - Gezi türetme

struct TripDerivationTests {
    /// 0–15 dk: 1000→1020 km, %80→%72. Park. 40–45 dk: 3 km. 3 saatlik boşlukta 77 km (kayıtsız).
    /// Sonda 0,2 km'lik gürültü.
    private let points = [
        point(0, odo: 1000, battery: 0.80, temp: 10),
        point(5, odo: 1008, battery: 0.77, temp: 10),
        point(10, odo: 1014, battery: 0.75, temp: 12),
        point(15, odo: 1020, battery: 0.72, temp: 12),
        point(25, odo: 1020, battery: 0.72),
        point(40, odo: 1020, battery: 0.72),
        point(45, odo: 1023, battery: 0.71),
        point(225, odo: 1100, battery: 0.60),
        point(230, odo: 1100.2, battery: 0.60),
    ]

    @Test func splitsTripsAtParkingAndGaps() {
        let trips = TripDeriver.trips(from: points)
        #expect(trips.count == 2)
    }

    @Test func tripFieldsAreComputed() throws {
        let trip = try #require(TripDeriver.trips(from: points).first)
        #expect(trip.distanceKm == 20)
        #expect(trip.duration == 15 * 60)
        #expect(trip.startBattery == 0.80)
        #expect(trip.endBattery == 0.72)
        let used = try #require(trip.batteryUsedPercent)
        #expect(abs(used - 8) < 1e-9)
        #expect(trip.averageOutsideTemp == 11)
        let speed = try #require(trip.averageSpeedKmh)
        #expect(abs(speed - 80) < 1e-9)
    }

    @Test func consumptionUsesCapacity() throws {
        let trip = try #require(TripDeriver.trips(from: points).first)
        // %8 × 82,7 kWh = 6,616 kWh; 20 km → 33,08 kWh/100 km
        let consumption = try #require(trip.consumption(capacityKWh: 82.7))
        #expect(abs(consumption - 33.08) < 0.001)
        #expect(trip.consumption(capacityKWh: nil) == nil)
    }

    @Test func shortTripHasNoConsumption() throws {
        let short = try #require(TripDeriver.trips(from: points).last)
        #expect(short.distanceKm == 3)
        #expect(short.consumption(capacityKWh: 82.7) == nil)
    }

    @Test func gapLongerThanLimitIsNotATrip() {
        let trips = TripDeriver.trips(from: [point(0, odo: 0), point(31, odo: 40)])
        #expect(trips.isEmpty)
    }

    @Test func odometerNoiseIsIgnored() {
        #expect(TripDeriver.trips(from: [point(0, odo: 100), point(5, odo: 100.2)]).isEmpty)
    }

    @Test func absurdJumpIsIgnored() {
        #expect(TripDeriver.trips(from: [point(0, odo: 0), point(5, odo: 2000)]).isEmpty)
    }

    @Test func missingOdometerIsIgnored() {
        #expect(TripDeriver.trips(from: [point(0, odo: nil), point(5, odo: nil)]).isEmpty)
    }

    @Test func chargingDuringTripHasNoBatteryUse() throws {
        let trip = try #require(TripDeriver.trips(from: [
            point(0, odo: 0, battery: 0.5),
            point(5, odo: 10, battery: 0.6),
        ]).first)
        #expect(trip.batteryUsedPercent == nil)
    }

    @Test func unsortedInputIsSorted() {
        let shuffled = [point(10, odo: 1014), point(0, odo: 1000), point(5, odo: 1008)]
        let trips = TripDeriver.trips(from: shuffled)
        #expect(trips.count == 1)
        #expect(trips.first?.distanceKm == 14)
    }

    @Test func weightedAverageConsumptionSkipsShortTrips() {
        let trips = TripDeriver.trips(from: points)
        let average = TripDeriver.averageConsumption(of: trips, capacityKWh: 82.7)
        #expect(average != nil)
        #expect(abs((average ?? 0) - 33.08) < 0.001)
        #expect(TripDeriver.averageConsumption(of: [], capacityKWh: 82.7) == nil)
    }
}

// MARK: - Geçmiş deposu

@MainActor
struct HistoryStoreTests {
    private func makeStore() -> (HistoryStore, URL) {
        let url = URL.temporaryDirectory.appending(path: "history-test-\(UUID().uuidString).json")
        return (HistoryStore(fileURL: url), url)
    }

    private func snapshot(_ date: Date?, odo: Double, live: Bool = true) -> VehicleSnapshot {
        var snapshot = VehicleSnapshot()
        snapshot.isLive = live
        snapshot.updatedAt = date
        snapshot.odometer = odo
        return snapshot
    }

    @Test func skipsSampleSnapshotsAndMissingVehicleTime() {
        let (store, _) = makeStore()
        store.record(snapshot(t0, odo: 1, live: false))
        store.record(snapshot(nil, odo: 1))
        #expect(store.points.isEmpty)
    }

    @Test func skipsMeasurementsCloserThanMinimumInterval() {
        let (store, _) = makeStore()
        store.record(snapshot(t0, odo: 1000))
        store.record(snapshot(t0.addingTimeInterval(100), odo: 1001))
        store.record(snapshot(t0.addingTimeInterval(6 * 60), odo: 1002))
        #expect(store.points.count == 2)
    }

    @Test func clearRemovesPointsAndFile() {
        let (store, url) = makeStore()
        store.record(snapshot(t0, odo: 1000))
        #expect(FileManager.default.fileExists(atPath: url.path()))
        store.clear()
        #expect(store.points.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path()))
    }

    @Test func persistsAcrossInstances() {
        let (store, url) = makeStore()
        store.record(snapshot(t0, odo: 1000))
        let reloaded = HistoryStore(fileURL: url)
        #expect(reloaded.points.count == 1)
        store.clear()
    }

    @Test func tripsFilterByEndDateNewestFirst() {
        let (store, _) = makeStore()
        // Eski gezi (10 gün önce) ve yeni gezi (1 gün önce).
        let now = t0.addingTimeInterval(20 * 24 * 3600)
        let old = now.addingTimeInterval(-10 * 24 * 3600)
        let recent = now.addingTimeInterval(-1 * 24 * 3600)
        for (base, odo) in [(old, 100.0), (recent, 500.0)] {
            store.record(snapshot(base, odo: odo))
            store.record(snapshot(base.addingTimeInterval(6 * 60), odo: odo + 10))
        }
        #expect(store.trips(lastDays: 30, now: now).count == 2)
        #expect(store.trips(lastDays: 7, now: now).count == 1)
        #expect(store.trips(lastDays: 30, now: now).first?.distanceKm == 10)
        let all = store.trips(lastDays: 30, now: now)
        #expect(all[0].start > all[1].start)
        store.clear()
    }
}

// MARK: - Şarj durumu ve renk

struct VehicleStateTests {
    private func state(chargeMode: String?) -> VehicleState {
        var state = VehicleState(vin: "X", name: "n", model: "m", edition: "e")
        state.chargeMode = chargeMode
        return state
    }

    @Test(arguments: ["CHRGMODE_CHARGE", "CHARGEMODE_AC_CHARGING", "DC_CHARGING", "CHARGING", "CHARGING_DC"])
    func chargingModes(mode: String) {
        #expect(state(chargeMode: mode).isCharging == true)
    }

    @Test(arguments: ["CHRGMODE_STANDBY", "NOT_CHARGING", ""])
    func nonChargingModes(mode: String) {
        #expect(state(chargeMode: mode).isCharging == false)
    }

    @Test func unknownChargeModeIsNil() {
        #expect(state(chargeMode: nil).isCharging == nil)
    }
}

struct VehicleColorTests {
    @Test(arguments: [
        ("Grey", VehicleColor.grey),
        ("BLUE", .blue),
        ("gray", .grey),
        ("OBSIDIAN_GREY", .obsidian_grey),
        ("obsidian-green", .obsidian_green),
        ("New White", .new_white),
    ])
    func apiNamesMap(name: String, expected: VehicleColor) {
        #expect(VehicleColor(apiName: name) == expected)
    }

    @Test func unknownApiNameIsNil() {
        #expect(VehicleColor(apiName: "PURPLE") == nil)
    }
}
