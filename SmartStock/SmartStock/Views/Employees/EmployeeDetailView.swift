//
//  EmployeeDetailView.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/16/26.
//

//
//  EmployeeDetailView.swift
//  SmartStock
//

import SwiftUI

struct EmployeeDetailView: View {
    let employee: Employee
    @State private var assignedStores: [Store]
    @State private var isLoadingStores = false
    @State private var storeErrorMessage: String?

    init(employee: Employee) {
        self.employee = employee
        _assignedStores = State(initialValue: employee.assignedStores)
    }

    var body: some View {
        List {
            Section("Employee") {
                detailRow("Full Name", employee.fullName)
                if let firstName = employee.firstName, !firstName.isEmpty {
                    detailRow("First Name", firstName)
                }

                if let middleName = employee.middleName, !middleName.isEmpty {
                    detailRow("Middle Name", middleName)
                }

                if let lastName = employee.lastName, !lastName.isEmpty {
                    detailRow("Last Name", lastName)
                }

                detailRow("Username", employee.username)
                detailRow("Role", employee.roleName)
                detailRow("Status", employee.isActive ? "Active" : "Inactive")

                if let email = employee.email, !email.isEmpty {
                    detailRow("Email", email)
                }

                if let phone = employee.phone, !phone.isEmpty {
                    detailRow("Phone", phone)
                }

                if let badgeId = employee.badgeId, !badgeId.isEmpty {
                    detailRow("Badge ID", badgeId)
                }

                if let authUserId = employee.authUserId, !authUserId.isEmpty {
                    detailRow("Auth User ID", authUserId)
                }

                if let createdAt = employee.createdAt {
                    detailRow("Created", createdAt.formatted(date: .abbreviated, time: .shortened))
                }
            }

            Section("Compensation") {
                if let compensationType = employee.compensationType, !compensationType.isEmpty {
                    detailRow("Type", compensationType)
                }

                if let salary = employee.salary {
                    detailRow("Salary", NSDecimalNumber(decimal: salary).stringValue)
                }

                if employee.compensationType?.isEmpty != false && employee.salary == nil {
                    Text("No compensation details")
                        .foregroundColor(.secondary)
                }
            }

            Section("Assigned Stores") {
                if isLoadingStores {
                    ProgressView("Loading stores...")
                } else if let storeErrorMessage {
                    Text(storeErrorMessage)
                        .foregroundStyle(.red)
                } else if assignedStores.isEmpty {
                    Text("No assigned stores")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(assignedStores) { store in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.name)

                            if let address = store.address, !address.isEmpty {
                                Text(address)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Employee Details")
        .task {
            await loadAssignedStores()
        }
    }

    private func loadAssignedStores() async {
        isLoadingStores = true
        storeErrorMessage = nil
        defer { isLoadingStores = false }

        do {
            assignedStores = try await EmployeeService.shared.fetchEmployeeStores(employeeId: employee.id)
        } catch {
            if assignedStores.isEmpty {
                storeErrorMessage = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }
}
