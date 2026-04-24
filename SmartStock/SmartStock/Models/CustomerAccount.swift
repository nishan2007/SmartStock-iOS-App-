//
//  CustomerAccount.swift
//  SmartStock
//

import Foundation

struct CustomerAccount: Decodable, Identifiable {
    let customerId: Int
    let accountNumber: String?
    let name: String
    let phone: String?
    let email: String?
    let creditLimit: Double?
    let currentBalance: Double?
    let isActive: Bool
    let isBusiness: Bool
    let accountNotes: String?
    let customerTypeId: Int?
    let createdAt: String?

    var id: Int { customerId }

    init(
        customerId: Int,
        accountNumber: String?,
        name: String,
        phone: String?,
        email: String?,
        creditLimit: Double?,
        currentBalance: Double?,
        isActive: Bool,
        isBusiness: Bool,
        accountNotes: String?,
        customerTypeId: Int?,
        createdAt: String?
    ) {
        self.customerId = customerId
        self.accountNumber = accountNumber
        self.name = name
        self.phone = phone
        self.email = email
        self.creditLimit = creditLimit
        self.currentBalance = currentBalance
        self.isActive = isActive
        self.isBusiness = isBusiness
        self.accountNotes = accountNotes
        self.customerTypeId = customerTypeId
        self.createdAt = createdAt
    }

    var accountNumberText: String {
        let trimmed = accountNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "No account number" : trimmed
    }

    var balanceText: String {
        String(format: "$%.2f", currentBalance ?? 0)
    }

    var creditLimitText: String {
        String(format: "$%.2f", creditLimit ?? 0)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        customerId = try container.decodeFlexibleInt(forKey: .customerId)
        accountNumber = try container.decodeFlexibleStringIfPresent(forKey: .accountNumber)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unnamed Customer"
        phone = try container.decodeFlexibleStringIfPresent(forKey: .phone)
        email = try container.decodeFlexibleStringIfPresent(forKey: .email)
        creditLimit = try container.decodeFlexibleDoubleIfPresent(forKey: .creditLimit)
        currentBalance = try container.decodeFlexibleDoubleIfPresent(forKey: .currentBalance)
        isActive = try container.decodeFlexibleBoolIfPresent(forKey: .isActive) ?? true
        isBusiness = try container.decodeFlexibleBoolIfPresent(forKey: .isBusiness) ?? false
        accountNotes = try container.decodeFlexibleStringIfPresent(forKey: .accountNotes)
        customerTypeId = try container.decodeFlexibleIntIfPresent(forKey: .customerTypeId)
        createdAt = try container.decodeFlexibleStringIfPresent(forKey: .createdAt)
    }

    enum CodingKeys: String, CodingKey {
        case customerId = "customer_id"
        case accountNumber = "account_number"
        case name
        case phone
        case email
        case creditLimit = "credit_limit"
        case currentBalance = "current_balance"
        case isActive = "is_active"
        case isBusiness = "is_business"
        case accountNotes = "account_notes"
        case customerTypeId = "customer_type_id"
        case createdAt = "created_at"
    }
}

private extension KeyedDecodingContainer where Key: CodingKey {
    func decodeFlexibleStringIfPresent(forKey key: Key) throws -> String? {
        if let value = try decodeIfPresent(String.self, forKey: key) {
            return value
        }

        if let value = try decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }

        if let value = try decodeIfPresent(Int64.self, forKey: key) {
            return String(value)
        }

        if let value = try decodeIfPresent(Double.self, forKey: key) {
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(value)
        }

        if let value = try decodeIfPresent(Bool.self, forKey: key) {
            return value ? "true" : "false"
        }

        return nil
    }

    func decodeFlexibleInt(forKey key: Key) throws -> Int {
        if let value = try decodeIfPresent(Int.self, forKey: key) {
            return value
        }

        if let value = try decodeIfPresent(Int64.self, forKey: key) {
            return Int(value)
        }

        if let value = try decodeIfPresent(String.self, forKey: key),
           let intValue = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return intValue
        }

        throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Expected an integer-compatible value.")
    }

    func decodeFlexibleDoubleIfPresent(forKey key: Key) throws -> Double? {
        if let value = try decodeIfPresent(Double.self, forKey: key) {
            return value
        }

        if let value = try decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }

        if let value = try decodeIfPresent(String.self, forKey: key) {
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return nil
    }

    func decodeFlexibleIntIfPresent(forKey key: Key) throws -> Int? {
        if let value = try decodeIfPresent(Int.self, forKey: key) {
            return value
        }

        if let value = try decodeIfPresent(Int64.self, forKey: key) {
            return Int(value)
        }

        if let value = try decodeIfPresent(String.self, forKey: key) {
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return nil
    }

    func decodeFlexibleBoolIfPresent(forKey key: Key) throws -> Bool? {
        if let value = try decodeIfPresent(Bool.self, forKey: key) {
            return value
        }

        if let value = try decodeIfPresent(Int.self, forKey: key) {
            return value != 0
        }

        if let value = try decodeIfPresent(String.self, forKey: key) {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "t", "1", "yes", "y":
                return true
            case "false", "f", "0", "no", "n":
                return false
            default:
                return nil
            }
        }

        return nil
    }
}

struct NewCustomerAccount: Encodable {
    let name: String
    let phone: String?
    let email: String?
    let isActive: Bool
    let isBusiness: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case phone
        case email
        case isActive = "is_active"
        case isBusiness = "is_business"
    }
}

struct UpdateCustomerAccount: Encodable {
    let name: String
    let phone: String?
    let email: String?
    let isActive: Bool
    let isBusiness: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case phone
        case email
        case isActive = "is_active"
        case isBusiness = "is_business"
    }
}
