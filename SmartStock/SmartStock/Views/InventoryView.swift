//
//  InventoryView.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/15/26.
//

import SwiftUI

struct InventoryView: View {
    @StateObject private var viewModel = InventoryViewModel()

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
                                        InventoryDetailView(item: item)
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
                        await viewModel.refresh()
                    }
                }
            }
            .navigationTitle("Inventory")
            .searchable(text: $viewModel.searchText, prompt: "Search by item, SKU, barcode, store...")
            .task {
                if viewModel.items.isEmpty {
                    await viewModel.loadInventory()
                }
            }
        }
    }

    private var summaryCards: some View {
        HStack(spacing: 12) {
            summaryCard(title: "Items", value: "\(viewModel.totalItemsCount)", systemImage: "shippingbox")
            summaryCard(title: "Low Stock", value: "\(viewModel.lowStockCount)", systemImage: "exclamationmark.circle")
            summaryCard(title: "Out", value: "\(viewModel.outOfStockCount)", systemImage: "xmark.circle")
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

    private func summaryCard(title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.headline)

            Text(value)
                .font(.title3.weight(.bold))

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
