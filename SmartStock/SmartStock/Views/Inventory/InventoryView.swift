//
//  InventoryView.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/15/26.
//

import SwiftUI

struct InventoryView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @StateObject private var viewModel = InventoryViewModel()
    @State private var isShowingNewItem = false
    @State private var isShowingScanner = false
    @State private var isShowingFilters = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView("Loading inventory...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
                    ContentUnavailableView(
                        "Unable to Load Inventory",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else if viewModel.filteredItems.isEmpty {
                    ContentUnavailableView(
                        "No Inventory Found",
                        systemImage: "shippingbox",
                        description: Text("Try changing your search, store, or stock filter.")
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            summaryCards

                            LazyVStack(spacing: 12) {
                                ForEach(viewModel.filteredItems) { item in
                                    Group {
                                        if canOpenItemDetails {
                                            NavigationLink {
                                                InventoryDetailView(item: item) {
                                                    Task {
                                                        await loadInventoryForCurrentPermissions()
                                                    }
                                                }
                                                .environmentObject(sessionManager)
                                            } label: {
                                                InventoryRowView(item: item)
                                            }
                                        } else {
                                            InventoryRowView(item: item)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding()
                    }
                    .refreshable {
                        await loadInventoryForCurrentPermissions()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Inventory")
                        .font(.title2.weight(.semibold))
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isShowingFilters = true
                    } label: {
                        Image(systemName: activeFilterCount == 0 ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: 34, height: 34)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Inventory filters")

                    Button {
                        isShowingScanner = true
                    } label: {
                        Image(systemName: "barcode.viewfinder")
                    }
                    .accessibilityLabel("Scan barcode")

                    if canAddNewItem {
                        Button {
                            isShowingNewItem = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .accessibilityLabel("Add item")
                    }

                    if canManageCustomOrderItems {
                        NavigationLink {
                            CustomOrderItemsView()
                                .environmentObject(sessionManager)
                        } label: {
                            Image(systemName: "tshirt.fill")
                        }
                        .accessibilityLabel("Custom Order Items")
                    }
                }
            }
            .searchable(text: $viewModel.searchText, prompt: "Search by item, SKU, barcode, store...")
            .onSubmit(of: .search) {
                Task {
                    await viewModel.searchBarcode(viewModel.searchText)
                }
            }
            .onChange(of: viewModel.searchText) {
                viewModel.resolvedBarcodeProductId = nil
            }
            .sheet(isPresented: $isShowingScanner) {
                BarcodeScannerSheet(
                    scannedCode: $viewModel.searchText,
                    isPresented: $isShowingScanner,
                    onScanned: { code in
                        Task {
                            await viewModel.searchBarcode(code)
                        }
                    }
                )
            }
            .sheet(isPresented: $isShowingFilters) {
                NavigationStack {
                    inventoryFiltersSheet
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $isShowingNewItem) {
                InventoryItemFormView(mode: .add, defaultStore: sessionManager.selectedStore) {
                    Task {
                        await loadInventoryForCurrentPermissions()
                    }
                }
                .environmentObject(sessionManager)
            }
            .task {
                if viewModel.items.isEmpty {
                    await loadInventoryForCurrentPermissions()
                }
            }
            .onChange(of: sessionManager.selectedStore?.id) { _, _ in
                Task {
                    await loadInventoryForCurrentPermissions()
                }
            }
        }
    }

    private var canOpenItemDetails: Bool {
        sessionManager.currentUser?.canAccess(.viewItemDetails) == true
        || sessionManager.currentUser?.canAccess(.editItem) == true
    }

    private var canAddNewItem: Bool {
        sessionManager.currentUser?.canAccess(.addNewItem) == true
    }

    private var canManageCustomOrderItems: Bool {
        sessionManager.currentUser?.canAccess(.customOrderItems) == true
        || sessionManager.currentUser?.canAccess(.customOrderPrintMaterials) == true
    }

    private var canViewAllStoresInventory: Bool {
        sessionManager.currentUser?.canAccess(.viewAllStoresInventory) == true
    }

    private var activeFilterCount: Int {
        (viewModel.selectedStatus == nil ? 0 : 1)
            + (canViewAllStoresInventory && viewModel.selectedLocationId != nil ? 1 : 0)
    }

    private func loadInventoryForCurrentPermissions() async {
        if canViewAllStoresInventory {
            await viewModel.loadInventory()
        } else {
            await viewModel.loadInventory(locationId: sessionManager.selectedStore?.id)
        }
    }

    private var summaryCards: some View {
        HStack(spacing: 12) {
            summaryCard(title: "Items", value: "\(viewModel.totalItemsCount)", systemImage: "shippingbox", tint: .blue)
            summaryCard(title: "Low Stock", value: "\(viewModel.lowStockCount)", systemImage: "exclamationmark.circle", tint: .orange)
            summaryCard(title: "Out", value: "\(viewModel.outOfStockCount)", systemImage: "xmark.circle", tint: .red)
        }
    }

    private func summaryCard(title: String, value: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)

            Text(value)
                .font(.title3.weight(.bold))

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            LinearGradient(
                colors: [tint.opacity(0.16), Color(.secondarySystemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var inventoryFiltersSheet: some View {
        List {
            if canViewAllStoresInventory {
                Section("Store") {
                    Picker("Store", selection: $viewModel.selectedLocationId) {
                        Text("All Stores").tag(Optional<Int>.none)
                        ForEach(viewModel.locations, id: \.id) { location in
                            Text(location.name).tag(Optional(location.id))
                        }
                    }
                }
            }

            Section("Stock Status") {
                Picker("Status", selection: $viewModel.selectedStatus) {
                    Text("All Status").tag(Optional<InventoryStockStatus>.none)
                    ForEach(InventoryStockStatus.allCases, id: \.self) { status in
                        Text(status.rawValue).tag(Optional(status))
                    }
                }
            }

            Section {
                Button {
                    resetFilters()
                } label: {
                    Label("Reset Filters", systemImage: "arrow.counterclockwise")
                }
                .disabled(activeFilterCount == 0)
            }
        }
        .navigationTitle("Filters")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    isShowingFilters = false
                }
            }
        }
    }

    private func resetFilters() {
        if canViewAllStoresInventory {
            viewModel.selectAllLocations()
        }
        viewModel.selectedStatus = nil
    }
}
