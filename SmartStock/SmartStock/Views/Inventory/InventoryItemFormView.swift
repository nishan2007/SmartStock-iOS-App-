//
//  InventoryItemFormView.swift
//  SmartStock
//

import Combine
import SwiftUI
import UIKit

struct InventoryItemFormView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionManager: SessionManager
    @StateObject private var viewModel: InventoryItemFormViewModel
    @State private var imageSource: UIImagePickerController.SourceType?
    @State private var isShowingImageOptions = false
    @State private var isShowingScanner = false
    @State private var scanTarget: BarcodeScanTarget = .primary

    let onSaved: () -> Void

    init(mode: InventoryEditorMode, defaultStore: Store?, onSaved: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: InventoryItemFormViewModel(mode: mode, defaultStore: defaultStore))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    hero
                    productSection
                    pricingSection
                    inventorySection
                    organizationSection
                    barcodeSection
                    imageSection

                    if let message = viewModel.errorMessage {
                        Text(message)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.red.opacity(0.09))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    Button {
                        Task {
                            let saved = await viewModel.save(user: sessionManager.currentUser)
                            if saved {
                                onSaved()
                                dismiss()
                            }
                        }
                    } label: {
                        HStack {
                            if viewModel.isSaving {
                                ProgressView()
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            Text(viewModel.mode.actionTitle)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(viewModel.isSaving)
                }
                .padding()
            }
            .background(
                LinearGradient(
                    colors: [Color.cyan.opacity(0.12), Color.orange.opacity(0.10), Color(.systemBackground)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle(viewModel.mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.load()
            }
            .sheet(isPresented: $isShowingScanner) {
                BarcodeScannerSheet(
                    scannedCode: .constant(""),
                    isPresented: $isShowingScanner,
                    onScanned: { code in
                        viewModel.applyScannedBarcode(code, to: scanTarget)
                    }
                )
            }
            .confirmationDialog("Product Image", isPresented: $isShowingImageOptions) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo") {
                        imageSource = .camera
                    }
                }
                Button("Choose Photo") {
                    imageSource = .photoLibrary
                }
                if viewModel.selectedImage != nil || !viewModel.draft.imageURL.isEmpty {
                    Button("Remove Image", role: .destructive) {
                        viewModel.clearImage()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $imageSource) { source in
                ImagePicker(sourceType: source, selectedImage: $viewModel.selectedImage)
            }
        }
    }

    private var canAdjustInventoryQuantity: Bool {
        sessionManager.currentUser?.canAccess(.adjustInventoryQuantity) == true
    }

    private var canEditInventoryFields: Bool {
        switch viewModel.mode {
        case .add:
            return true
        case .edit:
            return canAdjustInventoryQuantity
        }
    }

    private var isEditingItem: Bool {
        if case .edit = viewModel.mode {
            return true
        }
        return false
    }

    private var canViewCostPrice: Bool {
        sessionManager.currentUser?.canAccess(.viewCostPrice) == true
    }

    private var hero: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.mint, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: viewModel.mode == .add ? "plus.app.fill" : "pencil.and.list.clipboard")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.mode == .add ? "Build a product record" : "Tune this product")
                    .font(.headline)
                Text("Scan barcodes, add a photo, and keep stock details current.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground).opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var productSection: some View {
        formSection(title: "Product", tint: .blue, systemImage: "shippingbox.fill") {
            TextField("Item name", text: $viewModel.draft.name)
                .textInputAutocapitalization(.words)
            TextField("SKU", text: $viewModel.draft.sku)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            barcodeField("Primary barcode", text: $viewModel.draft.barcode, target: .primary)
            TextField("Description", text: $viewModel.draft.description, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    private var pricingSection: some View {
        formSection(title: "Pricing", tint: .green, systemImage: "dollarsign.circle.fill") {
            if canViewCostPrice {
                TextField("Cost price", text: $viewModel.draft.costPrice)
                    .keyboardType(.decimalPad)
            }
            TextField("Sale price", text: $viewModel.draft.price)
                .keyboardType(.decimalPad)
            Picker("Item type", selection: $viewModel.draft.productType) {
                ForEach(ProductType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var inventorySection: some View {
        formSection(title: "Stock", tint: .orange, systemImage: "chart.bar.fill") {
            if viewModel.draft.isInventoryItem {
                if isEditingItem {
                    LabeledContent("Store", value: sessionManager.selectedStore?.name ?? viewModel.stores.first(where: { $0.id == viewModel.draft.locationId })?.name ?? "Current Store")
                }

                if canEditInventoryFields {
                    if !isEditingItem {
                        Picker("Store", selection: $viewModel.draft.locationId) {
                            Text("Choose Store").tag(Int?.none)
                            ForEach(viewModel.stores) { store in
                                Text(store.name).tag(Int?.some(store.id))
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Quantity")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("Quantity", text: $viewModel.draft.quantity)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reorder Level")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("Reorder level", text: $viewModel.draft.reorderLevel)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                    }
                } else {
                    Label("Manual quantity changes in Edit Item require the Adjust Inventory Quantity permission.", systemImage: "lock.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Label("Services and non-inventory items do not track quantity.", systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var organizationSection: some View {
        formSection(title: "Organization", tint: .purple, systemImage: "folder.fill") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Department")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Department", selection: $viewModel.draft.categoryId) {
                    Text("None").tag(Int?.none)
                    ForEach(viewModel.departments) { department in
                        Text(department.name).tag(Int?.some(department.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text("Vendor")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Vendor", selection: $viewModel.draft.vendorId) {
                    Text("None").tag(Int?.none)
                    ForEach(viewModel.vendors) { vendor in
                        Text(vendor.name).tag(Int?.some(vendor.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var barcodeSection: some View {
        formSection(title: "Extra Barcodes", tint: .pink, systemImage: "barcode.viewfinder") {
            TextField("One barcode per line", text: $viewModel.draft.additionalBarcodes, axis: .vertical)
                .lineLimit(3...7)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)

            Button {
                scanTarget = .additional
                isShowingScanner = true
            } label: {
                Label("Scan Additional Barcode", systemImage: "barcode.viewfinder")
            }
            .buttonStyle(.bordered)
        }
    }

    private var imageSection: some View {
        formSection(title: "Image", tint: .teal, systemImage: "camera.fill") {
            HStack(spacing: 14) {
                imagePreview
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Photos are compressed to 200 KB or less before upload.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        isShowingImageOptions = true
                    } label: {
                        Label("Camera or Library", systemImage: "photo.badge.plus")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let image = viewModel.selectedImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if let url = URL(string: viewModel.draft.imageURL), !viewModel.draft.imageURL.isEmpty {
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
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }

    private func barcodeField(_ title: String, text: Binding<String>, target: BarcodeScanTarget) -> some View {
        HStack {
            TextField(title, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            Button {
                scanTarget = target
                isShowingScanner = true
            } label: {
                Image(systemName: "barcode.viewfinder")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
        }
    }

    private func formSection<Content: View>(
        title: String,
        tint: Color,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(tint)

            VStack(spacing: 12) {
                content()
            }
        }
        .padding()
        .background(Color(.systemBackground).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

enum BarcodeScanTarget {
    case primary
    case additional
}

@MainActor
final class InventoryItemFormViewModel: ObservableObject {
    @Published var draft: InventoryItemDraft
    @Published var stores: [Store] = []
    @Published var departments: [InventoryLookupOption] = []
    @Published var vendors: [VendorLookupOption] = []
    @Published var selectedImage: UIImage?
    @Published var errorMessage: String?
    @Published var isSaving = false

    let mode: InventoryEditorMode
    private let service = InventoryEditorService()
    private let defaultStore: Store?
    private var didLoad = false

    init(mode: InventoryEditorMode, defaultStore: Store?) {
        self.mode = mode
        self.defaultStore = defaultStore

        switch mode {
        case .add:
            var draft = InventoryItemDraft()
            draft.locationId = defaultStore?.id
            self.draft = draft
        case .edit(let item):
            self.draft = InventoryItemDraft(item: item)
        }
    }

    func load() async {
        guard !didLoad else { return }
        didLoad = true
        errorMessage = nil

        do {
            async let stores = service.fetchStores()
            async let departments = service.fetchDepartments()
            async let vendors = service.fetchVendors()

            self.stores = try await stores
            self.departments = try await departments
            self.vendors = try await vendors

            if draft.locationId == nil {
                draft.locationId = defaultStore?.id ?? self.stores.first?.id
            }

            if case .edit(let item) = mode {
                draft = try await service.fetchEditableProduct(productId: item.productId, locationId: item.locationId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save(user: AppUser?) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await service.save(draft: draft, selectedImage: selectedImage, user: user)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func applyScannedBarcode(_ code: String, to target: BarcodeScanTarget) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch target {
        case .primary:
            draft.barcode = trimmed
        case .additional:
            let separator = draft.additionalBarcodes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n"
            draft.additionalBarcodes += "\(separator)\(trimmed)"
        }
    }

    func clearImage() {
        selectedImage = nil
        draft.imageURL = ""
    }
}

extension UIImagePickerController.SourceType: @retroactive Identifiable {
    public var id: Int { rawValue }
}
