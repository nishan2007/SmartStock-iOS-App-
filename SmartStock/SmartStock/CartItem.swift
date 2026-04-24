//
//  CartItem.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/15/26.
//
import Foundation

struct CartItem: Identifiable {
    let id: UUID
    let product: Product
    var quantity: Int
    var unitPrice: Double
    var discountAmount: Double

    init(id: UUID = UUID(), product: Product, quantity: Int, unitPrice: Double? = nil, discountAmount: Double = 0) {
        self.id = id
        self.product = product
        self.quantity = quantity
        self.unitPrice = unitPrice ?? (product.price ?? 0)
        self.discountAmount = max(discountAmount, 0)
    }

    var subtotal: Double {
        unitPrice * Double(quantity)
    }

    var lineTotal: Double {
        max(subtotal - discountAmount, 0)
    }
}
