//
//  LocationManagementView.swift
//  SmartStock
//

import SwiftUI
import Supabase

struct LocationManagementView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @State private var locations: [Store] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var draftName = ""
    @State private var draftAddress = ""
    @State private var editingLocation: Store?
    @State private var editingName = ""
    @State private var editingAddress = ""

    var body: some View {
        List {
            if !canManageLocations {
                Section {
                    Text("You do not have permission to manage locations.")
                        .foregroundStyle(.secondary)
                }
            } else if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }

            Section("Locations") {
                if !canManageLocations {
                    EmptyView()
                } else if isLoading {
                    ProgressView("Loading locations...")
                } else if locations.isEmpty {
                    ContentUnavailableView("No Locations", systemImage: "storefront")
                } else {
                    ForEach(locations) { location in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(location.name)
                                if let address = location.address, !address.isEmpty {
                                    Text(address)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Edit") {
                                editingLocation = location
                                editingName = location.name
                                editingAddress = location.address ?? ""
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                }
            }

            if canManageLocations {
                Section("Add Location") {
                    TextField("Location name", text: $draftName)
                    TextField("Address", text: $draftAddress)
                    Button("Save Location") {
                        Task { await saveLocation() }
                    }
                    .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationTitle("Locations")
        .task {
            guard canManageLocations else { return }
            await loadLocations()
        }
        .refreshable {
            guard canManageLocations else { return }
            await loadLocations()
        }
        .alert("Edit Location", isPresented: Binding(get: { editingLocation != nil }, set: { if !$0 { editingLocation = nil } })) {
            TextField("Location name", text: $editingName)
            TextField("Address", text: $editingAddress)
            Button("Cancel", role: .cancel) { editingLocation = nil }
            Button("Save") { Task { await updateLocation() } }
        }
    }

    private var canManageLocations: Bool {
        sessionManager.currentUser?.canAccess(.locationManagement) == true
    }

    private func loadLocations() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            locations = try await StoreService.shared.fetchStores()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveLocation() async {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            _ = try await supabase
                .from("locations")
                .insert(LocationWritePayload(name: name, address: normalizedValue(draftAddress)))
                .execute()
            draftName = ""
            draftAddress = ""
            await loadLocations()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateLocation() async {
        guard let editingLocation else { return }
        let name = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            _ = try await supabase
                .from("locations")
                .update(LocationWritePayload(name: name, address: normalizedValue(editingAddress)))
                .eq("location_id", value: editingLocation.id)
                .execute()
            self.editingLocation = nil
            await loadLocations()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
