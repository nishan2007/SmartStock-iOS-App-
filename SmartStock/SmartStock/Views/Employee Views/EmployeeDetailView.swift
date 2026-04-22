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

    var body: some View {
        List {
            Section("Employee") {
                detailRow("Full Name", employee.fullName)
                detailRow("Username", employee.username)
                detailRow("Role", employee.roleName)
                detailRow("Status", employee.isActive ? "Active" : "Inactive")

                if let email = employee.email, !email.isEmpty {
                    detailRow("Email", email)
                }

                if let phone = employee.phone, !phone.isEmpty {
                    detailRow("Phone", phone)
                }

                if let createdAt = employee.createdAt {
                    detailRow("Created", createdAt.formatted(date: .abbreviated, time: .shortened))
                }
            }

            Section("Assigned Stores") {
                if employee.assignedStores.isEmpty {
                    Text("No assigned stores")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(employee.assignedStores) { store in
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
