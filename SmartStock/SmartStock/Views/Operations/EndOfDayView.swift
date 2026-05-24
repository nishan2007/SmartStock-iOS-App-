//
//  EndOfDayView.swift
//  SmartStock
//

import SwiftUI

struct EndOfDayView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    private let service = OperationsService()
    
    @State private var notes = ""
    @State private var report: EndOfDayReport?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedDate = Date()
    @State private var drawers: [CashDrawer] = []
    @State private var selectedDrawerId: Int64?
    @State private var currentDrawer: ResolvedCashDrawer?
    
    // MARK: - Cash Drawer Data
    private let denomValues: [Double] = [5000, 2000, 1000, 500, 100, 50, 20]
    private let denomDisplays: [String] = ["$5,000", "$2,000", "$1,000", "$500", "$100", "$50", "$20"]
    
    @State private var countedQtys: [Int] = Array(repeating: 0, count: 7)
    
    @State private var showCashDrawerModal = false
    
    private let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        formatter.minimum = 0
        formatter.maximum = 999
        return formatter
    }()
    
    private var totalCounted: Double {
        zip(countedQtys, denomValues)
            .map { Double($0) * $1 }
            .reduce(0, +)
    }
    
    private var floatQtys: [Int] {
        var floats = Array(repeating: 0, count: countedQtys.count)
        var remaining = 20000.0
        
        let idx20 = 6
        let idx50 = 5
        let idx100 = 4
        let idx500 = 3
        
        // 1. $20 bills - floor to nearest multiple of 5
        if remaining > 0 {
            let counted20 = countedQtys[idx20]
            let maxByValue = Int(floor(remaining / 20))
            let maxTake = min(counted20, maxByValue)
            let float20 = (maxTake / 5) * 5
            floats[idx20] = float20
            remaining -= Double(float20) * 20.0
        }
        
        // 2. $50 bills - always 0 in FLOAT
        floats[idx50] = 0
        
        // 3. $100 bills - largest multiple of $500
        if remaining > 0 {
            let base20 = Double(floats[idx20]) * 20.0
            let max100Qty = countedQtys[idx100]
            let maxSubtotal = base20 + Double(max100Qty) * 100.0
            let targetSubtotal = floor(maxSubtotal / 500.0) * 500.0
            let neededFrom100 = targetSubtotal - base20
            var float100 = Int(neededFrom100 / 100.0)
            
            let maxByRemaining = Int(floor(remaining / 100))
            float100 = min(float100, maxByRemaining, max100Qty)
            
            floats[idx100] = float100
            remaining -= Double(float100) * 100.0
        }
        
        // 4. $500 bills - even/odd rule for nice $1,000 multiples
        if remaining > 0 {
            let counted500 = countedQtys[idx500]
            let currentFloatSoFar = 20000.0 - remaining
            let mod1000 = Int(currentFloatSoFar) % 1000
            
            let maxByValue = Int(floor(remaining / 500.0))
            let maxTake = min(counted500, maxByValue)
            
            var float500 = 0
            if mod1000 == 0 {
                float500 = (maxTake / 2) * 2
            } else if mod1000 == 500 {
                float500 = (maxTake % 2 == 1) ? maxTake : max(0, maxTake - 1)
            } else {
                float500 = maxTake
            }
            
            floats[idx500] = float500
            remaining -= Double(float500) * 500.0
        }
        
        // 5. Higher bills ($1,000 → $5,000) - greedy, smallest first
        for i in stride(from: 2, through: 0, by: -1) {
            if remaining <= 0 { break }
            let dValue = denomValues[i]
            let counted = countedQtys[i]
            let maxTake = Int(floor(remaining / dValue))
            let take = min(counted, maxTake)
            floats[i] = take
            remaining -= Double(take) * dValue
        }
        
        return floats
    }
    
    private var cihQtys: [Int] {
        zip(countedQtys, floatQtys).map { $0 - $1 }
    }
    
    private var totalFloat: Double {
        zip(floatQtys, denomValues)
            .map { Double($0) * $1 }
            .reduce(0, +)
    }
    
    private var totalCIH: Double {
        totalCounted - totalFloat
    }
    
    // MARK: - New Cash Variance Logic (exactly as requested)
    private var varianceInfo: (text: String, color: Color)? {
        guard let report else { return nil }
        let variance = report.cash - totalCIH   // positive = short, negative = extra
        
        if variance == 0 {
            return nil
        } else if variance > 0 {
            return ("Short \(currency(abs(variance)))", .red)
        } else {
            return ("Extra \(currency(abs(variance)))", .green)
        }
    }
    
    var body: some View {
        Form {
            Section("Store") {
                Label(sessionManager.selectedStore?.name ?? "No store selected", systemImage: "storefront")
                DatePicker("Business Day", selection: $selectedDate, displayedComponents: .date)
                dayPickerControls
                Label(selectedDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                LabeledContent("Current Drawer", value: currentDrawer?.drawerName ?? "No drawer assigned")
                Picker("Drawer Filter", selection: $selectedDrawerId) {
                    Text("All Drawers").tag(nil as Int64?)
                    ForEach(drawers.filter(\.isActive)) { drawer in
                        Text(drawer.displayName).tag(Optional(drawer.drawerId))
                    }
                }
            }
            
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            
            // MARK: - Cash Drawer SUMMARY (main screen)
            Section("Cash Drawer") {
                Button {
                    showCashDrawerModal = true
                } label: {
                    Label("Edit Cash Drawer", systemImage: "dollarsign.circle.fill")
                        .foregroundStyle(.blue)
                }
                
                LabeledContent("Cash in Hand (CIH)") {
                    Text(currency(totalCIH))
                        .foregroundStyle(.primary)
                }
                
                // Cash Variance only appears when there is a difference
                if let varianceInfo {
                    LabeledContent("Cash Variance", value: varianceInfo.text)
                        .foregroundStyle(varianceInfo.color)
                }
                
                // Notes only appears when there is short/extra
                if varianceInfo != nil {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
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
                    metricRow("Customer Payments", currency(report.customerPayments.reduce(0.0) { $0 + abs($1.amount ?? 0) }))
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

                            Text("Drawer: \(sale.drawerText)")
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
                    Text("No sales found for this day.")
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("Customer Payments Today") {
                if let report, !report.customerPayments.isEmpty {
                    ForEach(report.customerPayments) { payment in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(payment.paymentIdText)
                                    .font(.headline)
                                Spacer()
                                Text(payment.amountText)
                                    .font(.headline)
                            }
                            
                            Text(payment.customerName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            Text("\(payment.createdAtText) • \(payment.employeeText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("\(payment.paymentMethodText) • Drawer: \(payment.drawerText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                } else if !isLoading {
                    Text("No customer account payments found for this day.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("End of Day")
        .refreshable {
            await loadReport()
        }
        .task {
            await loadDrawerContext()
            await loadReport()
        }
        // MARK: - Cash Drawer Modal (unchanged - clean totals at bottom)
        .sheet(isPresented: $showCashDrawerModal) {
            NavigationStack {
                Form {
                    // Header
                    HStack {
                        Text("$$")
                            .font(.headline)
                            .frame(width: 80, alignment: .leading)
                        Text("QTY")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .center)
                        Text("FLOAT")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .foregroundStyle(.green)
                        Text("CIH")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    
                    // Data rows
                    ForEach(0..<denomValues.count, id: \.self) { index in
                        HStack(spacing: 8) {
                            Text(denomDisplays[index])
                                .frame(width: 80, alignment: .leading)
                                .font(.system(size: 15))
                            
                            TextField("0", value: $countedQtys[index], formatter: numberFormatter)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .textFieldStyle(.roundedBorder)
                            
                            Text("\(floatQtys[index])")
                                .frame(maxWidth: .infinity, alignment: .center)
                                .foregroundStyle(.green)
                                .font(.system(size: 15, weight: .medium))
                            
                            Text("\(cihQtys[index])")
                                .frame(maxWidth: .infinity, alignment: .center)
                                .font(.system(size: 15))
                        }
                        .padding(.vertical, 2)
                        .padding(.horizontal)
                    }
                    
                    // Totals row at the bottom
                    HStack {
                        Text("TOTAL")
                            .frame(width: 80, alignment: .leading)
                            .font(.headline)
                        
                        Text(currency(totalCounted))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .font(.system(size: 15, weight: .semibold))
                        
                        Text(currency(totalFloat))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.green)
                        
                        Text(currency(totalCIH))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .padding(.horizontal)
                }
                .navigationTitle("Cash Drawer")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showCashDrawerModal = false
                        }
                    }
                }
            }
        }
        .onAppear {
            loadCashData()
        }
        .onDisappear {
            saveCashData()
        }
        .onChange(of: countedQtys) { _, _ in
            saveCashData()
        }
        .onChange(of: notes) { _, _ in
            saveCashData()
        }
        .onChange(of: selectedDate) { _, _ in
            Task { await loadReport() }
        }
        .onChange(of: selectedDrawerId) { _, _ in
            Task { await loadReport() }
        }
    }
    
    // MARK: - Persistence (now includes notes)
    private func saveCashData() {
        UserDefaults.standard.set(countedQtys, forKey: "endOfDayCountedQtys")
        UserDefaults.standard.set(notes, forKey: "endOfDayNotes")
    }
    
    private func loadCashData() {
        if let saved = UserDefaults.standard.array(forKey: "endOfDayCountedQtys") as? [Int],
           saved.count == 7 {
            countedQtys = saved
        }
        if let savedNotes = UserDefaults.standard.string(forKey: "endOfDayNotes") {
            notes = savedNotes
        }
    }

    private var dayPickerControls: some View {
        HStack {
            Button {
                moveSelectedDate(by: -1)
            } label: {
                Label("Previous Day", systemImage: "chevron.left")
            }
            .labelStyle(.iconOnly)

            Spacer()

            Button("Yesterday") {
                selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
            }

            Button("Today") {
                selectedDate = Date()
            }

            Spacer()

            Button {
                moveSelectedDate(by: 1)
            } label: {
                Label("Next Day", systemImage: "chevron.right")
            }
            .labelStyle(.iconOnly)
        }
    }

    private func moveSelectedDate(by days: Int) {
        selectedDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) ?? selectedDate
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
            report = try await service.fetchEndOfDayReport(storeId: store.id, cashDrawerId: selectedDrawerId, for: selectedDate)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadDrawerContext() async {
        guard let store = sessionManager.selectedStore else {
            drawers = []
            currentDrawer = nil
            selectedDrawerId = nil
            return
        }

        do {
            async let loadedDrawers = CashDrawerService().fetchDrawers(storeId: store.id, includeInactive: false)
            async let loadedCurrent = try? CashDrawerService().resolveAssignedDrawer(storeId: store.id, deviceId: sessionManager.currentDevice?.id)
            drawers = try await loadedDrawers
            currentDrawer = await loadedCurrent
            if let selectedDrawerId, !drawers.contains(where: { $0.drawerId == selectedDrawerId }) {
                self.selectedDrawerId = nil
            }
        } catch {
            drawers = []
            currentDrawer = nil
        }
    }
    
    // Whole dollars only (no decimals) - fits perfectly in all columns
    private func currency(_ value: Double) -> String {
        String(format: "$%.0f", value)
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
