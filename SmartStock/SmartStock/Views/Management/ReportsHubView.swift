//
//  ReportsHubView.swift
//  SmartStock
//

import SwiftUI

struct ReportsHubView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    private let service = OperationsService()
    @State private var report: EndOfDayReport?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("Reports") {
                if !canViewReports {
                    Text("You do not have permission to view reports.")
                        .foregroundStyle(.secondary)
                } else if isLoading {
                    ProgressView("Loading report...")
                } else if let report {
                    LabeledContent("Transactions", value: "\(report.transactions)")
                    LabeledContent("Total Sales", value: currency(report.totalSales))
                    LabeledContent("Discounts", value: currency(report.discounts))
                    LabeledContent("Returns", value: currency(report.returns))
                    LabeledContent("Net Sales", value: currency(report.netSales))
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                } else {
                    Text("No report available.")
                        .foregroundStyle(.secondary)
                }

                if sessionManager.currentUser?.canAccess(.viewSales) == true {
                    NavigationLink {
                        ViewSalesView()
                    } label: {
                        Label("Previous Transactions", systemImage: "clock.arrow.circlepath")
                    }
                }
            }
        }
        .navigationTitle("Reports")
        .task {
            guard canViewReports else { return }
            await loadReport()
        }
        .refreshable {
            guard canViewReports else { return }
            await loadReport()
        }
    }

    private var canViewReports: Bool {
        sessionManager.currentUser?.canAccess(.viewReports) == true
    }

    private func loadReport() async {
        guard let store = sessionManager.selectedStore else { return }
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
}
