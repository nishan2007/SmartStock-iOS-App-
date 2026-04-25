//
//  ViewSalesView.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/15/26.
//

import SwiftUI
import Supabase

struct ViewSalesView: View {
    private enum SalesPage: String, CaseIterable {
        case sales = "Sales"
        case returns = "Returns"
    }

    @EnvironmentObject var sessionManager: SessionManager

    @State private var selectedPage: SalesPage = .sales
    @State private var sales: [Sale] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Text("Sales")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)

                pageSelector
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 12)

            Divider()

            Group {
                if selectedPage == .sales {
                    salesContent
                } else {
                    ReturnHistoryView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transaction { transaction in
                transaction.animation = nil
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if selectedPage == .sales {
                await loadSales()
            }
        }
        .onAppear {
            if !availablePages.contains(selectedPage), let firstPage = availablePages.first {
                selectedPage = firstPage
            }
        }
        .onChange(of: selectedPage) { _, newPage in
            if newPage == .sales {
                Task {
                    await loadSales()
                }
            }
        }
    }

    private var canViewSales: Bool {
        sessionManager.currentUser?.canAccess(.viewSales) == true
    }

    private var canViewReturnHistory: Bool {
        sessionManager.currentUser?.canAccess(.viewSales) == true
    }

    private var availablePages: [SalesPage] {
        SalesPage.allCases.filter { page in
            switch page {
            case .sales:
                return canViewSales
            case .returns:
                return canViewReturnHistory
            }
        }
    }

    private var pageSelector: some View {
        GeometryReader { proxy in
            let pages = availablePages
            let selectedIndex = pages.firstIndex(of: selectedPage) ?? 0
            let segmentWidth = max((proxy.size.width - 12) / CGFloat(max(pages.count, 1)), 0)

            ZStack(alignment: .leading) {
                if !pages.isEmpty {
                    Capsule()
                        .fill(Color(.secondarySystemBackground))
                        .frame(width: segmentWidth, height: 34)
                        .offset(x: 6 + (segmentWidth * CGFloat(selectedIndex)))
                        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: selectedPage)
                }

                HStack(spacing: 0) {
                    ForEach(pages, id: \.self) { page in
                        Button {
                            selectedPage = page
                        } label: {
                            Text(page.rawValue)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(selectedPage == page ? Color.primary : .secondary)
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(6)
            .background(Color(.tertiarySystemBackground))
            .clipShape(Capsule())
        }
        .frame(height: 46)
    }

    private var salesContent: some View {
        Group {
                if isLoading {
                    ProgressView("Loading sales...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Text("Unable to load sales")
                            .font(.headline)
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                        Button("Try Again") {
                            Task {
                                await loadSales()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else if sales.isEmpty {
                    VStack(spacing: 12) {
                        Text("No sales found")
                            .font(.headline)
                        Text("Transactions for the selected store will appear here.")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    List(sales) { sale in
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

                                Text(formattedDate(for: sale))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                VStack(alignment: .leading, spacing: 4) {
                                    Label(sale.cashierName, systemImage: "person")

                                    HStack(spacing: 6) {
                                        Image(systemName: sale.sourceSystemImage)
                                            .accessibilityLabel(sale.sourceText)
                                        Text(sale.receiptNumberText)
                                    }
                                }
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                                HStack {
                                    Label(sale.storeName, systemImage: "storefront")

                                    Spacer()

                                    if sale.hasReturns {
                                        Text("Returned \(sale.returnedAmountText)")
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(.orange)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.orange.opacity(0.12))
                                            .clipShape(Capsule())
                                    }
                                }
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                                HStack {
                                    Text(sale.paymentMethodText)
                                    Spacer()
                                    Text(sale.itemCountText)
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .refreshable {
                        await loadSales()
                    }
                }
            }
    }

    private func loadSales() async {
        guard let store = sessionManager.selectedStore else {
            errorMessage = "No store selected."
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            sales = try await supabase
                .from("sales")
                .select("sale_id, total_amount, status, payment_method, transaction_source, created_at, payment_status, returned_amount, receipt_number, receipt_device_id, receipt_sequence, users(full_name), locations(name), customer_accounts(name), sale_items(quantity)")
                .eq("location_id", value: store.id)
                .order("sale_id", ascending: false)
                .execute()
                .value
        } catch {
            errorMessage = error.localizedDescription
            print("LOAD SALES ERROR:", error)
        }
    }
    private func formattedDate(for sale: Sale) -> String {
        if let date = extractCreatedAtDate(from: sale) {
            return Self.displayFormatter.string(from: date)
        }
        return "Unavailable"
    }

    private func extractCreatedAtDate(from sale: Sale) -> Date? {
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
}
