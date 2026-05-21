//
//  MainMenuView.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/15/26.
//
import SwiftUI
import UIKit

struct MainMenuView: View {
    private enum DashboardTile: String, CaseIterable, Identifiable {
        case makeSale
        case customOrders
        case customers
        case returns
        case issues
        case endOfDay
        case sales
        case inventory
        case customOrderItems
        case maintenance
        case receiving
        case storeTransfer
        case changeStore
        case timeClock
        case admin
        case reports

        var id: String { rawValue }

        static let defaultOrder: [DashboardTile] = [
            .makeSale,
            .customOrders,
            .customers,
            .returns,
            .issues,
            .endOfDay,
            .timeClock,
            .sales,
            .inventory,
            .customOrderItems,
            .maintenance,
            .receiving,
            .storeTransfer,
            .changeStore,
            .admin,
            .reports
        ]
    }

    @EnvironmentObject var sessionManager: SessionManager
    @AppStorage("mainMenuTileOrder") private var savedTileOrder = ""
    @State private var isShowingCustomizeMenu = false
    @State private var receiptDeviceName = ""

    var user: AppUser? {
        sessionManager.currentUser
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    mainMenuHeader

                    if let user {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(timeBasedGreeting),")
                                Text(user.fullName)
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
                        ForEach(orderedVisibleTiles) { tile in
                            NavigationLink {
                                destination(for: tile)
                            } label: {
                                menuTile(
                                    title: title(for: tile),
                                    subtitle: subtitle(for: tile),
                                    systemImage: systemImage(for: tile),
                                    tint: tint(for: tile)
                                )
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

                    loginPersistenceCard

                    if !orderedVisibleTiles.isEmpty {
                        Button {
                            isShowingCustomizeMenu = true
                        } label: {
                            Label("Customize Menu", systemImage: "slider.horizontal.3")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
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
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingCustomizeMenu) {
                customizeTilesSheet
            }
            .task {
                loadReceiptDeviceName()
            }
            .onChange(of: sessionManager.currentDevice?.localUsername) { _, localUsername in
                receiptDeviceName = localUsername?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if receiptDeviceName.isEmpty {
                    loadReceiptDeviceName()
                }
            }
        }
    }

    private func canAccess(_ permission: MobilePermission) -> Bool {
        user?.canAccess(permission) == true
    }

    private var canAccessAdminHub: Bool {
        user?.canManageEmployees == true
            || canAccess(.rolePermissions)
            || canAccess(.deviceManagement)
            || canAccess(.localDeviceSettings)
            || canAccess(.locationManagement)
            || canAccess(.departmentManagement)
            || canAccess(.vendorManagement)
            || canAccess(.viewVendor)
            || canAccess(.machineManagement)
            || canAccess(.partsManagement)
    }

    private var receivingSubtitle: String {
        switch (canAccess(.receiving), canAccess(.viewReceivingHistory)) {
        case (true, true):
            return "Receive and history"
        case (true, false):
            return "New stock"
        case (false, true):
            return "Receiving history"
        case (false, false):
            return "Receive stock"
        }
    }

    private var timeBasedGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())

        switch hour {
        case 5..<12:
            return "Good Morning"
        case 12..<15:
            return "Good Day"
        case 15..<18:
            return "Good Afternoon"
        default:
            return "Good Evening"
        }
    }

    private var mainMenuHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 56, alignment: .leading)
                .accessibilityLabel("SmartStock")

            Spacer(minLength: 12)

            Image("CompanyLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 118, height: 44)
                .accessibilityLabel("Company logo")
        }
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .center)
        .padding(.top, -20)
        .padding(.horizontal, -4)
    }

    private var orderedVisibleTiles: [DashboardTile] {
        let visibleTiles = DashboardTile.defaultOrder.filter(canShow)
        let savedTiles = savedTileOrder
            .split(separator: ",")
            .compactMap { DashboardTile(rawValue: String($0)) }
            .filter { visibleTiles.contains($0) }
        let missingTiles = visibleTiles.filter { !savedTiles.contains($0) }

        return savedTiles + missingTiles
    }

    @ViewBuilder
    private func destination(for tile: DashboardTile) -> some View {
        switch tile {
        case .makeSale:
            MakeSaleView()
        case .customOrders:
            CustomOrdersView()
        case .customers:
            CustomersView()
        case .returns:
            ReturnsView()
        case .issues:
            IssuesView()
                .environmentObject(sessionManager)
        case .endOfDay:
            EndOfDayView()
        case .sales:
            ViewSalesView()
        case .inventory:
            InventoryView()
        case .customOrderItems:
            CustomOrderItemsView()
        case .maintenance:
            MaintenanceView()
                .environmentObject(sessionManager)
        case .receiving:
            ReceivingView()
        case .storeTransfer:
            StoreTransferView()
        case .changeStore:
            StoreSelectionView()
                .environmentObject(sessionManager)
        case .timeClock:
            TimeClockView()
        case .admin:
            AdminHubView()
                .environmentObject(sessionManager)
        case .reports:
            ReportsHubView()
                .environmentObject(sessionManager)
        }
    }

    private func canShow(_ tile: DashboardTile) -> Bool {
        switch tile {
        case .makeSale:
            return canAccess(.makeSale)
        case .customOrders:
            return canAccess(.createCustomOrder)
                || canAccess(.manageCustomOrders)
                || canAccess(.viewAssignedCustomOrders)
                || canAccess(.ordersManagerDashboard)
                || canAccess(.ordersEndOfDay)
        case .customers:
            return canAccess(.customers)
        case .returns:
            return canAccess(.returns)
        case .issues:
            return user != nil
        case .endOfDay:
            return canAccess(.endOfDay)
        case .sales:
            return canAccess(.viewSales)
        case .inventory:
            return canAccess(.inventory)
        case .customOrderItems:
            return canAccess(.customOrderItems) || canAccess(.customOrderPrintMaterials)
        case .maintenance:
            return canAccess(.maintenanceManagement)
        case .receiving:
            return canAccess(.receiving) || canAccess(.viewReceivingHistory)
        case .storeTransfer:
            return canAccess(.storeTransfer)
        case .changeStore:
            return canAccess(.changeStore) && !sessionManager.isCurrentDeviceStoreRestricted
        case .timeClock:
            return canAccess(.timeClock)
        case .admin:
            return canAccessAdminHub
        case .reports:
            return canAccess(.viewReports)
        }
    }

    private func title(for tile: DashboardTile) -> String {
        switch tile {
        case .makeSale:
            return "Make Sale"
        case .customOrders:
            return "Custom Orders"
        case .customers:
            return "Customers"
        case .returns:
            return "Returns"
        case .issues:
            return "Issues"
        case .endOfDay:
            return "End of Day"
        case .sales:
            return "Sales"
        case .inventory:
            return "Inventory"
        case .customOrderItems:
            return "Custom Order Items"
        case .maintenance:
            return "Maintenance"
        case .receiving:
            return "Receiving"
        case .storeTransfer:
            return "Store Transfer"
        case .changeStore:
            return "Change Store"
        case .timeClock:
            return "Time Clock"
        case .admin:
            return "Admin"
        case .reports:
            return "Reports"
        }
    }

    private func subtitle(for tile: DashboardTile) -> String {
        switch tile {
        case .makeSale:
            return "Scan and checkout"
        case .customOrders:
            return "Entry and assignment"
        case .customers:
            return "Profiles and history"
        case .returns:
            return "Refunds and exchanges"
        case .issues:
            return "Report problems or ask for help"
        case .endOfDay:
            return "Closeout and notes"
        case .sales:
            return "Sales and return history"
        case .inventory:
            return "Stock and pricing"
        case .customOrderItems:
            return "Templates and stock"
        case .maintenance:
            return "Machines, parts, and tickets"
        case .receiving:
            return receivingSubtitle
        case .storeTransfer:
            return "Move stock"
        case .changeStore:
            return "Switch active location"
        case .timeClock:
            return "Punch in or out"
        case .admin:
            return "People, stores, and devices"
        case .reports:
            return "Summaries and history"
        }
    }

    private func systemImage(for tile: DashboardTile) -> String {
        switch tile {
        case .makeSale:
            return "cart.fill"
        case .customOrders:
            return "list.clipboard.fill"
        case .customers:
            return "person.2.fill"
        case .returns:
            return "arrow.uturn.backward.circle.fill"
        case .issues:
            return "questionmark.bubble.fill"
        case .endOfDay:
            return "checkmark.seal.fill"
        case .sales:
            return "chart.line.uptrend.xyaxis"
        case .inventory:
            return "shippingbox.fill"
        case .customOrderItems:
            return "tshirt.fill"
        case .maintenance:
            return "wrench.and.screwdriver.fill"
        case .receiving:
            return "tray.and.arrow.down.fill"
        case .storeTransfer:
            return "arrow.left.arrow.right.circle.fill"
        case .changeStore:
            return "storefront.circle.fill"
        case .timeClock:
            return "clock.fill"
        case .admin:
            return "lock.shield.fill"
        case .reports:
            return "chart.bar.doc.horizontal.fill"
        }
    }

    private func tint(for tile: DashboardTile) -> Color {
        switch tile {
        case .makeSale:
            return .green
        case .customOrders:
            return .purple
        case .customers:
            return .teal
        case .returns:
            return .red
        case .issues:
            return .pink
        case .endOfDay:
            return .indigo
        case .sales:
            return .blue
        case .inventory:
            return .orange
        case .customOrderItems:
            return .pink
        case .maintenance:
            return .mint
        case .receiving:
            return .cyan
        case .storeTransfer:
            return .brown
        case .changeStore:
            return .yellow
        case .timeClock:
            return .gray
        case .admin:
            return .purple
        case .reports:
            return .indigo
        }
    }

    private func saveTileOrder(_ tiles: [DashboardTile]) {
        savedTileOrder = tiles.map(\.rawValue).joined(separator: ",")
    }

    private func resetTileOrder() {
        savedTileOrder = ""
    }

    private var customizeTilesSheet: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(orderedVisibleTiles) { tile in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title(for: tile))
                                    .font(.headline)
                                Text(subtitle(for: tile))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: systemImage(for: tile))
                                .foregroundStyle(tint(for: tile))
                        }
                    }
                    .onMove { source, destination in
                        var updatedTiles = orderedVisibleTiles
                        updatedTiles.move(fromOffsets: source, toOffset: destination)
                        saveTileOrder(updatedTiles)
                    }
                } header: {
                    Text("Dashboard Tiles")
                } footer: {
                    Text("Only tiles you have permission to use appear here. New permissions are added automatically.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Customize Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        resetTileOrder()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isShowingCustomizeMenu = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var loginPersistenceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Login Security", systemImage: "lock.shield")
                .font(.headline)

            LabeledContent("Device", value: loginSecurityDeviceName)
                .font(.footnote.weight(.medium))

            LabeledContent("Receipt Device", value: loginSecurityReceiptDeviceName)
                .font(.footnote.weight(.medium))

            if sessionManager.canManagePersistentLoginApproval {
                Text(sessionManager.allowsPersistentLogin
                     ? "This device is approved to stay signed in."
                     : "This device is currently treated as a shared device and will require login after the app closes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text(sessionManager.currentDevice?.isBlocked == true
                     ? "This device has been blocked."
                     : sessionManager.allowsPersistentLogin
                     ? "This device is approved to stay signed in."
                     : "This device is in shared-device mode and will require login after the app closes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemBackground).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.blue.opacity(0.16), lineWidth: 1)
        )
    }

    private var loginSecurityDeviceName: String {
        if let deviceName = sessionManager.currentDevice?.deviceName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !deviceName.isEmpty {
            return deviceName
        }

        if let currentDevice = sessionManager.currentDevice {
            return currentDevice.modelName
        }

        return UIDevice.current.name
    }

    private var loginSecurityReceiptDeviceName: String {
        if let localUsername = sessionManager.currentDevice?.localUsername?.trimmingCharacters(in: .whitespacesAndNewlines),
           !localUsername.isEmpty {
            return localUsername
        }

        return receiptDeviceName.isEmpty ? "Not set" : receiptDeviceName
    }

    private func loadReceiptDeviceName() {
        receiptDeviceName = ReceiptNumberManager.shared.currentDeviceId()
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
