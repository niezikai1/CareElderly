// ViewModels/HistoryViewModel.swift
// Queries Core Data for historical vital-sign records and alert events,
// computes statistics, and provides grouped data for trend charts.

import Foundation
import CoreData
import Combine

// MARK: - Date Range Filter
enum DateRangeFilter: String, CaseIterable, Identifiable {
    case today   = "Today"
    case week    = "7 Days"
    case month   = "30 Days"
    case all     = "All Time"

    var id: String { rawValue }

    /// Returns the start date for this filter range (end is always now)
    var startDate: Date {
        let cal  = Calendar.current
        let now  = Date()
        switch self {
        case .today:  return cal.startOfDay(for: now)
        case .week:   return cal.date(byAdding: .day,   value: -7,  to: now)!
        case .month:  return cal.date(byAdding: .day,   value: -30, to: now)!
        case .all:    return Date(timeIntervalSince1970: 0)
        }
    }
}

// MARK: - History Content Tab
enum HistoryTab: String, CaseIterable, Identifiable {
    case vitals = "Vitals"
    case alerts = "Alerts"
    var id: String { rawValue }
}

// MARK: - Day-Aggregate (for trend chart)
/// One data point representing the average readings for a calendar day.
struct DailyAggregate: Identifiable {
    let id:          UUID = UUID()
    let date:        Date    // Midnight of the represented day
    let avgHeartRate:     Double
    let avgBreathingRate: Double
    let alertCount:  Int
}

// MARK: - HistoryViewModel
class HistoryViewModel: ObservableObject {

    // MARK: Published
    @Published var vitalRecords:     [VitalSignData]   = []
    @Published var alertRecords:     [AlertEvent]      = []
    @Published var dailyAggregates:  [DailyAggregate]  = []

    // Statistics
    @Published var avgHeartRate:     Double?
    @Published var avgBreathingRate: Double?
    @Published var totalAlertCount:  Int = 0
    @Published var criticalCount:    Int = 0

    // AI Analytics — exposed to AnalyticsView
    @Published var baseline: HealthBaseline? = nil

    // Filter state — changes trigger a re-fetch
    @Published var dateFilter:  DateRangeFilter = .week  { didSet { fetch() } }
    @Published var selectedTab: HistoryTab      = .vitals

    // MARK: Private
    private let persistence = PersistenceController.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init
    init() {
        fetch()
        // Observe Core Data changes (new records from VitalSignViewModel)
        NotificationCenter.default
            .publisher(for: .NSManagedObjectContextObjectsDidChange,
                       object: persistence.context)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.fetch() }
            .store(in: &cancellables)
    }

    // MARK: - Fetch
    /// Re-query Core Data for the current date range.
    func fetch() {
        let start = dateFilter.startDate
        let end   = Date()
        let ctx   = persistence.context

        // ── Vital sign records ───────────────────────────────────────────────
        let vReq = VitalSignRecord.fetchInRange(start: start, end: end)
        vReq.fetchLimit = 500   // Cap to avoid memory pressure
        // Fetch alerts FIRST so buildDailyAggregates can count them per day
        let aReq = AlertRecord.fetchInRange(start: start, end: end)
        do {
            let rawAlerts = try ctx.fetch(aReq)
            alertRecords  = rawAlerts.compactMap { $0.toAlertEvent }
            computeAlertStats(rawAlerts)
        } catch {
            print("❌ History alert fetch error: \(error)")
        }

        do {
            let rawVitals    = try ctx.fetch(vReq)
            vitalRecords     = rawVitals.map { $0.toVitalSignData }
            computeVitalStats(rawVitals)
            buildDailyAggregates(rawVitals)  // alertRecords is now populated
            // Build personalised baseline from all available records (not just current filter)
            buildBaseline()
        } catch {
            print("❌ History vital fetch error: \(error)")
        }
    }

    // MARK: - Statistics Computation

    private func computeVitalStats(_ records: [VitalSignRecord]) {
        guard !records.isEmpty else {
            avgHeartRate     = nil
            avgBreathingRate = nil
            return
        }
        let count = Double(records.count)
        avgHeartRate     = records.reduce(0) { $0 + $1.heartRate }     / count
        avgBreathingRate = records.reduce(0) { $0 + $1.breathingRate } / count
    }

    private func computeAlertStats(_ records: [AlertRecord]) {
        totalAlertCount = records.count
        criticalCount   = records.filter { AlertType(rawValue: $0.alertType)?.isCritical == true }.count
    }

    // MARK: - Daily Aggregates (for trend chart)

    private func buildDailyAggregates(_ records: [VitalSignRecord]) {
        let cal = Calendar.current

        // Group records by calendar day
        let grouped = Dictionary(grouping: records) { record in
            cal.startOfDay(for: record.timestamp)
        }

        // Compute daily averages, sorted by date ascending
        dailyAggregates = grouped
            .sorted { $0.key < $1.key }
            .map { (day, dayRecords) in
                let n     = Double(dayRecords.count)
                let avgHR = dayRecords.reduce(0) { $0 + $1.heartRate }     / n
                let avgBR = dayRecords.reduce(0) { $0 + $1.breathingRate } / n

                // Count alerts on that day
                let alertsOnDay = alertRecords.filter {
                    cal.startOfDay(for: $0.timestamp) == day
                }.count

                return DailyAggregate(
                    date:             day,
                    avgHeartRate:     avgHR,
                    avgBreathingRate: avgBR,
                    alertCount:       alertsOnDay
                )
            }
    }

    // MARK: - Baseline (uses ALL records, ignores date filter)

    private func buildBaseline() {
        // Fetch all records regardless of current date filter to maximise sample count
        let req = VitalSignRecord.fetchAllDescending()
        req.fetchLimit = 2000
        if let all = try? persistence.context.fetch(req) {
            baseline = HealthAnalyticsService.shared.computeBaseline(from: all)
        }
    }

    // MARK: - Acknowledge Alert
    /// Mark an alert as acknowledged in Core Data.
    func acknowledge(event: AlertEvent) {
        let ctx  = persistence.context
        let req  = AlertRecord.fetchAllDescending()
        req.predicate = NSPredicate(format: "id == %@", event.id as CVarArg)
        req.fetchLimit = 1
        if let record = try? ctx.fetch(req).first {
            record.isAcknowledged = true
            record.acknowledgedAt = Date()
            persistence.save()
            fetch()  // Refresh list
        }
    }
}
