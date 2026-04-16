//
//  CartItem.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/15/26.
//
import Foundation

struct CartItem: Identifiable {
    let id = UUID()
    let product: Product
    var quantity: Int

    var lineTotal: Double {
        (product.price ?? 0) * Double(quantity)
    }
}
