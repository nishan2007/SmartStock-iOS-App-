//
//  MainMenuView.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/15/26.
//
import SwiftUI

struct MainMenuView: View {
    @EnvironmentObject var sessionManager: SessionManager

    var user: AppUser? {
        sessionManager.currentUser
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {

                if let user {
                    VStack(spacing: 4) {
                        Text("Welcome, \(user.fullName)")
                            .font(.title2)

                        Text("Username: \(user.username)")
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // MAIN BUTTONS
                VStack(spacing: 16) {

                    NavigationLink {
                        MakeSaleView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "cart")
                                .font(.title3)
                                .frame(width: 28)

                            Text("Make Sale")
                                .font(.headline)

                            Spacer()
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)

                    
                    NavigationLink {
                        ViewSalesView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "list.bullet")
                                .font(.title3)
                                .frame(width: 28)

                            Text("View Sales")
                                .font(.headline)

                            Spacer()
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        InventoryView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "cube.box")
                                .font(.title3)
                                .frame(width: 28)

                            Text("View Inventory")
                                .font(.headline)

                            Spacer()
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)

                    // Only show if admin/manager
                    if user?.roleId == 1 {
                        MenuButton(title: "Employees", systemImage: "person.3") {
                            print("Go to Employee Management")
                        }
                    }
                }

                Spacer()

                Button("Log Out") {
                    Task {
                        await sessionManager.signOut()
                    }
                }
                .foregroundColor(.red)
            }
            .padding()
            .navigationTitle("SmartStock")
        }
    }
}
