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

    var body: some View {
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

                NavigationLink {
                    AddEmployeeView {
                        await viewModel.refresh()
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task {
            await viewModel.loadEmployees()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .overlay {
            if viewModel.isLoading {
                LoadingView(text: "Loading employees...")
                    .background(Color(.systemBackground).opacity(0.85))
            }
        }
    }
}

private struct EmployeeDetailScreenWrapper: View {
    let employee: Employee
    @ObservedObject var viewModel: EmployeesViewModel

    var body: some View {
        EmployeeDetailView(employee: employee)
            .toolbar {
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
