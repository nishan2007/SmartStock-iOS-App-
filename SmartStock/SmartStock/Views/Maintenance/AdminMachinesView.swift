//
//  AdminMachinesView.swift
//  SmartStock
//

import SwiftUI

struct AdminMachinesView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @State private var machines: [MaintenanceMachine] = []
    @State private var stores: [Store] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var editorDraft: MaintenanceMachineDraft?
    @State private var machinePendingDelete: MaintenanceMachine?

    var body: some View {
        List {
            if !canManageMachines {
                Section {
                    ContentUnavailableView(
                        "Machines Locked",
                        systemImage: "lock.shield",
                        description: Text("Your role does not have Machine Management access.")
                    )
                }
            } else {
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }

                Section("Machines") {
                    if isLoading {
                        ProgressView("Loading machines...")
                    } else if machines.isEmpty {
                        ContentUnavailableView("No Machines", systemImage: "wrench.and.screwdriver")
                    } else {
                        ForEach(machines) { machine in
                            Button {
                                editorDraft = MaintenanceMachineDraft(machine: machine)
                            } label: {
                                MachineSummaryRow(machine: machine)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) {
                                    machinePendingDelete = machine
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Machines")
        .toolbar {
            if canManageMachines {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        var draft = MaintenanceMachineDraft()
                        draft.locationId = stores.first?.id
                        editorDraft = draft
                    } label: {
                        Label("Add Machine", systemImage: "plus")
                    }
                }
            }
        }
        .task {
            guard canManageMachines else { return }
            await loadData()
        }
        .refreshable {
            guard canManageMachines else { return }
            await loadData()
        }
        .sheet(item: $editorDraft) { draft in
            NavigationStack {
                MachineEditorView(initialDraft: draft, stores: stores) { savedDraft in
                    await saveMachine(savedDraft)
                }
            }
        }
        .confirmationDialog(
            "Delete Machine?",
            isPresented: Binding(get: { machinePendingDelete != nil }, set: { if !$0 { machinePendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Machine", role: .destructive) {
                Task { await deleteSelectedMachine() }
            }
            Button("Cancel", role: .cancel) { machinePendingDelete = nil }
        } message: {
            Text("This removes the machine record and may remove associated compatibility links depending on database constraints.")
        }
    }

    private var canManageMachines: Bool {
        sessionManager.currentUser?.canAccess(.machineManagement) == true
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let machinesTask = MaintenanceService.shared.fetchMachines()
            async let storesTask = StoreService.shared.fetchStores()

            machines = try await machinesTask
            stores = try await storesTask
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveMachine(_ draft: MaintenanceMachineDraft) async {
        do {
            if let id = draft.id {
                try await MaintenanceService.shared.updateMachine(id: id, draft: draft)
            } else {
                _ = try await MaintenanceService.shared.createMachine(from: draft)
            }
            editorDraft = nil
            await loadData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteSelectedMachine() async {
        guard let machinePendingDelete else { return }
        do {
            try await MaintenanceService.shared.deleteMachine(id: machinePendingDelete.id)
            self.machinePendingDelete = nil
            await loadData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct MachineEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MaintenanceMachineDraft
    @State private var activeParts: [MaintenancePart] = []
    @State private var associatedParts: [MaintenanceMachinePart] = []
    @State private var selectedPartId: Int?
    @State private var associationNotes = ""
    @State private var associationError: String?
    @State private var isLoadingAssociations = false

    let stores: [Store]
    let onSave: (MaintenanceMachineDraft) async -> Void

    init(
        initialDraft: MaintenanceMachineDraft,
        stores: [Store],
        onSave: @escaping (MaintenanceMachineDraft) async -> Void
    ) {
        _draft = State(initialValue: initialDraft)
        self.stores = stores
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("Machine") {
                TextField("Machine name", text: $draft.machineName)
                TextField("Asset tag", text: $draft.assetTag)
                TextField("Serial number", text: $draft.serialNumber)
                TextField("Manufacturer", text: $draft.manufacturer)
                TextField("Model", text: $draft.model)
                TextField("Machine type", text: $draft.machineType)
            }

            Section("Store") {
                Picker("Store", selection: $draft.locationId) {
                    Text("Select Store").tag(Optional<Int>.none)
                    ForEach(stores) { store in
                        Text(store.name).tag(Optional(store.id))
                    }
                }
            }

            Section("Status") {
                Picker("Status", selection: $draft.status) {
                    ForEach(MaintenanceMachineStatus.allCases) { status in
                        Text(status.title).tag(status)
                    }
                }
            }

            Section("Dates") {
                TextField("Purchase date (YYYY-MM-DD)", text: $draft.purchaseDate)
                TextField("Warranty expiration (YYYY-MM-DD)", text: $draft.warrantyExpirationDate)
                TextField("Last service (YYYY-MM-DD)", text: $draft.lastServiceDate)
                TextField("Next service (YYYY-MM-DD)", text: $draft.nextServiceDate)
            }

            Section("Notes") {
                TextField("Notes", text: $draft.notes, axis: .vertical)
                    .lineLimit(3...6)
            }

            associatedPartsSection
        }
        .navigationTitle(draft.id == nil ? "New Machine" : "Edit Machine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await onSave(draft) }
                }
                .disabled(
                    draft.machineName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || draft.locationId == nil
                )
            }
        }
        .task {
            await loadAssociationData()
        }
    }

    @ViewBuilder
    private var associatedPartsSection: some View {
        Section("Associated Parts") {
            if draft.id == nil {
                Text("Save the machine before adding compatible parts.")
                    .foregroundStyle(.secondary)
            } else if isLoadingAssociations {
                ProgressView("Loading parts...")
            } else {
                if let associationError {
                    Text(associationError).foregroundStyle(.red)
                }

                Picker("Part", selection: $selectedPartId) {
                    Text("Select Part").tag(Optional<Int>.none)
                    ForEach(availableParts) { part in
                        Text(partLabel(part)).tag(Optional(part.id))
                    }
                }

                TextField("Association notes", text: $associationNotes, axis: .vertical)
                    .lineLimit(2...4)

                Button {
                    Task { await addSelectedPart() }
                } label: {
                    Label("Add Part", systemImage: "plus.circle.fill")
                }
                .disabled(selectedPartId == nil)

                if associatedParts.isEmpty {
                    Text("No associated parts.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(associatedParts) { association in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(association.partName)
                                        .font(.headline)
                                    Text(association.partNumberText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Remove", role: .destructive) {
                                    Task { await removeAssociation(association) }
                                }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.borderless)
                            }

                            if let notes = association.notes?.nilIfBlank {
                                Text(notes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var availableParts: [MaintenancePart] {
        let associatedPartIds = Set(associatedParts.map(\.partId))
        return activeParts.filter { !associatedPartIds.contains($0.id) }
    }

    private func loadAssociationData() async {
        guard let machineId = draft.id else { return }
        isLoadingAssociations = true
        associationError = nil
        defer { isLoadingAssociations = false }

        do {
            async let partsTask = MaintenanceService.shared.fetchParts(activeOnly: true)
            async let associationsTask = MaintenanceService.shared.fetchMachineParts(machineId: machineId)

            activeParts = try await partsTask
            associatedParts = try await associationsTask
            selectedPartId = availableParts.first?.id
        } catch {
            associationError = error.localizedDescription
        }
    }

    private func addSelectedPart() async {
        guard let machineId = draft.id, let selectedPartId else { return }
        associationError = nil

        do {
            try await MaintenanceService.shared.addPart(
                machineId: machineId,
                partId: selectedPartId,
                notes: associationNotes
            )
            associationNotes = ""
            await loadAssociationData()
        } catch {
            associationError = error.localizedDescription
        }
    }

    private func removeAssociation(_ association: MaintenanceMachinePart) async {
        associationError = nil

        do {
            try await MaintenanceService.shared.removeMachinePart(id: association.id)
            await loadAssociationData()
        } catch {
            associationError = error.localizedDescription
        }
    }

    private func partLabel(_ part: MaintenancePart) -> String {
        if let partNumber = part.partNumber?.nilIfBlank {
            return "\(part.partName) (\(partNumber))"
        }

        return part.partName
    }
}

extension MaintenanceMachineDraft: Identifiable {}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
