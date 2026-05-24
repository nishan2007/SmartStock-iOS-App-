//
//  CustomerOutstandingItemDetailView.swift
//  SmartStock
//

import SwiftUI

struct CustomerOutstandingItemDetailView: View {
    let item: CustomerOutstandingAccountItem

    var body: some View {
        List {
            Section("Outstanding Item") {
                detailRow("Type", typeText)
                detailRow("Reference", item.title)
                detailRow("Balance Due", currency(item.balanceDue))
                detailRow("Total", item.totalText)

                if let createdAt = formattedDate(item.createdAt) {
                    detailRow("Created", createdAt)
                }
            }
        }
        .navigationTitle(typeText)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var typeText: String {
        switch item {
        case .sale:
            return "Sale"
        case .customOrder:
            return "Custom Order"
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func formattedDate(_ value: String?) -> String? {
        guard let date = Sale.parseDate(value) else { return nil }
        return Self.dateFormatter.string(from: date)
    }

    private func currency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
