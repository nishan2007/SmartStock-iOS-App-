//
//  CustomerDetailView.swift
//  SmartStock
//

import SwiftUI
import Supabase

struct CustomerDetailView: View {
    @EnvironmentObject private var sessionManager: SessionManager

    let customer: CustomerAccount

    @State private var customerDetails: CustomerAccount
    @State private var isRefreshingCustomer = true
    @State private var isShowingEditSheet = false
    @State private var isUpdating = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var editName = ""
    @State private var editPhone = ""
    @State private var editEmail = ""
    @State private var editNotes = ""
    @State private var editAccountNumber = ""
    @State private var editCreditLimit = ""
    @State private var editIsActive = true
    @State private var editIsBusiness = false
    @State private var selectedSection: CustomerAccountDetailSection = .overview
    @State private var sales: [Sale] = []
    @State private var customOrders: [CustomOrder] = []
    @State private var payments: [CustomerPaymentHistoryEntry] = []
    @State private var transactions: [CustomerAccountTransactionEntry] = []
    @State private var outstandingItems: [CustomerOutstandingAccountItem] = []
    @State private var isLoadingActivity = true

    init(customer: CustomerAccount) {
        self.customer = customer
        _customerDetails = State(initialValue: customer)
    }

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            if let successMessage {
                Section {
                    Text(successMessage)
                        .foregroundStyle(.green)
                }
            }

            Section {
                Picker("Account Section", selection: $selectedSection) {
                    ForEach(CustomerAccountDetailSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
            }

            selectedAccountSections
        }
        .refreshable {
            await reloadCustomerData()
        }
        .navigationTitle(customerDetails.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canManageCustomers || canEditCustomerCreditLimit || canEditAccountNumber {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") {
                        prepareEditForm()
                        isShowingEditSheet = true
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingEditSheet) {
            NavigationStack {
                Form {
                    if canManageCustomers {
                        Section("Customer Details") {
                            TextField("Full name", text: $editName)
                            TextField("Phone", text: $editPhone)
                                .keyboardType(.phonePad)
                            TextField("Email", text: $editEmail)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                            TextField("Notes", text: $editNotes, axis: .vertical)
                                .lineLimit(3...6)
                            Toggle("Active", isOn: $editIsActive)
                            Toggle("Business", isOn: $editIsBusiness)
                        }
                    }

                    if canEditAccountNumber {
                        Section("Account Number") {
                            TextField("Account number", text: $editAccountNumber)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                        }
                    }

                    if canEditCustomerCreditLimit {
                        Section("Credit Limit") {
                            TextField("Credit limit", text: $editCreditLimit)
                                .keyboardType(.decimalPad)
                            Text("Current balance: \(customerDetails.balanceText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section {
                        Button {
                            Task {
                                await updateCustomer()
                            }
                        } label: {
                            if isUpdating {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Label("Save Changes", systemImage: "square.and.arrow.down")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .disabled(isUpdating || !canSaveEdits)
                    }
                }
                .navigationTitle("Edit Customer")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            isShowingEditSheet = false
                        }
                    }
                }
            }
        }
        .task {
            await reloadCustomerData()
        }
    }

    private var canManageCustomers: Bool {
        sessionManager.currentUser?.canAccess(.manageCustomers) == true
    }

    private var canEditCustomerCreditLimit: Bool {
        sessionManager.currentUser?.canAccess(.editCustomerCreditLimit) == true
    }

    private var canEditAccountNumber: Bool {
        sessionManager.currentUser?.canAccess(.editAccountNumber) == true
    }

    private var availableCredit: Double {
        (customerDetails.creditLimit ?? 0) - combinedCurrentBalance
    }

    private var accountLedgerBalance: Double {
        customerDetails.currentBalance ?? 0
    }

    private var customOrderBalanceDue: Double {
        let chargedCustomOrderIds = Set(
            transactions.compactMap { transaction -> Int64? in
                guard transaction.transactionType == "CUSTOM_ORDER_CREDIT" else { return nil }
                return transaction.customOrderId
            }
        )

        return customOrders.reduce(0) { total, order in
            guard order.paymentStatus != .paid, order.balanceDue > 0 else { return total }
            guard !chargedCustomOrderIds.contains(order.customOrderId) else { return total }
            return total + order.balanceDue
        }
    }

    private var combinedCurrentBalance: Double {
        accountLedgerBalance + customOrderBalanceDue
    }

    private var editTrimmedName: String {
        editName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSaveEdits: Bool {
        if canManageCustomers && editTrimmedName.isEmpty {
            return false
        }

        if canEditCustomerCreditLimit && parsedEditCreditLimit == nil {
            return false
        }

        return canManageCustomers || canEditCustomerCreditLimit || canEditAccountNumber
    }

    private var parsedEditCreditLimit: Double? {
        let trimmed = editCreditLimit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return Double(trimmed)
    }

    private var createdAtText: String? {
        guard let date = Sale.parseDate(customerDetails.createdAt) else { return nil }
        return Self.displayFormatter.string(from: date)
    }

    @ViewBuilder
    private var selectedAccountSections: some View {
        switch selectedSection {
        case .overview:
            overviewSections
        case .regularSales:
            regularSalesSections
        case .customOrders:
            customOrderSections
        case .payments:
            paymentSections
        case .transactions:
            transactionSections
        }
    }

    @ViewBuilder
    private var overviewSections: some View {
        Section("Customer Account") {
            if isRefreshingCustomer {
                loadingRow("Refreshing account...")
            }

            detailRow(title: "Account Number", value: customerDetails.accountNumberText)
            detailRow(title: "Customer Name", value: customerDetails.name)

            if let phone = nonEmpty(customerDetails.phone) {
                detailRow(title: "Phone", value: phone)
            }

            if let email = nonEmpty(customerDetails.email) {
                detailRow(title: "Email", value: email)
            }

            detailRow(title: "Current Balance", value: currency(combinedCurrentBalance))
            detailRow(title: "Account Ledger Balance", value: currency(accountLedgerBalance))
            detailRow(title: "Uncharged Custom Order Balance", value: currency(customOrderBalanceDue))
            detailRow(title: "Credit Limit", value: customerDetails.creditLimitText)
            detailRow(title: "Available Credit", value: currency(availableCredit))
            detailRow(title: "Status", value: customerDetails.isActive ? "Active" : "Inactive")
            detailRow(title: "Type", value: customerDetails.isBusiness ? "Business" : "Personal")

            if let createdAtText {
                detailRow(title: "Created", value: createdAtText)
            }

            if let notes = nonEmpty(customerDetails.accountNotes) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes")
                        .font(.subheadline.weight(.semibold))
                    Text(notes)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }

        Section("Summary") {
            LabeledContent("Regular Sales", value: "\(sales.count)")
            LabeledContent("Custom Orders", value: "\(customOrders.count)")
            LabeledContent("Payments", value: "\(payments.count)")
            LabeledContent("Transactions", value: "\(transactions.count)")
        }

        Section("Outstanding Account Items") {
            if isLoadingActivity {
                loadingRow("Loading account items...")
            } else if outstandingItems.isEmpty {
                ContentUnavailableView(
                    "No Outstanding Items",
                    systemImage: "checkmark.circle",
                    description: Text("Unpaid sales and custom orders will appear here.")
                )
            } else {
                ForEach(outstandingItems) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.title)
                                .font(.headline)
                            Spacer()
                            Text(currency(item.balanceDue))
                                .font(.headline)
                        }

                        HStack {
                            if let createdAt = formattedDate(item.createdAt) {
                                Text(createdAt)
                            }
                            Spacer()
                            Text("Total: \(item.totalText)")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }

        if canManageCustomers {
            Section("Account Actions") {
                NavigationLink {
                    CustomerPaymentView(customer: customerDetails) { newBalance in
                        customerDetails = CustomerAccount(
                            customerId: customerDetails.customerId,
                            accountNumber: customerDetails.accountNumber,
                            name: customerDetails.name,
                            phone: customerDetails.phone,
                            email: customerDetails.email,
                            creditLimit: customerDetails.creditLimit,
                            currentBalance: newBalance,
                            isActive: customerDetails.isActive,
                            isBusiness: customerDetails.isBusiness,
                            accountNotes: customerDetails.accountNotes,
                            customerTypeId: customerDetails.customerTypeId,
                            createdAt: customerDetails.createdAt
                        )
                        await reloadCustomerData()
                    }
                    .environmentObject(sessionManager)
                } label: {
                    Label("Record Payment", systemImage: "dollarsign.circle")
                }
            }
        }
    }

    @ViewBuilder
    private var regularSalesSections: some View {
        Section {
            LabeledContent("Sales", value: "\(sales.count)")
        }

        Section("Regular Sales") {
            if isLoadingActivity {
                loadingRow("Loading sales...")
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
                                Text("Sale \(sale.receiptNumberText)")
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

    @ViewBuilder
    private var customOrderSections: some View {
        Section {
            LabeledContent("Custom Orders", value: "\(customOrders.count)")
        }

        Section("Custom Orders") {
            if isLoadingActivity {
                loadingRow("Loading custom orders...")
            } else if customOrders.isEmpty {
                ContentUnavailableView(
                    "No Custom Orders",
                    systemImage: "list.clipboard",
                    description: Text("Custom orders linked to this customer will appear here.")
                )
            } else {
                ForEach(customOrders) { order in
                    NavigationLink {
                        CustomerCustomOrderDetailView(order: order)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(order.displayNumber)
                                        .font(.headline)
                                    Text("Status: \(order.status.title)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(order.totalText)
                                    .font(.headline)
                            }

                            HStack {
                                Text("Paid: \(currency(order.amountPaid))")
                                Spacer()
                                Text("Balance: \(order.balanceText)")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            HStack {
                                if let dueDate = formattedDate(order.dueDate) {
                                    Text("Due: \(dueDate)")
                                } else if let createdAt = formattedDate(order.createdAt) {
                                    Text("Created: \(createdAt)")
                                }
                                Spacer()
                                Text("Payment: \(order.paymentStatus.title)")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            if let paymentMethod = nonEmpty(order.paymentMethod) {
                                Text("Method: \(displayText(paymentMethod))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var paymentSections: some View {
        Section {
            LabeledContent("Payments", value: "\(payments.count)")
        }

        Section("Payments") {
            if isLoadingActivity {
                loadingRow("Loading payments...")
            } else if payments.isEmpty {
                ContentUnavailableView(
                    "No Payments Yet",
                    systemImage: "banknote",
                    description: Text("Recorded customer payments will appear here.")
                )
            } else {
                ForEach(payments) { payment in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(payment.paymentIdText)
                                    .font(.headline)

                                if let createdAt = formattedDate(payment.createdAt) {
                                    Text(createdAt)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Text(payment.paymentAmountText)
                                .font(.headline)
                        }

                        if let userName = nonEmpty(payment.userName) {
                            Text("By \(userName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(payment.customerAccountPaymentAllocations) { allocation in
                            HStack {
                                Text(allocation.sourceText)
                                Spacer()
                                Text(allocation.amountText)
                            }
                            .font(.subheadline)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    @ViewBuilder
    private var transactionSections: some View {
        Section {
            LabeledContent("Transactions", value: "\(transactions.count)")
        }

        Section("Transactions") {
            if isLoadingActivity {
                loadingRow("Loading transactions...")
            } else if transactions.isEmpty {
                ContentUnavailableView(
                    "No Transactions",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Account ledger entries will appear here.")
                )
            } else {
                ForEach(transactions) { transaction in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(transaction.displayType)
                                    .font(.headline)
                                Text(transaction.sourceText)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(transaction.amountText)
                                .font(.headline)
                        }

                        if let createdAt = formattedDate(transaction.createdAt) {
                            Text(createdAt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let userName = nonEmpty(transaction.userName) {
                            Text("By \(userName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let note = nonEmpty(transaction.note) {
                            Text(note)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func reloadCustomerData() async {
        async let customerRefresh: Void = refreshCustomerDetails()
        async let activityRefresh: Void = refreshAccountActivity()
        _ = await (customerRefresh, activityRefresh)
    }

    private func refreshCustomerDetails() async {
        isRefreshingCustomer = true
        defer { isRefreshingCustomer = false }

        do {
            customerDetails = try await CustomerAccountService.fetchCustomer(customerDetails.customerId)
        } catch {
            print("LOAD CUSTOMER DETAIL ERROR:", error)
            errorMessage = error.localizedDescription
        }
    }

    private func refreshAccountActivity() async {
        isLoadingActivity = true
        errorMessage = nil
        defer { isLoadingActivity = false }

        do {
            async let fetchedSales: [Sale] = supabase
                .from("sales")
                .select("sale_id, total_amount, status, transaction_source, created_at, payment_status, returned_amount, receipt_number, receipt_device_id, receipt_sequence, users(full_name), locations(name), customer_accounts(name)")
                .eq("customer_id", value: customerDetails.customerId)
                .order("sale_id", ascending: false)
                .execute()
                .value
            async let fetchedCustomOrders = CustomerAccountService.fetchCustomOrders(customerId: customerDetails.customerId)
            async let fetchedPayments = CustomerAccountService.fetchPaymentHistory(customerId: customerDetails.customerId)
            async let fetchedTransactions = CustomerAccountService.fetchTransactions(customerId: customerDetails.customerId)
            async let fetchedOutstandingItems = CustomerAccountService.fetchOutstandingAccountItems(customerId: customerDetails.customerId)

            sales = try await fetchedSales
            customOrders = try await fetchedCustomOrders
            payments = try await fetchedPayments
            transactions = try await fetchedTransactions
            outstandingItems = try await fetchedOutstandingItems
        } catch {
            print("LOAD CUSTOMER ACCOUNT ACTIVITY ERROR:", error)
            errorMessage = error.localizedDescription
        }
    }

    private func prepareEditForm() {
        editName = customerDetails.name
        editPhone = customerDetails.phone ?? ""
        editEmail = customerDetails.email ?? ""
        editNotes = customerDetails.accountNotes ?? ""
        editAccountNumber = customerDetails.accountNumber ?? ""
        editCreditLimit = customerDetails.creditLimit.map { String(format: "%.2f", $0) } ?? "0.00"
        editIsActive = customerDetails.isActive
        editIsBusiness = customerDetails.isBusiness
    }

    private func updateCustomer() async {
        if canManageCustomers && editTrimmedName.isEmpty {
            errorMessage = "Customer name is required."
            return
        }

        let creditLimit = parsedEditCreditLimit ?? (customerDetails.creditLimit ?? 0)

        if canEditCustomerCreditLimit && parsedEditCreditLimit == nil {
            errorMessage = "Enter a valid credit limit."
            return
        }

        isUpdating = true
        errorMessage = nil
        successMessage = nil
        defer { isUpdating = false }

        do {
            _ = try await supabase
                .from("customer_accounts")
                .update(
                    CustomerAccountUpdatePayload(
                        name: canManageCustomers ? editTrimmedName : customerDetails.name,
                        accountNumber: canEditAccountNumber ? normalizedValue(editAccountNumber) : customerDetails.accountNumber,
                        phone: canManageCustomers ? normalizedValue(editPhone) : customerDetails.phone,
                        email: canManageCustomers ? normalizedValue(editEmail) : customerDetails.email,
                        accountNotes: canManageCustomers ? normalizedValue(editNotes) : customerDetails.accountNotes,
                        creditLimit: creditLimit,
                        isActive: canManageCustomers ? editIsActive : customerDetails.isActive,
                        isBusiness: canManageCustomers ? editIsBusiness : customerDetails.isBusiness
                    )
                )
                .eq("customer_id", value: customerDetails.customerId)
                .execute()

            customerDetails = CustomerAccount(
                customerId: customerDetails.customerId,
                accountNumber: canEditAccountNumber ? normalizedValue(editAccountNumber) : customerDetails.accountNumber,
                name: canManageCustomers ? editTrimmedName : customerDetails.name,
                phone: canManageCustomers ? normalizedValue(editPhone) : customerDetails.phone,
                email: canManageCustomers ? normalizedValue(editEmail) : customerDetails.email,
                creditLimit: creditLimit,
                currentBalance: customerDetails.currentBalance,
                isActive: canManageCustomers ? editIsActive : customerDetails.isActive,
                isBusiness: canManageCustomers ? editIsBusiness : customerDetails.isBusiness,
                accountNotes: canManageCustomers ? normalizedValue(editNotes) : customerDetails.accountNotes,
                customerTypeId: customerDetails.customerTypeId,
                createdAt: customerDetails.createdAt
            )

            isShowingEditSheet = false
            successMessage = "Customer updated."
        } catch {
            print("UPDATE CUSTOMER ERROR:", error)
            errorMessage = error.localizedDescription
        }
    }

    private func normalizedValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func formattedDate(_ value: String?) -> String? {
        guard let date = Sale.parseDate(value) else { return nil }
        return Self.displayFormatter.string(from: date)
    }

    private func displayText(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func currency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    private func loadingRow(_ title: String) -> some View {
        HStack {
            Spacer()
            ProgressView(title)
            Spacer()
        }
    }

    @ViewBuilder
    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
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

private enum CustomerAccountDetailSection: String, CaseIterable, Identifiable {
    case overview
    case regularSales
    case customOrders
    case payments
    case transactions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return "Overview"
        case .regularSales:
            return "Sales"
        case .customOrders:
            return "Orders"
        case .payments:
            return "Payments"
        case .transactions:
            return "Ledger"
        }
    }
}

private struct CustomerAccountUpdatePayload: Encodable {
    let name: String
    let accountNumber: String?
    let phone: String?
    let email: String?
    let accountNotes: String?
    let creditLimit: Double
    let isActive: Bool
    let isBusiness: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case accountNumber = "account_number"
        case phone
        case email
        case accountNotes = "account_notes"
        case creditLimit = "credit_limit"
        case isActive = "is_active"
        case isBusiness = "is_business"
    }
}
