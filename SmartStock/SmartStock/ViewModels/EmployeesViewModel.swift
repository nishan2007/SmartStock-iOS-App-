//
//  EmployeesViewModel.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/16/26.
//

//
//  EmployeesViewModel.swift
//  SmartStock
//

import Foundation
import Combine

@MainActor
final class EmployeesViewModel: ObservableObject {
    @Published var employees: [Employee] = []
    @Published var searchText = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadEmployees() async {
        isLoading = true
        errorMessage = nil

        do {
            employees = try await EmployeeService.shared.fetchEmployees()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func refresh() async {
        await loadEmployees()
    }

    func toggleEmployeeStatus(_ employee: Employee) async {
        do {
            try await EmployeeService.shared.toggleEmployeeActive(
                employeeId: employee.id,
                isActive: !employee.isActive
            )
            await loadEmployees()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteEmployee(_ employee: Employee) async {
        do {
            try await EmployeeService.shared.deleteEmployee(employeeId: employee.id)
            await loadEmployees()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var filteredEmployees: [Employee] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !query.isEmpty else { return employees }

        return employees.filter { employee in
            employee.fullName.lowercased().contains(query) ||
            employee.username.lowercased().contains(query) ||
            employee.roleName.lowercased().contains(query) ||
            (employee.email?.lowercased().contains(query) ?? false)
        }
    }
}
