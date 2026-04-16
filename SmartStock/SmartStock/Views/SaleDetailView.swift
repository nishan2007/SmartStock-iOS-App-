//
//  SaleDetailView.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/15/26.
//

import SwiftUI
import Supabase

struct SaleDetailView: View {
    let sale: Sale

    @State private var items: [SaleItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("Transaction Info") {
                detailRow(title: "Sale ID", value: "#\(sale.sale_id)")
                detailRow(title: "Cashier", value: sale.cashierName)
                detailRow(title: "Store", value: sale.storeName)
                detailRow(title: "Source", value: sale.sourceText)
                detailRow(title: "Status", value: sale.status?.capitalized ?? "Unknown")
                detailRow(title: "Completed", value: completedAtText)
                detailRow(title: "Total", value: sale.totalText)
            }

            Section("Items") {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Loading items...")
                        Spacer()
                    }
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                } else if items.isEmpty {
                    Text("No sale items found.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.productName)
                                .font(.headline)

                            HStack {
                                Text("Qty: \(item.quantity)")
                                Spacer()
                                Text("Unit: \(item.unitPriceText)")
                                Spacer()
                                Text("Line: \(item.lineTotalText)")
                            }
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Sale Details")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadSaleItems()
        }
    }

    @ViewBuilder
    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private var completedAtText: String {
        if let date = extractCreatedAtDate() {
            return Self.displayFormatter.string(from: date)
        }
        return "Unavailable"
    }

    private func extractCreatedAtDate() -> Date? {
        let mirror = Mirror(reflecting: sale)

        for child in mirror.children {
            guard let label = child.label else { continue }
            let normalized = label.replacingOccurrences(of: "_", with: "").lowercased()

            guard normalized == "createdat" else { continue }

            if let date = child.value as? Date {
                return date
            }

            if let stringValue = child.value as? String,
               let parsed = Self.parseSaleDate(from: stringValue) {
                return parsed
            }

            let nestedMirror = Mirror(reflecting: child.value)
            if nestedMirror.displayStyle == .optional,
               let nestedChild = nestedMirror.children.first {
                if let date = nestedChild.value as? Date {
                    return date
                }
                if let stringValue = nestedChild.value as? String,
                   let parsed = Self.parseSaleDate(from: stringValue) {
                    return parsed
                }
            }
        }

        return nil
    }

    private static func parseSaleDate(from value: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = isoFormatter.date(from: value) {
            return date
        }

        let fallbackISOFormatter = ISO8601DateFormatter()
        fallbackISOFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        fallbackISOFormatter.formatOptions = [.withInternetDateTime]

        if let date = fallbackISOFormatter.date(from: value) {
            return date
        }

        for format in [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX",
            "yyyy-MM-dd HH:mm:ssXXXXX",
            "yyyy-MM-dd HH:mm:ss.SSSSSS",
            "yyyy-MM-dd HH:mm:ss"
        ] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format

            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private func loadSaleItems() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            items = try await supabase
                .from("sale_items")
                .select("sale_item_id, quantity, unit_price, products(name)")
                .eq("sale_id", value: sale.sale_id)
                .order("sale_item_id", ascending: true)
                .execute()
                .value
        } catch {
            errorMessage = error.localizedDescription
            print("LOAD SALE ITEMS ERROR:", error)
        }
    }
}
