//
//  AssignStoresView.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/16/26.
//

import SwiftUI

struct AssignStoresView: View {
    @Environment(\.dismiss) private var dismiss

    let employee: Employee
    var onSaved: (() async -> Void)?

    @State private var stores: [Store] = []
    @State private var selectedStoreIds: Set<Int> = []
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }
            }

            Section("Store Access") {
                ForEach(stores, id: \.id) { store in
                    Button {
                        if selectedStoreIds.contains(store.id) {
                            selectedStoreIds.remove(store.id)
                        } else {
                            selectedStoreIds.insert(store.id)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(store.name)
                                    .foregroundColor(.primary)

                                if let address = store.address, !address.isEmpty {
                                    Text(address)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            Image(systemName: selectedStoreIds.contains(store.id) ? "checkmark.circle.fill" : "circle")
                        }
                    }
                }
            }
        }
        .navigationTitle("Assign Stores")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") {
                        Task {
                            await saveStores()
                        }
                    }
                }
            }
        }
        .task {
            await loadStores()
        }
        .overlay {
            if isLoading {
                LoadingView()
                    .background(Color(.systemBackground).opacity(0.85))
            }
        }
    }

    private func loadStores() async {
        isLoading = true
        errorMessage = nil
        selectedStoreIds = Set(employee.assignedStores.map(\.id))

        do {
            stores = try await StoreService.shared.fetchStores()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func saveStores() async {
        isSaving = true
        errorMessage = nil

        do {
            try await EmployeeService.shared.updateEmployeeStores(
                employeeId: employee.id,
                storeIds: Array(selectedStoreIds)
            )

            if let onSaved {
                await onSaved()
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }
}
