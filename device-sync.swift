import Foundation
import CloudKit
import Combine

// MARK: - Syncable Model

struct SyncDocument: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var content: String
    var modifiedAt: Date
    var deviceID: String
    var version: Int

    init(
        id: UUID = UUID(),
        title: String,
        content: String,
        modifiedAt: Date = Date(),
        deviceID: String,
        version: Int = 1
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.modifiedAt = modifiedAt
        self.deviceID = deviceID
        self.version = version
    }
}

// MARK: - Device Identity

final class DeviceIdentity {

    static let shared = DeviceIdentity()

    private let key = "AppleSync.DeviceID"

    var id: String {
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }

        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: key)

        return newID
    }
}

// MARK: - Pending Changes

struct PendingChange: Codable, Identifiable {

    let id: UUID
    let document: SyncDocument
    let createdAt: Date

    init(document: SyncDocument) {
        self.id = UUID()
        self.document = document
        self.createdAt = Date()
    }
}

// MARK: - Local Sync Store

@MainActor
final class LocalSyncStore: ObservableObject {

    @Published private(set) var documents: [UUID: SyncDocument] = [:]

    private let queueKey = "AppleSync.PendingChanges"

    private var pendingChanges: [PendingChange] = []

    init() {
        loadPendingChanges()
    }

    func update(
        id: UUID,
        title: String,
        content: String
    ) {

        let currentVersion =
            documents[id]?.version ?? 0

        let document = SyncDocument(
            id: id,
            title: title,
            content: content,
            modifiedAt: Date(),
            deviceID: DeviceIdentity.shared.id,
            version: currentVersion + 1
        )

        documents[id] = document

        pendingChanges.append(
            PendingChange(document: document)
        )

        savePendingChanges()
    }

    func insert(
        title: String,
        content: String
    ) -> SyncDocument {

        let document = SyncDocument(
            title: title,
            content: content,
            deviceID: DeviceIdentity.shared.id
        )

        documents[document.id] = document

        pendingChanges.append(
            PendingChange(document: document)
        )

        savePendingChanges()

        return document
    }

    func pending() -> [PendingChange] {
        pendingChanges
    }

    func markSynced(_ change: PendingChange) {

        pendingChanges.removeAll {
            $0.id == change.id
        }

        savePendingChanges()
    }

    private func savePendingChanges() {

        guard let data = try? JSONEncoder().encode(pendingChanges) else {
            return
        }

        UserDefaults.standard.set(
            data,
            forKey: queueKey
        )
    }

    private func loadPendingChanges() {

        guard
            let data = UserDefaults.standard.data(
                forKey: queueKey
            ),
            let changes = try? JSONDecoder().decode(
                [PendingChange].self,
                from: data
            )
        else {
            return
        }

        pendingChanges = changes
    }
}

// MARK: - Conflict Resolution

struct SyncConflictResolver {

    func resolve(
        local: SyncDocument,
        remote: SyncDocument
    ) -> SyncDocument {

        // Same version: newest modification wins.
        if local.version == remote.version {
            return local.modifiedAt >= remote.modifiedAt
                ? local
                : remote
        }

        // Newer version wins.
        if local.version > remote.version {
            return local
        }

        return remote
    }
}

// MARK: - CloudKit Synchronizer

actor CloudSyncEngine {

    private let database =
        CKContainer.default().privateCloudDatabase

    private let recordType =
        "SyncDocument"

    private let resolver =
        SyncConflictResolver()

    func upload(
        _ document: SyncDocument
    ) async throws {

        let recordID = CKRecord.ID(
            recordName: document.id.uuidString
        )

        let record = CKRecord(
            recordType: recordType,
            recordID: recordID
        )

        record["title"] =
            document.title as CKRecordValue

        record["content"] =
            document.content as CKRecordValue

        record["modifiedAt"] =
            document.modifiedAt as CKRecordValue

        record["deviceID"] =
            document.deviceID as CKRecordValue

        record["version"] =
            document.version as CKRecordValue

        _ = try await database.save(record)
    }

    func download(
        id: UUID
    ) async throws -> SyncDocument? {

        let recordID = CKRecord.ID(
            recordName: id.uuidString
        )

        do {

            let record =
                try await database.record(for: recordID)

            guard
                let title =
                    record["title"] as? String,
                let content =
                    record["content"] as? String,
                let modifiedAt =
                    record["modifiedAt"] as? Date,
                let deviceID =
                    record["deviceID"] as? String,
                let version =
                    record["version"] as? Int
            else {
                return nil
            }

            return SyncDocument(
                id: id,
                title: title,
                content: content,
                modifiedAt: modifiedAt,
                deviceID: deviceID,
                version: version
            )

        } catch {

            return nil
        }
    }
}

// MARK: - Synchronization Coordinator

@MainActor
final class AppleDeviceSync: ObservableObject {

    let store = LocalSyncStore()

    private let cloud = CloudSyncEngine()

    @Published private(set) var isSynchronizing = false

    func synchronize() async {

        guard !isSynchronizing else {
            return
        }

        isSynchronizing = true

        defer {
            isSynchronizing = false
        }

        for change in store.pending() {

            do {

                try await cloud.upload(
                    change.document
                )

                store.markSynced(change)

            } catch {

                print(
                    "Sync failed:",
                    error.localizedDescription
                )
            }
        }
    }
}






import CloudKit

final class CloudChangeObserver {

    private let database =
        CKContainer.default().privateCloudDatabase

    func register() async throws {

        let subscription =
            CKQuerySubscription(
                recordType: "SyncDocument",
                predicate: NSPredicate(value: true),
                subscriptionID: "AppleSync.DocumentChanges",
                options: [
                    .firesOnRecordCreation,
                    .firesOnRecordUpdate,
                    .firesOnRecordDeletion
                ]
            )

        let notification =
            CKSubscription.NotificationInfo()

        notification.shouldSendContentAvailable = true

        subscription.notificationInfo =
            notification

        try await database.save(subscription)
    }
}



