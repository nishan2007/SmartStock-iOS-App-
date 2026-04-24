//
//  InventoryDetailView.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/15/26.
//

import SwiftUI

struct InventoryDetailView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    let item: InventoryItem
    var onSaved: () -> Void = {}
    @State private var isShowingEditor = false
    @State private var displayedItem: InventoryItem
    @State private var isLoadingCurrentStoreItem = false
    @State private var currentStoreErrorMessage: String?

    private let inventoryService = InventoryService()

    init(item: InventoryItem, onSaved: @escaping () -> Void = {}) {
        self.item = item
        self.onSaved = onSaved
        _displayedItem = State(initialValue: item)
    }

    private var canEditItem: Bool {
        sessionManager.currentUser?.canAccess(.editItem) == true
    }

    private var canViewCostPrice: Bool {
        sessionManager.currentUser?.canAccess(.viewCostPrice) == true
    }

    private var canViewVendor: Bool {
        sessionManager.currentUser?.canAccess(.viewVendor) == true
    }

    private var canViewCreatedBy: Bool {
        sessionManager.currentUser?.canAccess(.viewCreatedBy) == true
    }

    var body: some View {
        List {
            if let currentStoreErrorMessage {
                Section {
                    Text(currentStoreErrorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section {
                HStack(spacing: 16) {
                    productImage
                        .frame(width: 92, height: 92)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(displayedItem.name)
                            .font(.headline)
                        Text(displayedItem.sku)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        InventoryStatusBadge(status: displayedItem.status)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Product") {
                detailRow(label: "Product ID", value: "\(displayedItem.productId)")
                detailRow(label: "Name", value: displayedItem.name)
                detailRow(label: "SKU", value: displayedItem.sku)
                detailRow(label: "Barcode", value: displayedItem.barcode ?? "—")
                detailRow(label: "Type", value: displayedItem.productType.displayName)
                detailRow(label: "Category", value: displayedItem.categoryName ?? "—")
                if canViewVendor {
                    detailRow(label: "Vendor", value: displayedItem.vendorName ?? "—")
                }
                if canViewCreatedBy {
                    detailRow(label: "Created By", value: displayedItem.createdByName ?? "—")
                }
                detailRow(label: "Description", value: displayedItem.itemDescription ?? "—")
            }

            Section("Inventory") {
                if isLoadingCurrentStoreItem {
                    ProgressView("Loading current store inventory...")
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                detailRow(label: "Store", value: displayedItem.locationName)
                detailRow(label: "Quantity", value: displayedItem.quantityText)
                detailRow(label: "Reorder Level", value: displayedItem.reorderLevelText)
                detailRow(label: "Status", value: displayedItem.status.rawValue)
                if canViewCostPrice {
                    detailRow(label: "Cost Price", value: displayedItem.formattedCostPrice)
                }
                detailRow(label: "Selling Price", value: displayedItem.formattedPrice)
            }
        }
        .navigationTitle("Item Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canEditItem {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingEditor = true
                    } label: {
                        Image(systemName: "pencil.circle.fill")
                    }
                    .accessibilityLabel("Edit item")
                }
            }
        }
        .sheet(isPresented: $isShowingEditor) {
            InventoryItemFormView(mode: .edit(displayedItem), defaultStore: sessionManager.selectedStore) {
                onSaved()
            }
            .environmentObject(sessionManager)
        }
        .task {
            await loadCurrentStoreItemIfNeeded()
        }
    }

    @ViewBuilder
    private var productImage: some View {
        if let imageURL = item.imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    placeholderImage
                }
            }
        } else {
            placeholderImage
        }
    }

    private var placeholderImage: some View {
        ZStack {
            Color(.secondarySystemBackground)
            Image(systemName: "shippingbox.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }

    private func loadCurrentStoreItemIfNeeded() async {
        guard let selectedStore = sessionManager.selectedStore else { return }
        guard selectedStore.id != item.locationId else {
            displayedItem = item
            return
        }

        isLoadingCurrentStoreItem = true
        currentStoreErrorMessage = nil
        defer { isLoadingCurrentStoreItem = false }

        do {
            if let currentStoreItem = try await inventoryService.fetchInventoryItem(productId: item.productId, locationId: selectedStore.id) {
                displayedItem = currentStoreItem
            } else {
                currentStoreErrorMessage = "This item is not stocked at the current store."
            }
        } catch {
            currentStoreErrorMessage = error.localizedDescription
        }
    }
}
