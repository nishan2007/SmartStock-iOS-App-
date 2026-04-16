//
//  InventoryRowView.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/15/26.
//

import SwiftUI

struct InventoryRowView: View {
    let item: InventoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("SKU: \(item.sku)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Text("ID: \(item.productId)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let categoryName = item.categoryName, !categoryName.isEmpty {
                            Text(categoryName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer(minLength: 8)
                InventoryStatusBadge(status: item.status)
            }

            HStack {
                metricView(title: "Qty", value: item.quantityText)
                Spacer()
                metricView(title: "Reorder", value: item.reorderLevelText)
                Spacer()
                metricView(title: "Price", value: item.formattedPrice)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.locationName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                if let description = item.itemDescription, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(borderColor.opacity(0.35), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func metricView(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }

    private var rowBackground: Color {
        switch item.status {
        case .inStock:
            return Color(.secondarySystemBackground)
        case .lowStock:
            return Color.yellow.opacity(0.14)
        case .outOfStock:
            return Color.red.opacity(0.10)
        case .negative:
            return Color.orange.opacity(0.14)
        }
    }

    private var borderColor: Color {
        switch item.status {
        case .inStock:
            return .gray
        case .lowStock:
            return .yellow
        case .outOfStock:
            return .red
        case .negative:
            return .orange
        }
    }
}
