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

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    productImage
                        .frame(width: 92, height: 92)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.name)
                            .font(.headline)
                        Text(item.sku)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        InventoryStatusBadge(status: item.status)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Product") {
                detailRow(label: "Product ID", value: "\(item.productId)")
                detailRow(label: "Name", value: item.name)
                detailRow(label: "SKU", value: item.sku)
                detailRow(label: "Barcode", value: item.barcode ?? "—")
                detailRow(label: "Type", value: item.productType.displayName)
                detailRow(label: "Category", value: item.categoryName ?? "—")
                detailRow(label: "Vendor", value: item.vendorName ?? "—")
                detailRow(label: "Description", value: item.itemDescription ?? "—")
            }

            Section("Inventory") {
                detailRow(label: "Store", value: item.locationName)
                detailRow(label: "Quantity", value: item.quantityText)
                detailRow(label: "Reorder Level", value: item.reorderLevelText)
                detailRow(label: "Status", value: item.status.rawValue)
                detailRow(label: "Cost Price", value: item.formattedCostPrice)
                detailRow(label: "Selling Price", value: item.formattedPrice)
            }
        }
        .navigationTitle("Item Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingEditor = true
                } label: {
                    Image(systemName: "pencil.circle.fill")
                }
                .accessibilityLabel("Edit item")
            }
        }
        .sheet(isPresented: $isShowingEditor) {
            InventoryItemFormView(mode: .edit(item), defaultStore: sessionManager.selectedStore) {
                onSaved()
            }
            .environmentObject(sessionManager)
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
}
