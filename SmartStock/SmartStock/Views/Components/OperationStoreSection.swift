//
//  OperationStoreSection.swift
//  SmartStock
//

import SwiftUI

struct OperationStoreSection: View {
    let title: String
    let storeName: String?

    init(title: String = "Store", storeName: String?) {
        self.title = title
        self.storeName = storeName
    }

    var body: some View {
        Section(title) {
            Label(storeName ?? "No store selected", systemImage: "storefront")
        }
    }
}
