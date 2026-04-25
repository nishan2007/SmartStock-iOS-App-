//
//  ReturnHistoryView.swift
//  SmartStock
//

import SwiftUI
import Supabase

struct ReturnHistoryView: View {
    @EnvironmentObject private var sessionManager: SessionManager

    @State private var returns: [ReturnHistoryRow] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading returns...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Text("Unable to load returns")
                        .font(.headline)
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        Task {
                            await loadReturns()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if returns.isEmpty {
                VStack(spacing: 12) {
                    Text("No returns found")
                        .font(.headline)
                    Text("Returns for the selected store will appear here.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                List(returns) { returnRow in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Return #\(returnRow.returnId)")
                                .font(.headline)
                            Spacer()
                            Text(returnRow.refundAmountText)
                                .font(.headline)
                        }

                        Text(returnRow.createdAtText)
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        HStack(spacing: 12) {
                            Label(returnRow.userText, systemImage: "person")
                            Label(returnRow.storeName, systemImage: "storefront")
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                        HStack {
                            Text("Sale #\(returnRow.saleId)")
                            Spacer()
                            Text(returnRow.receiptText)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)

                        HStack {
                            Text(returnRow.refundMethodText)
                            Spacer()
                            Text("\(returnRow.itemCount) item\(returnRow.itemCount == 1 ? "" : "s")")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)

                        if let reason = returnRow.nonEmptyReason {
                            Text(reason)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .refreshable {
                    await loadReturns()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            await loadReturns()
        }
    }

    private func loadReturns() async {
        guard let store = sessionManager.selectedStore else {
            errorMessage = "No store selected."
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            returns = try await supabase
                .from("sale_returns")
                .select("return_id, sale_id, created_at, refund_method, refund_amount, reason, user_name, sales(receipt_number), locations(name), sale_return_items(quantity)")
                .eq("location_id", value: store.id)
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            errorMessage = error.localizedDescription
            print("LOAD RETURN HISTORY ERROR:", error)
        }
    }
}

private struct ReturnHistorySale: Decodable {
    let receiptNumber: String?

    enum CodingKeys: String, CodingKey {
        case receiptNumber = "receipt_number"
    }
}

private struct ReturnHistoryLocation: Decodable {
    let name: String?
}

private struct ReturnHistoryItem: Decodable {
    let quantity: Int?
}

private struct ReturnHistoryRow: Decodable, Identifiable {
    let returnId: Int64
    let saleId: Int
    let createdAt: String?
    let refundMethod: String?
    let refundAmount: Double?
    let reason: String?
    let userName: String?
    let sales: ReturnHistorySale?
    let locations: ReturnHistoryLocation?
    let saleReturnItems: [ReturnHistoryItem]

    var id: Int64 { returnId }

    var refundAmountText: String {
        String(format: "$%.2f", refundAmount ?? 0)
    }

    var createdAtText: String {
        guard let date = Sale.parseDate(createdAt) else { return "Unavailable" }
        return Self.displayFormatter.string(from: date)
    }

    var userText: String {
        let trimmed = userName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Unknown" : trimmed
    }

    var storeName: String {
        let trimmed = locations?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Unknown Store" : trimmed
    }

    var receiptText: String {
        let trimmed = sales?.receiptNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "No receipt" : trimmed
    }

    var refundMethodText: String {
        let trimmed = refundMethod?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Unknown Refund" : trimmed.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var itemCount: Int {
        saleReturnItems.reduce(0) { $0 + ($1.quantity ?? 0) }
    }

    var nonEmptyReason: String? {
        let trimmed = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    enum CodingKeys: String, CodingKey {
        case returnId = "return_id"
        case saleId = "sale_id"
        case createdAt = "created_at"
        case refundMethod = "refund_method"
        case refundAmount = "refund_amount"
        case reason
        case userName = "user_name"
        case sales
        case locations
        case saleReturnItems = "sale_return_items"
    }

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
