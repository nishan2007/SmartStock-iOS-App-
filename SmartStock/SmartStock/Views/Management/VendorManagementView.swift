//
//  VendorManagementView.swift
//  SmartStock
//

import SwiftUI
import Supabase

struct VendorManagementView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @State private var vendors: [VendorAdminRow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var draftName = ""
    @State private var editingVendor: VendorAdminRow?
    @State private var editingName = ""
    @State private var editingIsActive = true

    var body: some View {
        List {
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }

            Section("Vendors") {
                if isLoading {
                    ProgressView("Loading vendors...")
                } else if vendors.isEmpty {
                    ContentUnavailableView("No Vendors", systemImage: "building.2")
                } else {
                    ForEach(vendors) { vendor in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(vendor.name)
                                Text(vendor.isActive ? "Active" : "Inactive")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if canManageVendors {
                                Button("Edit") {
                                    editingVendor = vendor
                                    editingName = vendor.name
                                    editingIsActive = vendor.isActive
                                }
                                .font(.caption.weight(.semibold))
                            }
                        }
                    }
                }
            }

            if canManageVendors {
                Section("Add Vendor") {
                    TextField("Vendor name", text: $draftName)
                    Button("Save Vendor") {
                        Task { await saveVendor() }
                    }
                    .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationTitle("Vendors")
        .task {
            guard canViewVendors else {
                errorMessage = "You do not have permission to view vendors."
                return
            }
            await loadVendors()
        }
        .refreshable {
            guard canViewVendors else { return }
            await loadVendors()
        }
        .alert("Edit Vendor", isPresented: Binding(get: { editingVendor != nil }, set: { if !$0 { editingVendor = nil } })) {
            TextField("Vendor name", text: $editingName)
            Toggle("Active", isOn: $editingIsActive)
            Button("Cancel", role: .cancel) { editingVendor = nil }
            Button("Save") { Task { await updateVendor() } }
        }
    }

    private var canManageVendors: Bool {
        sessionManager.currentUser?.canAccess(.vendorManagement) == true
    }

    private var canViewVendors: Bool {
        canManageVendors || sessionManager.currentUser?.canAccess(.viewVendor) == true
    }

    private func loadVendors() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            vendors = try await supabase
                .from("vendors")
                .select("vendor_id, name, is_active")
                .order("name", ascending: true)
                .execute()
                .value
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveVendor() async {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            _ = try await supabase.from("vendors").insert(VendorWritePayload(name: name, isActive: true)).execute()
            draftName = ""
            await loadVendors()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateVendor() async {
        guard let editingVendor else { return }
        let name = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            _ = try await supabase
                .from("vendors")
                .update(VendorWritePayload(name: name, isActive: editingIsActive))
                .eq("vendor_id", value: editingVendor.id)
                .execute()
            self.editingVendor = nil
            await loadVendors()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
