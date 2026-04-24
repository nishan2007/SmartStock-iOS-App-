//
//  CustomersView.swift
//  SmartStock
//

import SwiftUI
import Supabase

struct CustomersView: View {
    @EnvironmentObject private var sessionManager: SessionManager

    @State private var searchText = ""
    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var isShowingNewCustomerForm = false
    @State private var customers: [CustomerAccount] = []
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

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
                LabeledContent("Customers", value: "\(filteredCustomers.count)")
                    .font(.subheadline.weight(.medium))

                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    LabeledContent("Results", value: "\(customers.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Customer List") {
                if isLoading && customers.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView("Loading customers...")
                        Spacer()
                    }
                } else if filteredCustomers.isEmpty {
                    ContentUnavailableView(
                        customers.isEmpty ? "No Customers Found" : "No Matching Customers",
                        systemImage: "person.2",
                        description: Text(customers.isEmpty
                                          ? "Customer accounts from the database will appear here."
                                          : "Try a different search term.")
                    )
                } else {
                    ForEach(filteredCustomers) { customer in
                        NavigationLink {
                            CustomerDetailView(customer: customer)
                                .environmentObject(sessionManager)
                        } label: {
                            customerRow(customer)
                        }
                    }
                }
            }

            if canManageCustomers {
                Section {
                    DisclosureGroup(isShowingNewCustomerForm ? "Hide New Customer Form" : "Add New Customer",
                                    isExpanded: $isShowingNewCustomerForm) {
                        TextField("Full name", text: $name)
                        TextField("Phone", text: $phone)
                            .keyboardType(.phonePad)
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)

                        Button {
                            Task {
                                await saveCustomer()
                            }
                        } label: {
                            if isSaving {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Label("Save Customer", systemImage: "person.crop.circle.badge.plus")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .disabled(isSaving || trimmedName.isEmpty)
                    }
                }
            }
        }
        .navigationTitle("Customers")
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search customers")
        .task {
            await loadCustomers()
        }
        .refreshable {
            await loadCustomers()
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canManageCustomers: Bool {
        sessionManager.currentUser?.canAccess(.manageCustomers) == true
    }

    private var filteredCustomers: [CustomerAccount] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !query.isEmpty else { return customers }

        return customers.filter { customer in
            customer.name.lowercased().contains(query)
            || customer.accountNumberText.lowercased().contains(query)
            || (customer.phone?.lowercased().contains(query) ?? false)
            || (customer.email?.lowercased().contains(query) ?? false)
        }
    }

    private func loadCustomers() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            customers = try await supabase
                .from("customer_accounts")
                .select("customer_id, account_number, name, phone, email, credit_limit, current_balance, is_active, is_business, account_notes, customer_type_id, created_at")
                .order("name", ascending: true)
                .execute()
                .value
        } catch {
            print("LOAD CUSTOMERS ERROR:", error)
            errorMessage = error.localizedDescription
        }
    }

    private func saveCustomer() async {
        let trimmedPhone = normalizedValue(phone)
        let trimmedEmail = normalizedValue(email)

        guard !trimmedName.isEmpty else {
            errorMessage = "Customer name is required."
            return
        }

        isSaving = true
        errorMessage = nil
        successMessage = nil
        defer { isSaving = false }

        do {
            _ = try await supabase
                .from("customer_accounts")
                .insert(
                    NewCustomerAccount(
                        name: trimmedName,
                        phone: trimmedPhone,
                        email: trimmedEmail,
                        isActive: true,
                        isBusiness: false
                    )
                )
                .execute()

            name = ""
            phone = ""
            email = ""
            isShowingNewCustomerForm = false
            successMessage = "Customer saved."
            await loadCustomers()
        } catch {
            print("SAVE CUSTOMER ERROR:", error)
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

    private func statusBadge(title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func customerRow(_ customer: CustomerAccount) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(customer.name)
                    .font(.headline)

                if !customer.isActive {
                    statusBadge(title: "Inactive", color: .red)
                } else if customer.isBusiness {
                    statusBadge(title: "Business", color: .blue)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            Text(customer.accountNumberText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let phone = nonEmpty(customer.phone) {
                Text(phone)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let email = nonEmpty(customer.email) {
                Text(email)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Balance: \(customer.balanceText)")
                Spacer()
                Text("Limit: \(customer.creditLimitText)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
