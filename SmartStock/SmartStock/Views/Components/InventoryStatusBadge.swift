//
//  LowStockCellRender.swift
//  SmartStock
//

//  Created by Nishan Narain on 4/15/26.
//

import SwiftUI

struct InventoryStatusBadge: View {
    let status: InventoryStockStatus

    var body: some View {
        Text(status.rawValue)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(backgroundColor)
            .clipShape(Capsule())
    }

    private var foregroundColor: Color {
        switch status {
        case .inStock:
            return .green
        case .lowStock:
            return .orange
        case .outOfStock:
            return .red
        case .negative:
            return .orange
        case .notTracked:
            return .blue
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .inStock:
            return Color.green.opacity(0.14)
        case .lowStock:
            return Color.yellow.opacity(0.22)
        case .outOfStock:
            return Color.red.opacity(0.14)
        case .negative:
            return Color.orange.opacity(0.18)
        case .notTracked:
            return Color.blue.opacity(0.14)
        }
    }
}
