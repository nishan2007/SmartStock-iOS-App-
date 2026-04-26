//
//  DeviceManagementView.swift
//  SmartStock
//

import SwiftUI

struct DeviceManagementView: View {
    @EnvironmentObject private var sessionManager: SessionManager

    @State private var devices: [TrackedDevice] = []
    @State private var stores: [Store] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }
            }

            if devices.isEmpty && !isLoading {
                Section {
                    ContentUnavailableView(
                        "No Devices Found",
                        systemImage: "iphone.slash",
                        description: Text("Tracked devices will appear here after employees sign in on iPhone or iPad.")
                    )
                }
            } else {
                Section("Tracked Devices") {
                    ForEach(devices) { device in
                        NavigationLink {
                            DeviceDetailView(device: device, stores: stores) { updatedDevice in
                                if let index = devices.firstIndex(where: { $0.id == updatedDevice.id }) {
                                    devices[index] = updatedDevice
                                }
                            }
                            .environmentObject(sessionManager)
                        } label: {
                            DeviceRow(device: device, stores: stores, isCurrent: device.installationId == DeviceService.shared.currentInstallationId())
                        }
                    }
                }
            }
        }
        .navigationTitle("Device Management")
        .task {
            await loadDevices()
        }
        .refreshable {
            await loadDevices()
        }
        .overlay {
            if isLoading {
                LoadingView(text: "Loading devices...")
                    .background(Color(.systemBackground).opacity(0.85))
            }
        }
    }

    private func loadDevices() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let devicesTask = DeviceService.shared.fetchDevices()
            async let storesTask = StoreService.shared.fetchStores()

            devices = try await devicesTask
            stores = try await storesTask
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DeviceRow: View {
    let device: TrackedDevice
    let stores: [Store]
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(device.modelName)
                    .font(.headline)

                if isCurrent {
                    Text("This Device")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer()
            }

            if let deviceName = device.deviceName, deviceName != device.modelName {
                Text(deviceName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                statusBadge(title: device.isBlocked ? "Blocked" : (device.isApproved ? "Approved" : "Shared"), color: device.isBlocked ? .red : (device.isApproved ? .green : .orange))

                if let assignedStoreName {
                    statusBadge(title: "Restricted: \(assignedStoreName)", color: .blue)
                }

                if let storeName = device.lastStoreName {
                    Text(storeName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(summaryLine)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var summaryLine: String {
        let platform = [device.osName, device.osVersion].compactMap { $0 }.joined(separator: " ")
        let user = device.lastLoginUserName ?? "No recent user"
        let lastSeen = device.lastSeen.formatted(date: .abbreviated, time: .shortened)
        return [platform, device.modelIdentifier, user, "Seen \(lastSeen)"].filter { !$0.isEmpty }.joined(separator: " • ")
    }

    private var assignedStoreName: String? {
        guard let assignedLocationId = device.assignedLocationId else { return nil }
        return stores.first { $0.id == assignedLocationId }?.name ?? "Store #\(assignedLocationId)"
    }

    private func statusBadge(title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

private struct DeviceDetailView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var device: TrackedDevice
    @State private var notes: String
    @State private var isApproved: Bool
    @State private var isBlocked: Bool
    @State private var assignedLocationId: Int?
    @State private var sessions: [TrackedDeviceSession] = []
    @State private var isLoadingSessions = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    let stores: [Store]
    let onSave: (TrackedDevice) -> Void

    init(device: TrackedDevice, stores: [Store], onSave: @escaping (TrackedDevice) -> Void) {
        _device = State(initialValue: device)
        _notes = State(initialValue: device.notes ?? "")
        _isApproved = State(initialValue: device.isApproved)
        _isBlocked = State(initialValue: device.isBlocked)
        _assignedLocationId = State(initialValue: device.assignedLocationId)
        self.stores = stores
        self.onSave = onSave
    }

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }
            }

            Section("Access") {
                Toggle("Approved To Stay Signed In", isOn: $isApproved)
                Toggle("Blocked Device", isOn: $isBlocked)

                Text("Unapproved devices can still be used, but they will not keep employees signed in after the app closes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Store Restriction") {
                Picker("Assigned Store", selection: $assignedLocationId) {
                    Text("No restriction").tag(Int?.none)

                    ForEach(stores) { store in
                        Text(store.name).tag(Optional(store.id))
                    }
                }

                Text("When a store is assigned, employees can only use this device if they also have access to that store.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Notes") {
                TextEditor(text: $notes)
                    .frame(minHeight: 100)
            }

            Section("Device Info") {
                detailRow("Model", device.modelName)
                detailRow("Identifier", device.modelIdentifier)
                detailRow("Name", device.deviceName ?? "Unknown")
                detailRow("Installation ID", device.installationId)
                detailRow("Platform", [device.osName, device.osVersion].compactMap { $0 }.joined(separator: " "))

                if let appVersion = device.appVersion {
                    detailRow("App Version", appVersion)
                }

                if let user = device.lastLoginUserName {
                    detailRow("Last User", user)
                }

                if let store = device.lastStoreName {
                    detailRow("Last Store", store)
                }

                detailRow("Assigned Store", assignedStoreText)

                detailRow("First Seen", device.firstSeen.formatted(date: .abbreviated, time: .shortened))
                detailRow("Last Seen", device.lastSeen.formatted(date: .abbreviated, time: .shortened))
            }

            Section("Recent Sessions") {
                if isLoadingSessions {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if sessions.isEmpty {
                    Text("No tracked sessions yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sessions) { session in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(session.sessionStatus)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background((session.sessionStatus == "ACTIVE" ? Color.green : Color.gray).opacity(0.12))
                                    .foregroundStyle(session.sessionStatus == "ACTIVE" ? .green : .secondary)
                                    .clipShape(Capsule())
                                Spacer()
                                Text(session.loginTime.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text([session.userName, session.storeName].compactMap { $0 }.joined(separator: " • "))
                                .font(.subheadline)

                            if let logoutTime = session.logoutTime {
                                Text("Ended \(logoutTime.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(device.deviceName ?? "Device")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    Task {
                        await saveChanges()
                    }
                }
                .disabled(isSaving)
            }
        }
        .task {
            await loadSessions()
        }
    }

    private func loadSessions() async {
        isLoadingSessions = true
        defer { isLoadingSessions = false }

        do {
            sessions = try await DeviceService.shared.fetchSessions(deviceId: device.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveChanges() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            let updatedDevice = try await DeviceService.shared.updateDeviceAccess(
                deviceId: device.id,
                isApproved: isApproved,
                isBlocked: isBlocked,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                assignedLocationId: assignedLocationId
            )

            device = updatedDevice
            notes = updatedDevice.notes ?? ""
            onSave(updatedDevice)
            sessionManager.handleTrackedDeviceUpdate(updatedDevice)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var assignedStoreText: String {
        guard let assignedLocationId else { return "No restriction" }
        return stores.first { $0.id == assignedLocationId }?.name ?? "Store #\(assignedLocationId)"
    }

    @ViewBuilder
    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value.isEmpty ? "—" : value)
                .multilineTextAlignment(.trailing)
        }
    }
}
