//
//  VendorItemsView.swift
//  SmartStock
//

import SwiftUI
import Supabase

struct VendorItemsView: View {
    @EnvironmentObject private var sessionManager: SessionManager

    let vendor: VendorAdminRow

    @State private var items: [VendorItemRow] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section {
                LabeledContent("Vendor", value: vendor.name)
                LabeledContent("Items", value: "\(items.count)")
            }

            Section("Items") {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Loading items...")
                        Spacer()
                    }
                } else if items.isEmpty {
                    ContentUnavailableView(
                        "No Items",
                        systemImage: "shippingbox",
                        description: Text("Items assigned to this vendor will appear here.")
                    )
                } else {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.displayName)
                                    .font(.headline)

                                Spacer()

                                if canViewCostPrice {
                                    Text(item.costPriceText)
                                        .font(.headline)
                                }
                            }

                            HStack(spacing: 12) {
                                Label(item.skuText, systemImage: "number")

                                if let barcodeText = item.barcodeText {
                                    Label(barcodeText, systemImage: "barcode")
                                }
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                            HStack {
                                Text(item.productTypeText)

                                Spacer()

                                if !canViewCostPrice {
                                    Text("Cost restricted")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(vendor.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadItems()
        }
        .refreshable {
            await loadItems()
        }
    }

    private var canViewCostPrice: Bool {
        sessionManager.currentUser?.canAccess(.vendorManagement) == true
            || sessionManager.currentUser?.canAccess(.viewCostPrice) == true
    }

    private func loadItems() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            items = try await supabase
                .from("products")
                .select("product_id, name, size, sku, barcode, cost_price, product_type")
                .eq("vendor_id", value: vendor.id)
                .order("name", ascending: true)
                .execute()
                .value
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct VendorItemRow: Decodable, Identifiable {
    let id: Int
    let name: String
    let size: String?
    let sku: String?
    let barcode: String?
    let costPrice: Decimal?
    let productType: String?

    enum CodingKeys: String, CodingKey {
        case id = "product_id"
        case name
        case size
        case sku
        case barcode
        case costPrice = "cost_price"
        case productType = "product_type"
    }

    var skuText: String {
        let trimmed = sku?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "No SKU" : trimmed
    }

    var displayName: String {
        displayProductName(name: name, size: size)
    }

    var barcodeText: String? {
        let trimmed = barcode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var costPriceText: String {
        guard let costPrice else { return "—" }
        return Self.currencyFormatter.string(from: costPrice as NSDecimalNumber) ?? "$0.00"
    }

    var productTypeText: String {
        let trimmed = productType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Unknown Type" : trimmed.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter
    }()
}
