//
//  EndOfDayView.swift
//  SmartStock
//

import SwiftUI

struct EndOfDayView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    private let service = OperationsService()

    @State private var countedCash = ""
    @State private var notes = ""
    @State private var report: EndOfDayReport?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Store") {
                Label(sessionManager.selectedStore?.name ?? "No store selected", systemImage: "storefront")
                Label(Date.now.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section("Cash Count") {
                TextField("Counted cash", text: $countedCash)
                    .keyboardType(.decimalPad)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)

                if let varianceText {
                    LabeledContent("Cash Variance", value: varianceText)
                }
            }

            Section("Summary") {
                if isLoading {
                    ProgressView("Loading report...")
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if let report {
                    metricRow("Transactions", "\(report.transactions)")
                    metricRow("Total Sales", currency(report.totalSales))
                    metricRow("Discounts", currency(report.discounts))
                    metricRow("Returns", currency(report.returns))
                    metricRow("Net Sales", currency(report.netSales))
                    metricRow("Paid", currency(report.paid))
                    metricRow("Unpaid", currency(report.unpaid))
                    metricRow("Cash", currency(report.cash))
                    metricRow("Card / Check", currency(report.card))
                    metricRow("Account", currency(report.account))
                } else {
                    Text("No report available.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Sales Today") {
                if let report, !report.sales.isEmpty {
                    ForEach(report.sales) { sale in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Sale #\(sale.sale_id)")
                                    .font(.headline)
                                Spacer()
                                Text(sale.totalAmountText)
                                    .font(.headline)
                            }

                            Text("\(sale.createdAtText) • \(sale.receiptText)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Text("\(sale.employeeText) • \(sale.deviceText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack {
                                Text(sale.payment_method ?? "Unknown Payment")
                                Spacer()
                                Text(sale.payment_status ?? "Unknown Status")
                                Spacer()
                                Text("Paid \(sale.amountPaidText)")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                } else if !isLoading {
                    Text("No sales found for today.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("End of Day")
        .refreshable {
            await loadReport()
        }
        .task {
            await loadReport()
        }
    }

    private var varianceText: String? {
        guard let report, let counted = Double(countedCash.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        let variance = counted - report.cash
        return currency(variance)
    }

    private func loadReport() async {
        guard let store = sessionManager.selectedStore else {
            errorMessage = "No store selected."
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            report = try await service.fetchEndOfDayReport(storeId: store.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func currency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    @ViewBuilder
    private func metricRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}
