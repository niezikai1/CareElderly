// Models/CoreDataModels.swift
// NSManagedObject subclasses for the two Core Data entities:
//   • VitalSignRecord  — one row per received vital-sign sample
//   • AlertRecord      — one row per alert event
//
// The data model is built programmatically in PersistenceController
// so no .xcdatamodeld file is required.

import CoreData
import Foundation

// MARK: - VitalSignRecord
/// Persistent store entry for a single vital-sign measurement.
@objc(VitalSignRecord)
final class VitalSignRecord: NSManagedObject {
    @NSManaged var id:              UUID
    @NSManaged var timestamp:       Date
    @NSManaged var heartRate:       Double   // bpm
    @NSManaged var breathingRate:   Double   // rpm
    @NSManaged var bodyTemperature: Double   // °C (0.0 = not recorded)

    // MARK: Convenience factory
    /// Insert a new record into the given context from a VitalSignData value object.
    @discardableResult
    static func insert(from data: VitalSignData,
                       in context: NSManagedObjectContext) -> VitalSignRecord {
        let record = VitalSignRecord(context: context)
        record.id              = data.id
        record.timestamp       = data.timestamp
        record.heartRate       = data.heartRate
        record.breathingRate   = data.breathingRate
        record.bodyTemperature = data.bodyTemperature ?? 0.0
        return record
    }

    // MARK: Conversion back to value type
    var toVitalSignData: VitalSignData {
        VitalSignData(heartRate: heartRate, breathingRate: breathingRate,
                      bodyTemperature: bodyTemperature > 0 ? bodyTemperature : nil,
                      timestamp: timestamp)
    }

    // MARK: Fetch requests
    /// All records sorted by timestamp descending (newest first).
    static func fetchAllDescending() -> NSFetchRequest<VitalSignRecord> {
        let req = NSFetchRequest<VitalSignRecord>(entityName: "VitalSignRecord")
        req.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        return req
    }

    /// Records whose timestamp falls within [start, end].
    static func fetchInRange(start: Date, end: Date) -> NSFetchRequest<VitalSignRecord> {
        let req = fetchAllDescending()
        req.predicate = NSPredicate(format: "timestamp >= %@ AND timestamp <= %@",
                                    start as NSDate, end as NSDate)
        return req
    }
}

// MARK: - AlertRecord
/// Persistent store entry for an alert event.
@objc(AlertRecord)
final class AlertRecord: NSManagedObject, Identifiable {
    @NSManaged var id:             UUID
    @NSManaged var timestamp:      Date
    @NSManaged var alertType:      String  // AlertType.rawValue
    @NSManaged var heartRate:      Double  // bpm at alert time (0 if unknown)
    @NSManaged var breathingRate:  Double  // rpm at alert time (0 if unknown)
    @NSManaged var isAcknowledged: Bool
    @NSManaged var acknowledgedAt: Date?   // nil until acknowledged

    // MARK: Convenience factory
    /// Insert a new record from an AlertEvent value object.
    @discardableResult
    static func insert(from event: AlertEvent,
                       in context: NSManagedObjectContext) -> AlertRecord {
        let record = AlertRecord(context: context)
        record.id             = event.id
        record.timestamp      = event.timestamp
        record.alertType      = event.type.rawValue
        record.heartRate      = event.heartRate      ?? 0
        record.breathingRate  = event.breathingRate  ?? 0
        record.isAcknowledged = event.isAcknowledged
        record.acknowledgedAt = event.acknowledgedAt
        return record
    }

    // MARK: Conversion back to value type
    var toAlertEvent: AlertEvent? {
        guard let type = AlertType(rawValue: alertType) else { return nil }
        return AlertEvent(
            id:             id,
            type:           type,
            timestamp:      timestamp,
            heartRate:      heartRate      > 0 ? heartRate      : nil,
            breathingRate:  breathingRate  > 0 ? breathingRate  : nil,
            isAcknowledged: isAcknowledged,
            acknowledgedAt: acknowledgedAt
        )
    }

    // MARK: Fetch requests
    /// All alert records sorted newest-first.
    static func fetchAllDescending() -> NSFetchRequest<AlertRecord> {
        let req = NSFetchRequest<AlertRecord>(entityName: "AlertRecord")
        req.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        return req
    }

    static func fetchPending() -> NSFetchRequest<AlertRecord> {
        let req = fetchAllDescending()
        req.predicate = NSPredicate(format: "isAcknowledged == NO")
        return req
    }

    static func fetchHandled() -> NSFetchRequest<AlertRecord> {
        let req = fetchAllDescending()
        req.predicate = NSPredicate(format: "isAcknowledged == YES")
        return req
    }

    /// Alert records in a given date range.
    static func fetchInRange(start: Date, end: Date) -> NSFetchRequest<AlertRecord> {
        let req = fetchAllDescending()
        req.predicate = NSPredicate(format: "timestamp >= %@ AND timestamp <= %@",
                                    start as NSDate, end as NSDate)
        return req
    }

    /// Unacknowledged critical alerts.
    static func fetchUnacknowledgedCritical() -> NSFetchRequest<AlertRecord> {
        let req = fetchAllDescending()
        let criticalTypes = AlertType.allCases
            .filter { $0.isCritical }
            .map { $0.rawValue }
        req.predicate = NSPredicate(
            format: "isAcknowledged == NO AND alertType IN %@", criticalTypes)
        return req
    }
}
