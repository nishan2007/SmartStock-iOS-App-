//
//  EditItemView.swift
//  SmartStock
//

import SwiftUI

struct EditItemView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @StateObject private var viewModel = InventoryViewModel()
    @State private var isShowingScanner = false
    @State private var isShowingNewItem = false

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.items.isEmpty {
                ProgressView("Loading items...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredItems.isEmpty {
                ContentUnavailableView(
                    emptyStateTitle,
                    systemImage: "shippingbox",
                    description: Text(emptyStateDescription)
                )
            } else {
                List(viewModel.filteredItems) { item in
                    if canEditItems {
                        NavigationLink {
                            InventoryDetailView(item: item) {
                                Task {
                                    await viewModel.refresh(locationId: sessionManager.selectedStore?.id)
                                }
                            }
                            .environmentObject(sessionManager)
                        } label: {
                            itemRow(item)
                        }
                    } else {
                        itemRow(item)
                    }
                }
            }
        }
        .navigationTitle("Items")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if canEditItems {
                    Button {
                        isShowingScanner = true
                    } label: {
                        Image(systemName: "barcode.viewfinder")
                    }
                    .accessibilityLabel("Scan barcode")
                }

                if canAddNewItem {
                    Button {
                        isShowingNewItem = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("New item")
                }
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Search item, SKU, barcode")
        .onSubmit(of: .search) {
            guard canEditItems else { return }

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

    private var canAddNewItem: Bool {
        sessionManager.currentUser?.canAccess(.addNewItem) == true
    }

    private var canEditItems: Bool {
        sessionManager.currentUser?.canAccess(.editItem) == true
    }

    private var emptyStateTitle: String {
        canEditItems ? "No Items Found" : "Create Your First Item"
    }

    private var emptyStateDescription: String {
        if canEditItems {
            return "Search for an item or check the selected store."
        }

        if canAddNewItem {
            return "Tap the plus button to create a new product."
        }

        return "You do not have item permissions."
    }

    private func itemRow(_ item: InventoryItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(.headline)
            Text("\(item.sku) - \(item.locationName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !canEditItems {
                Text("Edit permission required")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
