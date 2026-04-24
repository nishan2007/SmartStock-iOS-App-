//
//  EditItemView.swift
//  SmartStock
//

import SwiftUI

struct EditItemView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @StateObject private var viewModel = InventoryViewModel()
    @State private var isShowingScanner = false

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.items.isEmpty {
                ProgressView("Loading items...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredItems.isEmpty {
                ContentUnavailableView(
                    "No Items Found",
                    systemImage: "shippingbox",
                    description: Text("Search for an item or check the selected store.")
                )
            } else {
                List(viewModel.filteredItems) { item in
                    NavigationLink {
                        InventoryDetailView(item: item) {
                            Task {
                                await viewModel.refresh(locationId: sessionManager.selectedStore?.id)
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                                .font(.headline)
                            Text("\(item.sku) - \(item.locationName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Edit Item")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingScanner = true
                } label: {
                    Image(systemName: "barcode.viewfinder")
                }
                .accessibilityLabel("Scan barcode")
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Search item, SKU, barcode")
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
        .task {
            if viewModel.items.isEmpty {
                await viewModel.loadInventory(locationId: sessionManager.selectedStore?.id)
            }
        }
    }
}
