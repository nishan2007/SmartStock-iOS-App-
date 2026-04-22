//
//  MainMenuView.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/15/26.
//
import SwiftUI

struct MainMenuView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var isShowingNewItem = false

    var user: AppUser? {
        sessionManager.currentUser
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                if let user {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Welcome, \(user.fullName)")
                                .font(.title2.weight(.bold))

                            Text(sessionManager.selectedStore?.name ?? user.username)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "sparkles")
                            .font(.title2)
                            .foregroundStyle(.orange)
                    }
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [Color.mint.opacity(0.22), Color.cyan.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        if canAccess(.makeSale) {
                            NavigationLink {
                                MakeSaleView()
                            } label: {
                                menuTile(title: "Make Sale", subtitle: "Scan and checkout", systemImage: "cart.fill", tint: .green)
                            }
                            .buttonStyle(.plain)
                        }

                        if canAccess(.viewSales) {
                            NavigationLink {
                                ViewSalesView()
                            } label: {
                                menuTile(title: "Sales", subtitle: "History and details", systemImage: "chart.line.uptrend.xyaxis", tint: .blue)
                            }
                            .buttonStyle(.plain)
                        }

                        if canAccess(.returns) {
                            NavigationLink {
                                ReturnsView()
                            } label: {
                                menuTile(title: "Returns", subtitle: "Refunds and exchanges", systemImage: "arrow.uturn.backward.circle.fill", tint: .red)
                            }
                            .buttonStyle(.plain)
                        }

                        if canAccess(.endOfDay) {
                            NavigationLink {
                                EndOfDayView()
                            } label: {
                                menuTile(title: "End of Day", subtitle: "Closeout and notes", systemImage: "checkmark.seal.fill", tint: .indigo)
                            }
                            .buttonStyle(.plain)
                        }

                        if canAccess(.customers) {
                            NavigationLink {
                                CustomersView()
                            } label: {
                                menuTile(title: "Customers", subtitle: "Profiles and history", systemImage: "person.2.fill", tint: .teal)
                            }
                            .buttonStyle(.plain)
                        }

                        if canAccess(.inventory) {
                            NavigationLink {
                                InventoryView()
                            } label: {
                                menuTile(title: "Inventory", subtitle: "Stock and pricing", systemImage: "shippingbox.fill", tint: .orange)
                            }
                            .buttonStyle(.plain)
                        }

                        if canAccess(.receiving) {
                            NavigationLink {
                                ReceivingInventoryView()
                            } label: {
                                menuTile(title: "Receiving", subtitle: "New stock", systemImage: "tray.and.arrow.down.fill", tint: .cyan)
                            }
                            .buttonStyle(.plain)
                        }

                        if canAccess(.storeTransfer) {
                            NavigationLink {
                                StoreTransferView()
                            } label: {
                                menuTile(title: "Store Transfer", subtitle: "Move stock", systemImage: "arrow.left.arrow.right.circle.fill", tint: .brown)
                            }
                            .buttonStyle(.plain)
                        }

                        if canAccess(.editItem) {
                            NavigationLink {
                                EditItemView()
                            } label: {
                                menuTile(title: "Edit Item", subtitle: "Find and update", systemImage: "pencil.circle.fill", tint: .mint)
                            }
                            .buttonStyle(.plain)
                        }

                        if canAccess(.newItem) {
                            Button {
                                isShowingNewItem = true
                            } label: {
                                menuTile(title: "New Item", subtitle: "Photo and barcode", systemImage: "plus.app.fill", tint: .pink)
                            }
                            .buttonStyle(.plain)
                        }

                        if canAccess(.timeClock) {
                            NavigationLink {
                                TimeClockView()
                            } label: {
                                menuTile(title: "Time Clock", subtitle: "Punch in or out", systemImage: "clock.fill", tint: .gray)
                            }
                            .buttonStyle(.plain)
                        }

                        if canAccess(.employees) {
                            NavigationLink {
                                EmployeesView()
                            } label: {
                                menuTile(title: "Employees", subtitle: "Roles and stores", systemImage: "person.3.fill", tint: .purple)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        Task {
                            await sessionManager.signOut()
                        }
                    } label: {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
                .padding()
            }
            .background(
                LinearGradient(
                    colors: [Color.orange.opacity(0.10), Color.mint.opacity(0.08), Color(.systemBackground)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("SmartStock")
            .sheet(isPresented: $isShowingNewItem) {
                InventoryItemFormView(mode: .add, defaultStore: sessionManager.selectedStore) {}
                    .environmentObject(sessionManager)
            }
        }
    }

    private func canAccess(_ permission: MobilePermission) -> Bool {
        user?.canAccess(permission) == true
    }

    private func menuTile(title: String, subtitle: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.14))
                .clipShape(Circle())

            Spacer(minLength: 4)

            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 134, alignment: .topLeading)
        .padding()
        .background(Color(.systemBackground).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
    }
}
