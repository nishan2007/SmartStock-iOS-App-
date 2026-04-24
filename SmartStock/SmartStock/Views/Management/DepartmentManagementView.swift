//
//  DepartmentManagementView.swift
//  SmartStock
//

import SwiftUI
import Supabase

struct DepartmentManagementView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @State private var departments: [InventoryLookupOption] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var draftName = ""
    @State private var editingDepartment: InventoryLookupOption?
    @State private var editingName = ""

    var body: some View {
        List {
            if !canManageDepartments {
                Section {
                    Text("You do not have permission to manage departments.")
                        .foregroundStyle(.secondary)
                }
            } else if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }

            Section("Departments") {
                if !canManageDepartments {
                    EmptyView()
                } else if isLoading {
                    ProgressView("Loading departments...")
                } else if departments.isEmpty {
                    ContentUnavailableView("No Departments", systemImage: "square.grid.2x2")
                } else {
                    ForEach(departments) { department in
                        HStack {
                            Text(department.name)
                            Spacer()
                            Button("Edit") {
                                editingDepartment = department
                                editingName = department.name
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                }
            }

            if canManageDepartments {
                Section("Add Department") {
                    TextField("Department name", text: $draftName)
                    Button("Save Department") {
                        Task { await saveDepartment() }
                    }
                    .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationTitle("Departments")
        .task {
            guard canManageDepartments else { return }
            await loadDepartments()
        }
        .refreshable {
            guard canManageDepartments else { return }
            await loadDepartments()
        }
        .alert("Edit Department", isPresented: Binding(get: { editingDepartment != nil }, set: { if !$0 { editingDepartment = nil } })) {
            TextField("Department name", text: $editingName)
            Button("Cancel", role: .cancel) { editingDepartment = nil }
            Button("Save") { Task { await updateDepartment() } }
        }
    }

    private var canManageDepartments: Bool {
        sessionManager.currentUser?.canAccess(.departmentManagement) == true
    }

    private func loadDepartments() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            departments = try await supabase
                .from("categories")
                .select("category_id, name")
                .order("name", ascending: true)
                .execute()
                .value
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveDepartment() async {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            _ = try await supabase.from("categories").insert(["name": name]).execute()
            draftName = ""
            await loadDepartments()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateDepartment() async {
        guard let editingDepartment else { return }
        let name = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            _ = try await supabase
                .from("categories")
                .update(["name": name])
                .eq("category_id", value: editingDepartment.id)
                .execute()
            self.editingDepartment = nil
            await loadDepartments()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
