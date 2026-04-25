//
//  CustomerSalesHistoryView.swift
//  SmartStock
//

import SwiftUI
import Supabase

struct CustomerSalesHistoryView: View {
    let customer: CustomerAccount

    @State private var sales: [Sale] = []
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
                LabeledContent("Sales", value: "\(sales.count)")
            }

            Section("Sales History") {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Loading sales...")
                        Spacer()
                    }
                } else if sales.isEmpty {
                    ContentUnavailableView(
                        "No Sales Yet",
                        systemImage: "receipt",
                        description: Text("Sales for this customer will appear here.")
                    )
                } else {
                    ForEach(sales) { sale in
                        NavigationLink {
                            SaleDetailView(sale: sale)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Sale #\(sale.sale_id)")
                                        .font(.headline)
                                    Spacer()
                                    Text(sale.totalText)
                                        .font(.headline)
                                }

                                Text(sale.createdAtText)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                HStack {
                                    Text(sale.storeName)
                                    Spacer()
                                    Text(sale.paymentStatusText)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle("Sales History")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadSales()
        }
        .refreshable {
            await loadSales()
        }
    }

    private func loadSales() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            sales = try await supabase
                .from("sales")
                .select("sale_id, total_amount, status, transaction_source, created_at, payment_status, returned_amount, receipt_number, receipt_device_id, receipt_sequence, users(full_name), locations(name), customer_accounts(name)")
                .eq("customer_id", value: customer.customerId)
                .order("sale_id", ascending: false)
                .execute()
                .value
        } catch {
            print("LOAD CUSTOMER SALES ERROR:", error)
            errorMessage = error.localizedDescription
        }
    }
}
