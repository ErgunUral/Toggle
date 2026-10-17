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
    temp: Double? = nil,
    charging: Bool? = nil
) -> HistoryPoint {
    HistoryPoint(
        date: t0.addingTimeInterval(minutes * 60),
        battery: battery,
        rangeKm: nil,
        odometerKm: odo,
        outsideTemp: temp,
        isCharging: charging
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

    @Test func tripWithoutTemperatureHasNoAverage() throws {
        let trip = try #require(TripDeriver.trips(from: [point(0, odo: 0), point(5, odo: 10)]).first)
        #expect(trip.averageOutsideTemp == nil)
    }
}

// MARK: - Model adı ve lastik sıcaklıkları

struct VehicleInfoTests {
    @Test @MainActor func internalModelCodeMapsToMarketingName() {
        #expect(GarageStore.modelName("CSUV") == "T10X")
        #expect(GarageStore.modelName("csuv") == "T10X")
        #expect(GarageStore.modelName("T10F") == "T10F")
    }

    @Test func tireTemperaturesHasValue() {
        #expect(!TireTemperatures().hasValue)
        #expect(TireTemperatures(rearRight: 18).hasValue)
    }
}

// MARK: - Şarj oturumu türetme

struct ChargeDerivationTests {
    /// Araç yerinde (odometre sabit), 15 dakikada %50 → %66.
    private let fastCharge = [
        point(0, odo: 500, battery: 0.50),
        point(5, odo: 500, battery: 0.55),
        point(10, odo: 500, battery: 0.60),
        point(15, odo: 500, battery: 0.66),
    ]

    @Test func detectsContinuousSession() throws {
        let sessions = ChargeDeriver.sessions(from: fastCharge)
        let session = try #require(sessions.first)
        #expect(sessions.count == 1)
        #expect(!session.isApproximate)
        #expect(session.startBattery == 0.50)
        #expect(session.endBattery == 0.66)
        #expect(session.duration == 15 * 60)
        #expect(abs(session.gainPercent - 16) < 1e-9)
    }

    @Test func singlePointFluctuationIsNotACharge() {
        let sessions = ChargeDeriver.sessions(from: [
            point(0, odo: 0, battery: 0.72), point(5, odo: 0, battery: 0.73),
        ])
        #expect(sessions.isEmpty)
    }

    @Test func batteryGainWhileDrivingIsIgnored() {
        // Yavaşlarken geri kazanım: kilometre artıyor.
        let sessions = ChargeDeriver.sessions(from: [
            point(0, odo: 100, battery: 0.50), point(5, odo: 103, battery: 0.60),
        ])
        #expect(sessions.isEmpty)
    }

    @Test func batteryDropEndsTheSession() throws {
        let sessions = ChargeDeriver.sessions(from: [
            point(0, odo: 0, battery: 0.40), point(5, odo: 0, battery: 0.50),
            point(10, odo: 0, battery: 0.45),
            point(15, odo: 0, battery: 0.45), point(20, odo: 0, battery: 0.55),
        ])
        #expect(sessions.count == 2)
        #expect(sessions.map(\.endBattery) == [0.50, 0.55])
    }

    @Test func chargingFlagBridgesAPlateau() throws {
        let session = try #require(ChargeDeriver.sessions(from: [
            point(0, odo: 0, battery: 0.50, charging: true),
            point(5, odo: 0, battery: 0.60, charging: true),
            point(10, odo: 0, battery: 0.60, charging: true),
            point(15, odo: 0, battery: 0.70, charging: true),
        ]).first)
        #expect(session.endBattery == 0.70)
        #expect(session.duration == 15 * 60)
    }

    @Test func gapBetweenRecordsIsAnApproximateSession() throws {
        // Uygulama 5 saat kapalıydı; batarya %20 → %80, araç yerinde.
        let session = try #require(ChargeDeriver.sessions(from: [
            point(0, odo: 700, battery: 0.20), point(300, odo: 700, battery: 0.80),
        ]).first)
        #expect(session.isApproximate)
        #expect(abs(session.gainPercent - 60) < 1e-9)
    }

    @Test func gapLongerThanADayIsIgnored() {
        let sessions = ChargeDeriver.sessions(from: [
            point(0, odo: 0, battery: 0.20), point(25 * 60, odo: 0, battery: 0.90),
        ])
        #expect(sessions.isEmpty)
    }

    @Test func approximateSessionNeedsTheMinimumGain() {
        let sessions = ChargeDeriver.sessions(from: [
            point(0, odo: 0, battery: 0.50), point(300, odo: 0, battery: 0.52),
        ])
        #expect(sessions.isEmpty)
    }

    @Test func missingBatteryIsIgnored() {
        #expect(ChargeDeriver.sessions(from: [
            point(0, odo: 0, battery: nil), point(5, odo: 0, battery: 0.9),
        ]).isEmpty)
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

// MARK: - Dönem özeti

struct PeriodSummaryTests {
    private func trip(km: Double, minutes: Double, from: Double?, to: Double?) -> DerivedTrip {
        DerivedTrip(
            start: t0,
            end: t0.addingTimeInterval(minutes * 60),
            distanceKm: km,
            startBattery: from,
            endBattery: to,
            averageOutsideTemp: nil
        )
    }

    @Test func totalsAndAverageSpeed() {
        let summary = PeriodSummary(trips: [
            trip(km: 30, minutes: 30, from: 0.80, to: 0.74),
            trip(km: 60, minutes: 60, from: 0.74, to: 0.62),
        ])
        #expect(summary.tripCount == 2)
        #expect(summary.distanceKm == 90)
        #expect(summary.averageSpeedKmh == 60)
    }

    @Test func economyScoreFromBatteryUse() throws {
        // 90 km'de %18 düştü → 100 km'de %20 → (32 − 20) / 20 × 100 = 60.
        let summary = PeriodSummary(trips: [
            trip(km: 30, minutes: 30, from: 0.80, to: 0.74),
            trip(km: 60, minutes: 60, from: 0.74, to: 0.62),
        ])
        let per100 = try #require(summary.batteryPercentPer100Km)
        #expect(abs(per100 - 20) < 0.0001)
        let score = try #require(summary.economyScore)
        #expect(abs(score - 60) < 0.0001)
    }

    @Test func noScoreWithoutEnoughBatteryData() {
        let short = PeriodSummary(trips: [trip(km: 5, minutes: 10, from: 0.80, to: 0.78)])
        #expect(short.economyScore == nil)
        let missing = PeriodSummary(trips: [trip(km: 40, minutes: 40, from: nil, to: nil)])
        #expect(missing.economyScore == nil)
    }

    @Test func scoreIsClamped() throws {
        let thrifty = PeriodSummary(trips: [trip(km: 100, minutes: 90, from: 0.90, to: 0.85)])
        #expect(try #require(thrifty.economyScore) == 100)
        let heavy = PeriodSummary(trips: [trip(km: 50, minutes: 40, from: 0.90, to: 0.60)])
        #expect(try #require(heavy.economyScore) == 0)
    }
}

// MARK: - Sunucu analizleri

@Suite struct ServerAnalyticsTests {
    @Test func sarmalanmisYanitiCozerVeAlternatifAnahtarlariOkur() {
        let json: [String: Any] = ["data": [
            "journeys": [
                ["journey_id": "a", "start_ts": "2026-10-16T08:00:00Z", "distance_km": 12.5, "kwh_consumed": "2.1"],
                ["journey_id": "a", "start_ts": "2026-10-16T08:00:00Z", "distance_km": 99],
                ["journey_id": "b", "start_ts": "2026-10-17T08:00:00Z", "total_distance_km": 3],
            ],
            "journeys_pagination": ["has_more": true],
            "totals": ["total_km": 15.5],
        ]]
        let page = ServerAnalytics.page(from: json, isCharge: false)
        #expect(page.records.map(\.id) == ["b", "a"])
        #expect(page.records.last?.distanceKm == 12.5)
        #expect(page.records.last?.consumedKWh == 2.1)
        #expect(page.totals.distanceKm == 15.5)
        #expect(page.hasMore)
    }

    @Test func ozetBloklariniSirayladaDondurur() {
        let json: [String: Any] = ["all_time": ["journey_count": 4], "this_month": ["journey_count": 1]]
        let blocks = ServerAnalytics.insights(from: json)
        #expect(blocks.map(\.key) == ["this_month", "all_time"])
        #expect(blocks.last?.metrics.journeyCount == 4)
    }
}

// MARK: - Klima komutu sonucu

struct ClimateCommandResultTests {
    private func result(_ status: String) -> ClimateCommandResult {
        ClimateCommandResult(requestID: "r1", status: status, code: nil)
    }

    @Test func completedPasses() throws {
        try ClimateCommandError.check(result("COMPLETED"))
        try ClimateCommandError.check(result("completed"))
    }

    @Test(arguments: [
        ("FAILED", ClimateCommandError.failed),
        ("ERROR", ClimateCommandError.failed),
        ("REJECTED", ClimateCommandError.rejected),
        ("CANCELLED", ClimateCommandError.cancelled),
        ("", ClimateCommandError.unconfirmed),
        ("IN_PROGRESS", ClimateCommandError.unconfirmed),
    ])
    func nonCompletedStatusThrows(status: String, expected: ClimateCommandError) {
        #expect(throws: expected) {
            try ClimateCommandError.check(result(status))
        }
    }
}

// MARK: - Haftalık ekonomi puanı

struct WeeklyEconomyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// `daysAgo` gün önce biten, 20 km'lik ve verilen yüzde puan batarya harcayan gezi.
    private func trip(daysAgo: Double, usedPercent: Double, km: Double = 20) -> DerivedTrip {
        let end = now.addingTimeInterval(-daysAgo * 86_400)
        return DerivedTrip(
            start: end.addingTimeInterval(-1_800),
            end: end,
            distanceKm: km,
            startBattery: 0.9,
            endBattery: 0.9 - usedPercent / 100,
            averageOutsideTemp: nil
        )
    }

    @Test func returnsRequestedNumberOfWindowsOldestFirst() {
        let weeks = WeeklyEconomy.scores(from: [], weeks: 4, now: now)
        #expect(weeks.count == 4)
        #expect(weeks.map(\.start) == weeks.map(\.start).sorted())
        #expect(weeks.allSatisfy { $0.score == nil })
    }

    @Test func tripsFallIntoTheirWeek() {
        // %4 / 20 km = %20 / 100 km → 12...32 ölçeğinde 60 puan.
        let weeks = WeeklyEconomy.scores(from: [trip(daysAgo: 2, usedPercent: 4), trip(daysAgo: 10, usedPercent: 2)], weeks: 2, now: now)
        #expect(abs((weeks[1].score ?? 0) - 60) < 0.001)
        // %2 / 20 km = %10 / 100 km → 100 (üst sınır).
        #expect(weeks[0].score == 100)
    }

    @Test func changeComparesLastTwoScoredWeeks() {
        let weeks = WeeklyEconomy.scores(from: [trip(daysAgo: 2, usedPercent: 4), trip(daysAgo: 10, usedPercent: 2)], weeks: 3, now: now)
        #expect(abs((WeeklyEconomy.change(in: weeks) ?? 0) + 40) < 0.001)
    }

    @Test func noChangeWithSingleScoredWeek() {
        let weeks = WeeklyEconomy.scores(from: [trip(daysAgo: 2, usedPercent: 4)], weeks: 3, now: now)
        #expect(WeeklyEconomy.change(in: weeks) == nil)
    }

    @Test func tooShortDistanceHasNoScore() {
        let weeks = WeeklyEconomy.scores(from: [trip(daysAgo: 1, usedPercent: 1, km: 5)], weeks: 1, now: now)
        #expect(weeks[0].score == nil)
    }
}
