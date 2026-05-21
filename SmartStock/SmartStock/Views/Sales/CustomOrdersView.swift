//
//  CustomOrdersView.swift
//  SmartStock
//

import SwiftUI
import Supabase
#if canImport(UIKit)
import UIKit
#endif

struct CustomOrdersView: View {
    @EnvironmentObject private var sessionManager: SessionManager

    var body: some View {
        TabView {
            if can(.createCustomOrder) {
                CustomOrderEntryView()
                    .tabItem { Label("New", systemImage: "plus.circle.fill") }
            }

            CustomOrderListView(title: "Lookup", scope: .lookup(""))
                .tabItem { Label("Lookup", systemImage: "magnifyingglass") }

            if let userId = sessionManager.currentUser?.id, can(.viewAssignedCustomOrders) {
                CustomOrderListView(title: "My Orders", scope: .assigned(userId: userId))
                    .tabItem { Label("Mine", systemImage: "person.crop.circle") }
            }

            if can(.manageCustomOrders) {
                CustomOrderListView(title: "All Orders", scope: .all, readOnly: true)
                    .tabItem { Label("All", systemImage: "tray.full.fill") }
            }

            if can(.ordersManagerDashboard) || can(.manageCustomOrders) {
                CustomOrderManagerDashboardView()
                    .tabItem { Label("Manager", systemImage: "chart.bar.doc.horizontal") }
            }

            if can(.ordersEndOfDay) {
                CustomOrderEndOfDayView()
                    .tabItem { Label("EOD", systemImage: "checkmark.seal.fill") }
            }
        }
        .navigationTitle("Custom Orders")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func can(_ permission: MobilePermission) -> Bool {
        sessionManager.currentUser?.canAccess(permission) == true
    }
}

private struct CustomOrderListView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    private let service = CustomOrderService()

    let title: String
    let scope: CustomOrderService.OrderScope
    var readOnly = false

    @State private var orders: [CustomOrder] = []
    @State private var lookupText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedOrder: CustomOrder?

    var body: some View {
        List {
            if case .lookup = scope {
                Section {
                    HStack {
                        TextField("Order, customer, or phone", text: $lookupText)
                            .textInputAutocapitalization(.never)
                        Button {
                            Task { await loadOrders() }
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }

            Section {
                ForEach(orders) { order in
                    Button { selectedOrder = order } label: {
                        HStack {
                            CustomOrderRow(order: order)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .overlay {
            if isLoading && orders.isEmpty {
                ProgressView("Loading orders...")
            } else if orders.isEmpty && errorMessage == nil {
                ContentUnavailableView(title, systemImage: "list.clipboard", description: Text("No custom orders found."))
            }
        }
        .navigationTitle(title)
        .sheet(item: $selectedOrder) { order in
            CustomOrderDetailView(order: order, readOnly: readOnly) {
                await loadOrders()
            }
            .environmentObject(sessionManager)
        }
        .task { await loadOrders() }
        .refreshable { await loadOrders() }
    }

    private func loadOrders() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if case .lookup = scope {
                orders = lookupText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : try await service.fetchOrders(scope: .lookup(lookupText))
            } else {
                orders = try await service.fetchOrders(scope: scope)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CustomOrderRow: View {
    let order: CustomOrder

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(order.displayNumber)
                    .font(.headline)
                Spacer()
                Text(order.status.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusTint)
            }

            Text(order.customerName)
                .font(.subheadline)

            HStack {
                Text(order.totalText)
                Text(order.paymentStatus.title)
                Text("Balance \(order.balanceText)")
                if let locationName = order.locationName {
                    Text(locationName)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var statusTint: Color {
        switch order.status {
        case .new: return .blue
        case .assigned, .inProgress: return .orange
        case .ready: return .purple
        case .delivered, .completed: return .green
        case .cancelled: return .red
        }
    }
}

private struct LineDiscountSheetSelection: Identifiable {
    let id = UUID()
    let lineIndex: Int
    let line: CustomOrderDraftLine
}

private struct CustomOrderEntryView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    private let service = CustomOrderService()

    @State private var customerAccounts: [CustomerAccount] = []
    @State private var customItems: [CustomOrderItem] = []
    @State private var printMaterials: [CustomOrderPrintMaterial] = []
    @State private var printPresets: [CustomOrderPrintSizePreset] = []
    @State private var designPlacements: [CustomOrderDesignPlacement] = []
    @State private var preferences = CustomOrderCompanyPreferences(customOrderMinimumDepositPercent: 0, customOrderRefundApprovalLimit: 0)
    @State private var selectedCustomerId: Int?
    @State private var customerName = ""
    @State private var customerPhone = ""
    @State private var selectedItemId: Int64?
    @State private var selectedVariantId: Int64?
    @State private var selectedItemVariants: [CustomOrderItemVariant] = []
    @State private var itemLookupText = ""
    @State private var isLoadingVariants = false
    @State private var selectedDesignPlacementId: Int64?
    @State private var designPlacementText = ""
    @State private var draftLine = CustomOrderDraftLine(item: PlaceholderCustomOrderItem.item)
    @State private var dueDate = Date()
    @State private var hasDueDate = false
    @State private var orderNotes = ""
    @State private var paymentMethod: CustomOrderPaymentMethod = .cash
    @State private var paymentAmountText = ""
    @State private var paymentReference = ""
    @State private var depositOverrideReason = ""
    @State private var lines: [CustomOrderDraftLine] = []
    @State private var discountSelection: LineDiscountSheetSelection?
    @State private var discountPercentText = ""
    @State private var discountReason = ""
    @State private var discountErrorMessage: String?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var createdOrderMessage: String?

    var body: some View {
        Form {
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            if let createdOrderMessage { Section { Text(createdOrderMessage).foregroundStyle(.green) } }

                Section("Customer") {
                    Picker("Existing Customer", selection: $selectedCustomerId) {
                        Text("New customer").tag(Int?.none)
                        ForEach(customerAccounts.filter(\.isActive)) { customer in
                            Text(customer.name).tag(Int?.some(customer.customerId))
                        }
                    }
                    .onChange(of: selectedCustomerId) { _, _ in fillSelectedCustomer() }

                    TextField("Customer name", text: $customerName)
                    TextField("Phone number", text: $customerPhone)
                        .keyboardType(.phonePad)
                }

                Section("Add Line") {
                    HStack {
                        TextField("Scan SKU or barcode", text: $itemLookupText)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled(true)
                        Button {
                            Task { await applyItemLookup() }
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .buttonStyle(.bordered)
                        .disabled(itemLookupText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    Picker("Item", selection: $selectedItemId) {
                        Text("Select item").tag(Int64?.none)
                        ForEach(customItems.filter(\.isActive)) { item in
                            Text("\(item.itemName) - \(item.displaySku) - \(item.priceText)").tag(Int64?.some(item.customItemId))
                        }
                    }
                    .onChange(of: selectedItemId) { _, _ in
                        Task { await resetDraftLineForSelectedItem() }
                    }

                    if let selectedItem, selectedItem.hasVariants {
                        Picker("Variant", selection: $selectedVariantId) {
                            Text("Select variant").tag(Int64?.none)
                            ForEach(availableVariants) { variant in
                                Text("\(variant.variantName) - \(variant.displaySku) - \(variant.priceText)").tag(Int64?.some(variant.variantId))
                            }
                        }
                        .onChange(of: selectedVariantId) { _, _ in resetDraftLine(keepItem: true) }
                        .task(id: selectedItem.customItemId) {
                            await loadVariants(for: selectedItem)
                        }

                        if isLoadingVariants {
                            ProgressView("Loading variants...")
                        } else if availableVariants.isEmpty {
                            Text("No variants found for this item.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if selectedItem?.pricingType == .variable {
                        TextField("Manual price", text: $draftLine.unitPriceText)
                            .keyboardType(.decimalPad)
                        if draftLine.hasPriceOverride {
                            TextField("Price override reason", text: $draftLine.priceOverrideReason, axis: .vertical)
                        }
                    }

                    if selectedItem?.pricingType == .area {
                        HStack {
                            TextField("Width", text: $draftLine.widthText).keyboardType(.decimalPad)
                            TextField("Length", text: $draftLine.lengthText).keyboardType(.decimalPad)
                        }
                        HStack {
                            TextField("Dimension unit", text: $draftLine.dimensionUnit)
                            TextField("Area unit", text: $draftLine.areaUnit)
                        }
                        TextField("Area price", text: $draftLine.areaPriceText)
                            .keyboardType(.decimalPad)
                        if draftLine.hasPriceOverride {
                            TextField("Price override reason", text: $draftLine.priceOverrideReason, axis: .vertical)
                        }

                        if let unitPrice = draftLine.unitPrice {
                            LabeledContent("Calculated area", value: draftLine.areaText)
                            LabeledContent("Calculated price", value: String(format: "$%.2f", unitPrice))
                        }
                    }

                    DisclosureGroup("Print Add Ons") {
                        ForEach(draftLine.printAddons.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 10) {
                                Picker("Material", selection: materialSelectionBinding(for: index)) {
                                    Text("Select material").tag(Int64?.none)
                                    ForEach(printMaterials) { material in
                                        Text(material.materialName).tag(Int64?.some(material.materialId))
                                    }
                                }

                                Picker("Print Size", selection: presetSelectionBinding(for: index)) {
                                    Text("Custom size / price").tag(Int64?.none)
                                    ForEach(presetsForAddon(at: index)) { preset in
                                        Text("\(preset.presetName) - \(preset.priceText)").tag(Int64?.some(preset.presetId))
                                    }
                                }

                                if draftLine.printAddons[index].preset == nil {
                                    Picker("Pricing", selection: $draftLine.printAddons[index].pricingMode) {
                                        Text("Fixed").tag("FIXED_PRESET")
                                        Text("By Lines").tag("PER_LINE")
                                    }
                                    .pickerStyle(.segmented)
                                } else {
                                    LabeledContent("Pricing", value: draftLine.printAddons[index].pricingMode == "PER_LINE" ? "By Lines" : "Fixed")
                                }

                                TextField(pricePlaceholder(for: draftLine.printAddons[index]), text: $draftLine.printAddons[index].priceText)
                                    .keyboardType(.decimalPad)

                                if draftLine.printAddons[index].pricingMode == "PER_LINE" {
                                    TextField("Number of print lines", text: $draftLine.printAddons[index].lineCountText)
                                        .keyboardType(.numberPad)
                                }

                                TextField("Print description", text: $draftLine.printAddons[index].printDescription, axis: .vertical)

                                HStack {
                                    Text(addonSummary(draftLine.printAddons[index]))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button(role: .destructive) {
                                        draftLine.printAddons.remove(at: index)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        Button {
                            draftLine.printAddons.append(newPrintAddonDraft())
                        } label: {
                            Label("Add Print Add On", systemImage: "plus.circle")
                        }
                    }

                    if designPlacements.isEmpty {
                        Text("No design placements found.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Design Placement", selection: $selectedDesignPlacementId) {
                            Text("Select placement").tag(Int64?.none)
                            ForEach(designPlacements) { placement in
                                Text(placement.placementName).tag(Int64?.some(placement.designPlacementId))
                            }
                        }

                        TextField("What goes here", text: $designPlacementText, axis: .vertical)

                        Button {
                            addDesignPlacementNote()
                        } label: {
                            Label("Add Placement", systemImage: "plus.circle")
                        }
                        .disabled(selectedDesignPlacementId == nil || designPlacementText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    TextField("Order instructions", text: $draftLine.lineNotes, axis: .vertical)

                    if selectedItem != nil {
                        LabeledContent("Line total", value: String(format: "$%.2f", draftLine.lineTotal))
                    }

                    TextField("Quantity", text: $draftLine.quantityText)
                        .keyboardType(.numberPad)

                    Button {
                        addLine()
                    } label: {
                        Label("Add Line", systemImage: "plus.circle")
                    }
                    .disabled(selectedItem == nil || (selectedItem?.hasVariants == true && selectedVariant == nil))
                }

                if !lines.isEmpty {
                    Section("Lines") {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(line.variant.map { "\(line.item.itemName) - \($0.variantName)" } ?? line.item.itemName)
                                        .font(.headline)
                                    Spacer()
                                    Text(String(format: "$%.2f", line.lineTotal))
                                        .font(.subheadline.weight(.semibold))
                                }
                                HStack {
                                    Text("Qty \(line.quantityText)")
                                    if line.discountPercent > 0 {
                                        Text("Discount \(line.discountPercent, specifier: "%.1f")%")
                                    }
                                    if !line.printAddons.isEmpty {
                                        Text("Print \(line.printAddons.count)")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    if discountSelection?.lineIndex == index {
                                        discountSelection = nil
                                    }
                                    lines.remove(at: index)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }

                                Button {
                                    openDiscountSheet(forLineAt: index)
                                } label: {
                                    Label("Discount", systemImage: "percent")
                                }
                                .tint(.blue)
                            }
                        }
                        .onDelete { lines.remove(atOffsets: $0) }

                        LabeledContent("Total", value: String(format: "$%.2f", orderTotal))
                        LabeledContent("Minimum deposit", value: String(format: "$%.2f", minimumDepositRequired))
                    }
                }

                Section("Order") {
                    Toggle("Due date", isOn: $hasDueDate)
                    if hasDueDate { DatePicker("Due", selection: $dueDate, displayedComponents: .date) }
                    TextField("Order notes", text: $orderNotes, axis: .vertical)
                }

                Section("Payment") {
                    Picker("Method", selection: $paymentMethod) {
                        ForEach(CustomOrderPaymentMethod.allCases) { method in
                            Text(method.title).tag(method)
                        }
                    }
                    TextField("Upfront payment", text: $paymentAmountText)
                        .keyboardType(.decimalPad)
                    if paymentMethod.requiresReference {
                        TextField("Payment reference", text: $paymentReference)
                    }
                    if upfrontPayment + 0.0001 < minimumDepositRequired {
                        TextField("Deposit override reason", text: $depositOverrideReason, axis: .vertical)
                    }
                }

                Button {
                    Task { await save() }
                } label: {
                    Label(isSaving ? "Creating" : "Create Custom Order", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(isSaving || lines.isEmpty)
        }
        .navigationTitle("New Custom Order")
        .dismissKeyboardOnTap()
        .scrollDismissesKeyboard(.interactively)
        .task { await loadLookups() }
        .sheet(item: $discountSelection) { selection in
            discountSheet(for: selection)
        }
    }

    private var selectedCustomer: CustomerAccount? {
        guard let selectedCustomerId else { return nil }
        return customerAccounts.first { $0.customerId == selectedCustomerId }
    }

    private var selectedItem: CustomOrderItem? {
        guard let selectedItemId else { return nil }
        return customItems.first { $0.customItemId == selectedItemId }
    }

    private var selectedVariant: CustomOrderItemVariant? {
        guard let selectedVariantId else { return nil }
        return availableVariants.first { $0.variantId == selectedVariantId }
    }

    private var availableVariants: [CustomOrderItemVariant] {
        let embedded = selectedItem?.variants.filter(\.isActive) ?? []
        return selectedItemVariants.isEmpty ? embedded : selectedItemVariants
    }

    private var orderTotal: Double { lines.reduce(0) { $0 + $1.lineTotal } }
    private var upfrontPayment: Double { Double(paymentAmountText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0 }
    private var minimumDepositRequired: Double { orderTotal * preferences.customOrderMinimumDepositPercent / 100 }

    @ViewBuilder
    private func discountSheet(for selection: LineDiscountSheetSelection) -> some View {
        NavigationStack {
            Form {
                if let discountErrorMessage {
                    Section {
                        Text(discountErrorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section("Line") {
                    LabeledContent("Item", value: selection.line.variant.map { "\(selection.line.item.itemName) - \($0.variantName)" } ?? selection.line.item.itemName)
                    LabeledContent("Original total", value: String(format: "$%.2f", selection.line.originalLineTotal))
                }

                Section("Discount") {
                    TextField("Discount percent", text: $discountPercentText)
                        .keyboardType(.decimalPad)

                    if let percent = Double(discountPercentText.trimmingCharacters(in: .whitespacesAndNewlines)), percent > 0 {
                        let discountAmount = selection.line.originalLineTotal * min(max(percent, 0), 100) / 100
                        LabeledContent("Discount amount", value: String(format: "$%.2f", discountAmount))
                        LabeledContent("New line total", value: String(format: "$%.2f", max(selection.line.originalLineTotal - discountAmount, 0)))
                    }

                    TextField("Discount reason", text: $discountReason, axis: .vertical)
                }
            }
            .navigationTitle("Line Discount")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        discountSelection = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        applyDiscount()
                    }
                }
            }
            .dismissKeyboardOnTap()
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func loadLookups() async {
        do {
            async let customers: [CustomerAccount] = supabase
                .from("customer_accounts")
                .select("customer_id, account_number, name, phone, email, credit_limit, current_balance, is_active, is_business, account_notes, customer_type_id, created_at")
                .order("name", ascending: true)
                .execute()
                .value
            async let items = service.fetchItems(activeOnly: true)
            async let materials = service.fetchPrintMaterials(activeOnly: true)
            async let presets = service.fetchPrintSizePresets(activeOnly: true)
            async let placements = service.fetchDesignPlacements(activeOnly: true)
            async let prefs = service.fetchCompanyPreferences(locationId: sessionManager.selectedStore?.id)

            customerAccounts = try await customers
            customItems = try await items
            printMaterials = try await materials
            printPresets = try await presets
            designPlacements = try await placements
            selectedDesignPlacementId = selectedDesignPlacementId ?? designPlacements.first?.designPlacementId
            preferences = try await prefs
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fillSelectedCustomer() {
        guard let selectedCustomer else { return }
        customerName = selectedCustomer.name
        customerPhone = selectedCustomer.phone ?? ""
    }

    private func applyItemLookup() async {
        let lookup = itemLookupText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lookup.isEmpty else { return }

        do {
            let result = try await service.searchCustomOrderItemSelection(lookup)
            guard let item = result.item else {
                errorMessage = "No custom order item found for \(lookup)."
                return
            }

            if !customItems.contains(where: { $0.customItemId == item.customItemId }) {
                customItems.append(item)
            }
            selectedItemId = item.customItemId
            selectedItemVariants = []
            selectedVariantId = nil
            if item.hasVariants {
                await loadVariants(for: item)
                if let variant = result.variant {
                    selectedVariantId = variant.variantId
                }
            }
            resetDraftLine()
            itemLookupText = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetDraftLineForSelectedItem() async {
        selectedVariantId = nil
        selectedItemVariants = []
        guard let selectedItem else { return }

        if selectedItem.hasVariants {
            await loadVariants(for: selectedItem)
        }

        resetDraftLine()
    }

    private func loadVariants(for item: CustomOrderItem) async {
        guard item.hasVariants else { return }
        isLoadingVariants = true
        defer { isLoadingVariants = false }

        do {
            let variants = try await service.fetchVariants(customItemId: item.customItemId, activeOnly: false)
            guard selectedItemId == item.customItemId else { return }
            selectedItemVariants = variants
            if selectedVariantId == nil, variants.count == 1 {
                selectedVariantId = variants.first?.variantId
                resetDraftLine(keepItem: true)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func materialSelectionBinding(for index: Int) -> Binding<Int64?> {
        Binding {
            guard draftLine.printAddons.indices.contains(index) else { return nil }
            return draftLine.printAddons[index].material?.materialId
        } set: { materialId in
            guard draftLine.printAddons.indices.contains(index) else { return }
            draftLine.printAddons[index].material = printMaterials.first { $0.materialId == materialId }
            draftLine.printAddons[index].preset = nil
            draftLine.printAddons[index].pricingMode = "FIXED_PRESET"
            draftLine.printAddons[index].priceText = ""
        }
    }

    private func presetSelectionBinding(for index: Int) -> Binding<Int64?> {
        Binding {
            guard draftLine.printAddons.indices.contains(index) else { return nil }
            return draftLine.printAddons[index].preset?.presetId
        } set: { presetId in
            guard draftLine.printAddons.indices.contains(index) else { return }
            let preset = presetsForAddon(at: index).first { $0.presetId == presetId }
            draftLine.printAddons[index].preset = preset
            draftLine.printAddons[index].pricingMode = preset?.pricingMode ?? "FIXED_PRESET"
            draftLine.printAddons[index].priceText = preset?.fixedPrice.map { String(format: "%.2f", $0) } ?? ""
        }
    }

    private func presetsForAddon(at index: Int) -> [CustomOrderPrintSizePreset] {
        guard draftLine.printAddons.indices.contains(index),
              let materialId = draftLine.printAddons[index].material?.materialId else {
            return []
        }
        return printPresets.filter { $0.materialId == materialId }
    }

    private func newPrintAddonDraft() -> CustomOrderPrintAddonDraft {
        let material = printMaterials.first
        let preset = printPresets.first { $0.materialId == material?.materialId }
        return CustomOrderPrintAddonDraft(
            material: material,
            preset: preset,
            pricingMode: preset?.pricingMode ?? "FIXED_PRESET",
            printDescription: "",
            priceText: preset?.fixedPrice.map { String(format: "%.2f", $0) } ?? "",
            lineCountText: "1"
        )
    }

    private func pricePlaceholder(for addon: CustomOrderPrintAddonDraft) -> String {
        if addon.pricingMode == "PER_LINE" {
            return "Print price per line"
        }
        return "Print price"
    }

    private func addonSummary(_ addon: CustomOrderPrintAddonDraft) -> String {
        if addon.pricingMode == "PER_LINE" {
            return "\(addon.lineCount) lines x \(addon.unitPriceText) = \(String(format: "$%.2f", addon.price))"
        }
        return "Fixed total \(String(format: "$%.2f", addon.price))"
    }

    private func addDesignPlacementNote() {
        guard let selectedDesignPlacementId,
              let placement = designPlacements.first(where: { $0.designPlacementId == selectedDesignPlacementId }) else {
            return
        }

        let note = designPlacementText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { return }

        let placementLine = "\(placement.placementName): \(note)"
        let existingInstructions = draftLine.lineNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        draftLine.lineNotes = existingInstructions.isEmpty ? placementLine : "\(existingInstructions)\n\(placementLine)"
        designPlacementText = ""
    }

    private func openDiscountSheet(forLineAt index: Int) {
        guard lines.indices.contains(index) else { return }
        let line = lines[index]
        discountSelection = LineDiscountSheetSelection(lineIndex: index, line: line)
        discountPercentText = line.discountPercentText
        discountReason = line.discountReason
        discountErrorMessage = nil
    }

    private func applyDiscount() {
        guard let discountSelection else { return }
        guard lines.indices.contains(discountSelection.lineIndex) else {
            self.discountSelection = nil
            return
        }

        let trimmedPercent = discountPercentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let percent = Double(trimmedPercent) ?? 0
        guard percent >= 0 && percent <= 100 else {
            discountErrorMessage = "Discount percent must be between 0 and 100."
            return
        }

        let trimmedReason = discountReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard percent == 0 || !trimmedReason.isEmpty else {
            discountErrorMessage = "Discount reason is required."
            return
        }

        lines[discountSelection.lineIndex].discountPercentText = percent == 0 ? "" : String(format: "%.2f", percent)
        lines[discountSelection.lineIndex].discountReason = percent == 0 ? "" : trimmedReason
        discountErrorMessage = nil
        self.discountSelection = nil
    }

    private func resetDraftLine(keepItem: Bool = false) {
        guard let selectedItem else { return }
        let variant = selectedVariant
        draftLine = CustomOrderDraftLine(item: selectedItem, variant: variant)
        if selectedItem.pricingType == .area {
            draftLine.areaPriceText = draftLine.basePrice.map { String(format: "%.2f", $0) } ?? ""
        }
    }

    private func addLine() {
        guard selectedItem != nil else { return }
        if draftLine.unitPrice == nil {
            errorMessage = "Enter valid line pricing."
            return
        }

        let trimmedQuantity = draftLine.quantityText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let quantity = Int(trimmedQuantity),
              let numericQuantity = Double(trimmedQuantity),
              quantity > 0,
              Double(quantity) == numericQuantity else {
            errorMessage = "Quantity must be a whole number."
            return
        }

        for _ in 0..<quantity {
            lines.append(draftLine.singleQuantityCopy())
        }

        selectedItemId = nil
        selectedVariantId = nil
        designPlacementText = ""
        draftLine = CustomOrderDraftLine(item: PlaceholderCustomOrderItem.item)
        errorMessage = nil
    }

    private func save() async {
        guard let user = sessionManager.currentUser else { return }
        isSaving = true
        errorMessage = nil
        createdOrderMessage = nil
        defer { isSaving = false }

        do {
            let result = try await service.createOrder(
                customer: selectedCustomer,
                customerName: customerName,
                customerPhone: customerPhone,
                dueDate: hasDueDate ? dueDate : nil,
                notes: orderNotes,
                lines: lines,
                paymentMethod: paymentMethod,
                paymentAmount: upfrontPayment,
                paymentReference: paymentReference,
                depositOverrideReason: depositOverrideReason,
                user: user,
                store: sessionManager.selectedStore,
                device: sessionManager.currentDevice
            )
            createdOrderMessage = "Created custom order #\(result.orderId)."
            lines = []
            paymentAmountText = ""
            paymentReference = ""
            depositOverrideReason = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CustomOrderDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionManager: SessionManager
    private let service = CustomOrderService()

    let order: CustomOrder
    var readOnly = false
    let onSaved: () async -> Void

    @State private var employees: [CustomOrderEmployee] = []
    @State private var selectedEmployeeId: Int?
    @State private var selectedStatus: CustomOrderStatus
    @State private var productionNotes = ""
    @State private var deliveryNotes = ""
    @State private var refundReason = "Payment Mistake"
    @State private var refundAmountText = ""
    @State private var paymentMethod: CustomOrderPaymentMethod = .cash
    @State private var paymentAmountText = ""
    @State private var paymentReference = ""
    @State private var cancelReason = ""
    @State private var auditLog: [CustomOrderAuditEntry] = []
    @State private var statusHistory: [CustomOrderStatusHistoryEntry] = []
    @State private var deliveryHistory: [CustomOrderLineDeliveryHistoryEntry] = []
    @State private var productionHistory: [CustomOrderLineProductionHistoryEntry] = []
    @State private var errorMessage: String?
    @State private var actionInProgress = false
    @State private var isLinesExpanded = true
    @State private var isPaymentsExpanded = false
    @State private var isStatusHistoryExpanded = false
    @State private var isProductionHistoryExpanded = false
    @State private var isDeliveryHistoryExpanded = false
    @State private var isAuditHistoryExpanded = false

    init(order: CustomOrder, readOnly: Bool = false, onSaved: @escaping () async -> Void) {
        self.order = order
        self.readOnly = readOnly
        self.onSaved = onSaved
        _selectedStatus = State(initialValue: order.status)
        _selectedEmployeeId = State(initialValue: order.assignedToUserId)
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }

                Section("Customer") {
                    CustomOrderSummaryRows(order: order)
                }

                Section {
                    DisclosureGroup(isExpanded: $isLinesExpanded) {
                        ForEach(order.lines) { line in
                            VStack(alignment: .leading, spacing: 14) {
                                CustomOrderLineDetailCard(line: line)
                                if !readOnly {
                                    lineActions(line)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } label: {
                        sectionHeader("Order Lines", count: order.lines.count)
                    }
                }

                Section {
                    DisclosureGroup(isExpanded: $isPaymentsExpanded) {
                        if order.payments.isEmpty {
                            Text("No payments recorded.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(order.payments) { payment in
                                VStack(alignment: .leading, spacing: 4) {
                                    LabeledContent(payment.paymentMethod.title, value: payment.amountText)
                                    if let reference = payment.paymentReference, !reference.isEmpty {
                                        Text("Reference: \(reference)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    historyCaption(nil, payment.takenByName, payment.createdAt, nil)
                                }
                            }
                        }
                    } label: {
                        sectionHeader("Payments", count: order.payments.count)
                    }
                }

                if !readOnly && order.balanceDue > 0 && (can(.createCustomOrder) || canManage) {
                    Section("Post-Order Payment") {
                        Picker("Method", selection: $paymentMethod) {
                            ForEach(CustomOrderPaymentMethod.allCases) { method in
                                Text(method.title).tag(method)
                            }
                        }
                        TextField("Amount", text: $paymentAmountText)
                            .keyboardType(.decimalPad)
                        if paymentMethod.requiresReference {
                            TextField("Payment reference", text: $paymentReference)
                        }
                        Button(actionInProgress ? "Recording..." : "Record Payment") { Task { await recordPayment() } }
                            .disabled(actionInProgress)
                    }
                }

                if canManage && !readOnly {
                    Section("Order Management") {
                        Picker("Assigned To", selection: $selectedEmployeeId) {
                            Text("Unassigned").tag(Int?.none)
                            ForEach(employees) { employee in
                                Text(employee.displayName).tag(Int?.some(employee.userId))
                            }
                        }
                        Picker("Status", selection: $selectedStatus) {
                            ForEach(CustomOrderStatus.allCases) { Text($0.title).tag($0) }
                        }
                        Button(actionInProgress ? "Updating..." : "Update Order") { Task { await updateOrderManagement() } }
                            .disabled(!hasManagementChanges || actionInProgress)
                    }
                }

                if !readOnly && (canCancelOrder || canRefundOrder) {
                    Section("Cancel / Refund") {
                        if canRefundOrder {
                            Picker("Refund reason", selection: $refundReason) {
                                Text("Payment Mistake").tag("Payment Mistake")
                                Text("Customer Return").tag("Customer Return")
                                Text("Quality Issue").tag("Quality Issue")
                                Text("Manager Approved").tag("Manager Approved")
                            }

                            TextField("Refund amount for selected line", text: $refundAmountText)
                                .keyboardType(.decimalPad)

                            Menu {
                                Button(role: .destructive) {
                                    Task { await refundAllLines() }
                                } label: {
                                    Label("All Lines", systemImage: "list.bullet.rectangle")
                                }

                                ForEach(order.lines) { line in
                                    Button(role: .destructive) {
                                        Task { await refund(line) }
                                    } label: {
                                        Text(line.displayName)
                                    }
                                }
                            } label: {
                                Label(actionInProgress ? "Processing..." : "Refund", systemImage: "arrow.uturn.backward.circle")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                            .disabled(actionInProgress || order.lines.isEmpty)
                        }

                        if canCancelOrder && order.status != .cancelled {
                            TextField("Cancellation reason", text: $cancelReason, axis: .vertical)
                            Button(role: .destructive) { Task { await cancelOrder() } } label: {
                                Text(actionInProgress ? "Cancelling..." : "Cancel Order")
                            }
                            .disabled(actionInProgress)
                        }
                    }
                }

                Section {
                    DisclosureGroup(isExpanded: $isStatusHistoryExpanded) {
                        if statusHistory.isEmpty {
                            Text("No status history yet.").foregroundStyle(.secondary)
                        } else {
                            ForEach(statusHistory) { entry in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(entry.oldStatus?.title ?? "Created") -> \(entry.newStatus.title)")
                                        .font(.subheadline.weight(.semibold))
                                    historyCaption(entry.reason, entry.userName, entry.createdAt, entry.deviceName)
                                }
                            }
                        }
                    } label: {
                        sectionHeader("Status History", count: statusHistory.count)
                    }
                }

                Section {
                    DisclosureGroup(isExpanded: $isProductionHistoryExpanded) {
                        if productionHistory.isEmpty {
                            Text("No production updates yet.").foregroundStyle(.secondary)
                        } else {
                            ForEach(productionHistory) { entry in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(entry.displayName): \(entry.oldStatus?.title ?? "Not Started") -> \(entry.newStatus.title)")
                                        .font(.subheadline.weight(.semibold))
                                    historyCaption(entry.notes, entry.updatedByName, entry.createdAt, entry.deviceName)
                                }
                            }
                        }
                    } label: {
                        sectionHeader("Production History", count: productionHistory.count)
                    }
                }

                Section {
                    DisclosureGroup(isExpanded: $isDeliveryHistoryExpanded) {
                        if deliveryHistory.isEmpty {
                            Text("No delivered lines yet.").foregroundStyle(.secondary)
                        } else {
                            ForEach(deliveryHistory) { entry in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.displayName).font(.subheadline.weight(.semibold))
                                    historyCaption(entry.deliveryNotes, entry.deliveredByName, entry.deliveredAt, entry.deviceName)
                                }
                            }
                        }
                    } label: {
                        sectionHeader("Delivery History", count: deliveryHistory.count)
                    }
                }

                Section {
                    DisclosureGroup(isExpanded: $isAuditHistoryExpanded) {
                        if auditLog.isEmpty {
                            Text("No audit entries yet.").foregroundStyle(.secondary)
                        } else {
                            ForEach(auditLog) { entry in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.title).font(.subheadline.weight(.semibold))
                                    if let field = entry.fieldName {
                                        Text("\(field): \(entry.oldValue ?? "-") -> \(entry.newValue ?? "-")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    historyCaption(entry.reason, entry.userName, entry.createdAt, entry.deviceName)
                                }
                            }
                        }
                    } label: {
                        sectionHeader("Audit History", count: auditLog.count)
                    }
                }
            }
            .navigationTitle(order.displayNumber)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .dismissKeyboardOnTap()
            .scrollDismissesKeyboard(.interactively)
            .task {
                await loadEmployees()
                await loadHistory()
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func historyCaption(_ note: String?, _ userName: String?, _ createdAt: String?, _ deviceName: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let note, !note.isEmpty {
                Text(note)
            }
            Text([userName, createdAt, deviceName].compactMap { $0 }.joined(separator: " | "))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func lineActions(_ line: CustomOrderLine) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if can(.customOrderProductionSteps) || canManage {
                Menu {
                    ForEach(CustomOrderProductionStatus.allCases) { status in
                        Button(status.title) { Task { await updateProduction(line, status: status) } }
                    }
                } label: {
                    Label("Production", systemImage: "checklist")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .disabled(actionInProgress)
            }

            if (can(.customOrderLineDelivery) || canManage) && line.deliveryStatus != .delivered {
                Button { Task { await deliver(line) } } label: {
                    Label(actionInProgress ? "Delivering..." : "Deliver Line", systemImage: "shippingbox.and.arrow.backward")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .disabled(actionInProgress)
            }

        }
        .controlSize(.regular)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func labeledDetail(_ label: String, _ value: String) -> some View {
        Text("\(label): \(value)")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func numberText(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
    }

    private var canManage: Bool { sessionManager.currentUser?.canAccess(.manageCustomOrders) == true }

    private var canRefundOrder: Bool {
        can(.customOrderRefunds) || can(.customOrderLineReturns) || canManage
    }

    private var canCancelOrder: Bool {
        can(.customOrderCancel) || canManage
    }

    private func can(_ permission: MobilePermission) -> Bool {
        sessionManager.currentUser?.canAccess(permission) == true
    }

    private var selectedEmployee: CustomOrderEmployee? {
        guard let selectedEmployeeId else { return nil }
        return employees.first { $0.userId == selectedEmployeeId }
    }

    private var hasManagementChanges: Bool {
        selectedEmployeeId != order.assignedToUserId || selectedStatus != order.status
    }

    private func loadEmployees() async {
        guard canManage else { return }
        do { employees = try await service.fetchEmployees() } catch { errorMessage = error.localizedDescription }
    }

    private func updateOrderManagement() async {
        guard let user = sessionManager.currentUser else { return }
        guard !actionInProgress else { return }
        actionInProgress = true
        defer { actionInProgress = false }
        do {
            if selectedEmployeeId != order.assignedToUserId, let selectedEmployee {
                try await service.assignOrder(order, to: selectedEmployee, by: user, device: sessionManager.currentDevice)
            }
            if selectedStatus != order.status {
                try await service.updateStatus(order: order, status: selectedStatus, reason: nil, user: user, device: sessionManager.currentDevice)
            }
            await onSaved()
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    private func updateProduction(_ line: CustomOrderLine, status: CustomOrderProductionStatus) async {
        guard let user = sessionManager.currentUser else { return }
        guard !actionInProgress else { return }
        actionInProgress = true
        defer { actionInProgress = false }
        do {
            try await service.updateLineProduction(order: order, line: line, status: status, notes: productionNotes, user: user, device: sessionManager.currentDevice)
            await onSaved()
        } catch { errorMessage = error.localizedDescription }
    }

    private func deliver(_ line: CustomOrderLine) async {
        guard let user = sessionManager.currentUser else { return }
        guard !actionInProgress else { return }
        actionInProgress = true
        defer { actionInProgress = false }
        do {
            try await service.deliverLine(order: order, line: line, notes: deliveryNotes, user: user, device: sessionManager.currentDevice)
            await onSaved()
        } catch { errorMessage = error.localizedDescription }
    }

    private func refund(_ line: CustomOrderLine) async {
        guard let user = sessionManager.currentUser else { return }
        guard !actionInProgress else { return }
        actionInProgress = true
        defer { actionInProgress = false }
        do {
            try await service.refundLine(order: order, line: line, returnType: "PARTIAL", reason: refundReason, amount: refundAmount(for: line), notes: nil, user: user, device: sessionManager.currentDevice, store: sessionManager.selectedStore, hasApprovalPermission: can(.customOrderRefundApproval))
            await onSaved()
        } catch { errorMessage = error.localizedDescription }
    }

    private func refundAllLines() async {
        guard let user = sessionManager.currentUser else { return }
        guard !actionInProgress else { return }
        actionInProgress = true
        defer { actionInProgress = false }
        do {
            var runningBalance = order.balanceDue
            for line in order.lines {
                let amount = max(line.lineTotal - line.returns.reduce(0) { $0 + $1.refundAmount }, 0)
                guard amount > 0 else { continue }
                try await service.refundLine(order: order, line: line, returnType: "FULL", reason: refundReason, amount: amount, notes: "Refund all lines", user: user, device: sessionManager.currentDevice, store: sessionManager.selectedStore, hasApprovalPermission: can(.customOrderRefundApproval), currentBalanceDue: runningBalance)
                if refundReason == "Payment Mistake" {
                    runningBalance += amount
                } else {
                    runningBalance = max(runningBalance - min(runningBalance, amount), 0)
                }
            }
            await onSaved()
        } catch { errorMessage = error.localizedDescription }
    }

    private func refundAmount(for line: CustomOrderLine) -> Double {
        let enteredAmount = Double(refundAmountText.trimmingCharacters(in: .whitespacesAndNewlines))
        return enteredAmount ?? max(line.lineTotal - line.returns.reduce(0) { $0 + $1.refundAmount }, 0)
    }

    private func recordPayment() async {
        guard let user = sessionManager.currentUser else { return }
        guard !actionInProgress else { return }
        actionInProgress = true
        defer { actionInProgress = false }
        do {
            try await service.recordPayment(order: order, method: paymentMethod, amount: Double(paymentAmountText) ?? 0, reference: paymentReference, user: user, store: sessionManager.selectedStore, device: sessionManager.currentDevice)
            await onSaved()
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    private func cancelOrder() async {
        guard let user = sessionManager.currentUser else { return }
        guard !actionInProgress else { return }
        actionInProgress = true
        defer { actionInProgress = false }
        do {
            try await service.cancelOrder(order: order, reason: cancelReason, user: user, device: sessionManager.currentDevice)
            await onSaved()
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    private func loadHistory() async {
        do {
            async let audits = service.fetchAuditLog(orderId: order.customOrderId)
            async let statuses = service.fetchStatusHistory(orderId: order.customOrderId)
            async let deliveries = service.fetchDeliveryHistory(orderId: order.customOrderId)
            async let productions = service.fetchProductionHistory(orderId: order.customOrderId)
            auditLog = try await audits
            statusHistory = try await statuses
            deliveryHistory = try await deliveries
            productionHistory = try await productions
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CustomOrderSummaryRows: View {
    let order: CustomOrder

    var body: some View {
        LabeledContent("Name", value: order.customerName)
        LabeledContent("Phone", value: order.customerPhone)
        LabeledContent("Total", value: order.totalText)
        LabeledContent("Paid", value: String(format: "$%.2f", order.amountPaid))
        LabeledContent("Balance", value: order.balanceText)
        LabeledContent("Payment", value: order.paymentStatus.title)
        LabeledContent("Status", value: order.status.title)
        if let assignedToName = order.assignedToName, !assignedToName.isEmpty {
            LabeledContent("Assigned", value: assignedToName)
        }
        if let locationName = order.locationName {
            LabeledContent("Location", value: locationName)
        }
        if let notes = order.orderNotes, !notes.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Order Notes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(notes)
            }
        }
    }
}

private struct CustomOrderLineDetailCard: View {
    let line: CustomOrderLine

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(line.displayName)
                        .font(.headline)
                    Text("\(line.pricingType.title) | \(line.itemType.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(line.totalText)
                    .font(.subheadline.weight(.semibold))
            }

            HStack {
                statusPill("Production", line.productionStatus.title)
                statusPill("Delivery", line.deliveryStatus.title)
            }

            detailRows
            printRows
            returnRows
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var detailRows: some View {
        if let details = line.customizationDetails, !details.isEmpty {
            labeledDetail("Customization", details)
        }
        if let notes = line.lineNotes, !notes.isEmpty {
            labeledDetail("Order instructions", notes)
        }
        if line.pricingType == .area {
            let sizeText = [line.widthValue.map(numberText), line.lengthValue.map(numberText)]
                .compactMap { $0 }
                .joined(separator: " x ")
            if !sizeText.isEmpty {
                labeledDetail("Size", "\(sizeText) \(line.dimensionUnit ?? "")")
            }
            if let areaValue = line.areaValue {
                labeledDetail("Area", "\(numberText(areaValue)) \(line.areaUnit ?? "")")
            }
            if let areaPrice = line.areaPrice {
                labeledDetail("Area price", String(format: "$%.2f", areaPrice))
            }
        }
        if line.originalLineTotal > line.lineTotal {
            labeledDetail("Original total", String(format: "$%.2f", line.originalLineTotal))
        }
        if let reason = line.lineDiscountReason, !reason.isEmpty {
            labeledDetail("Discount reason", reason)
        }
        if let reason = line.priceOverrideReason, !reason.isEmpty {
            labeledDetail("Override reason", reason)
        }
    }

    @ViewBuilder
    private var printRows: some View {
        if !line.printAddons.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Print Add Ons")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(line.printAddons) { addon in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(addon.materialName ?? "Add On") \(addon.presetName ?? "")")
                            .font(.subheadline.weight(.semibold))
                        Text(addon.priceText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if addon.pricingMode == "PER_LINE" {
                            Text("Lines: \(addon.lineCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let description = addon.printDescription, !description.isEmpty {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var returnRows: some View {
        if !line.returns.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Returns / Refunds")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(line.returns) { itemReturn in
                    Text("\(itemReturn.refundReason) \(String(format: "$%.2f", itemReturn.refundAmount))")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func statusPill(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func labeledDetail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
        }
    }

    private func numberText(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
    }
}

private extension View {
    func dismissKeyboardOnTap() -> some View {
        background(KeyboardDismissTapView())
    }
}

#if canImport(UIKit)
private struct KeyboardDismissTapView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear

        DispatchQueue.main.async {
            guard let hostView = view.superview,
                  hostView.gestureRecognizers?.contains(where: { $0.name == "SmartStockKeyboardDismissTap" }) != true else {
                return
            }

            let recognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.dismissKeyboard))
            recognizer.name = "SmartStockKeyboardDismissTap"
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = context.coordinator
            hostView.addGestureRecognizer(recognizer)
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        @objc func dismissKeyboard() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
#else
private struct KeyboardDismissTapView: View {
    var body: some View { EmptyView() }
}
#endif

private struct CustomOrderManagerDashboardView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    private let service = CustomOrderService()
    @State private var orders: [CustomOrder] = []
    @State private var selectedOrder: CustomOrder?
    @State private var statusFilter: CustomOrderManagerStatusFilter = .all

    var body: some View {
        List {
            Section("By Status") {
                ForEach(CustomOrderStatus.allCases) { status in
                    LabeledContent(status.title, value: "\(orders.filter { $0.status == status }.count)")
                }
            }
            Section("Open Balances") {
                LabeledContent("Balance due", value: String(format: "$%.2f", orders.reduce(0) { $0 + $1.balanceDue }))
                LabeledContent("Ready", value: "\(orders.filter { $0.status == .ready }.count)")
            }
            Section("Filters") {
                Picker("Status", selection: $statusFilter) {
                    Text("All statuses").tag(CustomOrderManagerStatusFilter.all)
                    Text("Current orders").tag(CustomOrderManagerStatusFilter.current)
                    ForEach(CustomOrderStatus.allCases) { status in
                        Text(status.title).tag(CustomOrderManagerStatusFilter.status(status))
                    }
                }
            }
            Section("Location Orders") {
                if orders.isEmpty {
                    Text("No orders found for this location.")
                        .foregroundStyle(.secondary)
                } else if filteredOrders.isEmpty {
                    Text("No orders match these filters.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredOrders) { order in
                        Button {
                            selectedOrder = order
                        } label: {
                            HStack {
                                CustomOrderRow(order: order)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Orders Manager")
        .sheet(item: $selectedOrder) { order in
            CustomOrderDetailView(order: order, readOnly: false) {
                await load()
            }
            .environmentObject(sessionManager)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var filteredOrders: [CustomOrder] {
        return orders.filter { order in
            statusFilter.matches(order)
        }
    }

    private func load() async {
        orders = (try? await service.fetchOrders(scope: .manager(locationId: sessionManager.selectedStore?.id))) ?? []
    }
}

private enum CustomOrderManagerStatusFilter: Hashable {
    case all
    case current
    case status(CustomOrderStatus)

    func matches(_ order: CustomOrder) -> Bool {
        switch self {
        case .all:
            return true
        case .current:
            return order.status != .delivered
        case .status(let status):
            return order.status == status
        }
    }
}

private struct CustomOrderEndOfDayView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    private let service = CustomOrderService()
    @State private var payments: [CustomOrderPayment] = []
    @State private var returns: [CustomOrderEndOfDayReturn] = []
    @State private var filterCurrentDevice = true
    @State private var filterCurrentUser = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }

            Section("Filters") {
                Toggle("Current device only", isOn: $filterCurrentDevice)
                Toggle("Current user only", isOn: $filterCurrentUser)
                if let storeName = sessionManager.selectedStore?.name {
                    LabeledContent("Location", value: storeName)
                }
            }
            .onChange(of: filterCurrentDevice) { _, _ in Task { await load() } }
            .onChange(of: filterCurrentUser) { _, _ in Task { await load() } }

            Section("Payments") {
                ForEach(CustomOrderPaymentMethod.allCases) { method in
                    LabeledContent(method.title, value: String(format: "$%.2f", total(for: method)))
                }
                LabeledContent("Total Payments", value: String(format: "$%.2f", paymentTotal))
            }

            Section("Refunds / Returns") {
                LabeledContent("Refunded Amount", value: String(format: "$%.2f", refundTotal))
                LabeledContent("Balance Reduced", value: String(format: "$%.2f", balanceReductionTotal))
                LabeledContent("Actual Payout", value: String(format: "$%.2f", payoutTotal))
            }

            Section("Payment Transactions") {
                if paymentTransactions.isEmpty {
                    Text("No payments found.").foregroundStyle(.secondary)
                } else {
                    ForEach(paymentTransactions) { payment in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(payment.paymentMethod.title)
                                Spacer()
                                Text(payment.amountText)
                            }
                            .font(.subheadline.weight(.semibold))
                            if let reference = payment.paymentReference, !reference.isEmpty {
                                Text("Reference: \(reference)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text([payment.takenByName, payment.createdAt, payment.deviceName].compactMap { $0 }.joined(separator: " | "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Return / Refund Transactions") {
                if returns.isEmpty {
                    Text("No returns or refunds found.").foregroundStyle(.secondary)
                } else {
                    ForEach(returns) { itemReturn in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(itemReturn.displayName)
                                Spacer()
                                Text(itemReturn.amountText)
                            }
                            .font(.subheadline.weight(.semibold))
                            Text(itemReturn.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Balance \(itemReturn.balanceReductionText) | Payout \(itemReturn.payoutText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text([itemReturn.createdByName, itemReturn.createdAt, itemReturn.deviceName].compactMap { $0 }.joined(separator: " | "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Orders End Of Day")
        .task { await load() }
        .refreshable { await load() }
    }

    private var paymentTransactions: [CustomOrderPayment] {
        payments.filter { !$0.isRefundAction }
    }

    private var paymentTotal: Double {
        paymentTransactions.reduce(0) { $0 + $1.amount }
    }

    private var refundTotal: Double {
        returns.reduce(0) { $0 + $1.refundAmount }
    }

    private var balanceReductionTotal: Double {
        returns.reduce(0) { $0 + $1.balanceReduction }
    }

    private var payoutTotal: Double {
        returns.reduce(0) { $0 + $1.payoutAmount }
    }

    private func total(for method: CustomOrderPaymentMethod) -> Double {
        paymentTransactions.filter { $0.paymentMethod == method }.reduce(0) { $0 + $1.amount }
    }

    private func load() async {
        errorMessage = nil
        do {
            async let loadedPayments = service.fetchEndOfDay(
                locationId: sessionManager.selectedStore?.id,
                deviceId: filterCurrentDevice ? sessionManager.currentDevice?.id.uuidString : nil,
                userId: filterCurrentUser ? sessionManager.currentUser?.id : nil
            )
            async let loadedReturns = service.fetchEndOfDayReturns(
                locationId: sessionManager.selectedStore?.id,
                deviceId: filterCurrentDevice ? sessionManager.currentDevice?.id.uuidString : nil,
                userId: filterCurrentUser ? sessionManager.currentUser?.id : nil
            )
            payments = try await loadedPayments
            returns = try await loadedReturns
        } catch {
            errorMessage = error.localizedDescription
            payments = []
            returns = []
        }
    }
}

private enum PlaceholderCustomOrderItem {
    static let item = try! JSONDecoder().decode(CustomOrderItem.self, from: Data("""
    {"custom_item_id":0,"item_name":"","product_type":"INVENTORY","pricing_type":"FIXED","quantity_on_hand":0,"reorder_level":0,"has_variants":false,"is_active":true}
    """.utf8))
}
