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
    @Published var username = ""
    @Published var fullName = ""
    @Published var email = ""
    @Published var phone = ""
    @Published var password = ""
    @Published var selectedRoleId: Int?
    @Published var isActive = true
    @Published var selectedStoreIds: Set<Int> = []

    @Published var roles: [Role] = []
    @Published var stores: [Store] = []

    @Published var isSaving = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    let employee: Employee?

    init(employee: Employee? = nil) {
        self.employee = employee

        if let employee {
            username = employee.username
            fullName = employee.fullName
            email = employee.email ?? ""
            phone = employee.phone ?? ""
            selectedRoleId = employee.roleId
            isActive = employee.isActive
            selectedStoreIds = Set(employee.assignedStores.map(\.id))
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

        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Username is required."
            return false
        }

        guard !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Full name is required."
            return false
        }

        guard let selectedRoleId else {
            errorMessage = "Please select a role."
            return false
        }

        if !isEditing && password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Password is required for new employees."
            return false
        }

        isSaving = true

        do {
            if let employee {
                try await EmployeeService.shared.updateEmployee(
                    employeeId: employee.id,
                    username: username,
                    fullName: fullName,
                    email: email,
                    phone: phone,
                    passwordHash: password.isEmpty ? nil : password,
                    roleId: selectedRoleId,
                    isActive: isActive
                )

                try await EmployeeService.shared.updateEmployeeStores(
                    employeeId: employee.id,
                    storeIds: Array(selectedStoreIds)
                )
            } else {
                try await EmployeeService.shared.createEmployee(
                    username: username,
                    fullName: fullName,
                    email: email,
                    phone: phone,
                    password: password,
                    roleId: selectedRoleId,
                    isActive: isActive,
                    storeIds: Array(selectedStoreIds)
                )
            }

            isSaving = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
            return false
        }
    }
}
