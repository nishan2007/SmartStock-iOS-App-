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
    @State private var availablePermissions: [RolePermissionDefinition] = []
    @State private var permissionsByRole: [Int: Set<MobilePermission>] = [:]
    @State private var isLoading = false
    @State private var savingRoleIds: Set<Int> = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }
            }

            if !isLoading && roles.isEmpty {
                ContentUnavailableView(
                    "No Roles Found",
                    systemImage: "person.3.sequence",
                    description: Text("Check that public.roles has rows and an authenticated SELECT policy.")
                )
            } else if !isLoading && availablePermissions.isEmpty {
                ContentUnavailableView(
                    "No Mobile Permissions",
                    systemImage: "lock.shield",
                    description: Text("No rows were returned from mobile_permissions.")
                )
            } else {
                permissionsSection
            }
        }
        .navigationTitle("Mobile Permissions")
        .task {
            await loadRoles()
        }
        .refreshable {
            await loadRoles()
        }
        .overlay {
            if isLoading {
                LoadingView(text: "Loading permissions...")
                    .background(Color(.systemBackground).opacity(0.85))
            }
        }
    }

    private var permissionsSection: some View {
        Section("Mobile App Permissions") {
            ForEach(roles) { role in
                DisclosureGroup {
                    ForEach(groupedPermissions, id: \.title) { group in
                        Section(group.title) {
                            ForEach(group.permissions) { permission in
                                Toggle(isOn: binding(for: permission.permission, role: role)) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(permission.title)

                                        if let description = permission.description, !description.isEmpty {
                                            Text(description)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Button {
                        Task {
                            await savePermissions(for: role)
                        }
                    } label: {
                        if savingRoleIds.contains(role.id) {
                            ProgressView()
                        } else {
                            Label("Save \(role.name)", systemImage: "checkmark.circle.fill")
                        }
                    }
                    .disabled(savingRoleIds.contains(role.id))
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(role.name)
                        Text("\(permissionsByRole[role.id, default: []].count) mobile permissions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var groupedPermissions: [(title: String, permissions: [RolePermissionDefinition])] {
        let grouped = Dictionary(grouping: availablePermissions, by: \.groupTitle)
        let preferredOrder = ["Sales", "Inventory", "Operations", "Employee", "Device", "Admin"]
        let remainingTitles = grouped.keys
            .filter { !preferredOrder.contains($0) }
            .sorted()
        let order = preferredOrder + remainingTitles

        return order.compactMap { title in
            guard let permissions = grouped[title] else { return nil }
            return (title, permissions.sorted { $0.sortOrder < $1.sortOrder })
        }
    }

    private func loadRoles() async {
        isLoading = true
        errorMessage = nil

        do {
            async let rolesTask = RoleService.shared.fetchRoles()
            async let availablePermissionsTask = RoleService.shared.fetchAvailableMobilePermissions()
            async let permissionsTask = RoleService.shared.fetchMobilePermissionsByRole()

            roles = try await rolesTask
            availablePermissions = try await availablePermissionsTask
            permissionsByRole = try await permissionsTask
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func binding(for permission: MobilePermission, role: Role) -> Binding<Bool> {
        Binding {
            permissionsByRole[role.id, default: []].contains(permission)
        } set: { isEnabled in
            var permissions = permissionsByRole[role.id, default: []]

            if isEnabled {
                permissions.insert(permission)
            } else {
                permissions.remove(permission)
            }

            permissionsByRole[role.id] = permissions
        }
    }

    private func savePermissions(for role: Role) async {
        savingRoleIds.insert(role.id)
        errorMessage = nil
        defer {
            savingRoleIds.remove(role.id)
        }

        do {
            try await RoleService.shared.updateMobilePermissions(
                roleId: role.id,
                permissions: permissionsByRole[role.id, default: []]
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
