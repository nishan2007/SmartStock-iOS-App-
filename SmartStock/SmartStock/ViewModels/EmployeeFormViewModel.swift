//
//  EmployeeFormViewModel.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/16/26.
//

//
//  EmployeeFormViewModel.swift
//  SmartStock
//

import Foundation
import Combine

@MainActor
final class EmployeeFormViewModel: ObservableObject {
    @Published var username = "" {
        didSet {
            guard !isApplyingGeneratedUsername else { return }
            hasCustomUsername = username.trimmingCharacters(in: .whitespacesAndNewlines) != lastGeneratedUsername
        }
    }
    @Published var firstName = "" {
        didSet {
            updateGeneratedUsernameIfNeeded()
        }
    }
    @Published var middleName = ""
    @Published var lastName = "" {
        didSet {
            updateGeneratedUsernameIfNeeded()
        }
    }
    @Published var email = ""
    @Published var phone = ""
    @Published var badgeId = ""
    @Published var compensationType = ""
    @Published var salaryText = ""
    @Published var password = ""
    @Published var selectedRoleId: Int?
    @Published var isActive = true
    @Published var selectedStoreIds: Set<Int> = []

    @Published var roles: [Role] = []
    @Published var stores: [Store] = []

    @Published var isSaving = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var missingRequiredFields: Set<EmployeeFormRequiredField> = []

    let employee: Employee?
    private var hasCustomUsername = false
    private var isApplyingGeneratedUsername = false
    private var lastGeneratedUsername = ""

    init(employee: Employee? = nil) {
        self.employee = employee

        if let employee {
            username = employee.username
            firstName = employee.firstName ?? inferredNameParts(from: employee.fullName).first
            middleName = employee.middleName ?? inferredNameParts(from: employee.fullName).middle
            lastName = employee.lastName ?? inferredNameParts(from: employee.fullName).last
            email = employee.email ?? ""
            phone = employee.phone ?? ""
            badgeId = employee.badgeId ?? ""
            compensationType = employee.compensationType ?? ""
            salaryText = employee.salary.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
            selectedRoleId = employee.roleId
            isActive = employee.isActive
            selectedStoreIds = Set(employee.assignedStores.map(\.id))
            hasCustomUsername = true
        } else {
            updateGeneratedUsernameIfNeeded()
        }
    }

    var isEditing: Bool {
        employee != nil
    }

    func loadDependencies() async {
        isLoading = true
        errorMessage = nil

        do {
            async let rolesTask = RoleService.shared.fetchRoles()
            async let storesTask = StoreService.shared.fetchStores()

            roles = try await rolesTask
            stores = try await storesTask

            if selectedRoleId == nil {
                selectedRoleId = roles.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func save() async -> Bool {
        errorMessage = nil
        missingRequiredFields = []

        let trimmedFirstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMiddleName = middleName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCompensationType = compensationType.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSalary = salaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedFirstName.isEmpty {
            missingRequiredFields.insert(.firstName)
        }

        if trimmedLastName.isEmpty {
            missingRequiredFields.insert(.lastName)
        }

        if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missingRequiredFields.insert(.email)
        }

        if trimmedPhone.isEmpty {
            missingRequiredFields.insert(.phone)
        }

        if trimmedCompensationType.isEmpty {
            missingRequiredFields.insert(.compensationType)
        }

        if trimmedSalary.isEmpty {
            missingRequiredFields.insert(.salary)
        }

        if selectedRoleId == nil {
            missingRequiredFields.insert(.role)
        }

        if !isEditing && trimmedPassword.isEmpty {
            missingRequiredFields.insert(.password)
        }

        if !missingRequiredFields.isEmpty {
            errorMessage = "Fill in the required fields highlighted below."
            return false
        }

        let finalUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? generatedUsername(firstName: trimmedFirstName, lastName: trimmedLastName)
            : username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalUsername.isEmpty else {
            errorMessage = "Enter first and last name, or set a username manually."
            return false
        }

        let finalFullName = composedFullName(
            firstName: trimmedFirstName,
            middleName: trimmedMiddleName,
            lastName: trimmedLastName
        )

        guard let selectedRoleId else { return false }

        let salary: Decimal?
        if let parsedSalary = Decimal(string: trimmedSalary) {
            salary = parsedSalary
        } else {
            errorMessage = "Salary must be a valid number."
            return false
        }

        isSaving = true

        do {
            if let employee {
                try await EmployeeService.shared.updateEmployee(
                    employee: employee,
                    username: finalUsername,
                    firstName: trimmedFirstName,
                    middleName: trimmedMiddleName,
                    lastName: trimmedLastName,
                    fullName: finalFullName,
                    email: email,
                    phone: phone,
                    badgeId: badgeId,
                    compensationType: compensationType,
                    salary: salary,
                    password: password,
                    roleId: selectedRoleId,
                    isActive: isActive
                )

                try await EmployeeService.shared.updateEmployeeStores(
                    employeeId: employee.id,
                    storeIds: Array(selectedStoreIds)
                )
            } else {
                try await EmployeeService.shared.createEmployee(
                    username: finalUsername,
                    firstName: trimmedFirstName,
                    middleName: trimmedMiddleName,
                    lastName: trimmedLastName,
                    fullName: finalFullName,
                    email: email,
                    phone: phone,
                    badgeId: badgeId,
                    compensationType: compensationType,
                    salary: salary,
                    password: password,
                    roleId: selectedRoleId,
                    isActive: isActive,
                    storeIds: Array(selectedStoreIds)
                )
            }

            isSaving = false
            return true
        } catch {
            errorMessage = friendlyMessage(for: error)
            isSaving = false
            return false
        }
    }

    private func friendlyMessage(for error: Error) -> String {
        let message = error.localizedDescription
        let lowercasedMessage = message.lowercased()

        if lowercasedMessage.contains("users_badge_id_unique_idx")
            || lowercasedMessage.contains("badge_id")
                && (lowercasedMessage.contains("duplicate") || lowercasedMessage.contains("unique")) {
            return "That badge ID is already assigned to another employee."
        }

        return message
    }

    private func updateGeneratedUsernameIfNeeded() {
        guard !isEditing else { return }

        let generated = generatedUsername(firstName: firstName, lastName: lastName)
        lastGeneratedUsername = generated

        guard !hasCustomUsername else { return }

        isApplyingGeneratedUsername = true
        username = generated
        isApplyingGeneratedUsername = false
    }

    private func generatedUsername(firstName: String, lastName: String) -> String {
        let trimmedFirstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let firstInitial = trimmedFirstName.first else {
            return ""
        }

        let cleanedLastName = cleanedUsernamePart(trimmedLastName)
        guard !cleanedLastName.isEmpty else { return "" }

        return "\(String(firstInitial).uppercased())-\(cleanedLastName)"
    }

    private func cleanedUsernamePart(_ value: String) -> String {
        value
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func composedFullName(firstName: String, middleName: String, lastName: String) -> String {
        [firstName, middleName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func inferredNameParts(from fullName: String) -> (first: String, middle: String, last: String) {
        let parts = fullName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        guard let first = parts.first else { return ("", "", "") }
        guard parts.count > 1 else { return (first, "", "") }

        let last = parts.last ?? ""
        let middle = parts.dropFirst().dropLast().joined(separator: " ")
        return (first, middle, last)
    }
}

enum EmployeeFormRequiredField: Hashable {
    case firstName
    case lastName
    case email
    case phone
    case compensationType
    case salary
    case password
    case role
}
