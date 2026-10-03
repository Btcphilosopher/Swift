```swift
//
//  iCloudDashboard.swift
//
//  Native SwiftUI iCloud management dashboard.
//
//  Architecture:
//
//      SwiftUI Dashboard
//             │
//      iCloudDashboardModel
//             │
//      ┌──────┼───────────────┐
//      │      │               │
//   Storage  Files          Sync
//      │      │               │
//   Backup  Devices       Activity
//             │
//        iCloudService
//             │
//      CloudKit / iCloud
//
//  NOTE:
//  The service layer below contains a realistic local/demo implementation.
//  Replace its methods with Apple's supported CloudKit/iCloud APIs when
//  connecting to a real iCloud container.
//

import SwiftUI
import Foundation
import Combine

#if canImport(CloudKit)
import CloudKit
#endif


// ============================================================
// MARK: - MODELS
// ============================================================

enum DashboardSection: String, CaseIterable, Identifiable {

    case overview
    case files
    case storage
    case sync
    case backups
    case devices
    case activity
    case settings

    var id: String { rawValue }

    var title: String {

        switch self {
        case .overview: return "Overview"
        case .files: return "Files"
        case .storage: return "Storage"
        case .sync: return "Sync"
        case .backups: return "Backups"
        case .devices: return "Devices"
        case .activity: return "Activity"
        case .settings: return "Settings"
        }
    }

    var icon: String {

        switch self {
        case .overview: return "square.grid.2x2"
        case .files: return "folder"
        case .storage: return "internaldrive"
        case .sync: return "arrow.triangle.2.circlepath"
        case .backups: return "externaldrive.badge.icloud"
        case .devices: return "laptopcomputer.and.iphone"
        case .activity: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }
}


// ============================================================
// MARK: - STORAGE
// ============================================================

struct StorageCategory: Identifiable {

    let id = UUID()

    let name: String
    let bytes: Int64
    let icon: String
}

struct StorageSnapshot {

    var totalBytes: Int64
    var usedBytes: Int64
    var categories: [StorageCategory]

    var freeBytes: Int64 {
        max(0, totalBytes - usedBytes)
    }

    var usageRatio: Double {

        guard totalBytes > 0 else {
            return 0
        }

        return Double(usedBytes) /
            Double(totalBytes)
    }
}


// ============================================================
// MARK: - FILES
// ============================================================

enum CloudFileType: String {

    case document
    case image
    case video
    case audio
    case folder
    case archive
    case other

    var icon: String {

        switch self {
        case .document:
            return "doc.text"

        case .image:
            return "photo"

        case .video:
            return "video"

        case .audio:
            return "waveform"

        case .folder:
            return "folder.fill"

        case .archive:
            return "archivebox"

        case .other:
            return "doc"
        }
    }
}

struct CloudFileItem: Identifiable {

    let id: UUID
    var name: String
    var path: String
    var type: CloudFileType
    var sizeBytes: Int64
    var modified: Date
    var isSynced: Bool
    var isDownloaded: Bool

    init(
        name: String,
        path: String,
        type: CloudFileType,
        sizeBytes: Int64,
        modified: Date = Date(),
        isSynced: Bool = true,
        isDownloaded: Bool = true
    ) {

        self.id = UUID()
        self.name = name
        self.path = path
        self.type = type
        self.sizeBytes = sizeBytes
        self.modified = modified
        self.isSynced = isSynced
        self.isDownloaded = isDownloaded
    }
}


// ============================================================
// MARK: - SYNC
// ============================================================

enum SyncState: String {

    case idle
    case syncing
    case completed
    case paused
    case error

    var icon: String {

        switch self {
        case .idle:
            return "checkmark.circle"

        case .syncing:
            return "arrow.triangle.2.circlepath"

        case .completed:
            return "checkmark.circle.fill"

        case .paused:
            return "pause.circle"

        case .error:
            return "exclamationmark.triangle"
        }
    }
}

struct SyncStatus {

    var state: SyncState
    var filesProcessed: Int
    var totalFiles: Int
    var bytesTransferred: Int64
    var totalBytes: Int64

    var progress: Double {

        guard totalBytes > 0 else {
            return 0
        }

        return min(
            1,
            Double(bytesTransferred) /
                Double(totalBytes)
        )
    }
}


// ============================================================
// MARK: - DEVICES
// ============================================================

enum AppleDeviceKind: String {

    case mac
    case iphone
    case ipad
    case watch
    case other

    var icon: String {

        switch self {

        case .mac:
            return "laptopcomputer"

        case .iphone:
            return "iphone"

        case .ipad:
            return "ipad"

        case .watch:
            return "applewatch"

        case .other:
            return "desktopcomputer"
        }
    }
}

struct AppleDevice: Identifiable {

    let id = UUID()

    let name: String
    let kind: AppleDeviceKind

    var online: Bool
    var battery: Double

    var lastSeen: Date
    var storageUsed: Int64
    var storageTotal: Int64
}


// ============================================================
// MARK: - BACKUPS
// ============================================================

struct BackupRecord: Identifiable {

    let id = UUID()

    let deviceName: String
    let deviceType: AppleDeviceKind

    var sizeBytes: Int64
    var date: Date

    var encrypted: Bool
    var successful: Bool
}


// ============================================================
// MARK: - ACTIVITY
// ============================================================

enum ActivityType {

    case upload
    case download
    case sync
    case backup
    case delete
    case warning

    var icon: String {

        switch self {

        case .upload:
            return "arrow.up.circle"

        case .download:
            return "arrow.down.circle"

        case .sync:
            return "arrow.triangle.2.circlepath"

        case .backup:
            return "externaldrive.badge.icloud"

        case .delete:
            return "trash"

        case .warning:
            return "exclamationmark.triangle"
        }
    }
}

struct CloudActivity: Identifiable {

    let id = UUID()

    let type: ActivityType
    let title: String
    let detail: String
    let date: Date
}


// ============================================================
// MARK: - ICLOUD SERVICE PROTOCOL
// ============================================================

protocol iCloudServiceProtocol {

    func fetchStorage() async throws
        -> StorageSnapshot

    func fetchFiles() async throws
        -> [CloudFileItem]

    func fetchDevices() async throws
        -> [AppleDevice]

    func fetchBackups() async throws
        -> [BackupRecord]

    func fetchActivity() async throws
        -> [CloudActivity]

    func startSync() async throws

    func pauseSync() async throws

    func deleteFile(
        _ file: CloudFileItem
    ) async throws
}


// ============================================================
// MARK: - DEMO SERVICE
// ============================================================

actor DemoiCloudService:
    iCloudServiceProtocol {

    private var files: [CloudFileItem] = []

    init() {

        let now = Date()

        files = [

            CloudFileItem(
                name: "Aureom Manuscript",
                path: "/Documents/Aureom Manuscript.docx",
                type: .document,
                sizeBytes: 84_000_000,
                modified: now
                    .addingTimeInterval(-7200)
            ),

            CloudFileItem(
                name: "Research Library",
                path: "/Documents/Research",
                type: .folder,
                sizeBytes: 3_200_000_000,
                modified: now
                    .addingTimeInterval(-86400)
            ),

            CloudFileItem(
                name: "London 2026",
                path: "/Photos/London 2026",
                type: .image,
                sizeBytes: 8_700_000_000,
                modified: now
                    .addingTimeInterval(-172800)
            ),

            CloudFileItem(
                name: "Production Master",
                path: "/Video/Production Master.mov",
                type: .video,
                sizeBytes: 21_400_000_000,
                modified: now
                    .addingTimeInterval(-259200)
            ),

            CloudFileItem(
                name: "Music Library",
                path: "/Audio/Music",
                type: .audio,
                sizeBytes: 6_300_000_000,
                modified: now
                    .addingTimeInterval(-345600)
            ),

            CloudFileItem(
                name: "Archive 2025",
                path: "/Archives/Archive 2025.zip",
                type: .archive,
                sizeBytes: 14_500_000_000,
                modified: now
                    .addingTimeInterval(-604800)
            )
        ]
    }

    func fetchStorage()
        async throws -> StorageSnapshot {

        let categories = [

            StorageCategory(
                name: "Photos",
                bytes: 280_000_000_000,
                icon: "photo"
            ),

            StorageCategory(
                name: "Backups",
                bytes: 190_000_000_000,
                icon: "externaldrive"
            ),

            StorageCategory(
                name: "Documents",
                bytes: 82_000_000_000,
                icon: "doc.text"
            ),

            StorageCategory(
                name: "Videos",
                bytes: 145_000_000_000,
                icon: "video"
            ),

            StorageCategory(
                name: "Other",
                bytes: 23_000_000_000,
                icon: "ellipsis.circle"
            )
        ]

        return StorageSnapshot(
            totalBytes: 2_000_000_000_000,
            usedBytes: 720_000_000_000,
            categories: categories
        )
    }

    func fetchFiles()
        async throws -> [CloudFileItem] {

        return files
    }

    func fetchDevices()
        async throws -> [AppleDevice] {

        return [

            AppleDevice(
                name: "MacBook Pro",
                kind: .mac,
                online: true,
                battery: 0.84,
                lastSeen: Date(),
                storageUsed: 620_000_000_000,
                storageTotal: 1_000_000_000_000
            ),

            AppleDevice(
                name: "iPhone",
                kind: .iphone,
                online: true,
                battery: 0.72,
                lastSeen: Date(),
                storageUsed: 180_000_000_000,
                storageTotal: 256_000_000_000
            ),

            AppleDevice(
                name: "iPad Pro",
                kind: .ipad,
                online: true,
                battery: 0.61,
                lastSeen: Date(),
                storageUsed: 340_000_000_000,
                storageTotal: 512_000_000_000
            ),

            AppleDevice(
                name: "Apple Watch",
                kind: .watch,
                online: false,
                battery: 0.34,
                lastSeen: Date()
                    .addingTimeInterval(-3600),
                storageUsed: 12_000_000_000,
                storageTotal: 32_000_000_000
            )
        ]
    }

    func fetchBackups()
        async throws -> [BackupRecord] {

        return [

            BackupRecord(
                deviceName: "iPhone",
                deviceType: .iphone,
                sizeBytes: 82_000_000_000,
                date: Date()
                    .addingTimeInterval(-3600),
                encrypted: true,
                successful: true
            ),

            BackupRecord(
                deviceName: "iPad Pro",
                deviceType: .ipad,
                sizeBytes: 116_000_000_000,
                date: Date()
                    .addingTimeInterval(-86400),
                encrypted: true,
                successful: true
            ),

            BackupRecord(
                deviceName: "MacBook Pro",
                deviceType: .mac,
                sizeBytes: 248_000_000_000,
                date: Date()
                    .addingTimeInterval(-172800),
                encrypted: true,
                successful: true
            )
        ]
    }

    func fetchActivity()
        async throws -> [CloudActivity] {

        return [

            CloudActivity(
                type: .sync,
                title: "Sync completed",
                detail: "18 files synchronised",
                date: Date()
            ),

            CloudActivity(
                type: .upload,
                title: "Aureom Manuscript uploaded",
                detail: "84 MB",
                date: Date()
                    .addingTimeInterval(-3600)
            ),

            CloudActivity(
                type: .backup,
                title: "iPhone backup completed",
                detail: "82 GB",
                date: Date()
                    .addingTimeInterval(-7200)
            ),

            CloudActivity(
                type: .download,
                title: "Research Library downloaded",
                detail: "3.2 GB",
                date: Date()
                    .addingTimeInterval(-14400)
            )
        ]
    }

    func startSync() async throws {

        try await Task.sleep(
            nanoseconds: 1_000_000_000
        )
    }

    func pauseSync() async throws {

        try await Task.sleep(
            nanoseconds: 250_000_000
        )
    }

    func deleteFile(
        _ file: CloudFileItem
    ) async throws {

        files.removeAll {
            $0.id == file.id
        }
    }
}


// ============================================================
// MARK: - DASHBOARD MODEL
// ============================================================

@MainActor
final class iCloudDashboardModel:
    ObservableObject {

    @Published var selectedSection:
        DashboardSection = .overview

    @Published var storage:
        StorageSnapshot?

    @Published var files:
        [CloudFileItem] = []

    @Published var devices:
        [AppleDevice] = []

    @Published var backups:
        [BackupRecord] = []

    @Published var activities:
        [CloudActivity] = []

    @Published var syncStatus =
        SyncStatus(
            state: .idle,
            filesProcessed: 0,
            totalFiles: 0,
            bytesTransferred: 0,
            totalBytes: 0
        )

    @Published var searchText = ""

    @Published var isLoading = false

    @Published var errorMessage:
        String?

    private let service:
        any iCloudServiceProtocol

    init(
        service: any iCloudServiceProtocol =
            DemoiCloudService()
    ) {

        self.service = service
    }

    // MARK: Load

    func load() async {

        isLoading = true
        errorMessage = nil

        do {

            async let storageTask =
                service.fetchStorage()

            async let filesTask =
                service.fetchFiles()

            async let devicesTask =
                service.fetchDevices()

            async let backupsTask =
                service.fetchBackups()

            async let activityTask =
                service.fetchActivity()

            storage = try await storageTask
            files = try await filesTask
            devices = try await devicesTask
            backups = try await backupsTask
            activities = try await activityTask

        } catch {

            errorMessage =
                error.localizedDescription
        }

        isLoading = false
    }

    // MARK: Filter

    var filteredFiles:
        [CloudFileItem] {

        let query =
            searchText
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        guard !query.isEmpty else {
            return files
        }

        return files.filter {

            $0.name.localizedCaseInsensitiveContains(
                query
            )
            ||
            $0.path.localizedCaseInsensitiveContains(
                query
            )
        }
    }

    // MARK: Sync

    func startSync() {

        Task {

            syncStatus = SyncStatus(
                state: .syncing,
                filesProcessed: 0,
                totalFiles: files.count,
                bytesTransferred: 0,
                totalBytes:
                    files.reduce(
                        0
                    ) {
                        $0 + $1.sizeBytes
                    }
            )

            do {

                try await service.startSync()

                syncStatus = SyncStatus(
                    state: .completed,
                    filesProcessed: files.count,
                    totalFiles: files.count,
                    bytesTransferred:
                        files.reduce(
                            0
                        ) {
                            $0 + $1.sizeBytes
                        },
                    totalBytes:
                        files.reduce(
                            0
                        ) {
                            $0 + $1.sizeBytes
                        }
                )

            } catch {

                syncStatus = SyncStatus(
                    state: .error,
                    filesProcessed: 0,
                    totalFiles: files.count,
                    bytesTransferred: 0,
                    totalBytes: 0
                )
            }
        }
    }

    func pauseSync() {

        Task {

            try? await service.pauseSync()

            syncStatus.state = .paused
        }
    }

    // MARK: Delete

    func delete(
        _ file: CloudFileItem
    ) {

        Task {

            do {

                try await service.deleteFile(
                    file
                )

                files.removeAll {
                    $0.id == file.id
                }

            } catch {

                errorMessage =
                    error.localizedDescription
            }
        }
    }
}


// ============================================================
// MARK: - ROOT DASHBOARD
// ============================================================

struct iCloudDashboard: View {

    @StateObject private var model =
        iCloudDashboardModel()

    var body: some View {

        NavigationSplitView {

            SidebarView(
                selection:
                    $model.selectedSection
            )

        } detail: {

            VStack(spacing: 0) {

                TopBar(
                    model: model
                )

                Divider()

                ScrollView {

                    DashboardContent(
                        model: model
                    )
                    .padding(30)
                }
                .background(
                    Color(
                        red: 0.96,
                        green: 0.965,
                        blue: 0.975
                    )
                )
            }
        }
        .task {

            await model.load()
        }
        .frame(
            minWidth: 1100,
            minHeight: 720
        )
    }
}


// ============================================================
// MARK: - SIDEBAR
// ============================================================

struct SidebarView: View {

    @Binding var selection:
        DashboardSection

    var body: some View {

        List(
            DashboardSection.allCases,
            selection: $selection
        ) {

            section in

            Label(
                section.title,
                systemImage: section.icon
            )
            .tag(section)
        }
        .navigationTitle("iCloud")
        .safeAreaInset(
            edge: .bottom
        ) {

            VStack(alignment: .leading) {

                Divider()

                HStack {

                    Circle()
                        .fill(.green)
                        .frame(
                            width: 8,
                            height: 8
                        )

                    Text("iCloud connected")
                        .font(.caption)

                }
                .padding()
            }
        }
    }
}


// ============================================================
// MARK: - TOP BAR
// ============================================================

struct TopBar: View {

    @ObservedObject var model:
        iCloudDashboardModel

    var body: some View {

        HStack {

            Text(
                model.selectedSection.title
            )
            .font(
                .system(
                    size: 25,
                    weight: .semibold
                )
            )

            Spacer()

            if model.isLoading {

                ProgressView()
                    .controlSize(.small)
            }

            Button {

                Task {
                    await model.load()
                }

            } label: {

                Image(
                    systemName:
                        "arrow.clockwise"
                )
            }
            .buttonStyle(.borderless)

            Menu {

                Button(
                    "Start Sync",
                    systemImage:
                        "arrow.triangle.2.circlepath"
                ) {

                    model.startSync()
                }

                Button(
                    "Pause Sync",
                    systemImage:
                        "pause"
                ) {

                    model.pauseSync()
                }

            } label: {

                Image(
                    systemName:
                        "ellipsis.circle"
                )
                .font(.title3)
            }
        }
        .padding(
            .horizontal,
            30
        )
        .padding(
            .vertical,
            16
        )
    }
}


// ============================================================
// MARK: - CONTENT ROUTER
// ============================================================

struct DashboardContent: View {

    @ObservedObject var model:
        iCloudDashboardModel

    var body: some View {

        switch model.selectedSection {

        case .overview:

            OverviewPage(
                model: model
            )

        case .files:

            FilesPage(
                model: model
            )

        case .storage:

            StoragePage(
                model: model
            )

        case .sync:

            SyncPage(
                model: model
            )

        case .backups:

            BackupsPage(
                model: model
            )

        case .devices:

            DevicesPage(
                model: model
            )

        case .activity:

            ActivityPage(
                model: model
            )

        case .settings:

            SettingsPage()
        }
    }
}


// ============================================================
// MARK: - OVERVIEW
// ============================================================

struct OverviewPage: View {

    @ObservedObject var model:
        iCloudDashboardModel

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 24
        ) {

            Text(
                "Your iCloud at a glance."
            )
            .font(.title2)

            HStack(spacing: 18) {

                if let storage =
                    model.storage {

                    StorageCard(
                        storage: storage
                    )
                }

                SyncCard(
                    status:
                        model.syncStatus
                )

                DeviceCard(
                    devices:
                        model.devices
                )
            }

            HStack(
                alignment: .top,
                spacing: 18
            ) {

                RecentActivityCard(
                    activities:
                        Array(
                            model.activities
                                .prefix(4)
                        )
                )

                QuickActionsCard(
                    model: model
                )
            }

            DevicesOverview(
                devices:
                    model.devices
            )
        }
    }
}


// ============================================================
// MARK: - STORAGE CARD
// ============================================================

struct StorageCard: View {

    let storage:
        StorageSnapshot

    var body: some View {

        DashboardCard {

            VStack(
                alignment: .leading,
                spacing: 16
            ) {

                HStack {

                    Label(
                        "Storage",
                        systemImage:
                            "internaldrive"
                    )

                    Spacer()

                    Text(
                        ByteFormatter.string(
                            storage.usedBytes
                        )
                    )
                    .font(.headline)
                }

                ProgressView(
                    value:
                        storage.usageRatio
                )

                HStack {

                    Text(
                        "\(Int(
                            storage.usageRatio * 100
                        ))% used"
                    )

                    Spacer()

                    Text(
                        ByteFormatter.string(
                            storage.freeBytes
                        ) + " free"
                    )
                    .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }
}


// ============================================================
// MARK: - SYNC CARD
// ============================================================

struct SyncCard: View {

    let status:
        SyncStatus

    var body: some View {

        DashboardCard {

            VStack(
                alignment: .leading,
                spacing: 16
            ) {

                HStack {

                    Label(
                        "Sync",
                        systemImage:
                            status.state.icon
                    )

                    Spacer()

                    Text(
                        status.state.rawValue
                            .capitalized
                    )
                    .foregroundStyle(
                        .secondary
                    )
                }

                ProgressView(
                    value:
                        status.progress
                )

                Text(
                    "\(status.filesProcessed) of " +
                    "\(status.totalFiles) files"
                )
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )
            }
        }
    }
}


// ============================================================
// MARK: - DEVICE CARD
// ============================================================

struct DeviceCard: View {

    let devices:
        [AppleDevice]

    var body: some View {

        DashboardCard {

            VStack(
                alignment: .leading,
                spacing: 14
            ) {

                Label(
                    "Devices",
                    systemImage:
                        "laptopcomputer.and.iphone"
                )

                Text(
                    "\(devices.filter {
                        $0.online
                    }.count) online"
                )
                .font(
                    .system(
                        size: 28,
                        weight: .semibold
                    )
                )

                Text(
                    "\(devices.count) Apple devices"
                )
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )
            }
        }
    }
}


// ============================================================
// MARK: - RECENT ACTIVITY
// ============================================================

struct RecentActivityCard: View {

    let activities:
        [CloudActivity]

    var body: some View {

        DashboardCard {

            VStack(
                alignment: .leading,
                spacing: 16
            ) {

                Text("Recent Activity")
                    .font(.headline)

                ForEach(
                    activities
                ) { activity in

                    ActivityRow(
                        activity: activity
                    )
                }
            }
        }
    }
}


// ============================================================
// MARK: - QUICK ACTIONS
// ============================================================

struct QuickActionsCard: View {

    @ObservedObject var model:
        iCloudDashboardModel

    var body: some View {

        DashboardCard {

            VStack(
                alignment: .leading,
                spacing: 14
            ) {

                Text("Quick Actions")
                    .font(.headline)

                Button {

                    model.startSync()

                } label: {

                    Label(
                        "Sync Now",
                        systemImage:
                            "arrow.triangle.2.circlepath"
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                }
                .buttonStyle(.borderedProminent)

                Button {

                    model.selectedSection =
                        .storage

                } label: {

                    Label(
                        "Manage Storage",
                        systemImage:
                            "internaldrive"
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                }
                .buttonStyle(.bordered)
            }
        }
    }
}


// ============================================================
// MARK: - FILES PAGE
// ============================================================

struct FilesPage: View {

    @ObservedObject var model:
        iCloudDashboardModel

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 20
        ) {

            HStack {

                TextField(
                    "Search iCloud",
                    text:
                        $model.searchText
                )
                .textFieldStyle(
                    .roundedBorder
                )

                Button(
                    "Upload",
                    systemImage:
                        "arrow.up"
                ) {
                    // Connect to FileImporter
                }
                .buttonStyle(
                    .borderedProminent
                )
            }

            DashboardCard {

                LazyVStack(spacing: 0) {

                    ForEach(
                        model.filteredFiles
                    ) { file in

                        FileRow(
                            file: file,
                            deleteAction: {
                                model.delete(
                                    file
                                )
                            }
                        )

                        Divider()
                    }
                }
            }
        }
    }
}


// ============================================================
// MARK: - FILE ROW
// ============================================================

struct FileRow: View {

    let file:
        CloudFileItem

    let deleteAction:
        () -> Void

    var body: some View {

        HStack(spacing: 14) {

            Image(
                systemName:
                    file.type.icon
            )
            .font(.title3)
            .frame(width: 30)

            VStack(
                alignment: .leading,
                spacing: 3
            ) {

                Text(file.name)
                    .font(.body)

                Text(file.path)
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
            }

            Spacer()

            Text(
                ByteFormatter.string(
                    file.sizeBytes
                )
            )
            .font(.caption)

            if file.isSynced {

                Image(
                    systemName:
                        "checkmark.circle.fill"
                )
                .foregroundStyle(
                    .green
                )
            }

            Menu {

                Button(
                    "Download",
                    systemImage:
                        "arrow.down"
                ) {
                }

                Button(
                    "Share",
                    systemImage:
                        "square.and.arrow.up"
                ) {
                }

                Divider()

                Button(
                    "Delete",
                    systemImage:
                        "trash"
                ) {

                    deleteAction()
                }

            } label: {

                Image(
                    systemName:
                        "ellipsis"
                )
            }
            .buttonStyle(
                .borderless
            )
        }
        .padding(
            .vertical,
            12
        )
    }
}


// ============================================================
// MARK: - STORAGE PAGE
// ============================================================

struct StoragePage: View {

    @ObservedObject var model:
        iCloudDashboardModel

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 24
        ) {

            if let storage =
                model.storage {

                DashboardCard {

                    VStack(
                        alignment: .leading,
                        spacing: 18
                    ) {

                        Text(
                            "iCloud Storage"
                        )
                        .font(.title3)

                        HStack {

                            Text(
                                ByteFormatter.string(
                                    storage.usedBytes
                                )
                            )
                            .font(
                                .system(
                                    size: 38,
                                    weight: .bold
                                )
                            )

                            Text(
                                "of " +
                                ByteFormatter.string(
                                    storage.totalBytes
                                )
                            )
                            .foregroundStyle(
                                .secondary
                            )
                        }

                        ProgressView(
                            value:
                                storage.usageRatio
                        )

                        ForEach(
                            storage.categories
                        ) { category in

                            StorageCategoryRow(
                                category:
                                    category,
                                total:
                                    storage.usedBytes
                            )
                        }
                    }
                }
            }
        }
    }
}


// ============================================================
// MARK: - STORAGE CATEGORY
// ============================================================

struct StorageCategoryRow:
    View {

    let category:
        StorageCategory

    let total:
        Int64

    var body: some View {

        HStack {

            Image(
                systemName:
                    category.icon
            )
            .frame(width: 28)

            Text(category.name)

            Spacer()

            Text(
                ByteFormatter.string(
                    category.bytes
                )
            )

            ProgressView(
                value:
                    Double(category.bytes) /
                    Double(max(1, total))
            )
            .frame(width: 100)
        }
        .padding(
            .vertical,
            5
        )
    }
}


// ============================================================
// MARK: - SYNC PAGE
// ============================================================

struct SyncPage: View {

    @ObservedObject var model:
        iCloudDashboardModel

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 24
        ) {

            DashboardCard {

                VStack(
                    alignment: .leading,
                    spacing: 20
                ) {

                    HStack {

                        Image(
                            systemName:
                                "arrow.triangle.2.circlepath"
                        )
                        .font(.largeTitle)

                        VStack(
                            alignment: .leading
                        ) {

                            Text(
                                "iCloud Sync"
                            )
                            .font(.title2)

                            Text(
                                model.syncStatus
                                    .state
                                    .rawValue
                                    .capitalized
                            )
                            .foregroundStyle(
                                .secondary
                            )
                        }

                        Spacer()

                        Button(
                            "Sync Now"
                        ) {

                            model.startSync()
                        }
                        .buttonStyle(
                            .borderedProminent
                        )
                    }

                    ProgressView(
                        value:
                            model.syncStatus
                                .progress
                    )

                    HStack {

                        Text(
                            "\(model.syncStatus.filesProcessed) files"
                        )

                        Spacer()

                        Text(
                            ByteFormatter.string(
                                model.syncStatus
                                    .bytesTransferred
                            )
                        )
                    }
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
                }
            }
        }
    }
}


// ============================================================
// MARK: - BACKUPS PAGE
// ============================================================

struct BackupsPage: View {

    @ObservedObject var model:
        iCloudDashboardModel

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 20
        ) {

            Text(
                "Device Backups"
            )
            .font(.title2)

            DashboardCard {

                ForEach(
                    model.backups
                ) { backup in

                    HStack(spacing: 15) {

                        Image(
                            systemName:
                                backup.deviceType.icon
                        )
                        .font(.title2)

                        VStack(
                            alignment: .leading
                        ) {

                            Text(
                                backup.deviceName
                            )

                            Text(
                                backup.date,
                                style: .relative
                            )
                            .font(.caption)
                            .foregroundStyle(
                                .secondary
                            )
                        }

                        Spacer()

                        VStack(
                            alignment: .trailing
                        ) {

                            Text(
                                ByteFormatter.string(
                                    backup.sizeBytes
                                )
                            )

                            Label(
                                "Encrypted",
                                systemImage:
                                    "lock.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(
                                .green
                            )
                        }
                    }
                    .padding(
                        .vertical,
                        10
                    )

                    Divider()
                }
            }
        }
    }
}


// ============================================================
// MARK: - DEVICES PAGE
// ============================================================

struct DevicesPage: View {

    @ObservedObject var model:
        iCloudDashboardModel

    var body: some View {

        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ],
            spacing: 18
        ) {

            ForEach(
                model.devices
            ) { device in

                DeviceDetailCard(
                    device: device
                )
            }
        }
    }
}


// ============================================================
// MARK: - DEVICE DETAIL CARD
// ============================================================

struct DeviceDetailCard: View {

    let device:
        AppleDevice

    var body: some View {

        DashboardCard {

            VStack(
                alignment: .leading,
                spacing: 16
            ) {

                HStack {

                    Image(
                        systemName:
                            device.kind.icon
                    )
                    .font(.largeTitle)

                    VStack(
                        alignment: .leading
                    ) {

                        Text(
                            device.name
                        )
                        .font(.headline)

                        HStack {

                            Circle()
                                .fill(
                                    device.online
                                    ? .green
                                    : .gray
                                )
                                .frame(
                                    width: 7,
                                    height: 7
                                )

                            Text(
                                device.online
                                ? "Online"
                                : "Offline"
                            )
                            .font(.caption)
                        }
                    }

                    Spacer()
                }

                Divider()

                HStack {

                    Label(
                        "\(Int(
                            device.battery * 100
                        ))%",
                        systemImage:
                            "battery.75"
                    )

                    Spacer()

                    Text(
                        ByteFormatter.string(
                            device.storageUsed
                        )
                        +
                        " / " +
                        ByteFormatter.string(
                            device.storageTotal
                        )
                    )
                    .font(.caption)
                }

                ProgressView(
                    value:
                        Double(
                            device.storageUsed
                        )
                        /
                        Double(
                            device.storageTotal
                        )
                )
            }
        }
    }
}


// ============================================================
// MARK: - DEVICES OVERVIEW
// ============================================================

struct DevicesOverview: View {

    let devices:
        [AppleDevice]

    var body: some View {

        DashboardCard {

            VStack(
                alignment: .leading,
                spacing: 16
            ) {

                Text(
                    "Apple Devices"
                )
                .font(.headline)

                HStack(spacing: 25) {

                    ForEach(
                        devices
                    ) { device in

                        VStack(spacing: 8) {

                            Image(
                                systemName:
                                    device.kind.icon
                            )
                            .font(.title)

                            Text(
                                device.name
                            )
                            .font(.caption)

                            Circle()
                                .fill(
                                    device.online
                                    ? .green
                                    : .gray
                                )
                                .frame(
                                    width: 7,
                                    height: 7
                                )
                        }
                    }
                }
            }
        }
    }
}


// ============================================================
// MARK: - ACTIVITY PAGE
// ============================================================

struct ActivityPage: View {

    @ObservedObject var model:
        iCloudDashboardModel

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 20
        ) {

            Text(
                "Activity"
            )
            .font(.title2)

            DashboardCard {

                ForEach(
                    model.activities
                ) { activity in

                    ActivityRow(
                        activity: activity
                    )

                    Divider()
                }
            }
        }
    }
}


// ============================================================
// MARK: - ACTIVITY ROW
// ============================================================

struct ActivityRow: View {

    let activity:
        CloudActivity

    var body: some View {

        HStack(spacing: 14) {

            Image(
                systemName:
                    activity.type.icon
            )
            .frame(width: 25)

            VStack(
                alignment: .leading
            ) {

                Text(
                    activity.title
                )

                Text(
                    activity.detail
                )
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )
            }

            Spacer()

            Text(
                activity.date,
                style: .relative
            )
            .font(.caption)
            .foregroundStyle(
                .secondary
            )
        }
        .padding(
            .vertical,
            8
        )
    }
}


// ============================================================
// MARK: - SETTINGS
// ============================================================

struct SettingsPage: View {

    @State private var
        optimiseStorage = true

    @State private var
        automaticSync = true

    @State private var
        cellularSync = false

    @State private var
        optimiseBackups = true

    var body: some View {

        Form {

            Section(
                "iCloud"
            ) {

                LabeledContent(
                    "Account"
                ) {

                    Text(
                        "Connected"
                    )
                    .foregroundStyle(
                        .green
                    )
                }

                LabeledContent(
                    "Container"
                ) {

                    Text(
                        "iCloud.com.example.app"
                    )
                    .font(.caption)
                }
            }

            Section(
                "Sync"
            ) {

                Toggle(
                    "Automatic Sync",
                    isOn:
                        $automaticSync
                )

                Toggle(
                    "Cellular Sync",
                    isOn:
                        $cellularSync
                )
            }

            Section(
                "Optimisation"
            ) {

                Toggle(
                    "Optimise Storage",
                    isOn:
                        $optimiseStorage
                )

                Toggle(
                    "Optimise Backups",
                    isOn:
                        $optimiseBackups
                )
            }
        }
        .formStyle(.grouped)
    }
}


// ============================================================
// MARK: - CARD
// ============================================================

struct DashboardCard<Content:
    View>: View {

    @ViewBuilder
    let content: () -> Content

    init(
        @ViewBuilder content:
            @escaping () -> Content
    ) {

        self.content = content
    }

    var body: some View {

        content()
            .padding(22)
            .background(
                .background,
                in:
                    RoundedRectangle(
                        cornerRadius: 16,
                        style: .continuous
                    )
            )
            .overlay {

                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
                .stroke(
                    Color.primary
                        .opacity(0.07)
                )
            }
    }
}


// ============================================================
// MARK: - BYTE FORMATTER
// ============================================================

enum ByteFormatter {

    static func string(
        _ bytes: Int64
    ) -> String {

        let formatter =
            ByteCountFormatter()

        formatter.allowedUnits =
            [
                .useGB,
                .useTB,
                .useMB
            ]

        formatter.countStyle =
            .file

        return formatter.string(
            fromByteCount:
                bytes
        )
    }
}


// ============================================================
// MARK: - APP
// ============================================================

@main
struct iCloudDashboardApp:
    App {

    var body: some Scene {

        WindowGroup {

            iCloudDashboard()
        }
        .windowStyle(
            .automatic
        )
    }
}
```


