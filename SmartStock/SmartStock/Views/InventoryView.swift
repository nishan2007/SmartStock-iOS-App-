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
                            locationFilterBar
                            statusFilterBar

                            LazyVStack(spacing: 12) {
                                ForEach(viewModel.filteredItems) { item in
                                    NavigationLink {
                                        InventoryDetailView(item: item) {
                                            Task {
                                                await viewModel.refresh(locationId: sessionManager.selectedStore?.id)
                                            }
                                        }
                                    } label: {
                                        InventoryRowView(item: item)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding()
                    }
                    .refreshable {
                        await viewModel.refresh(locationId: sessionManager.selectedStore?.id)
                    }
                }
            }
            .navigationTitle("Inventory")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isShowingScanner = true
                    } label: {
                        Image(systemName: "barcode.viewfinder")
                    }
                    .accessibilityLabel("Scan barcode")

                    Button {
                        isShowingNewItem = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Add item")
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
            .sheet(isPresented: $isShowingNewItem) {
                InventoryItemFormView(mode: .add, defaultStore: sessionManager.selectedStore) {
                    Task {
                        await viewModel.refresh(locationId: sessionManager.selectedStore?.id)
                    }
                }
                .environmentObject(sessionManager)
            }
            .task {
                if viewModel.items.isEmpty {
                    await viewModel.loadInventory(locationId: sessionManager.selectedStore?.id)
                }
            }
        }
    }

    private var summaryCards: some View {
        HStack(spacing: 12) {
            summaryCard(title: "Items", value: "\(viewModel.totalItemsCount)", systemImage: "shippingbox", tint: .blue)
            summaryCard(title: "Low Stock", value: "\(viewModel.lowStockCount)", systemImage: "exclamationmark.circle", tint: .orange)
            summaryCard(title: "Out", value: "\(viewModel.outOfStockCount)", systemImage: "xmark.circle", tint: .red)
        }
    }

    private var locationFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "All Stores", isSelected: viewModel.selectedLocationId == nil) {
                    viewModel.selectAllLocations()
                }

                ForEach(viewModel.locations, id: \.id) { location in
                    filterChip(title: location.name, isSelected: viewModel.selectedLocationId == location.id) {
                        viewModel.selectedLocationId = location.id
                    }
                }
            }
        }
    }

    private var statusFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "All Status", isSelected: viewModel.selectedStatus == nil) {
                    viewModel.selectedStatus = nil
                }

                ForEach(InventoryStockStatus.allCases, id: \.self) { status in
                    filterChip(title: status.rawValue, isSelected: viewModel.selectedStatus == status) {
                        viewModel.selectedStatus = status
                    }
                }
            }
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

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground))
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
