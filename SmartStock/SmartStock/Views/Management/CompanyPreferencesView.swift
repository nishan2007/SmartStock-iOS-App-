//
//  CompanyPreferencesView.swift
//  SmartStock
//

import SwiftUI
import Supabase
import Combine

enum CompanyPreferencesSection: String, CaseIterable, Identifiable {
    case identity
    case locations
    case cashDrawers
    case saleReceipt
    case customOrderDeposit
    case customOrderReceipt

    var id: String { rawValue }

    var title: String {
        switch self {
        case .identity: return "Company Identity"
        case .locations: return "Locations"
        case .cashDrawers: return "Cash Drawer Manager"
        case .saleReceipt: return "Sale Receipt & Formatting"
        case .customOrderDeposit: return "Order Deposit & Refund Approval"
        case .customOrderReceipt: return "Receipt/Slip Formatting"
        }
    }

    var icon: String {
        switch self {
        case .identity: return "building.2"
        case .locations: return "map"
        case .cashDrawers: return "tray.2"
        case .saleReceipt: return "receipt"
        case .customOrderDeposit: return "creditcard"
        case .customOrderReceipt: return "doc.text"
        }
    }
}

struct CompanyPreferencesView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @StateObject private var viewModel: CompanyPreferencesViewModel
    @StateObject private var locationsModel = LocationsManagementViewModel()
    @StateObject private var cashDrawerModel = CashDrawerManagementViewModel()
    private let initialSection: CompanyPreferencesSection

    init(initialSection: CompanyPreferencesSection = .identity) {
        self.initialSection = initialSection
        _viewModel = StateObject(wrappedValue: CompanyPreferencesViewModel(initialSection: initialSection))
    }

    var body: some View {
        Group {
            if initialSection == .identity {
                preferencesHub
            } else {
                sectionDestination(initialSection)
            }
        }
        .task {
            await viewModel.load(sessionManager: sessionManager)
            await locationsModel.loadIfAllowed(sessionManager: sessionManager)
            await cashDrawerModel.loadIfAllowed(sessionManager: sessionManager)
        }
    }

    @ViewBuilder
    private var preferencesHub: some View {
        List {
            if companyItems.isEmpty && operationsItems.isEmpty && saleItems.isEmpty && customOrderItems.isEmpty {
                ContentUnavailableView(
                    "No Company Preferences",
                    systemImage: "lock.shield",
                    description: Text("Your role does not currently have company preference permissions.")
                )
            }

            if !companyItems.isEmpty {
                Section("Company") {
                    ForEach(companyItems) { item in preferenceNavigationRow(item) }
                }
            }

            if !operationsItems.isEmpty {
                Section("Operations") {
                    ForEach(operationsItems) { item in preferenceNavigationRow(item) }
                }
            }

            if !saleItems.isEmpty {
                Section("Sale") {
                    ForEach(saleItems) { item in preferenceNavigationRow(item) }
                }
            }

            if !customOrderItems.isEmpty {
                Section("Custom Orders") {
                    ForEach(customOrderItems) { item in preferenceNavigationRow(item) }
                }
            }
        }
        .navigationTitle("Company Preferences")
    }

    @ViewBuilder
    private func sectionDestination(_ section: CompanyPreferencesSection) -> some View {
        Group {
            switch section {
            case .identity:
                CompanyIdentitySectionView(viewModel: viewModel, canEdit: canAccess(.companyPreferences))
            case .locations:
                LocationsManagementSectionView(viewModel: locationsModel, canManage: canAccess(.locationManagement))
            case .cashDrawers:
                CashDrawerManagementSectionView(viewModel: cashDrawerModel, canManage: canAccess(.cashDrawerManagement))
            case .saleReceipt:
                SaleReceiptSectionView(viewModel: viewModel, canEdit: canAccess(.companyPreferences), storeName: sessionManager.selectedStore?.name ?? "Main Store")
            case .customOrderDeposit:
                CustomOrderDepositSectionView(
                    viewModel: viewModel,
                    canEditDeposit: canAccess(.customOrderDepositSettings) || canAccess(.companyPreferences),
                    canEditRefundApproval: canAccess(.customOrderRefundApprovalSettings) || canAccess(.companyPreferences)
                )
            case .customOrderReceipt:
                CustomOrderReceiptSectionView(viewModel: viewModel, canEdit: canAccess(.companyPreferences), storeName: sessionManager.selectedStore?.name ?? "Main Store")
            }
        }
        .navigationTitle(section.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await refresh(section) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }

                if section.isCompanySettingsSection {
                    Button {
                        Task { await viewModel.save(sessionManager: sessionManager) }
                    } label: {
                        Label(viewModel.isSaving ? "Saving" : "Save", systemImage: "checkmark.circle")
                    }
                    .disabled(viewModel.isSaving || !viewModel.canSave(sessionManager: sessionManager))
                }
            }
        }
    }

    private var companyItems: [CompanyPreferenceItem] {
        [
            canView(.identity) ? item(.identity, "Company name, logo, and shared identity", .indigo) : nil
        ].compactMap { $0 }
    }

    private var operationsItems: [CompanyPreferenceItem] {
        [
            canView(.locations) ? item(.locations, "Store records, addresses, and timezones", .red) : nil,
            canView(.cashDrawers) ? item(.cashDrawers, "Store drawers and device assignments", .green) : nil
        ].compactMap { $0 }
    }

    private var saleItems: [CompanyPreferenceItem] {
        [
            canView(.saleReceipt) ? item(.saleReceipt, "Receipt fields, logo, and 40-column preview", .blue) : nil
        ].compactMap { $0 }
    }

    private var customOrderItems: [CompanyPreferenceItem] {
        [
            canView(.customOrderDeposit) ? item(.customOrderDeposit, "Minimum deposits and refund approval limits", .orange) : nil,
            canView(.customOrderReceipt) ? item(.customOrderReceipt, "Order slip behavior, fields, and previews", .purple) : nil
        ].compactMap { $0 }
    }

    private func item(_ section: CompanyPreferencesSection, _ subtitle: String, _ tint: Color) -> CompanyPreferenceItem {
        CompanyPreferenceItem(section: section, title: section.title, subtitle: subtitle, systemImage: section.icon, tint: tint)
    }

    private func preferenceNavigationRow(_ item: CompanyPreferenceItem) -> some View {
        NavigationLink {
            sectionDestination(item.section)
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

    private func refresh(_ section: CompanyPreferencesSection) async {
        switch section {
        case .locations:
            await locationsModel.loadIfAllowed(sessionManager: sessionManager)
        case .cashDrawers:
            await cashDrawerModel.loadIfAllowed(sessionManager: sessionManager)
        default:
            await viewModel.load(sessionManager: sessionManager)
        }
    }

    private func canView(_ section: CompanyPreferencesSection) -> Bool {
        switch section {
        case .identity, .saleReceipt, .customOrderReceipt:
            return canAccess(.companyPreferences)
        case .locations:
            return canAccess(.locationManagement)
        case .cashDrawers:
            return canAccess(.cashDrawerManagement)
        case .customOrderDeposit:
            return canAccess(.customOrderDepositSettings) || canAccess(.customOrderRefundApprovalSettings) || canAccess(.companyPreferences)
        }
    }

    private func canAccess(_ permission: MobilePermission) -> Bool {
        sessionManager.currentUser?.canAccess(permission) == true
    }
}

private struct CompanyPreferenceItem: Identifiable {
    let id = UUID()
    let section: CompanyPreferencesSection
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
}

private extension CompanyPreferencesSection {
    var isCompanySettingsSection: Bool {
        switch self {
        case .identity, .saleReceipt, .customOrderDeposit, .customOrderReceipt:
            return true
        case .locations, .cashDrawers:
            return false
        }
    }
}

@MainActor
final class CompanyPreferencesViewModel: ObservableObject {
    @Published var selectedSection: CompanyPreferencesSection
    @Published var companyName = "SmartStock"
    @Published var receiptLogoURL = ""
    @Published var receiptHeaderLine = ""
    @Published var receiptFooterLine = "Thank you"
    @Published var showReceiptLogo = true
    @Published var showSaleIdOnReceipt = true
    @Published var showDeviceIdOnReceipt = true
    @Published var showCustomerOnReceipt = true
    @Published var showSkuOnReceipt = true
    @Published var showItemDiscountsOnReceipt = true
    @Published var showPaymentStatusOnReceipt = true
    @Published var nextReceiptCounter = "1"
    @Published var customOrderSlipEnabled = true
    @Published var customOrderSlipAutoPrint = false
    @Published var customOrderSlipTitle = "Customer's Order Slip"
    @Published var customOrderSlipContactLine = ""
    @Published var customOrderSlipEmailLine = ""
    @Published var customOrderSlipFooterNote = "Please keep this slip for your records."
    @Published var customOrderSlipBlankDetailLines = "4"
    @Published var customOrderSlipShowLogo = true
    @Published var customOrderSlipShowOrderNumber = true
    @Published var customOrderSlipShowDueDate = true
    @Published var customOrderSlipShowCustomerPhone = true
    @Published var customOrderSlipShowCustomerAccount = true
    @Published var customOrderSlipShowStore = true
    @Published var customOrderSlipShowDevice = true
    @Published var customOrderSlipShowCashier = true
    @Published var customOrderSlipShowLineItems = true
    @Published var customOrderSlipShowPricing = true
    @Published var customOrderSlipShowPaymentSummary = true
    @Published var customOrderSlipShowPaymentReference = true
    @Published var customOrderSlipShowTakenBy = true
    @Published var customOrderSlipShowSignatures = true
    @Published var minimumDepositPercent = "0"
    @Published var refundApprovalLimit = "0"
    @Published var isSaving = false
    @Published var message: String?

    private let service = CustomOrderService()

    init(initialSection: CompanyPreferencesSection) {
        selectedSection = initialSection
    }

    func load(sessionManager: SessionManager) async {
        do {
            let prefs = try await service.fetchCompanyPreferences(locationId: sessionManager.selectedStore?.id)
            companyName = prefs.companyName
            receiptLogoURL = prefs.receiptLogoURL
            receiptHeaderLine = prefs.receiptHeaderLine
            receiptFooterLine = prefs.receiptFooterLine
            showReceiptLogo = prefs.showReceiptLogo
            showSaleIdOnReceipt = prefs.showSaleIdOnReceipt
            showDeviceIdOnReceipt = prefs.showDeviceIdOnReceipt
            showCustomerOnReceipt = prefs.showCustomerOnReceipt
            showSkuOnReceipt = prefs.showSkuOnReceipt
            showItemDiscountsOnReceipt = prefs.showItemDiscountsOnReceipt
            showPaymentStatusOnReceipt = prefs.showPaymentStatusOnReceipt
            nextReceiptCounter = String(max(prefs.nextReceiptCounter, 1))
            customOrderSlipEnabled = prefs.customOrderSlipEnabled
            customOrderSlipAutoPrint = prefs.customOrderSlipAutoPrint
            customOrderSlipTitle = prefs.customOrderSlipTitle
            customOrderSlipContactLine = prefs.customOrderSlipContactLine
            customOrderSlipEmailLine = prefs.customOrderSlipEmailLine
            customOrderSlipFooterNote = prefs.customOrderSlipFooterNote
            customOrderSlipBlankDetailLines = String(prefs.customOrderSlipBlankDetailLines)
            customOrderSlipShowLogo = prefs.customOrderSlipShowLogo
            customOrderSlipShowOrderNumber = prefs.customOrderSlipShowOrderNumber
            customOrderSlipShowDueDate = prefs.customOrderSlipShowDueDate
            customOrderSlipShowCustomerPhone = prefs.customOrderSlipShowCustomerPhone
            customOrderSlipShowCustomerAccount = prefs.customOrderSlipShowCustomerAccount
            customOrderSlipShowStore = prefs.customOrderSlipShowStore
            customOrderSlipShowDevice = prefs.customOrderSlipShowDevice
            customOrderSlipShowCashier = prefs.customOrderSlipShowCashier
            customOrderSlipShowLineItems = prefs.customOrderSlipShowLineItems
            customOrderSlipShowPricing = prefs.customOrderSlipShowPricing
            customOrderSlipShowPaymentSummary = prefs.customOrderSlipShowPaymentSummary
            customOrderSlipShowPaymentReference = prefs.customOrderSlipShowPaymentReference
            customOrderSlipShowTakenBy = prefs.customOrderSlipShowTakenBy
            customOrderSlipShowSignatures = prefs.customOrderSlipShowSignatures
            minimumDepositPercent = String(format: "%.2f", prefs.customOrderMinimumDepositPercent)
            refundApprovalLimit = String(format: "%.2f", prefs.customOrderRefundApprovalLimit)
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    func canSave(sessionManager: SessionManager) -> Bool {
        let user = sessionManager.currentUser
        return user?.canAccess(.companyPreferences) == true
            || user?.canAccess(.customOrderDepositSettings) == true
            || user?.canAccess(.customOrderRefundApprovalSettings) == true
    }

    func save(sessionManager: SessionManager) async {
        isSaving = true
        defer { isSaving = false }

        do {
            try await service.saveCompanyPreferences(preferences, locationId: sessionManager.selectedStore?.id)
            message = "Saved company preferences."
        } catch {
            message = error.localizedDescription
        }
    }

    var preferences: CustomOrderCompanyPreferences {
        CustomOrderCompanyPreferences(
            companyName: companyName,
            receiptLogoURL: receiptLogoURL,
            receiptHeaderLine: receiptHeaderLine,
            receiptFooterLine: receiptFooterLine,
            showReceiptLogo: showReceiptLogo,
            showSaleIdOnReceipt: showSaleIdOnReceipt,
            showDeviceIdOnReceipt: showDeviceIdOnReceipt,
            showCustomerOnReceipt: showCustomerOnReceipt,
            showSkuOnReceipt: showSkuOnReceipt,
            showItemDiscountsOnReceipt: showItemDiscountsOnReceipt,
            showPaymentStatusOnReceipt: showPaymentStatusOnReceipt,
            nextReceiptCounter: max(Int(nextReceiptCounter) ?? 1, 1),
            customOrderSlipEnabled: customOrderSlipEnabled,
            customOrderSlipAutoPrint: customOrderSlipAutoPrint,
            customOrderSlipTitle: customOrderSlipTitle,
            customOrderSlipContactLine: customOrderSlipContactLine,
            customOrderSlipEmailLine: customOrderSlipEmailLine,
            customOrderSlipFooterNote: customOrderSlipFooterNote,
            customOrderSlipBlankDetailLines: Int(customOrderSlipBlankDetailLines) ?? 4,
            customOrderSlipShowLogo: customOrderSlipShowLogo,
            customOrderSlipShowOrderNumber: customOrderSlipShowOrderNumber,
            customOrderSlipShowDueDate: customOrderSlipShowDueDate,
            customOrderSlipShowCustomerPhone: customOrderSlipShowCustomerPhone,
            customOrderSlipShowCustomerAccount: customOrderSlipShowCustomerAccount,
            customOrderSlipShowStore: customOrderSlipShowStore,
            customOrderSlipShowDevice: customOrderSlipShowDevice,
            customOrderSlipShowCashier: customOrderSlipShowCashier,
            customOrderSlipShowLineItems: customOrderSlipShowLineItems,
            customOrderSlipShowPricing: customOrderSlipShowPricing,
            customOrderSlipShowPaymentSummary: customOrderSlipShowPaymentSummary,
            customOrderSlipShowPaymentReference: customOrderSlipShowPaymentReference,
            customOrderSlipShowTakenBy: customOrderSlipShowTakenBy,
            customOrderSlipShowSignatures: customOrderSlipShowSignatures,
            customOrderMinimumDepositPercent: Double(minimumDepositPercent) ?? 0,
            customOrderRefundApprovalLimit: Double(refundApprovalLimit) ?? 0
        )
    }
}

struct CompanyIdentitySectionView: View {
    @ObservedObject var viewModel: CompanyPreferencesViewModel
    let canEdit: Bool

    var body: some View {
        Form {
            if let message = viewModel.message {
                Section { Text(message).foregroundStyle(message.hasPrefix("Saved") ? .green : .red) }
            }
            Section("Company Identity") {
                TextField("Company name", text: $viewModel.companyName)
                TextField("Receipt logo URL", text: $viewModel.receiptLogoURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                logoPreviewImage(urlString: viewModel.receiptLogoURL, isVisible: true)
            }
            .disabled(!canEdit)
        }
    }
}

struct SaleReceiptSectionView: View {
    @ObservedObject var viewModel: CompanyPreferencesViewModel
    let canEdit: Bool
    let storeName: String

    var body: some View {
        Form {
            if let message = viewModel.message {
                Section { Text(message).foregroundStyle(message.hasPrefix("Saved") ? .green : .red) }
            }
            Section("Receipt Formatting") {
                TextField("Header line", text: $viewModel.receiptHeaderLine)
                TextField("Footer line", text: $viewModel.receiptFooterLine)
                TextField("Receipt Counter Start", text: $viewModel.nextReceiptCounter)
                    .keyboardType(.numberPad)
                Toggle("Show logo on receipt", isOn: $viewModel.showReceiptLogo)
                Toggle("Show sale ID", isOn: $viewModel.showSaleIdOnReceipt)
                Toggle("Show device ID", isOn: $viewModel.showDeviceIdOnReceipt)
                Toggle("Show customer/account", isOn: $viewModel.showCustomerOnReceipt)
                Toggle("Show SKU", isOn: $viewModel.showSkuOnReceipt)
                Toggle("Show item discounts", isOn: $viewModel.showItemDiscountsOnReceipt)
                Toggle("Show payment status", isOn: $viewModel.showPaymentStatusOnReceipt)
            }
            .disabled(!canEdit)

            Section("40-Column Sample") {
                ScrollView(.horizontal) {
                    VStack(spacing: 8) {
                        logoPreviewImage(urlString: viewModel.receiptLogoURL, isVisible: viewModel.showReceiptLogo)
                        Text(sampleReceiptText)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    private var sampleReceiptText: String {
        ReceiptPrintingService.fortyColumnText(
            for: ReceiptPrintPayload(
                saleId: 12345,
                receiptNumber: "0001-0001-000123",
                date: Date(timeIntervalSince1970: 1_776_790_275),
                cashierName: "Sample Cashier",
                deviceId: "0001",
                customerName: "Alex Customer",
                storeName: storeName,
                paymentMethod: "CASH",
                paymentStatus: "PAID",
                amountPaid: 21.37,
                cashCollected: 25.00,
                changeDue: 3.63,
                subtotal: 22.50,
                discountAmount: 1.13,
                total: 21.37,
                items: [
                    ReceiptPrintLineItem(name: "Salted Chips", sku: "CHIP-001", quantity: 2, unitPrice: 2.38, discountAmount: 0.24),
                    ReceiptPrintLineItem(name: "Sparkling Water", sku: "DRINK-010", quantity: 3, unitPrice: 1.43, discountAmount: 0),
                    ReceiptPrintLineItem(name: "Notebook", sku: "NOTE-200", quantity: 1, unitPrice: 12.32, discountAmount: 0)
                ]
            ),
            preferences: viewModel.preferences
        )
    }
}

struct CustomOrderDepositSectionView: View {
    @ObservedObject var viewModel: CompanyPreferencesViewModel
    let canEditDeposit: Bool
    let canEditRefundApproval: Bool

    var body: some View {
        Form {
            if let message = viewModel.message {
                Section { Text(message).foregroundStyle(message.hasPrefix("Saved") ? .green : .red) }
            }
            Section("Order Deposit & Refund Approval") {
                LabeledContent("Minimum deposit %") {
                    TextField("0.00", text: $viewModel.minimumDepositPercent)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .disabled(!canEditDeposit)
                }

                LabeledContent("Refund approval limit") {
                    TextField("0.00", text: $viewModel.refundApprovalLimit)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .disabled(!canEditRefundApproval)
                }
            }
        }
    }
}

struct CustomOrderReceiptSectionView: View {
    @ObservedObject var viewModel: CompanyPreferencesViewModel
    let canEdit: Bool
    let storeName: String

    var body: some View {
        Form {
            if let message = viewModel.message {
                Section { Text(message).foregroundStyle(message.hasPrefix("Saved") ? .green : .red) }
            }
            Section("Slip Behavior") {
                Toggle("Enable custom order slips", isOn: $viewModel.customOrderSlipEnabled)
                Toggle("Auto-print after saving custom order", isOn: $viewModel.customOrderSlipAutoPrint)
                TextField("Slip title", text: $viewModel.customOrderSlipTitle)
                TextField("Contact line", text: $viewModel.customOrderSlipContactLine)
                TextField("Email line", text: $viewModel.customOrderSlipEmailLine)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                TextField("Footer note", text: $viewModel.customOrderSlipFooterNote, axis: .vertical)
                LabeledContent("Blank detail lines") {
                    TextField("4", text: $viewModel.customOrderSlipBlankDetailLines)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
            }
            .disabled(!canEdit)

            Section("Slip Fields") {
                Toggle("Show logo", isOn: $viewModel.customOrderSlipShowLogo)
                Toggle("Show order number", isOn: $viewModel.customOrderSlipShowOrderNumber)
                Toggle("Show due date", isOn: $viewModel.customOrderSlipShowDueDate)
                Toggle("Show customer phone", isOn: $viewModel.customOrderSlipShowCustomerPhone)
                Toggle("Show customer account number", isOn: $viewModel.customOrderSlipShowCustomerAccount)
                Toggle("Show store/location", isOn: $viewModel.customOrderSlipShowStore)
                Toggle("Show device", isOn: $viewModel.customOrderSlipShowDevice)
                Toggle("Show cashier", isOn: $viewModel.customOrderSlipShowCashier)
                Toggle("Show line items", isOn: $viewModel.customOrderSlipShowLineItems)
                Toggle("Show pricing", isOn: $viewModel.customOrderSlipShowPricing)
                Toggle("Show payment summary", isOn: $viewModel.customOrderSlipShowPaymentSummary)
                Toggle("Show payment reference", isOn: $viewModel.customOrderSlipShowPaymentReference)
                Toggle("Show taken/delivered by", isOn: $viewModel.customOrderSlipShowTakenBy)
                Toggle("Show signature lines", isOn: $viewModel.customOrderSlipShowSignatures)
            }
            .disabled(!canEdit)

            Section("Letter Slip Preview") {
                letterSlipPreview
            }

            Section("40-Column Slip Preview") {
                ScrollView(.horizontal) {
                    VStack(spacing: 8) {
                        logoPreviewImage(urlString: viewModel.receiptLogoURL, isVisible: viewModel.customOrderSlipShowLogo)
                        Text(CustomOrderSlipPrintingService.fortyColumnText(for: sampleSlipPayload, preferences: viewModel.preferences))
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    private var letterSlipPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                logoPreviewImage(urlString: viewModel.receiptLogoURL, isVisible: viewModel.customOrderSlipShowLogo, compact: true)
                VStack(alignment: .leading) {
                    Text(viewModel.customOrderSlipTitle)
                        .font(.headline)
                    Text(viewModel.companyName)
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                Text("Letter")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow { Text("Order"); Text("CO-000123").fontWeight(.semibold) }
                GridRow { Text("Customer"); Text("Alex Customer").fontWeight(.semibold) }
                GridRow { Text("Due"); Text("May 30, 2026").fontWeight(.semibold) }
            }
        }
        .padding(.vertical, 6)
    }

    private var sampleSlipPayload: CustomOrderSlipPayload {
        CustomOrderSlipPayload(order: CustomOrder.sampleSlipOrder, customerAccountNumber: "C-000100", storeName: storeName, deviceName: "POS-DEMO", cashierName: "Sample Cashier")
    }
}

@ViewBuilder
private func logoPreviewImage(urlString: String, isVisible: Bool, compact: Bool = false) -> some View {
    if isVisible {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = logoPreviewURL(urlString), !trimmedURL.isEmpty {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(width: compact ? 60 : 180, height: compact ? 36 : 70)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: compact ? 70 : 190, height: compact ? 42 : 76)
                case .failure:
                    Label("Logo URL could not load", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                @unknown default:
                    EmptyView()
                }
            }
            .frame(maxWidth: compact ? 80 : .infinity, alignment: .center)
        } else if !compact {
            Text("No logo URL saved")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private func logoPreviewURL(_ value: String) -> URL? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let url = URL(string: trimmed) { return url }
    return trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).flatMap(URL.init(string:))
}

private extension CustomOrder {
    static var sampleSlipOrder: CustomOrder {
        let json = """
        {
          "custom_order_id": 123,
          "order_number": "CO-000123",
          "customer_id": 100,
          "customer_name": "Alex Customer",
          "customer_phone": "555-0100",
          "status": "NEW",
          "payment_status": "PARTIAL",
          "payment_method": "CASH",
          "payment_reference": "DEP-123",
          "due_date": "2026-05-30",
          "order_notes": "Rush if possible.",
          "total_amount": 85.00,
          "amount_paid": 25.00,
          "refunded_amount": 0,
          "balance_due": 60.00,
          "location_name": "Main Store",
          "device_name": "POS-DEMO",
          "taken_by_name": "Sample Cashier",
          "created_at": "2026-05-22T10:30:00Z",
          "custom_order_payments": [],
          "custom_order_lines": [
            {
              "custom_order_line_id": 1,
              "custom_order_id": 123,
              "custom_item_id": 10,
              "item_name": "Custom Hoodie",
              "variant_name": "Large / Black",
              "pricing_type": "FIXED",
              "quantity": 1,
              "unit_price": 85.00,
              "original_line_total": 85.00,
              "line_discount_percent": 0,
              "line_discount_amount": 0,
              "line_total": 85.00,
              "customization_details": "Front logo, white vinyl",
              "order_instructions": "Customer will pick up.",
              "delivery_status": "PENDING",
              "production_status": "NOT_STARTED",
              "custom_order_line_print_addons": [],
              "custom_order_line_returns": []
            }
          ]
        }
        """
        return try! JSONDecoder().decode(CustomOrder.self, from: Data(json.utf8))
    }
}
