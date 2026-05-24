//
//  CompanyPreferencesManagementSections.swift
//  SmartStock
//

import SwiftUI
import Supabase
import Combine

@MainActor
final class LocationsManagementViewModel: ObservableObject {
    @Published var locations: [LocationPreferenceRow] = []
    @Published var searchText = ""
    @Published var selectedLocationId: Int?
    @Published var draftName = ""
    @Published var draftStoreCode = "0001"
    @Published var draftAddress = ""
    @Published var draftTimeZone = TimeZone.current.identifier
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var message: String?

    private let client = supabase

    var filteredLocations: [LocationPreferenceRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return locations }
        return locations.filter {
            $0.name.lowercased().contains(query)
                || ($0.address ?? "").lowercased().contains(query)
                || $0.receiptStoreCode.lowercased().contains(query)
                || $0.timeZoneIdentifier.lowercased().contains(query)
        }
    }

    var selectedLocation: LocationPreferenceRow? {
        locations.first { $0.id == selectedLocationId }
    }

    func loadIfAllowed(sessionManager: SessionManager) async {
        guard sessionManager.currentUser?.canAccess(.locationManagement) == true else { return }
        await load()
    }

    func load() async {
        isLoading = true
        message = nil
        defer { isLoading = false }

        do {
            locations = try await client
                .from("locations")
                .select("location_id, name, receipt_store_code, address, timezone, created_at")
                .order("name", ascending: true)
                .execute()
                .value
            if selectedLocationId == nil {
                select(locations.first)
            } else if let selectedLocationId, !locations.contains(where: { $0.id == selectedLocationId }) {
                select(locations.first)
            }
        } catch {
            locations = []
            message = error.localizedDescription
        }
    }

    func select(_ location: LocationPreferenceRow?) {
        selectedLocationId = location?.id
        draftName = location?.name ?? ""
        draftStoreCode = location?.receiptStoreCode ?? "0001"
        draftAddress = location?.address ?? ""
        draftTimeZone = location?.timeZoneIdentifier ?? TimeZone.current.identifier
    }

    func clearDraft() {
        selectedLocationId = nil
        draftName = ""
        draftStoreCode = "0001"
        draftAddress = ""
        draftTimeZone = TimeZone.current.identifier
    }

    func save() async {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            message = "Location name is required."
            return
        }
        let storeCode = sanitizeCode(draftStoreCode)
        guard !storeCode.isEmpty else {
            message = "Store code must be a number from 0001 to 9999."
            return
        }
        guard TimeZone(identifier: draftTimeZone) != nil else {
            message = "Enter a valid timezone identifier."
            return
        }

        isSaving = true
        message = nil
        defer { isSaving = false }

        do {
            let payload = LocationPreferenceWritePayload(name: name, receipt_store_code: storeCode, address: normalizedValue(draftAddress), timezone: draftTimeZone)
            if let selectedLocationId {
                _ = try await client
                    .from("locations")
                    .update(payload)
                    .eq("location_id", value: selectedLocationId)
                    .execute()
            } else {
                _ = try await client
                    .from("locations")
                    .insert(payload)
                    .execute()
            }
            message = "Saved location."
            await load()
        } catch {
            message = error.localizedDescription
        }
    }

    private func sanitizeCode(_ value: String) -> String {
        let digits = value.replacingOccurrences(of: "\\D+", with: "", options: .regularExpression)
        guard let parsed = Int(digits), parsed > 0 else { return "" }
        return String(format: "%04d", min(parsed, 9999))
    }
}

struct LocationPreferenceRow: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let receiptStoreCode: String
    let address: String?
    let timeZoneIdentifier: String

    enum CodingKeys: String, CodingKey {
        case id = "location_id"
        case name
        case receiptStoreCode = "receipt_store_code"
        case address
        case timeZoneIdentifier = "timezone"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        receiptStoreCode = (try? container.decode(String.self, forKey: .receiptStoreCode)) ?? "0001"
        address = try container.decodeIfPresent(String.self, forKey: .address)
        timeZoneIdentifier = try container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier) ?? TimeZone.current.identifier
    }
}

private struct LocationPreferenceWritePayload: Encodable {
    let name: String
    let receipt_store_code: String
    let address: String?
    let timezone: String
}

struct LocationsManagementSectionView: View {
    @ObservedObject var viewModel: LocationsManagementViewModel
    let canManage: Bool

    var body: some View {
        Form {
            if !canManage {
                lockedSection("You do not have permission to manage locations.")
            } else {
                if let message = viewModel.message {
                    Section { Text(message).foregroundStyle(message.hasPrefix("Saved") ? .green : .red) }
                }

                Section("Locations") {
                    TextField("Search locations", text: $viewModel.searchText)
                        .textInputAutocapitalization(.never)
                    if viewModel.isLoading {
                        ProgressView("Loading locations...")
                    } else if viewModel.filteredLocations.isEmpty {
                        ContentUnavailableView("No Locations", systemImage: "storefront")
                    } else {
                        ForEach(viewModel.filteredLocations) { location in
                            Button {
                                viewModel.select(location)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(location.name)
                                            .font(.headline)
                                        Text("Store Code: \(location.receiptStoreCode)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text([location.address, location.timeZoneIdentifier].compactMap { $0 }.joined(separator: " | "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if viewModel.selectedLocationId == location.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section(viewModel.selectedLocationId == nil ? "New Location" : "Location Detail") {
                    TextField("Name", text: $viewModel.draftName)
                    TextField("Store Code (0001-9999)", text: $viewModel.draftStoreCode)
                        .keyboardType(.numberPad)
                    TextField("Address", text: $viewModel.draftAddress, axis: .vertical)
                    TextField("Timezone", text: $viewModel.draftTimeZone)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    HStack {
                        Button {
                            viewModel.clearDraft()
                        } label: {
                            Label("Clear", systemImage: "plus")
                        }
                        Spacer()
                        Button {
                            Task { await viewModel.save() }
                        } label: {
                            Label(viewModel.isSaving ? "Saving" : "Save Location", systemImage: "checkmark.circle")
                        }
                        .disabled(viewModel.isSaving)
                    }
                }
            }
        }
    }
}

@MainActor
final class CashDrawerManagementViewModel: ObservableObject {
    @Published var stores: [Store] = []
    @Published var selectedStoreId: Int?
    @Published var drawers: [CashDrawer] = []
    @Published var assignments: [CashDrawerDeviceAssignment] = []
    @Published var devices: [TrackedDevice] = []
    @Published var includeInactive = false
    @Published var selectedDrawerId: Int64?
    @Published var drawerName = ""
    @Published var drawerDescription = ""
    @Published var startingCashText = "20000.00"
    @Published var floatMixQuantities: [Int: String] = [:]
    @Published var allowFloatMismatch = false
    @Published var drawerIsActive = true
    @Published var selectedDeviceId: UUID?
    @Published var assignmentNotes = ""
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var message: String?

    private let service = CashDrawerService()

    var activeDrawers: [CashDrawer] { drawers.filter(\.isActive) }
    var selectedDrawer: CashDrawer? { drawers.first { $0.drawerId == selectedDrawerId } }
    var selectedStore: Store? { stores.first { $0.id == selectedStoreId } }
    var floatMixTotalInCents: Int { service.floatMixTotalInCents(parsedFloatMixOrDefault()) }
    var startingCashInCents: Int? { parseMoneyToCents(startingCashText) }
    var floatMixMatchesStartingCash: Bool {
        guard let startingCashInCents else { return false }
        return floatMixTotalInCents == startingCashInCents
    }

    func loadIfAllowed(sessionManager: SessionManager) async {
        guard sessionManager.currentUser?.canAccess(.cashDrawerManagement) == true else { return }
        await load(sessionManager: sessionManager)
    }

    func load(sessionManager: SessionManager) async {
        isLoading = true
        message = nil
        defer { isLoading = false }

        do {
            async let loadedStores = StoreService.shared.fetchStores()
            async let loadedDevices = DeviceService.shared.fetchDevices()
            stores = try await loadedStores
            devices = try await loadedDevices
            if selectedStoreId == nil {
                selectedStoreId = sessionManager.selectedStore?.id ?? stores.first?.id
            }
            await loadDrawerData()
            if selectedDeviceId == nil {
                selectedDeviceId = sessionManager.currentDevice?.id ?? devices.first?.id
            }
        } catch {
            message = error.localizedDescription
        }
    }

    func loadDrawerData() async {
        guard let selectedStoreId else {
            drawers = []
            assignments = []
            return
        }

        do {
            async let loadedDrawers = service.fetchDrawers(storeId: selectedStoreId, includeInactive: includeInactive)
            async let loadedAssignments = service.fetchAssignments(storeId: selectedStoreId, activeOnly: !includeInactive)
            drawers = try await loadedDrawers
            assignments = try await loadedAssignments
            if selectedDrawerId == nil {
                selectDrawer(drawers.first)
            } else if let selectedDrawerId, !drawers.contains(where: { $0.drawerId == selectedDrawerId }) {
                selectDrawer(drawers.first)
            }
        } catch {
            drawers = []
            assignments = []
            message = error.localizedDescription
        }
    }

    func selectDrawer(_ drawer: CashDrawer?) {
        selectedDrawerId = drawer?.drawerId
        drawerName = drawer?.drawerName ?? ""
        drawerDescription = drawer?.drawerCode ?? ""
        startingCashText = formatMoney(drawer?.startingCashAmount ?? CashDrawer.defaultStartingCashAmount)
        setFloatMix(drawer?.floatMix ?? CashDrawer.defaultFloatMix)
        allowFloatMismatch = false
        drawerIsActive = drawer?.isActive ?? true
    }

    func clearDrawer() {
        selectedDrawerId = nil
        drawerName = ""
        drawerDescription = ""
        startingCashText = "20000.00"
        setFloatMix(CashDrawer.defaultFloatMix)
        allowFloatMismatch = false
        drawerIsActive = true
    }

    func saveDrawer() async {
        guard let selectedStoreId else {
            message = "Select a store before saving a drawer."
            return
        }

        isSaving = true
        message = nil
        defer { isSaving = false }

        do {
            guard let startingCashInCents = parseMoneyToCents(startingCashText) else {
                throw NSError(domain: "CashDrawerService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Enter a valid starting cash amount."])
            }
            guard startingCashInCents >= 0 else {
                throw NSError(domain: "CashDrawerService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Starting cash cannot be negative."])
            }

            let parsedFloatMix = try parsedFloatMixOrThrow()
            let floatMixTotal = service.floatMixTotalInCents(parsedFloatMix)
            if floatMixTotal != startingCashInCents && !allowFloatMismatch {
                throw NSError(
                    domain: "CashDrawerService",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Float mix total does not match starting cash. Enable \"Allow float mismatch\" to save anyway."]
                )
            }

            _ = try await service.saveDrawer(
                storeId: selectedStoreId,
                draft: CashDrawerDraft(
                    drawerName: drawerName,
                    drawerCode: drawerDescription,
                    startingCashAmount: Decimal(startingCashInCents) / Decimal(100),
                    floatMix: parsedFloatMix,
                    isActive: drawerIsActive
                ),
                drawerId: selectedDrawerId
            )
            message = "Saved drawer."
            await loadDrawerData()
        } catch {
            message = error.localizedDescription
        }
    }

    func assignDevice() async {
        guard let selectedStoreId else {
            message = "Select a store before assigning a drawer."
            return
        }
        guard let selectedDeviceId, let selectedDrawer else {
            message = "Select a device and drawer."
            return
        }

        do {
            try await service.assign(deviceId: selectedDeviceId, to: selectedDrawer, storeId: selectedStoreId, notes: assignmentNotes)
            assignmentNotes = ""
            message = "Assigned drawer."
            await loadDrawerData()
        } catch {
            message = error.localizedDescription
        }
    }

    func unassign(_ assignment: CashDrawerDeviceAssignment) async {
        do {
            try await service.unassign(deviceId: assignment.deviceId, storeId: assignment.storeId)
            message = "Unassigned drawer."
            await loadDrawerData()
        } catch {
            message = error.localizedDescription
        }
    }

    func deviceName(for deviceId: UUID) -> String {
        devices.first(where: { $0.id == deviceId })?.drawerDisplayName ?? "Device \(deviceId.uuidString.prefix(8))"
    }

    private func setFloatMix(_ mix: [Int: Int]) {
        var updated: [Int: String] = [:]
        for denomination in CashDrawer.floatDenominations {
            updated[denomination] = String(mix[denomination] ?? 0)
        }
        floatMixQuantities = updated
    }

    private func parsedFloatMixOrThrow() throws -> [Int: Int] {
        var result: [Int: Int] = [:]
        for denomination in CashDrawer.floatDenominations {
            let rawValue = (floatMixQuantities[denomination] ?? "0").trimmingCharacters(in: .whitespacesAndNewlines)
            let valueText = rawValue.isEmpty ? "0" : rawValue
            guard let quantity = Int(valueText) else {
                throw NSError(domain: "CashDrawerService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Float quantity for \(formatDenomination(denomination)) must be a whole number."])
            }
            guard quantity >= 0 else {
                throw NSError(domain: "CashDrawerService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Float quantities cannot be negative."])
            }
            if quantity > 0 {
                result[denomination] = quantity
            }
        }
        return result
    }

    private func parsedFloatMixOrDefault() -> [Int: Int] {
        (try? parsedFloatMixOrThrow()) ?? [:]
    }

    private func parseMoneyToCents(_ text: String) -> Int? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard !cleaned.isEmpty else { return 2_000_000 }
        guard let amount = Decimal(string: cleaned) else { return nil }
        let cents = NSDecimalNumber(decimal: amount)
            .multiplying(by: NSDecimalNumber(value: 100))
        return cents.intValue
    }

    func formatDenomination(_ denomination: Int) -> String {
        String(format: "$%.2f", Double(denomination) / 100)
    }

    func formatCents(_ cents: Int) -> String {
        String(format: "$%.2f", Double(cents) / 100)
    }

    private func formatMoney(_ amount: Decimal) -> String {
        NSDecimalNumber(decimal: amount).stringValue
    }
}

struct CashDrawerManagementSectionView: View {
    @ObservedObject var viewModel: CashDrawerManagementViewModel
    let canManage: Bool

    var body: some View {
        Form {
            if !canManage {
                lockedSection("You do not have permission to manage cash drawers.")
            } else {
                if let message = viewModel.message {
                    Section { Text(message).foregroundStyle(message.hasPrefix("Saved") || message.hasPrefix("Assigned") || message.hasPrefix("Unassigned") ? .green : .red) }
                }

                Section("Store") {
                    Picker("Store", selection: $viewModel.selectedStoreId) {
                        Text("Select Store").tag(nil as Int?)
                        ForEach(viewModel.stores) { store in
                            Text(store.name).tag(Optional(store.id))
                        }
                    }
                    Toggle("Include inactive", isOn: $viewModel.includeInactive)
                    Button {
                        Task { await viewModel.loadDrawerData() }
                    } label: {
                        Label("Refresh Drawers", systemImage: "arrow.clockwise")
                    }
                }
                .onChange(of: viewModel.selectedStoreId) { _, _ in Task { await viewModel.loadDrawerData() } }
                .onChange(of: viewModel.includeInactive) { _, _ in Task { await viewModel.loadDrawerData() } }

                Section("Drawers") {
                    if viewModel.isLoading {
                        ProgressView("Loading drawers...")
                    } else if viewModel.drawers.isEmpty {
                        ContentUnavailableView("No Cash Drawers", systemImage: "tray")
                    } else {
                        ForEach(viewModel.drawers) { drawer in
                            Button {
                                viewModel.selectDrawer(drawer)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(drawer.displayName)
                                            .font(.headline)
                                        Text(drawer.isActive ? "Active" : "Inactive")
                                            .font(.caption)
                                            .foregroundStyle(drawer.isActive ? .green : .secondary)
                                    }
                                    Spacer()
                                    if viewModel.selectedDrawerId == drawer.drawerId {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section(viewModel.selectedDrawerId == nil ? "New Drawer" : "Drawer Editor") {
                    TextField("Name", text: $viewModel.drawerName)
                    TextField("Description / Code", text: $viewModel.drawerDescription)
                    TextField("Starting Cash", text: $viewModel.startingCashText)
                        .keyboardType(.decimalPad)
                    ForEach(CashDrawer.floatDenominations, id: \.self) { denomination in
                        TextField(
                            "\(viewModel.formatDenomination(denomination)) quantity",
                            text: Binding(
                                get: { viewModel.floatMixQuantities[denomination] ?? "0" },
                                set: { viewModel.floatMixQuantities[denomination] = $0 }
                            )
                        )
                        .keyboardType(.numberPad)
                    }
                    HStack {
                        Text("Float Mix Total")
                        Spacer()
                        Text(viewModel.formatCents(viewModel.floatMixTotalInCents))
                            .foregroundStyle(
                                viewModel.floatMixMatchesStartingCash
                                ? Color.green
                                : Color.red
                            )
                    }
                    if let startingCashInCents = viewModel.startingCashInCents {
                        HStack {
                            Text("Starting Cash Value")
                            Spacer()
                            Text(viewModel.formatCents(startingCashInCents))
                                .foregroundStyle(
                                    viewModel.floatMixMatchesStartingCash
                                    ? Color.green
                                    : Color.red
                                )
                        }
                    } else {
                        Text("Starting cash amount is invalid.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Toggle("Allow float mismatch", isOn: $viewModel.allowFloatMismatch)
                    Toggle("Active", isOn: $viewModel.drawerIsActive)
                    HStack {
                        Button {
                            viewModel.clearDrawer()
                        } label: {
                            Label("New", systemImage: "plus")
                        }
                        Spacer()
                        Button {
                            Task { await viewModel.saveDrawer() }
                        } label: {
                            Label(viewModel.isSaving ? "Saving" : "Save Drawer", systemImage: "checkmark.circle")
                        }
                        .disabled(viewModel.isSaving)
                    }
                }

                Section("Device Assignment") {
                    Picker("Device", selection: $viewModel.selectedDeviceId) {
                        Text("Select Device").tag(nil as UUID?)
                        ForEach(viewModel.devices) { device in
                            Text(device.drawerDisplayName).tag(Optional(device.id))
                        }
                    }
                    Picker("Drawer", selection: $viewModel.selectedDrawerId) {
                        Text("Select Drawer").tag(nil as Int64?)
                        ForEach(viewModel.activeDrawers) { drawer in
                            Text(drawer.displayName).tag(Optional(drawer.drawerId))
                        }
                    }
                    TextField("Notes", text: $viewModel.assignmentNotes, axis: .vertical)
                    Button {
                        Task { await viewModel.assignDevice() }
                    } label: {
                        Label("Assign Device", systemImage: "link")
                    }
                }

                Section("Current Assignments") {
                    if viewModel.assignments.isEmpty {
                        Text("No active device assignments.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.assignments) { assignment in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(assignment.devices?.displayName ?? viewModel.deviceName(for: assignment.deviceId))
                                            .font(.headline)
                                        Text(assignment.cashDrawers?.displayName ?? "Drawer #\(assignment.drawerId)")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Unassign") {
                                        Task { await viewModel.unassign(assignment) }
                                    }
                                    .buttonStyle(.borderless)
                                }
                                if let notes = assignment.notes, !notes.isEmpty {
                                    Text(notes)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
    }
}

@ViewBuilder
private func lockedSection(_ text: String) -> some View {
    Section {
        Label(text, systemImage: "lock")
            .foregroundStyle(.secondary)
    }
}

private extension TrackedDevice {
    var drawerDisplayName: String {
        let name = deviceName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let local = localUsername?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty { return name }
        if !local.isEmpty { return local }
        return modelName
    }
}
