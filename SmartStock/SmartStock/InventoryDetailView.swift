//
//  InventoryDetailView.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/15/26.
//

import SwiftUI

struct InventoryDetailView: View {
    let item: InventoryItem

    var body: some View {
        List {
            Section("Product") {
                detailRow(label: "Product ID", value: "\(item.productId)")
                detailRow(label: "Name", value: item.name)
                detailRow(label: "SKU", value: item.sku)
                detailRow(label: "Barcode", value: item.barcode ?? "—")
                detailRow(label: "Category", value: item.categoryName ?? "—")
                detailRow(label: "Description", value: item.itemDescription ?? "—")
            }

            Section("Inventory") {
                detailRow(label: "Store", value: item.locationName)
                detailRow(label: "Quantity", value: item.quantityText)
                detailRow(label: "Reorder Level", value: item.reorderLevelText)
                detailRow(label: "Status", value: item.status.rawValue)
                detailRow(label: "Selling Price", value: item.formattedPrice)
            }
        }
        .navigationTitle("Item Details")
        .navigationBarTitleDisplayMode(.inline)
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
