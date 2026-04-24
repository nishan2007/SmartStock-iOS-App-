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
    @State private var sales: [Sale] = []
    @State private var isLoadingSales = true
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

            Section("Customer Info") {
                detailRow(title: "Name", value: customerDetails.name)
                detailRow(title: "Account Number", value: customerDetails.accountNumberText)

                if let phone = nonEmpty(customerDetails.phone) {
                    detailRow(title: "Phone", value: phone)
                }

                if let email = nonEmpty(customerDetails.email) {
                    detailRow(title: "Email", value: email)
                }

                detailRow(title: "Balance", value: customerDetails.balanceText)
                detailRow(title: "Credit Limit", value: customerDetails.creditLimitText)
                detailRow(title: "Status", value: customerDetails.isActive ? "Active" : "Inactive")
                detailRow(title: "Type", value: customerDetails.isBusiness ? "Business" : "Personal")

                if let createdAtText = createdAtText {
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

            Section("Transaction History") {
                if isLoadingSales {
                    HStack {
                        Spacer()
                        ProgressView("Loading history...")
                        Spacer()
                    }
                } else if sales.isEmpty {
                    ContentUnavailableView(
                        "No Transactions Yet",
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
            await loadSales()
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

    private func loadSales() async {
        isLoadingSales = true
        errorMessage = nil
        defer { isLoadingSales = false }

        do {
            sales = try await supabase
                .from("sales")
                .select("sale_id, total_amount, status, transaction_source, created_at, payment_status, returned_amount, receipt_number, receipt_device_id, receipt_sequence, users(full_name), locations(name), customer_accounts(name)")
                .eq("customer_id", value: customerDetails.customerId)
                .order("sale_id", ascending: false)
                .execute()
                .value
        } catch {
            print("LOAD CUSTOMER SALES ERROR:", error)
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
