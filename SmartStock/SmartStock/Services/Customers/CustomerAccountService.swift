//
//  CustomerAccountService.swift
//  SmartStock
//

import Foundation
import Supabase

struct CustomerAccountTransactionSaleSummary: Decodable {
    let paymentStatus: String?
    let totalAmount: Double?
    let amountPaid: Double?
    let returnedAmount: Double?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case paymentStatus = "payment_status"
        case totalAmount = "total_amount"
        case amountPaid = "amount_paid"
        case returnedAmount = "returned_amount"
        case createdAt = "created_at"
    }
}

struct CustomerAccountTransactionEntry: Decodable, Identifiable {
    let transactionId: Int
    let customerId: Int
    let saleId: Int?
    let amount: Double
    let transactionType: String
    let note: String?
    let createdAt: String?
    let paymentId: String?
    let userName: String?
    let sales: CustomerAccountTransactionSaleSummary?

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

    enum CodingKeys: String, CodingKey {
        case transactionId = "transaction_id"
        case customerId = "customer_id"
        case saleId = "sale_id"
        case amount
        case transactionType = "transaction_type"
        case note
        case createdAt = "created_at"
        case paymentId = "payment_id"
        case userName = "user_name"
        case sales
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
    let saleId: Int
    let amount: Double
    let sales: CustomerPaymentAllocationSaleSummary?

    var id: Int { allocationId }

    var amountText: String {
        String(format: "$%.2f", amount)
    }

    enum CodingKeys: String, CodingKey {
        case allocationId = "allocation_id"
        case saleId = "sale_id"
        case amount
        case sales
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
}

struct NewCustomerAccountTransaction: Encodable {
    let customer_id: Int
    let location_id: Int
    let sale_id: Int?
    let amount: Double
    let transaction_type: String
    let note: String?
    let user_name: String
}

enum CustomerAccountService {
    static func fetchCustomer(_ customerId: Int) async throws -> CustomerAccount {
        try await supabase
            .from("customer_accounts")
            .select("customer_id, account_number, name, phone, email, credit_limit, current_balance, is_active, is_business, account_notes, customer_type_id, created_at")
            .eq("customer_id", value: customerId)
            .single()
            .execute()
            .value
    }

    static func fetchTransactions(customerId: Int) async throws -> [CustomerAccountTransactionEntry] {
        try await supabase
            .from("customer_account_transactions")
            .select("transaction_id, customer_id, sale_id, amount, transaction_type, note, created_at, payment_id, user_name, sales(payment_status, total_amount, amount_paid, returned_amount, created_at)")
            .eq("customer_id", value: customerId)
            .order("created_at", ascending: false)
            .order("transaction_id", ascending: false)
            .execute()
            .value
    }

    static func fetchPaymentHistory(customerId: Int) async throws -> [CustomerPaymentHistoryEntry] {
        try await supabase
            .from("customer_account_transactions")
            .select("transaction_id, payment_id, created_at, user_name, amount, note, customer_account_payment_allocations(allocation_id, sale_id, amount, sales(total_amount, amount_paid, payment_status, created_at))")
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

    static func recordPayment(
        customerId: Int,
        amount: Double,
        note: String?,
        userName: String,
        locationId: Int
    ) async throws -> RecordCustomerPaymentResult {
        let rows: [RecordCustomerPaymentResult] = try await supabase
            .rpc(
                "record_customer_account_payment",
                params: RecordCustomerPaymentParams(
                    target_customer_id: customerId,
                    target_amount: amount,
                    target_note: normalizedValue(note),
                    target_user_name: userName,
                    target_location_id: locationId
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
