// Services/PersistenceController.swift
// Core Data stack — programmatically constructed NSManagedObjectModel,
// SQLite-backed NSPersistentContainer, and convenience CRUD helpers.
//
// Usage:
//   let ctx = PersistenceController.shared.context
//   VitalSignRecord.insert(from: data, in: ctx)
//   PersistenceController.shared.save()

import CoreData
import Foundation

final class PersistenceController {

    // MARK: - Singleton
    static let shared = PersistenceController()

    /// In-memory instance for unit testing / SwiftUI Previews
    static let preview: PersistenceController = {
        let ctrl = PersistenceController(inMemory: true)
        // Seed preview data
        let ctx = ctrl.context
        for data in VitalSignData.mockHistory(count: 50) {
            VitalSignRecord.insert(from: data, in: ctx)
        }
        for event in AlertEvent.mockEvents() {
            AlertRecord.insert(from: event, in: ctx)
        }
        ctrl.save()
        return ctrl
    }()

    // MARK: - Container
    let container: NSPersistentContainer

    // MARK: - Init
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(
            name: "CareElderlyStore",
            managedObjectModel: PersistenceController.buildManagedObjectModel()
        )

        if inMemory {
            // Store in /dev/null so nothing is written to disk
            container.persistentStoreDescriptions.first?.url =
                URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { [container] description, error in
            guard let error = error as NSError? else { return }

            // Schema mismatch — destroy the store (sqlite + sqlite-wal + sqlite-shm)
            // and retry on the main queue to avoid nested CoreData queue deadlock.
            print("⚠️ Core Data load failed (\(error.localizedDescription)) — recreating store")
            if let url = description.url {
                let psc = container.persistentStoreCoordinator
                try? psc.destroyPersistentStore(at: url, ofType: NSSQLiteStoreType, options: nil)
            }
            DispatchQueue.main.async {
                container.loadPersistentStores { _, retryError in
                    if let e = retryError as NSError? {
                        fatalError("Core Data retry failed: \(e), \(e.userInfo)")
                    }
                }
            }
        }

        // Automatically merge background-context saves into the view context
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: - Convenience Accessors
    /// The main-thread managed object context (use for all UI reads)
    var context: NSManagedObjectContext { container.viewContext }

    // MARK: - Save
    /// Persist any pending changes in the view context.
    func save() {
        let ctx = container.viewContext
        guard ctx.hasChanges else { return }
        do {
            try ctx.save()
        } catch {
            print("❌ Core Data save error: \(error.localizedDescription)")
        }
    }

    // MARK: - Background Save Helper
    /// Execute a block on a background context and save automatically.
    func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        container.performBackgroundTask { ctx in
            block(ctx)
            if ctx.hasChanges {
                try? ctx.save()
            }
        }
    }

    // MARK: - Delete All Records
    func deleteAllRecords() {
        let ctx = container.viewContext
        for entity in ["VitalSignRecord", "AlertRecord"] {
            let req = NSFetchRequest<NSFetchRequestResult>(entityName: entity)
            let del = NSBatchDeleteRequest(fetchRequest: req)
            _ = try? ctx.execute(del)
        }
        try? ctx.save()
        ctx.refreshAllObjects()
    }

    // MARK: - Batch Delete Helper
    /// Delete all records older than a given date to keep disk usage bounded.
    func deleteRecordsOlderThan(_ date: Date) {
        let ctx = container.viewContext

        let vitalReq = NSFetchRequest<NSFetchRequestResult>(entityName: "VitalSignRecord")
        vitalReq.predicate = NSPredicate(format: "timestamp < %@", date as NSDate)
        let deleteVital = NSBatchDeleteRequest(fetchRequest: vitalReq)

        let alertReq = NSFetchRequest<NSFetchRequestResult>(entityName: "AlertRecord")
        alertReq.predicate = NSPredicate(format: "timestamp < %@", date as NSDate)
        let deleteAlert = NSBatchDeleteRequest(fetchRequest: alertReq)

        do {
            try ctx.execute(deleteVital)
            try ctx.execute(deleteAlert)
            try ctx.save()
        } catch {
            print("❌ Batch delete error: \(error.localizedDescription)")
        }
    }

    // MARK: - Programmatic NSManagedObjectModel
    /// Build the Core Data schema entirely in code so no .xcdatamodeld file is needed.
    static func buildManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        // ── VitalSignRecord ──────────────────────────────────────────────────
        let vitalEntity = NSEntityDescription()
        vitalEntity.name = "VitalSignRecord"
        vitalEntity.managedObjectClassName = NSStringFromClass(VitalSignRecord.self)

        let vsID   = makeAttr("id",              type: .UUIDAttributeType,   optional: false)
        let vsTS   = makeAttr("timestamp",       type: .dateAttributeType,    optional: false)
        let vsHR   = makeAttr("heartRate",       type: .doubleAttributeType,  optional: false)
        let vsBR   = makeAttr("breathingRate",   type: .doubleAttributeType,  optional: false)
        let vsTemp = makeAttr("bodyTemperature", type: .doubleAttributeType,  optional: false)

        vitalEntity.properties = [vsID, vsTS, vsHR, vsBR, vsTemp]

        // ── AlertRecord ──────────────────────────────────────────────────────
        let alertEntity = NSEntityDescription()
        alertEntity.name = "AlertRecord"
        alertEntity.managedObjectClassName = NSStringFromClass(AlertRecord.self)

        let arID   = makeAttr("id",             type: .UUIDAttributeType,    optional: false)
        let arTS   = makeAttr("timestamp",      type: .dateAttributeType,    optional: false)
        let arType = makeAttr("alertType",      type: .stringAttributeType,  optional: false)
        let arHR   = makeAttr("heartRate",      type: .doubleAttributeType,  optional: false)
        let arBR   = makeAttr("breathingRate",  type: .doubleAttributeType,  optional: false)
        let arAck  = makeAttr("isAcknowledged", type: .booleanAttributeType, optional: false)
        let arAt   = makeAttr("acknowledgedAt", type: .dateAttributeType,    optional: true)

        alertEntity.properties = [arID, arTS, arType, arHR, arBR, arAck, arAt]

        model.entities = [vitalEntity, alertEntity]
        return model
    }

    /// Helper that creates a configured NSAttributeDescription.
    private static func makeAttr(_ name: String,
                                  type: NSAttributeType,
                                  optional: Bool) -> NSAttributeDescription {
        let attr = NSAttributeDescription()
        attr.name          = name
        attr.attributeType = type
        attr.isOptional    = optional
        return attr
    }
}
