//
//  EmployeesView.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/16/26.
//

//
//  EmployeesView.swift
//  SmartStock
//

import SwiftUI

struct EmployeesView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @StateObject private var viewModel = EmployeesViewModel()
    @State private var employeePendingDeletion: Employee?

    private var canManageEmployees: Bool {
        sessionManager.currentUser?.canManageEmployees == true
    }

    var body: some View {
        Group {
            if !canManageEmployees {
                ContentUnavailableView(
                    "Employee Management Locked",
                    systemImage: "lock.fill",
                    description: Text("Your role does not include the Employee Management mobile permission.")
                )
            } else {
                List {
                    if let error = viewModel.errorMessage {
                        Section {
                            Text(error)
                                .foregroundColor(.red)
                        }
                    }

                    if viewModel.filteredEmployees.isEmpty && !viewModel.isLoading {
                        EmptyEmployeesView()
                            .listRowSeparator(.hidden)
                    } else {
                        Section {
                            ForEach(viewModel.filteredEmployees) { employee in
                                NavigationLink {
                                    EmployeeDetailScreenWrapper(employee: employee, viewModel: viewModel)
                                        .environmentObject(sessionManager)
                                } label: {
                                    EmployeeRowView(employee: employee)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    NavigationLink {
                                        EditEmployeeView(employee: employee) {
                                            await viewModel.refresh()
                                        }
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.blue)

                                    Button {
                                        Task {
                                            await viewModel.toggleEmployeeStatus(employee)
                                        }
                                    } label: {
                                        Label(
                                            employee.isActive ? "Deactivate" : "Activate",
                                            systemImage: employee.isActive ? "pause.circle" : "play.circle"
                                        )
                                    }
                                    .tint(employee.isActive ? .orange : .green)

                                    Button(role: .destructive) {
                                        employeePendingDeletion = employee
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Employees")
        .searchable(text: $viewModel.searchText, prompt: "Search employees")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if sessionManager.currentUser?.canAccess(.rolePermissions) == true {
                    NavigationLink {
                        RolePermissionsView()
                    } label: {
                        Image(systemName: "person.badge.key")
                    }
                }

                if sessionManager.currentUser?.canAccess(.deviceManagement) == true {
                    NavigationLink {
                        DeviceManagementView()
                            .environmentObject(sessionManager)
                    } label: {
                        Image(systemName: "iphone.badge.checkmark")
                    }
                }

                if canManageEmployees {
                    NavigationLink {
                        AddEmployeeView {
                            await viewModel.refresh()
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .task {
            if canManageEmployees {
                await viewModel.loadEmployees()
            }
        }
        .refreshable {
            if canManageEmployees {
                await viewModel.refresh()
            }
        }
        .confirmationDialog(
            "Delete Employee",
            isPresented: Binding(
                get: { employeePendingDeletion != nil },
                set: { if !$0 { employeePendingDeletion = nil } }
            ),
            presenting: employeePendingDeletion
        ) { employee in
            Button("Delete \(employee.fullName)", role: .destructive) {
                Task {
                    await viewModel.deleteEmployee(employee)
                    employeePendingDeletion = nil
                }
            }
        } message: { employee in
            Text("This deletes the Supabase Auth user first. The local employee is only removed if Auth deletion succeeds.")
        }
        .overlay {
            if canManageEmployees && viewModel.isLoading {
                LoadingView(text: "Loading employees...")
                    .background(Color(.systemBackground).opacity(0.85))
            }
        }
    }
}

private struct EmployeeDetailScreenWrapper: View {
    @EnvironmentObject private var sessionManager: SessionManager
    let employee: Employee
    @ObservedObject var viewModel: EmployeesViewModel

    var body: some View {
        EmployeeDetailView(employee: employee)
            .toolbar {
                if sessionManager.currentUser?.canManageEmployees == true {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        NavigationLink {
                            AssignStoresView(employee: employee) {
                                await viewModel.refresh()
                            }
                        } label: {
                            Image(systemName: "building.2")
                        }

                        NavigationLink {
                            EditEmployeeView(employee: employee) {
                                await viewModel.refresh()
                            }
                        } label: {
                            Image(systemName: "pencil")
                        }
                    }
                }
            }
    }
}
