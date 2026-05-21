//
//  CustomOrderItemsView.swift
//  SmartStock
//

import SwiftUI

struct CustomOrderItemsView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    private let service = CustomOrderService()

    private enum ManagementScreen: String, CaseIterable, Identifiable {
        case items = "Items"
        case printMaterials = "Print Materials"

        var id: String { rawValue }
    }

    private enum SetupStatusFilter: String, CaseIterable, Identifiable {
        case active = "Active"
        case inactive = "Inactive"
        case all = "All"

        var id: String { rawValue }

        func includes(_ isActive: Bool) -> Bool {
            switch self {
            case .active:
                return isActive
            case .inactive:
                return !isActive
            case .all:
                return true
            }
        }
    }

    @State private var selectedScreen: ManagementScreen = .items
    @State private var statusFilter: SetupStatusFilter = .active
    @State private var items: [CustomOrderItem] = []
    @State private var materials: [CustomOrderPrintMaterial] = []
    @State private var presets: [CustomOrderPrintSizePreset] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var editingItem: CustomOrderItem?
    @State private var editingMaterial: CustomOrderPrintMaterial?
    @State private var isShowingAddItem = false
    @State private var isShowingAddMaterial = false
    @State private var isShowingScanner = false
    @State private var isShowingFilters = false

    var body: some View {
        Group {
            if isLoading && activeListIsEmpty {
                ProgressView(selectedScreen == .items ? "Loading custom order items..." : "Loading print materials...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        summaryCards

                        Picker("Management Screen", selection: $selectedScreen) {
                            ForEach(ManagementScreen.allCases) { screen in
                                Text(screen.rawValue).tag(screen)
                            }
                        }
                        .pickerStyle(.segmented)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.callout)
                                .foregroundStyle(.red)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.10))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }

                        if selectedScreen == .items {
                            itemsSection
                        } else {
                            printMaterialsSection
                        }
                    }
                    .padding()
                }
                .refreshable {
                    await loadActiveScreen()
                }
            }
        }
        .navigationTitle("Custom Order Items")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: selectedScreen == .items ? "Search custom items" : "Search print materials")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    isShowingFilters = true
                } label: {
                    Image(systemName: activeFilterCount == 0 ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 34, height: 34)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Custom order item filters")

                if selectedScreen == .items {
                    Button {
                        isShowingScanner = true
                    } label: {
                        Image(systemName: "barcode.viewfinder")
                    }
                    .accessibilityLabel("Scan custom item barcode")
                }

                if selectedScreen == .items && canManageCustomItems {
                    Button {
                        isShowingAddItem = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Add custom order item")
                } else if selectedScreen == .printMaterials && canManagePrintMaterials {
                    Button {
                        isShowingAddMaterial = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Add print material")
                }
            }
        }
        .sheet(isPresented: $isShowingScanner) {
            BarcodeScannerSheet(
                scannedCode: $searchText,
                isPresented: $isShowingScanner,
                onScanned: { code in
                    searchText = code.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            )
        }
        .sheet(isPresented: $isShowingFilters) {
            NavigationStack {
                customOrderFiltersSheet
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $isShowingAddItem) {
            CustomOrderItemFormView(item: nil) {
                await loadItems()
            }
            .environmentObject(sessionManager)
        }
        .sheet(item: $editingItem) { item in
            CustomOrderItemFormView(item: item) {
                await loadItems()
            }
            .environmentObject(sessionManager)
        }
        .sheet(isPresented: $isShowingAddMaterial) {
            CustomOrderPrintMaterialFormView(material: nil, presets: []) {
                await loadPrintMaterials()
            }
            .environmentObject(sessionManager)
        }
        .sheet(item: $editingMaterial) { material in
            CustomOrderPrintMaterialFormView(material: material, presets: presetsForMaterial(material.materialId)) {
                await loadPrintMaterials()
            }
            .environmentObject(sessionManager)
        }
        .task {
            await loadActiveScreen()
        }
        .onChange(of: selectedScreen) { _, _ in
            Task { await loadActiveScreen() }
        }
    }

    private var itemsSection: some View {
        LazyVStack(spacing: 12) {
            if filteredItems.isEmpty {
                setupEmptyState(
                    title: "No Custom Order Items",
                    systemImage: "tshirt",
                    message: statusFilter == .inactive ? "No inactive custom items found." : "Add templates for custom order entry and receiving."
                )
            } else {
                ForEach(filteredItems) { item in
                    NavigationLink {
                        CustomOrderItemDetailView(item: item) {
                            await loadItems()
                        }
                        .environmentObject(sessionManager)
                    } label: {
                        CustomOrderItemCardView(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var printMaterialsSection: some View {
        LazyVStack(spacing: 12) {
            if filteredMaterials.isEmpty {
                setupEmptyState(
                    title: "No Print Materials",
                    systemImage: "paintpalette",
                    message: statusFilter == .inactive ? "No inactive print materials found." : "Add print add-on materials and size presets."
                )
            } else {
                ForEach(filteredMaterials) { material in
                    NavigationLink {
                        CustomOrderPrintMaterialDetailView(material: material, presets: presetsForMaterial(material.materialId)) {
                            await loadPrintMaterials()
                        }
                        .environmentObject(sessionManager)
                    } label: {
                        CustomOrderPrintMaterialCardView(material: material, presets: presetsForMaterial(material.materialId))
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if canManagePrintMaterials && material.isActive {
                            Button(role: .destructive) {
                                Task { await deactivatePrintMaterial(material) }
                            } label: {
                                Label("Deactivate", systemImage: "xmark.circle")
                            }
                        }
                    }
                }
            }
        }
    }

    private func setupEmptyState(title: String, systemImage: String, message: String) -> some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var summaryCards: some View {
        HStack(spacing: 12) {
            if selectedScreen == .items {
                summaryCard(title: "Items", value: "\(items.count)", systemImage: "tshirt", tint: .blue)
                summaryCard(title: "Low Stock", value: "\(lowStockItemCount)", systemImage: "exclamationmark.circle", tint: .orange)
                summaryCard(title: "Inactive", value: "\(items.filter { !$0.isActive }.count)", systemImage: "xmark.circle", tint: .red)
            } else {
                summaryCard(title: "Materials", value: "\(materials.count)", systemImage: "paintpalette", tint: .blue)
                summaryCard(title: "Print Sizes", value: "\(presets.count)", systemImage: "rectangle.3.group", tint: .orange)
                summaryCard(title: "Inactive", value: "\(materials.filter { !$0.isActive }.count)", systemImage: "xmark.circle", tint: .red)
            }
        }
    }

    private func summaryCard(title: String, value: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)

            Text(value)
                .font(.title3.weight(.bold))

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            LinearGradient(
                colors: [tint.opacity(0.16), Color(.secondarySystemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var canManageCustomItems: Bool {
        sessionManager.currentUser?.canAccess(.customOrderItems) == true
    }

    private var canManagePrintMaterials: Bool {
        sessionManager.currentUser?.canAccess(.customOrderPrintMaterials) == true
        || sessionManager.currentUser?.canAccess(.customOrderItems) == true
    }

    private var activeFilterCount: Int {
        statusFilter == .active ? 0 : 1
    }

    private var activeListIsEmpty: Bool {
        selectedScreen == .items ? items.isEmpty : materials.isEmpty
    }

    private var lowStockItemCount: Int {
        items.filter { item in
            guard item.itemType == .inventory else { return false }
            if item.hasVariants {
                return item.variants.contains { $0.quantityOnHand <= $0.reorderLevel }
            }
            return item.quantityOnHand <= item.reorderLevel
        }.count
    }

    private var filteredItems: [CustomOrderItem] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let statusRows = items.filter { statusFilter.includes($0.isActive) }
        guard !trimmed.isEmpty else { return statusRows }
        return statusRows.filter {
            $0.itemName.localizedCaseInsensitiveContains(trimmed)
                || $0.code.localizedCaseInsensitiveContains(trimmed)
                || ($0.sku?.localizedCaseInsensitiveContains(trimmed) == true)
                || ($0.barcode?.localizedCaseInsensitiveContains(trimmed) == true)
                || $0.extraBarcodes.contains { $0.localizedCaseInsensitiveContains(trimmed) }
                || $0.variants.contains { variant in
                    variant.variantName.localizedCaseInsensitiveContains(trimmed)
                        || (variant.sku?.localizedCaseInsensitiveContains(trimmed) == true)
                        || (variant.barcode?.localizedCaseInsensitiveContains(trimmed) == true)
                }
        }
    }

    private var filteredMaterials: [CustomOrderPrintMaterial] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let statusRows = materials.filter { statusFilter.includes($0.isActive) }
        guard !trimmed.isEmpty else { return statusRows }
        return statusRows.filter { material in
            material.materialName.localizedCaseInsensitiveContains(trimmed)
            || (material.description?.localizedCaseInsensitiveContains(trimmed) == true)
            || presetsForMaterial(material.materialId).contains { preset in
                preset.presetName.localizedCaseInsensitiveContains(trimmed)
            }
        }
    }

    private func numberText(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
    }

    private func priceColor(for item: CustomOrderItem) -> Color {
        switch item.pricingType {
        case .fixed:
            return .green
        case .variable:
            return .orange
        case .area:
            return .purple
        }
    }

    private var customOrderFiltersSheet: some View {
        List {
            Section("Status") {
                Picker("Show", selection: $statusFilter) {
                    ForEach(SetupStatusFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
            }

            Section {
                Button {
                    resetFilters()
                } label: {
                    Label("Reset Filters", systemImage: "arrow.counterclockwise")
                }
                .disabled(activeFilterCount == 0)
            }
        }
        .navigationTitle("Filters")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    isShowingFilters = false
                }
            }
        }
    }

    private func resetFilters() {
        statusFilter = .active
    }

    private func loadItems() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            items = try await service.fetchItems()
        } catch {
            errorMessage = customOrderSetupErrorMessage(error)
        }
    }

    private func loadPrintMaterials() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let materialRows = service.fetchPrintMaterials(activeOnly: false)
            async let presetRows = service.fetchPrintSizePresets(activeOnly: false)
            materials = try await materialRows
            presets = try await presetRows
        } catch {
            errorMessage = customOrderSetupErrorMessage(error)
        }
    }

    private func loadActiveScreen() async {
        if selectedScreen == .items {
            await loadItems()
        } else {
            await loadPrintMaterials()
        }
    }

    private func deactivatePrintMaterial(_ material: CustomOrderPrintMaterial) async {
        do {
            try await service.deactivatePrintMaterial(materialId: material.materialId)
            await loadPrintMaterials()
        } catch {
            errorMessage = customOrderSetupErrorMessage(error)
        }
    }

    private func presetsForMaterial(_ materialId: Int64?) -> [CustomOrderPrintSizePreset] {
        guard let materialId else { return [] }
        return presets.filter { $0.materialId == materialId }
    }
}

private struct CustomOrderItemCardView: View {
    let item: CustomOrderItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                itemImage
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.itemName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("SKU: \(item.displaySku)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Text("ID: \(item.customItemId)")
                        Text(item.pricingType.title)
                        if item.hasVariants {
                            Text("\(item.variants.count) variants")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
                customOrderItemStatusBadge(item: item)
            }

            HStack {
                metricView(title: "Qty", value: item.itemType == .inventory && !item.hasVariants ? setupNumberText(item.quantityOnHand) : variantQuantityText)
                Spacer()
                metricView(title: "Reorder", value: item.itemType == .inventory && !item.hasVariants ? setupNumberText(item.reorderLevel) : variantReorderText)
                Spacer()
                metricView(title: "Type", value: item.itemType.title)
                Spacer()
                metricView(title: "Price", value: item.priceText)
            }

            VStack(alignment: .leading, spacing: 4) {
                if let barcode = item.barcode, !barcode.isEmpty {
                    Text("Barcode: \(barcode)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                if let description = item.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(itemRowBackground(item))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(itemBorderColor(item).opacity(0.35), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var itemImage: some View {
        if let imageUrl = item.displayImageUrl, let url = URL(string: imageUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    placeholderImage
                }
            }
        } else {
            placeholderImage
        }
    }

    private var placeholderImage: some View {
        ZStack {
            Color.white.opacity(0.65)
            Image(systemName: item.hasVariants ? "square.stack.3d.up.fill" : "tshirt.fill")
                .foregroundStyle(.secondary)
        }
    }

    private var variantQuantityText: String {
        guard item.hasVariants else { return item.itemType == .inventory ? setupNumberText(item.quantityOnHand) : "-" }
        return setupNumberText(item.variants.reduce(0) { $0 + $1.quantityOnHand })
    }

    private var variantReorderText: String {
        guard item.hasVariants else { return item.itemType == .inventory ? setupNumberText(item.reorderLevel) : "-" }
        return setupNumberText(item.variants.reduce(0) { $0 + $1.reorderLevel })
    }

    private func metricView(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }
}

private struct CustomOrderPrintMaterialCardView: View {
    let material: CustomOrderPrintMaterial
    let presets: [CustomOrderPrintSizePreset]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Color.white.opacity(0.65)
                    Image(systemName: "paintpalette.fill")
                        .foregroundStyle(.secondary)
                }
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(material.materialName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(material.pricingModeTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("ID: \(material.materialId)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
                statusBadge(title: material.isActive ? "Active" : "Inactive", tint: material.isActive ? .green : .secondary)
            }

            HStack {
                metricView(title: "Presets", value: "\(presets.count)")
                Spacer()
                metricView(title: "Fixed", value: "\(presets.filter { $0.pricingMode != "PER_LINE" }.count)")
                Spacer()
                metricView(title: "Per Line", value: "\(presets.filter { $0.pricingMode == "PER_LINE" }.count)")
                Spacer()
                metricView(title: "Status", value: material.isActive ? "Active" : "Inactive")
            }

            if presets.isEmpty {
                Text("No print sizes for this material.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(presets.prefix(3))) { preset in
                        HStack {
                            Text(preset.presetName)
                            Spacer()
                            Text(preset.pricingMode == "PER_LINE" ? "\(preset.priceText) / line" : preset.priceText)
                        }
                    }
                    if presets.count > 3 {
                        Text("+\(presets.count - 3) more print sizes")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(material.isActive ? Color(.secondarySystemBackground) : Color.red.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke((material.isActive ? Color.gray : Color.red).opacity(0.35), lineWidth: 1)
        )
    }

    private func metricView(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }
}

private struct CustomOrderItemDetailView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    let item: CustomOrderItem
    let onSaved: () async -> Void

    @State private var isShowingEditor = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    itemImage
                        .frame(width: 92, height: 92)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.itemName)
                            .font(.headline)
                        Text(item.displaySku)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        customOrderItemStatusBadge(item: item)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Item") {
                detailRow("Item ID", "\(item.customItemId)")
                detailRow("Name", item.itemName)
                detailRow("SKU", item.displaySku)
                detailRow("Barcode", item.barcode ?? "-")
                detailRow("Extra Barcodes", item.extraBarcodes.isEmpty ? "-" : item.extraBarcodes.joined(separator: ", "))
                detailRow("Type", item.itemType.title)
                detailRow("Pricing", item.pricingType.title)
                detailRow("Active", item.isActive ? "Yes" : "No")
                detailRow("Description", item.description ?? "-")
            }

            Section("Pricing") {
                detailRow("Display Price", item.priceText)
                if item.pricingType == .fixed && !item.hasVariants {
                    detailRow("Fixed Price", setupCurrencyText(item.fixedPrice ?? 0))
                }
                if item.pricingType == .area {
                    if !item.hasVariants {
                        detailRow("Area Price", setupCurrencyText(item.areaPrice ?? 0))
                    }
                    detailRow("Price Unit", item.areaPriceUnit ?? "-")
                    detailRow("Size Unit", item.dimensionUnit ?? "-")
                    detailRow("Max Width", item.maxWidth.map(setupNumberText) ?? "-")
                    detailRow("Max Length", item.maxLength.map(setupNumberText) ?? "-")
                }
            }

            Section("Stock") {
                if item.itemType == .inventory && item.hasVariants {
                    detailRow("Variant Quantity", setupNumberText(item.variants.reduce(0) { $0 + $1.quantityOnHand }))
                    detailRow("Variant Sold", setupNumberText(item.variants.reduce(0) { $0 + $1.soldQuantity }))
                } else if item.itemType == .inventory {
                    detailRow("Quantity on Hand", setupNumberText(item.quantityOnHand))
                    detailRow("Reorder Level", setupNumberText(item.reorderLevel))
                    detailRow("Total Sold", setupNumberText(item.soldQuantity))
                } else {
                    detailRow("Total Sold", setupNumberText(item.soldQuantity))
                    detailRow("Stock Tracking", "No")
                }
            }

            if item.hasVariants {
                Section("Variants") {
                    if item.variants.isEmpty {
                        Text("No variants set up for this item.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(item.variants) { variant in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(variant.variantName)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(variant.isActive ? "Active" : "Inactive")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(variant.isActive ? .green : .secondary)
                                }
                                HStack {
                                    Label(variant.displaySku, systemImage: "number")
                                    Spacer()
                                    Text(variant.priceText)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                HStack {
                                    Text("Qty \(setupNumberText(variant.quantityOnHand))")
                                    Text("Reorder \(setupNumberText(variant.reorderLevel))")
                                    Text("Sold \(setupNumberText(variant.soldQuantity))")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle("Item Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingEditor = true
                    } label: {
                        Image(systemName: "pencil.circle.fill")
                    }
                    .accessibilityLabel("Edit custom order item")
                }
            }
        }
        .sheet(isPresented: $isShowingEditor) {
            CustomOrderItemFormView(item: item) {
                await onSaved()
            }
            .environmentObject(sessionManager)
        }
    }

    private var canEdit: Bool {
        sessionManager.currentUser?.canAccess(.customOrderItems) == true
    }

    @ViewBuilder
    private var itemImage: some View {
        if let imageUrl = item.displayImageUrl, let url = URL(string: imageUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    placeholderImage
                }
            }
        } else {
            placeholderImage
        }
    }

    private var placeholderImage: some View {
        ZStack {
            Color(.secondarySystemBackground)
            Image(systemName: item.hasVariants ? "square.stack.3d.up.fill" : "tshirt.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CustomOrderPrintMaterialDetailView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    let material: CustomOrderPrintMaterial
    let presets: [CustomOrderPrintSizePreset]
    let onSaved: () async -> Void

    @State private var isShowingEditor = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    ZStack {
                        Color(.secondarySystemBackground)
                        Image(systemName: "paintpalette.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(material.materialName)
                            .font(.headline)
                        Text(material.pricingModeTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        statusBadge(title: material.isActive ? "Active" : "Inactive", tint: material.isActive ? .green : .secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Material") {
                detailRow("Material ID", "\(material.materialId)")
                detailRow("Name", material.materialName)
                detailRow("Default Pricing", material.pricingModeTitle)
                detailRow("Active", material.isActive ? "Yes" : "No")
                detailRow("Description", material.description ?? "-")
            }

            Section("Print Sizes") {
                if presets.isEmpty {
                    Text("No print sizes for this material.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(presets) { preset in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(preset.presetName)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(preset.pricingMode == "PER_LINE" ? "\(preset.priceText) / line" : preset.priceText)
                            }
                            HStack {
                                Text(preset.pricingMode == "PER_LINE" ? "Per line" : "Fixed")
                                Text(preset.isActive ? "Active" : "Inactive")
                                    .foregroundStyle(preset.isActive ? .green : .secondary)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Material Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingEditor = true
                    } label: {
                        Image(systemName: "pencil.circle.fill")
                    }
                    .accessibilityLabel("Edit print material")
                }
            }
        }
        .sheet(isPresented: $isShowingEditor) {
            CustomOrderPrintMaterialFormView(material: material, presets: presets) {
                await onSaved()
            }
            .environmentObject(sessionManager)
        }
    }

    private var canEdit: Bool {
        sessionManager.currentUser?.canAccess(.customOrderPrintMaterials) == true
        || sessionManager.currentUser?.canAccess(.customOrderItems) == true
    }
}

private func detailRow(_ label: String, _ value: String) -> some View {
    HStack(alignment: .top) {
        Text(label)
            .foregroundStyle(.secondary)
        Spacer(minLength: 16)
        Text(value)
            .multilineTextAlignment(.trailing)
    }
}

private func customOrderItemStatusBadge(item: CustomOrderItem) -> some View {
    let status = customOrderItemStatus(item)
    return statusBadge(title: status.title, tint: status.tint)
}

private func statusBadge(title: String, tint: Color) -> some View {
    Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.14))
        .clipShape(Capsule())
}

private func customOrderItemStatus(_ item: CustomOrderItem) -> (title: String, tint: Color) {
    guard item.isActive else { return ("Inactive", .secondary) }
    guard item.itemType == .inventory else { return ("No Stock", .blue) }

    let qty: Double
    let reorder: Double
    if item.hasVariants {
        qty = item.variants.reduce(0) { $0 + $1.quantityOnHand }
        reorder = item.variants.reduce(0) { $0 + $1.reorderLevel }
    } else {
        qty = item.quantityOnHand
        reorder = item.reorderLevel
    }

    if qty < 0 { return ("Negative", .orange) }
    if qty == 0 { return ("Out", .red) }
    if qty <= reorder { return ("Low Stock", .yellow) }
    return ("In Stock", .green)
}

private func itemRowBackground(_ item: CustomOrderItem) -> Color {
    guard item.isActive else { return Color.red.opacity(0.10) }
    guard item.itemType == .inventory else { return Color.blue.opacity(0.10) }
    let status = customOrderItemStatus(item).title
    switch status {
    case "Negative":
        return Color.orange.opacity(0.14)
    case "Out":
        return Color.red.opacity(0.10)
    case "Low Stock":
        return Color.yellow.opacity(0.14)
    default:
        return Color(.secondarySystemBackground)
    }
}

private func itemBorderColor(_ item: CustomOrderItem) -> Color {
    customOrderItemStatus(item).tint
}

private func setupNumberText(_ value: Double) -> String {
    value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
}

private func setupCurrencyText(_ value: Double) -> String {
    String(format: "$%.2f", value)
}

private struct CustomOrderPrintMaterialFormView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionManager: SessionManager
    private let service = CustomOrderService()

    let material: CustomOrderPrintMaterial?
    let presets: [CustomOrderPrintSizePreset]
    let onSaved: () async -> Void

    @State private var draft: CustomOrderPrintMaterialDraft
    @State private var localPresets: [CustomOrderPrintSizePreset]
    @State private var editingPreset: CustomOrderPrintSizePreset?
    @State private var isShowingAddPreset = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var currentMaterialId: Int64?

    init(material: CustomOrderPrintMaterial?, presets: [CustomOrderPrintSizePreset], onSaved: @escaping () async -> Void) {
        self.material = material
        self.presets = presets
        self.onSaved = onSaved
        _draft = State(initialValue: material.map(CustomOrderPrintMaterialDraft.init(material:)) ?? CustomOrderPrintMaterialDraft())
        _localPresets = State(initialValue: presets)
        _currentMaterialId = State(initialValue: material?.materialId)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section("Material") {
                    TextField("Material name", text: $draft.materialName)
                    TextField("Description", text: $draft.description, axis: .vertical)
                    Picker("Default pricing", selection: $draft.pricingMode) {
                        Text("Fixed Preset").tag("FIXED_PRESET")
                        Text("Per Line").tag("PER_LINE")
                    }
                    Toggle("Active", isOn: $draft.isActive)
                }

                Section("Print Sizes") {
                    if currentMaterialId == nil {
                        Text("Save the material before adding print sizes.")
                            .foregroundStyle(.secondary)
                    } else if localPresets.isEmpty {
                        Text("No print sizes for this material.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(localPresets) { preset in
                            Button {
                                editingPreset = preset
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(preset.presetName)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Text(preset.priceText)
                                            .foregroundStyle(.secondary)
                                    }
                                    HStack {
                                        Text(preset.pricingMode == "PER_LINE" ? "Per line" : "Fixed")
                                        Text(preset.isActive ? "Active" : "Inactive")
                                            .foregroundStyle(preset.isActive ? .green : .secondary)
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if canManagePrintMaterials && preset.isActive {
                                    Button(role: .destructive) {
                                        Task { await deactivatePreset(preset) }
                                    } label: {
                                        Label("Deactivate", systemImage: "xmark.circle")
                                    }
                                }
                            }
                        }
                    }

                    Button {
                        isShowingAddPreset = true
                    } label: {
                        Label("Add Print Size", systemImage: "plus.circle")
                    }
                    .disabled(currentMaterialId == nil || !canManagePrintMaterials)
                }
            }
            .navigationTitle(currentMaterialId == nil ? "New Print Material" : "Edit Print Material")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving" : "Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving || !canManagePrintMaterials)
                }
            }
            .sheet(isPresented: $isShowingAddPreset) {
                if let currentMaterialId {
                    CustomOrderPrintSizePresetFormView(materialId: currentMaterialId, preset: nil, defaultPricingMode: draft.pricingMode) {
                        await loadPresets()
                        await onSaved()
                    }
                }
            }
            .sheet(item: $editingPreset) { preset in
                if let currentMaterialId {
                    CustomOrderPrintSizePresetFormView(materialId: currentMaterialId, preset: preset, defaultPricingMode: draft.pricingMode) {
                        await loadPresets()
                        await onSaved()
                    }
                }
            }
        }
    }

    private var canManagePrintMaterials: Bool {
        sessionManager.currentUser?.canAccess(.customOrderPrintMaterials) == true
        || sessionManager.currentUser?.canAccess(.customOrderItems) == true
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let wasUnsaved = currentMaterialId == nil
            currentMaterialId = try await service.savePrintMaterial(draft, existingMaterialId: currentMaterialId)
            await onSaved()
            if !wasUnsaved {
                dismiss()
            }
        } catch {
            errorMessage = customOrderSetupErrorMessage(error)
        }
    }

    private func loadPresets() async {
        guard let currentMaterialId else { return }
        do {
            localPresets = try await service.fetchPrintSizePresets(activeOnly: false)
                .filter { $0.materialId == currentMaterialId }
        } catch {
            errorMessage = customOrderSetupErrorMessage(error)
        }
    }

    private func deactivatePreset(_ preset: CustomOrderPrintSizePreset) async {
        do {
            try await service.deactivatePrintSizePreset(presetId: preset.presetId)
            await loadPresets()
            await onSaved()
        } catch {
            errorMessage = customOrderSetupErrorMessage(error)
        }
    }
}

private struct CustomOrderPrintSizePresetFormView: View {
    @Environment(\.dismiss) private var dismiss
    private let service = CustomOrderService()

    let materialId: Int64
    let preset: CustomOrderPrintSizePreset?
    let onSaved: () async -> Void

    @State private var draft: CustomOrderPrintSizePresetDraft
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(materialId: Int64, preset: CustomOrderPrintSizePreset?, defaultPricingMode: String, onSaved: @escaping () async -> Void) {
        self.materialId = materialId
        self.preset = preset
        self.onSaved = onSaved
        var initialDraft = preset.map(CustomOrderPrintSizePresetDraft.init(preset:)) ?? CustomOrderPrintSizePresetDraft()
        if preset == nil {
            initialDraft.pricingMode = defaultPricingMode
        }
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section("Print Size") {
                    TextField("Size name", text: $draft.presetName)
                    Picker("Pricing", selection: $draft.pricingMode) {
                        Text("Fixed Preset").tag("FIXED_PRESET")
                        Text("Per Line").tag("PER_LINE")
                    }
                    if draft.pricingMode == "PER_LINE" {
                        Text("Per-line pricing lets the cashier enter the line count during order entry. The charge is line count times this price.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent(draft.pricingMode == "PER_LINE" ? "Price per line" : "Fixed price") {
                        TextField("0.00", text: $draft.fixedPrice)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Toggle("Active", isOn: $draft.isActive)
                }
            }
            .navigationTitle(preset == nil ? "New Print Size" : "Edit Print Size")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving" : "Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            _ = try await service.savePrintSizePreset(draft, materialId: materialId, existingPresetId: preset?.presetId)
            await onSaved()
            dismiss()
        } catch {
            errorMessage = customOrderSetupErrorMessage(error)
        }
    }
}

private enum CustomOrderMovementFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case receiving = "Receiving"
    case sales = "Sales"

    var id: String { rawValue }
}

private struct CustomOrderItemFormView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionManager: SessionManager
    private let service = CustomOrderService()

    let item: CustomOrderItem?
    let onSaved: () async -> Void

    @State private var draft: CustomOrderItemDraft
    @State private var currentItemId: Int64?
    @State private var variants: [CustomOrderItemVariant] = []
    @State private var movements: [CustomOrderItemMovement] = []
    @State private var extraBarcodes: [CustomOrderItemBarcode] = []
    @State private var newBarcode = ""
    @State private var movementFilter: CustomOrderMovementFilter = .all
    @State private var isMovementHistoryExpanded = false
    @State private var editingVariant: CustomOrderItemVariant?
    @State private var isShowingAddVariant = false
    @State private var isShowingDeactivateConfirmation = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(item: CustomOrderItem?, onSaved: @escaping () async -> Void) {
        self.item = item
        self.onSaved = onSaved
        let initialDraft: CustomOrderItemDraft
        if let item {
            initialDraft = CustomOrderItemDraft(item: item)
        } else {
            initialDraft = CustomOrderItemDraft()
        }
        _draft = State(initialValue: initialDraft)
        _currentItemId = State(initialValue: item?.customItemId)
        _extraBarcodes = State(initialValue: item?.extraBarcodeRows ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section("Template") {
                    TextField("Item name", text: $draft.itemName)
                    LabeledContent("Item SKU", value: generatedItemSku)
                    Picker("Type", selection: $draft.itemType) {
                        ForEach(CustomOrderItemType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    TextField("Primary barcode", text: $draft.barcode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled(true)
                    TextField("Item description", text: $draft.description, axis: .vertical)
                    Toggle("Track Sizes / Variants", isOn: $draft.hasVariants)
                    if !draft.hasVariants {
                        TextField("Item image URL", text: $draft.imageUrl)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                        imagePreview(urlString: draft.imageUrl)
                    }
                    Toggle("Active", isOn: $draft.isActive)
                }

                Section("More Barcodes") {
                    if let itemId = currentItemId {
                        if extraBarcodes.isEmpty {
                            Text("No extra barcodes.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(extraBarcodes) { barcode in
                                HStack {
                                    Label(barcode.barcode, systemImage: "barcode")
                                    Spacer()
                                    Button(role: .destructive) {
                                        Task { await deleteBarcode(barcode) }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(!canManageCustomItems)
                                }
                            }
                        }

                        HStack {
                            TextField("Add extra barcode", text: $newBarcode)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled(true)
                            Button("Add") {
                                Task { await addBarcode(itemId: itemId) }
                            }
                            .disabled(newBarcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !canManageCustomItems)
                        }
                    } else {
                        Text("Save the item before adding more barcodes.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Pricing") {
                    Picker("Pricing Type", selection: $draft.pricingType) {
                        ForEach(CustomOrderPricingType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    if draft.pricingType == .fixed && !draft.hasVariants {
                        TextField("Fixed price", text: $draft.fixedPrice)
                            .keyboardType(.decimalPad)
                    } else if draft.pricingType == .fixed && draft.hasVariants {
                        Text("Prices are set on each variant.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if draft.pricingType == .area {
                        if !draft.hasVariants {
                            LabeledContent("Price per area unit") {
                                TextField("0.00", text: $draft.areaPrice)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                            }
                        } else {
                            Text("Area price is set on each variant.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Picker("Price unit", selection: $draft.areaPriceUnit) {
                            Text("Square Feet").tag("sq ft")
                            Text("Square Inches").tag("sq in")
                            Text("Square Meters").tag("sq m")
                            Text("Square Centimeters").tag("sq cm")
                        }
                        Picker("Size unit", selection: $draft.dimensionUnit) {
                            Text("Inches").tag("in")
                            Text("Feet").tag("ft")
                            Text("Centimeters").tag("cm")
                            Text("Millimeters").tag("mm")
                            Text("Meters").tag("m")
                        }
                        TextField("Max width", text: $draft.maxWidth)
                            .keyboardType(.decimalPad)
                        TextField("Max length", text: $draft.maxLength)
                            .keyboardType(.decimalPad)
                    }
                }

                if draft.itemType == .inventory && !draft.hasVariants {
                    Section("Stock") {
                        LabeledContent("Quantity on hand") {
                            TextField("0", text: $draft.quantityOnHand)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Reorder level") {
                            TextField("0", text: $draft.reorderLevel)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                } else if draft.itemType == .inventory && draft.hasVariants {
                    Section("Stock") {
                        Text("Quantity and reorder levels are set on each variant.")
                            .foregroundStyle(.secondary)
                    }
                }

                if currentItemId != nil {
                    Section("Totals") {
                        LabeledContent("Total sold", value: numberText(totalSoldQuantity))
                        if !draft.hasVariants {
                            LabeledContent("Quantity on hand", value: numberText(item?.quantityOnHand ?? Double(draft.quantityOnHand) ?? 0))
                        }
                        if !variants.isEmpty {
                            LabeledContent("Variant stock", value: numberText(variants.reduce(0) { $0 + $1.quantityOnHand }))
                            LabeledContent("Variant sold", value: numberText(variants.reduce(0) { $0 + $1.soldQuantity }))
                        }
                    }
                }

                if currentItemId != nil && draft.hasVariants {
                    Section("Variants") {
                        if variants.isEmpty {
                            Text("No variants set up for this item.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(variants) { variant in
                                Button {
                                    editingVariant = variant
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        if let imageUrl = variant.imageUrl, let url = URL(string: imageUrl) {
                                            AsyncImage(url: url) { image in
                                                image.resizable().scaledToFill()
                                            } placeholder: {
                                                Image(systemName: "photo")
                                                    .foregroundStyle(.secondary)
                                            }
                                            .frame(width: 44, height: 44)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                        }

                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack {
                                                Text(variant.variantName)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(.primary)
                                                Spacer()
                                                Text(variant.isActive ? "Active" : "Inactive")
                                                    .foregroundStyle(variant.isActive ? .green : .secondary)
                                            }
                                            HStack {
                                                Label(variant.displaySku, systemImage: "number")
                                                Text(variant.priceText)
                                            }
                                            HStack {
                                                Text("Qty \(numberText(variant.quantityOnHand))")
                                                Text("Reorder \(numberText(variant.reorderLevel))")
                                                Label(variant.quantityOnHand <= variant.reorderLevel ? "Low stock" : "Stock OK", systemImage: variant.quantityOnHand <= variant.reorderLevel ? "exclamationmark.triangle" : "checkmark.circle")
                                                    .foregroundStyle(variant.quantityOnHand <= variant.reorderLevel ? .orange : .green)
                                            }
                                            if let barcode = variant.barcode, !barcode.isEmpty {
                                                Label(barcode, systemImage: "barcode")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .font(.caption)
                                        Spacer(minLength: 0)
                                    }
                                }
                            }
                        }

                        Button {
                            isShowingAddVariant = true
                        } label: {
                            Label("Add Variant", systemImage: "plus.circle")
                        }
                        .disabled(!canManageCustomItems)
                    }
                } else if item == nil && draft.hasVariants {
                    Section("Variants") {
                        Text("Save the item before adding variants.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Variants") {
                        Text("Turn on Track Sizes / Variants to set variant-level pricing, stock, barcodes, and images.")
                            .foregroundStyle(.secondary)
                    }
                }

                if currentItemId != nil {
                    Section {
                        Button {
                            withAnimation {
                                isMovementHistoryExpanded.toggle()
                            }
                        } label: {
                            HStack {
                                Text("Movement History")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(filteredMovements.count)")
                                    .foregroundStyle(.secondary)
                                Image(systemName: isMovementHistoryExpanded ? "chevron.up" : "chevron.down")
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if isMovementHistoryExpanded {
                            Picker("History Filter", selection: $movementFilter) {
                                ForEach(CustomOrderMovementFilter.allCases) { filter in
                                    Text(filter.rawValue).tag(filter)
                                }
                            }
                            .pickerStyle(.segmented)

                            if filteredMovements.isEmpty {
                                Text("No movement history for this item.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(filteredMovements) { movement in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(movement.reasonTitle)
                                                .font(.subheadline.weight(.semibold))
                                            Spacer()
                                            Text(movement.quantityText)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(movement.changeQuantity < 0 ? .red : (movement.changeQuantity > 0 ? .green : .secondary))
                                        }

                                        HStack {
                                            if let variantName = movement.variantName, !variantName.isEmpty {
                                                Text("Variant: \(variantName)")
                                            }
                                            if let userName = movement.userName, !userName.isEmpty {
                                                Text("User: \(userName)")
                                            }
                                            if let createdAt = movement.createdAt {
                                                Text(createdAt)
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                        if let receiveId = movement.receiveId, !receiveId.isEmpty {
                                            Text("Receive: \(receiveId)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        if let note = movement.note, !note.isEmpty {
                                            Text(note)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                }

                Section("Actions") {
                    Button(item == nil ? "Clear Form" : "Reset Unsaved Changes") {
                        resetDraft()
                    }
                    .disabled(!canManageCustomItems)

                    if currentItemId != nil && draft.isActive {
                        Button("Deactivate Item", role: .destructive) {
                            isShowingDeactivateConfirmation = true
                        }
                        .disabled(!canManageCustomItems)
                    }
                }
            }
            .navigationTitle(currentItemId == nil ? "New Custom Item" : "Edit Custom Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving" : "Save") {
                        Task {
                            await save()
                        }
                    }
                    .disabled(isSaving || !canManageCustomItems)
                }
            }
            .sheet(isPresented: $isShowingAddVariant) {
                if let currentItemId {
                    CustomOrderVariantFormView(itemId: currentItemId, parentItemName: draft.itemName, variant: nil, requiresPrice: variantPriceRequired) {
                        await loadDetailData()
                    }
                }
            }
            .sheet(item: $editingVariant) { variant in
                if let currentItemId {
                    CustomOrderVariantFormView(itemId: currentItemId, parentItemName: draft.itemName, variant: variant, requiresPrice: variantPriceRequired) {
                        await loadDetailData()
                    }
                }
            }
            .confirmationDialog("Deactivate this custom item?", isPresented: $isShowingDeactivateConfirmation, titleVisibility: .visible) {
                Button("Deactivate Item", role: .destructive) {
                    Task { await deactivateItem() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Old orders can still reference it, but it will no longer appear as an active item.")
            }
            .task {
                await loadDetailData()
            }
        }
    }

    private var canManageCustomItems: Bool {
        sessionManager.currentUser?.canAccess(.customOrderItems) == true
    }

    private var variantPriceRequired: Bool {
        draft.pricingType == .fixed || draft.pricingType == .area
    }

    private var generatedItemSku: String {
        CustomOrderService.generatedSku(from: [draft.itemName])
    }

    private var totalSoldQuantity: Double {
        if variants.isEmpty {
            return item?.soldQuantity ?? 0
        }
        return variants.reduce(item?.soldQuantity ?? 0) { $0 + $1.soldQuantity }
    }

    private var filteredMovements: [CustomOrderItemMovement] {
        switch movementFilter {
        case .all:
            return movements
        case .receiving:
            return movements.filter(\.isReceiving)
        case .sales:
            return movements.filter(\.isSale)
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let wasUnsaved = currentItemId == nil
            let savedId = try await service.saveItem(draft, existingItemId: currentItemId)
            currentItemId = savedId
            await onSaved()
            if wasUnsaved && draft.hasVariants {
                await loadDetailData()
                isShowingAddVariant = true
            } else {
                dismiss()
            }
        } catch {
            errorMessage = customOrderSetupErrorMessage(error)
        }
    }

    private func loadVariants() async {
        guard let currentItemId else { return }
        do {
            variants = try await service.fetchVariants(customItemId: currentItemId, activeOnly: false)
        } catch {
            errorMessage = customOrderSetupErrorMessage(error)
        }
    }

    private func loadDetailData() async {
        await loadVariants()
        guard let currentItemId else { return }
        do {
            async let movementRows = service.fetchItemMovements(customItemId: currentItemId)
            async let barcodeRows = service.fetchItemBarcodes(customItemId: currentItemId)
            movements = try await movementRows
            extraBarcodes = try await barcodeRows
        } catch {
            errorMessage = customOrderSetupErrorMessage(error)
        }
    }

    private func addBarcode(itemId: Int64) async {
        do {
            try await service.addItemBarcode(customItemId: itemId, barcode: newBarcode)
            newBarcode = ""
            extraBarcodes = try await service.fetchItemBarcodes(customItemId: itemId)
            await onSaved()
        } catch {
            errorMessage = customOrderSetupErrorMessage(error)
        }
    }

    private func deleteBarcode(_ barcode: CustomOrderItemBarcode) async {
        do {
            try await service.deleteItemBarcode(barcode.customItemBarcodeId)
            if let currentItemId {
                extraBarcodes = try await service.fetchItemBarcodes(customItemId: currentItemId)
                await onSaved()
            }
        } catch {
            errorMessage = customOrderSetupErrorMessage(error)
        }
    }

    private func deactivateItem() async {
        guard let currentItemId else { return }
        do {
            try await service.deactivateItem(customItemId: currentItemId)
            draft.isActive = false
            await onSaved()
            dismiss()
        } catch {
            errorMessage = customOrderSetupErrorMessage(error)
        }
    }

    private func resetDraft() {
        if let item {
            draft = CustomOrderItemDraft(item: item)
            currentItemId = item.customItemId
            extraBarcodes = item.extraBarcodeRows
        } else {
            draft = CustomOrderItemDraft()
            currentItemId = nil
            variants = []
            movements = []
            extraBarcodes = []
        }
        newBarcode = ""
        errorMessage = nil
    }

    private func numberText(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
    }

    @ViewBuilder
    private func imagePreview(urlString: String) -> some View {
        if let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)), !urlString.isEmpty {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                ProgressView()
            }
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct CustomOrderVariantFormView: View {
    @Environment(\.dismiss) private var dismiss
    private let service = CustomOrderService()

    let itemId: Int64
    let parentItemName: String
    let variant: CustomOrderItemVariant?
    let requiresPrice: Bool
    let onSaved: () async -> Void

    @State private var draft: CustomOrderVariantDraft
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(itemId: Int64, parentItemName: String, variant: CustomOrderItemVariant?, requiresPrice: Bool, onSaved: @escaping () async -> Void) {
        self.itemId = itemId
        self.parentItemName = parentItemName
        self.variant = variant
        self.requiresPrice = requiresPrice
        self.onSaved = onSaved
        let initialDraft: CustomOrderVariantDraft
        if let variant {
            initialDraft = CustomOrderVariantDraft(variant: variant, parentItemName: parentItemName)
        } else {
            var draft = CustomOrderVariantDraft()
            draft.parentItemName = parentItemName
            initialDraft = draft
        }
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }

                Section("Variant") {
                    TextField("Variant name", text: $draft.variantName)
                    LabeledContent("SKU", value: generatedVariantSku)
                    TextField("Barcode", text: $draft.barcode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled(true)
                    LabeledContent(requiresPrice ? "Variant price" : "Variant price (optional)") {
                        TextField("0.00", text: $draft.fixedPrice)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    TextField("Image URL", text: $draft.imageUrl)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    imagePreview(urlString: draft.imageUrl)
                    Toggle("Active", isOn: $draft.isActive)
                }

                Section("Stock") {
                    LabeledContent("Quantity on hand") {
                        TextField("0", text: $draft.quantityOnHand)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Reorder level") {
                        TextField("0", text: $draft.reorderLevel)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .navigationTitle(variant == nil ? "New Variant" : "Edit Variant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving" : "Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await service.saveVariant(draft, customItemId: itemId, existingVariantId: variant?.variantId, requiresPrice: requiresPrice)
            await onSaved()
            dismiss()
        } catch {
            errorMessage = customOrderSetupErrorMessage(error)
        }
    }

    private var generatedVariantSku: String {
        CustomOrderService.generatedSku(from: [parentItemName, draft.variantName])
    }

    @ViewBuilder
    private func imagePreview(urlString: String) -> some View {
        if let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)), !urlString.isEmpty {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                ProgressView()
            }
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

private func customOrderSetupErrorMessage(_ error: Error) -> String {
    let message = error.localizedDescription
    let lower = message.lowercased()

    if lower.contains("duplicate")
        || lower.contains("unique constraint")
        || lower.contains("23505") {
        if lower.contains("custom_order_print_materials")
            || lower.contains("material_name") {
            return "A print material with that name already exists."
        }

        if lower.contains("custom_order_print_size_presets")
            || lower.contains("preset_name") {
            return "That print size name already exists for this material."
        }

        if lower.contains("custom_order_item_barcodes")
            || lower.contains("barcode") {
            return "That barcode is already assigned to another custom order item or variant."
        }

        if lower.contains("custom_order_item_variants")
            || lower.contains("variant_name") {
            return "That variant name or SKU already exists for this item."
        }

        if lower.contains("custom_order_items")
            || lower.contains("item_name")
            || lower.contains("sku") {
            return "That item name or generated SKU already exists. Rename it slightly and try again."
        }
    }

    return message
}
