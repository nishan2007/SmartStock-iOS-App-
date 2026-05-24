//
//  CustomerAccountService.swift
//  SmartStock
//

import Foundation
import Supabase

struct CustomerAccountTransactionSaleSummary: Decodable {
    let receiptNumber: String?
    let paymentStatus: String?
    let totalAmount: Double?
    let amountPaid: Double?
    let returnedAmount: Double?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case receiptNumber = "receipt_number"
        case paymentStatus = "payment_status"
        case totalAmount = "total_amount"
        case amountPaid = "amount_paid"
        case returnedAmount = "returned_amount"
        case createdAt = "created_at"
    }
}

struct CustomerAccountTransactionCustomOrderSummary: Decodable {
    let orderNumber: String?
    let totalAmount: Double?
    let amountPaid: Double?
    let balanceDue: Double?
    let paymentStatus: String?

    enum CodingKeys: String, CodingKey {
        case orderNumber = "order_number"
        case totalAmount = "total_amount"
        case amountPaid = "amount_paid"
        case balanceDue = "balance_due"
        case paymentStatus = "payment_status"
    }
}

struct CustomerAccountTransactionEntry: Decodable, Identifiable {
    let transactionId: Int
    let customerId: Int
    let saleId: Int?
    let customOrderId: Int64?
    let amount: Double
    let transactionType: String
    let note: String?
    let createdAt: String?
    let paymentId: String?
    let userName: String?
    let sales: CustomerAccountTransactionSaleSummary?
    let customOrders: CustomerAccountTransactionCustomOrderSummary?

    var id: Int { transactionId }

    var amountText: String {
        String(format: "$%.2f", amount)
    }

    var displayType: String {
        switch transactionType {
        case "SALE_CREDIT":
            return "Sale Credit"
        case "SALE_PAID":
            return "Sale Paid"
        case "MANUAL_CHARGE":
            return "Manual Charge"
        case "PAYMENT":
            return "Payment"
        default:
            return transactionType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var sourceText: String {
        if customOrderId != nil {
            let number = customOrders?.orderNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return "Custom Order \(number.isEmpty ? "#\(customOrderId ?? 0)" : number)"
        }

        if saleId != nil {
            let receipt = sales?.receiptNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return "Sale \(receipt.isEmpty ? "#\(saleId ?? 0)" : receipt)"
        }

        return "Account"
    }

    enum CodingKeys: String, CodingKey {
        case transactionId = "transaction_id"
        case customerId = "customer_id"
        case saleId = "sale_id"
        case customOrderId = "custom_order_id"
        case amount
        case transactionType = "transaction_type"
        case note
        case createdAt = "created_at"
        case paymentId = "payment_id"
        case userName = "user_name"
        case sales
        case customOrders = "custom_orders"
    }
}

struct CustomerPaymentAllocationSaleSummary: Decodable {
    let totalAmount: Double?
    let amountPaid: Double?
    let paymentStatus: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case totalAmount = "total_amount"
        case amountPaid = "amount_paid"
        case paymentStatus = "payment_status"
        case createdAt = "created_at"
    }
}

struct CustomerPaymentAllocation: Decodable, Identifiable {
    let allocationId: Int
    let saleId: Int?
    let customOrderId: Int64?
    let amount: Double
    let sales: CustomerPaymentAllocationSaleSummary?
    let customOrders: CustomerAccountTransactionCustomOrderSummary?

    var id: Int { allocationId }

    var amountText: String {
        String(format: "$%.2f", amount)
    }

    var sourceText: String {
        if let customOrderId {
            let number = customOrders?.orderNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return "Custom Order \(number.isEmpty ? "#\(customOrderId)" : number)"
        }

        if let saleId {
            return "Sale #\(saleId)"
        }

        return "Account"
    }

    enum CodingKeys: String, CodingKey {
        case allocationId = "allocation_id"
        case saleId = "sale_id"
        case customOrderId = "custom_order_id"
        case amount
        case sales
        case customOrders = "custom_orders"
    }
}

struct CustomerPaymentHistoryEntry: Decodable, Identifiable {
    let transactionId: Int
    let paymentId: String?
    let createdAt: String?
    let userName: String?
    let amount: Double
    let note: String?
    let customerAccountPaymentAllocations: [CustomerPaymentAllocation]

    var id: Int { transactionId }

    var paymentIdText: String {
        let trimmed = paymentId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? String(format: "PAY-%06d", transactionId) : trimmed
    }

    var paymentAmountText: String {
        String(format: "$%.2f", abs(amount))
    }

    var totalApplied: Double {
        customerAccountPaymentAllocations.reduce(0) { $0 + $1.amount }
    }

    enum CodingKeys: String, CodingKey {
        case transactionId = "transaction_id"
        case paymentId = "payment_id"
        case createdAt = "created_at"
        case userName = "user_name"
        case amount
        case note
        case customerAccountPaymentAllocations = "customer_account_payment_allocations"
    }
}

struct CustomerOutstandingSale: Decodable, Identifiable {
    let saleId: Int
    let totalAmount: Double?
    let amountPaid: Double?
    let returnedAmount: Double?
    let paymentStatus: String?
    let createdAt: String?

    var id: Int { saleId }

    var netTotal: Double {
        max((totalAmount ?? 0) - (returnedAmount ?? 0), 0)
    }

    var balanceDue: Double {
        max(netTotal - (amountPaid ?? 0), 0)
    }

    var balanceDueText: String {
        String(format: "$%.2f", balanceDue)
    }

    enum CodingKeys: String, CodingKey {
        case saleId = "sale_id"
        case totalAmount = "total_amount"
        case amountPaid = "amount_paid"
        case returnedAmount = "returned_amount"
        case paymentStatus = "payment_status"
        case createdAt = "created_at"
    }
}

struct CustomerOutstandingCustomOrder: Decodable, Identifiable {
    let customOrderId: Int64
    let orderNumber: String?
    let totalAmount: Double?
    let amountPaid: Double?
    let balanceDue: Double?
    let paymentStatus: String?
    let createdAt: String?

    var id: Int64 { customOrderId }

    var displayNumber: String {
        let trimmed = orderNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Custom #\(customOrderId)" : trimmed
    }

    var balanceDueText: String {
        String(format: "$%.2f", balanceDue ?? 0)
    }

    enum CodingKeys: String, CodingKey {
        case customOrderId = "custom_order_id"
        case orderNumber = "order_number"
        case totalAmount = "total_amount"
        case amountPaid = "amount_paid"
        case balanceDue = "balance_due"
        case paymentStatus = "payment_status"
        case createdAt = "created_at"
    }
}

enum CustomerOutstandingAccountItem: Identifiable {
    case sale(CustomerOutstandingSale)
    case customOrder(CustomerOutstandingCustomOrder)

    var id: String {
        switch self {
        case .sale(let sale):
            return "sale-\(sale.saleId)"
        case .customOrder(let order):
            return "custom-order-\(order.customOrderId)"
        }
    }

    var title: String {
        switch self {
        case .sale(let sale):
            return "Sale #\(sale.saleId)"
        case .customOrder(let order):
            return "Custom Order \(order.displayNumber)"
        }
    }

    var createdAt: String? {
        switch self {
        case .sale(let sale):
            return sale.createdAt
        case .customOrder(let order):
            return order.createdAt
        }
    }

    var balanceDue: Double {
        switch self {
        case .sale(let sale):
            return sale.balanceDue
        case .customOrder(let order):
            return max(order.balanceDue ?? 0, 0)
        }
    }

    var totalText: String {
        switch self {
        case .sale(let sale):
            return String(format: "$%.2f", sale.netTotal)
        case .customOrder(let order):
            return String(format: "$%.2f", order.totalAmount ?? 0)
        }
    }
}

struct RecordCustomerPaymentResult: Decodable {
    let paymentTransactionId: Int
    let paymentId: String
    let appliedNote: String
    let newBalance: Double

    enum CodingKeys: String, CodingKey {
        case paymentTransactionId = "payment_transaction_id"
        case paymentId = "payment_id"
        case appliedNote = "applied_note"
        case newBalance = "new_balance"
    }
}

struct RecordCustomerPaymentParams: Encodable {
    let target_customer_id: Int
    let target_amount: Double
    let target_note: String
    let target_user_name: String
    let target_location_id: Int
    let target_payment_method: String
    let target_payment_reference: String?
    let target_cash_drawer_id: Int64?
    let target_cash_drawer_name: String?
}

struct NewCustomerAccountTransaction: Encodable {
    let customer_id: Int
    let location_id: Int
    let sale_id: Int?
    let amount: Double
    let transaction_type: String
    let payment_method: String?
    let payment_reference: String?
    let cash_drawer_id: Int64?
    let cash_drawer_name: String?
    let note: String?
    let user_name: String
    let device_id: String?
    let device_name: String?
}

enum CustomerAccountService {
    static func fetchCustomers() async throws -> [CustomerAccount] {
        try await supabase
            .from("customer_accounts")
            .select("customer_id, account_number, name, phone, email, credit_limit, current_balance, is_active, is_business, account_notes, customer_type_id, created_at")
            .order("name", ascending: true)
            .execute()
            .value
    }

    static func createCustomer(_ customer: NewCustomerAccount) async throws {
        _ = try await supabase
            .from("customer_accounts")
            .insert(customer)
            .execute()
    }

    static func fetchCustomer(_ customerId: Int) async throws -> CustomerAccount {
        try await supabase
            .from("customer_accounts")
            .select("customer_id, account_number, name, phone, email, credit_limit, current_balance, is_active, is_business, account_notes, customer_type_id, created_at")
            .eq("customer_id", value: customerId)
            .single()
            .execute()
            .value
    }

    static func updateCustomer(customerId: Int, payload: CustomerAccountUpdatePayload) async throws {
        _ = try await supabase
            .from("customer_accounts")
            .update(payload)
            .eq("customer_id", value: customerId)
            .execute()
    }

    static func fetchSales(customerId: Int) async throws -> [Sale] {
        try await supabase
            .from("sales")
            .select("sale_id, total_amount, status, transaction_source, created_at, payment_status, returned_amount, receipt_number, receipt_device_id, receipt_sequence, users(full_name), locations(name), customer_accounts(name)")
            .eq("customer_id", value: customerId)
            .order("sale_id", ascending: false)
            .execute()
            .value
    }

    static func fetchTransactions(customerId: Int) async throws -> [CustomerAccountTransactionEntry] {
        try await supabase
            .from("customer_account_transactions")
            .select("transaction_id, customer_id, sale_id, custom_order_id, amount, transaction_type, note, created_at, payment_id, user_name, sales(receipt_number, payment_status, total_amount, amount_paid, returned_amount, created_at), custom_orders(order_number, total_amount, amount_paid, balance_due, payment_status)")
            .eq("customer_id", value: customerId)
            .order("created_at", ascending: false)
            .order("transaction_id", ascending: false)
            .execute()
            .value
    }

    static func fetchPaymentHistory(customerId: Int) async throws -> [CustomerPaymentHistoryEntry] {
        try await supabase
            .from("customer_account_transactions")
            .select("transaction_id, payment_id, created_at, user_name, amount, note, customer_account_payment_allocations(allocation_id, sale_id, custom_order_id, amount, sales(total_amount, amount_paid, payment_status, created_at), custom_orders(order_number, total_amount, amount_paid, balance_due, payment_status))")
            .eq("customer_id", value: customerId)
            .eq("transaction_type", value: "PAYMENT")
            .order("created_at", ascending: false)
            .order("transaction_id", ascending: false)
            .execute()
            .value
    }

    static func fetchOutstandingAccountSales(customerId: Int) async throws -> [CustomerOutstandingSale] {
        try await supabase
            .from("sales")
            .select("sale_id, total_amount, amount_paid, returned_amount, payment_status, created_at")
            .eq("customer_id", value: customerId)
            .eq("payment_method", value: "ACCOUNT")
            .neq("payment_status", value: "PAID")
            .order("created_at", ascending: true)
            .order("sale_id", ascending: true)
            .execute()
            .value
    }

    static func fetchCustomOrders(customerId: Int) async throws -> [CustomOrder] {
        try await supabase
            .from("custom_orders")
            .select("""
                custom_order_id,
                order_number,
                customer_id,
                customer_name,
                customer_phone,
                status,
                due_date,
                total_amount,
                amount_paid,
                balance_due,
                payment_method,
                payment_status,
                created_at
            """)
            .eq("customer_id", value: customerId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    static func fetchCustomOrderLines(customOrderId: Int64) async throws -> [CustomOrderLine] {
        try await supabase
            .from("custom_order_lines")
            .select("""
                custom_order_line_id,
                item_name,
                variant_name,
                pricing_type,
                unit_price,
                line_total,
                customization_details,
                order_instructions,
                print_material_name,
                print_size_name,
                print_charge,
                line_discount_amount,
                line_discount_percent
            """)
            .eq("custom_order_id", value: String(customOrderId))
            .order("sort_order", ascending: true)
            .execute()
            .value
    }

    static func fetchCustomOrderPayments(customOrderId: Int64) async throws -> [CustomOrderPayment] {
        try await supabase
            .from("custom_order_payments")
            .select("""
                custom_order_payment_id,
                payment_amount,
                payment_method,
                payment_reference,
                payment_action,
                taken_by_name,
                created_at
            """)
            .eq("custom_order_id", value: String(customOrderId))
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    static func fetchOutstandingCustomOrders(customerId: Int) async throws -> [CustomerOutstandingCustomOrder] {
        let rows: [CustomerOutstandingCustomOrder] = try await supabase
            .from("custom_orders")
            .select("custom_order_id, order_number, total_amount, amount_paid, balance_due, payment_status, created_at")
            .eq("customer_id", value: customerId)
            .neq("payment_status", value: "PAID")
            .gt("balance_due", value: 0)
            .order("created_at", ascending: true)
            .execute()
            .value

        return rows
    }

    static func fetchOutstandingAccountItems(customerId: Int) async throws -> [CustomerOutstandingAccountItem] {
        async let fetchedSales = fetchOutstandingAccountSales(customerId: customerId)
        async let fetchedCustomOrders = fetchOutstandingCustomOrders(customerId: customerId)

        let loadedSales = try await fetchedSales
        let loadedCustomOrders = try await fetchedCustomOrders
        let saleItems = loadedSales.map(CustomerOutstandingAccountItem.sale)
        let customOrderItems = loadedCustomOrders.map(CustomerOutstandingAccountItem.customOrder)

        return (saleItems + customOrderItems).sorted { first, second in
            let firstDate = Sale.parseDate(first.createdAt) ?? .distantPast
            let secondDate = Sale.parseDate(second.createdAt) ?? .distantPast
            return firstDate < secondDate
        }
    }

    static func recordPayment(
        customerId: Int,
        amount: Double,
        note: String?,
        userName: String,
        locationId: Int,
        paymentMethod: CustomOrderPaymentMethod,
        paymentReference: String?,
        cashDrawer: ResolvedCashDrawer?
    ) async throws -> RecordCustomerPaymentResult {
        let rows: [RecordCustomerPaymentResult] = try await supabase
            .rpc(
                "record_customer_account_payment",
                params: RecordCustomerPaymentParams(
                    target_customer_id: customerId,
                    target_amount: amount,
                    target_note: normalizedValue(note),
                    target_user_name: userName,
                    target_location_id: locationId,
                    target_payment_method: paymentMethod.rawValue,
                    target_payment_reference: normalizedValue(paymentReference).isEmpty ? nil : normalizedValue(paymentReference),
                    target_cash_drawer_id: cashDrawer?.drawerId,
                    target_cash_drawer_name: cashDrawer?.drawerName
                )
            )
            .execute()
            .value

        guard let result = rows.first else {
            throw NSError(domain: "CustomerAccountService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "The payment was recorded, but no result was returned."
            ])
        }

        return result
    }

    private static func normalizedValue(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed
    }
}
