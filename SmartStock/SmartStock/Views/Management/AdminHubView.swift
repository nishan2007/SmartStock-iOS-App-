//
//  AdminHubView.swift
//  SmartStock
//

import SwiftUI

struct AdminHubView: View {
    @EnvironmentObject private var sessionManager: SessionManager

    var body: some View {
        List {
            if peopleItems.isEmpty && storeItems.isEmpty && deviceItems.isEmpty {
                ContentUnavailableView(
                    "No Admin Tools",
                    systemImage: "lock.shield",
                    description: Text("Your role does not currently have any admin permissions.")
                )
            }

            if !peopleItems.isEmpty {
                Section("People") {
                    ForEach(peopleItems) { item in
                        adminNavigationRow(item)
                    }
                }
            }

            if !storeItems.isEmpty {
                Section("Store Setup") {
                    ForEach(storeItems) { item in
                        adminNavigationRow(item)
                    }
                }
            }

            if !deviceItems.isEmpty {
                Section("Devices") {
                    ForEach(deviceItems) { item in
                        adminNavigationRow(item)
                    }
                }
            }
        }
        .navigationTitle("Admin")
    }

    private var peopleItems: [AdminHubItem] {
        [
            sessionManager.currentUser?.canManageEmployees == true ? AdminHubItem(
                title: "Employees",
                subtitle: "Employee records and store access",
                systemImage: "person.3.fill",
                tint: .purple,
                destination: AnyView(EmployeesView().environmentObject(sessionManager))
            ) : nil,
            canAccess(.rolePermissions) ? AdminHubItem(
                title: "Role Permissions",
                subtitle: "Mobile app access by role",
                systemImage: "person.badge.key.fill",
                tint: .indigo,
                destination: AnyView(RolePermissionsView())
            ) : nil
        ].compactMap { $0 }
    }

    private var storeItems: [AdminHubItem] {
        [
            canAccess(.departmentManagement) ? AdminHubItem(
                title: "Departments",
                subtitle: "Category management",
                systemImage: "square.grid.2x2.fill",
                tint: .cyan,
                destination: AnyView(DepartmentManagementView().environmentObject(sessionManager))
            ) : nil,
            canAccess(.vendorManagement) || canAccess(.viewVendor) ? AdminHubItem(
                title: "Vendors",
                subtitle: "Supplier records and item costs",
                systemImage: "building.2.fill",
                tint: .brown,
                destination: AnyView(VendorManagementView().environmentObject(sessionManager))
            ) : nil,
            canAccess(.machineManagement) ? AdminHubItem(
                title: "Machines",
                subtitle: "Maintenance equipment and parts links",
                systemImage: "wrench.and.screwdriver.fill",
                tint: .mint,
                destination: AnyView(AdminMachinesView().environmentObject(sessionManager))
            ) : nil,
            canAccess(.partsManagement) ? AdminHubItem(
                title: "Parts",
                subtitle: "Maintenance inventory and storage",
                systemImage: "gearshape.2.fill",
                tint: .orange,
                destination: AnyView(AdminPartsView().environmentObject(sessionManager))
            ) : nil,
            canAccess(.companyPreferences)
                || canAccess(.locationManagement)
                || canAccess(.cashDrawerManagement)
                || canAccess(.customOrderDepositSettings)
                || canAccess(.customOrderRefundApprovalSettings) ? AdminHubItem(
                title: "Company Preferences",
                subtitle: "Identity, locations, drawers, receipts, and order controls",
                systemImage: "slider.horizontal.3",
                tint: .indigo,
                destination: AnyView(CompanyPreferencesView().environmentObject(sessionManager))
            ) : nil
        ].compactMap { $0 }
    }

    private var deviceItems: [AdminHubItem] {
        [
            canAccess(.deviceManagement) ? AdminHubItem(
                title: "Device Management",
                subtitle: "Approvals, restrictions, and sessions",
                systemImage: "iphone.badge.checkmark",
                tint: .blue,
                destination: AnyView(DeviceManagementView().environmentObject(sessionManager))
            ) : nil,
            canAccess(.localDeviceSettings) ? AdminHubItem(
                title: "Local Device Settings",
                subtitle: "Receipt and device numbering",
                systemImage: "number.square.fill",
                tint: .orange,
                destination: AnyView(DeviceReceiptSettingsView().environmentObject(sessionManager))
            ) : nil
        ].compactMap { $0 }
    }

    private func canAccess(_ permission: MobilePermission) -> Bool {
        sessionManager.currentUser?.canAccess(permission) == true
    }

    private func adminNavigationRow(_ item: AdminHubItem) -> some View {
        NavigationLink {
            item.destination
        } label: {
            HStack(spacing: 14) {
                Image(systemName: item.systemImage)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(item.tint.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct AdminHubItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let destination: AnyView
}
