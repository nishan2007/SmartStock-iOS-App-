//
//  RolePermissionsView.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/16/26.
//

//
//  RolePermissionsView.swift
//  SmartStock
//

import SwiftUI

struct RolePermissionsView: View {
    @State private var roles: [Role] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }
            }

            Section("Roles") {
                ForEach(roles) { role in
                    HStack {
                        Text(role.name)
                        Spacer()
                        Text("#\(role.id)")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Roles")
        .task {
            await loadRoles()
        }
        .overlay {
            if isLoading {
                LoadingView()
                    .background(Color(.systemBackground).opacity(0.85))
            }
        }
    }

    private func loadRoles() async {
        isLoading = true
        errorMessage = nil

        do {
            roles = try await RoleService.shared.fetchRoles()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
