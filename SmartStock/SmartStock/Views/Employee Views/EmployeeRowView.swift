//
//  EmployeeRowView.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/16/26.
//

//
//  EmployeeRowView.swift
//  SmartStock
//

import SwiftUI

struct EmployeeRowView: View {
    let employee: Employee

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(employee.fullName)
                    .font(.headline)

                Spacer()

                Text(employee.isActive ? "Active" : "Inactive")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(employee.isActive ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                    .cornerRadius(8)
            }

            Text("@\(employee.username)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack {
                Label(employee.roleName, systemImage: "person.badge.key")
                    .font(.caption)

                Spacer()

                Text("\(employee.assignedStores.count) store\(employee.assignedStores.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let email = employee.email, !email.isEmpty {
                Text(email)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}
