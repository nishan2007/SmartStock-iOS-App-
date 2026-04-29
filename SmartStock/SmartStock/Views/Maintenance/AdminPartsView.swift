//
//  AdminPartsView.swift
//  SmartStock
//

import SwiftUI

struct AdminPartsView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @State private var parts: [MaintenancePart] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var editorDraft: MaintenancePartDraft?
    @State private var partPendingDelete: MaintenancePart?

    var body: some View {
        List {
            if !canManageParts {
                Section {
                    ContentUnavailableView(
                        "Parts Locked",
                        systemImage: "lock.shield",
                        description: Text("Your role does not have Parts Management access.")
                    )
                }
            } else {
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }

                Section("Parts") {
                    if isLoading {
                        ProgressView("Loading parts...")
                    } else if parts.isEmpty {
                        ContentUnavailableView("No Parts", systemImage: "gearshape.2")
                    } else {
                        ForEach(parts) { part in
                            Button {
                                editorDraft = MaintenancePartDraft(part: part)
                            } label: {
                                PartSummaryRow(part: part)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) {
                                    partPendingDelete = part
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Parts")
        .toolbar {
            if canManageParts {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorDraft = MaintenancePartDraft()
                    } label: {
                        Label("Add Part", systemImage: "plus")
                    }
                }
            }
        }
        .task {
            guard canManageParts else { return }
            await loadParts()
        }
        .refreshable {
            guard canManageParts else { return }
            await loadParts()
        }
        .sheet(item: $editorDraft) { draft in
            NavigationStack {
                PartEditorView(initialDraft: draft) { savedDraft in
                    await savePart(savedDraft)
                }
            }
        }
        .confirmationDialog(
            "Delete Part?",
            isPresented: Binding(get: { partPendingDelete != nil }, set: { if !$0 { partPendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Part", role: .destructive) {
                Task { await deleteSelectedPart() }
            }
            Button("Cancel", role: .cancel) { partPendingDelete = nil }
        } message: {
            Text("This removes the part record. Existing machine associations may also be affected by database constraints.")
        }
    }

    private var canManageParts: Bool {
        sessionManager.currentUser?.canAccess(.partsManagement) == true
    }

    private func loadParts() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            parts = try await MaintenanceService.shared.fetchParts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func savePart(_ draft: MaintenancePartDraft) async {
        do {
            if let id = draft.id {
                try await MaintenanceService.shared.updatePart(id: id, draft: draft)
            } else {
                try await MaintenanceService.shared.createPart(from: draft)
            }
            editorDraft = nil
            await loadParts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteSelectedPart() async {
        guard let partPendingDelete else { return }
        do {
            try await MaintenanceService.shared.deletePart(id: partPendingDelete.id)
            self.partPendingDelete = nil
            await loadParts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PartEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MaintenancePartDraft
    let onSave: (MaintenancePartDraft) async -> Void

    init(initialDraft: MaintenancePartDraft, onSave: @escaping (MaintenancePartDraft) async -> Void) {
        _draft = State(initialValue: initialDraft)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("Part") {
                TextField("Name", text: $draft.partName)
                TextField("Part number", text: $draft.partNumber)
                TextField("Category", text: $draft.category)
                Toggle("Active", isOn: $draft.isActive)
            }

            Section("Inventory") {
                TextField("On hand quantity", text: $draft.quantityOnHand)
                    .keyboardType(.numberPad)
                TextField("Reorder point", text: $draft.reorderPoint)
                    .keyboardType(.numberPad)
                TextField("Reorder quantity", text: $draft.reorderQuantity)
                    .keyboardType(.numberPad)
                TextField("Unit cost", text: $draft.unitCost)
                    .keyboardType(.decimalPad)
            }

            Section("Storage") {
                TextField("Vendor", text: $draft.vendorName)
                TextField("Bin location", text: $draft.binLocation)
            }

            Section("Notes") {
                TextField("Notes", text: $draft.notes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle(draft.id == nil ? "New Part" : "Edit Part")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await onSave(draft) }
                }
                .disabled(draft.partName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

extension MaintenancePartDraft: Identifiable {}
