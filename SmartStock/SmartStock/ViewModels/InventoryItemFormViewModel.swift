//
//  InventoryItemFormViewModel.swift
//  SmartStock
//

import Combine
import Foundation
import UIKit

@MainActor
final class InventoryItemFormViewModel: ObservableObject {
    @Published var draft: InventoryItemDraft
    @Published var stores: [Store] = []
    @Published var departments: [InventoryLookupOption] = []
    @Published var vendors: [VendorLookupOption] = []
    @Published var selectedImage: UIImage?
    @Published var errorMessage: String?
    @Published var isSaving = false
    @Published var isLookingUpBarcode = false
    @Published var barcodeLookupMessage: String?

    let mode: InventoryEditorMode
    let successfulBarcodeLookupMessage = "Product details found. Review and edit before saving."
    private let service = InventoryEditorService()
    private let barcodeLookupService = BarcodeProductLookupService()
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
            if let returnedSku = try await service.save(draft: draft, selectedImage: selectedImage, user: user) {
                draft.sku = returnedSku
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func applyScannedBarcode(_ code: String, to target: BarcodeScanTarget) async {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch target {
        case .primary:
            draft.barcode = trimmed
            if mode == .add {
                await lookupBarcodeDetails()
            }
        case .additional:
            let separator = draft.additionalBarcodes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n"
            draft.additionalBarcodes += "\(separator)\(trimmed)"
        }
    }

    func lookupBarcodeDetails() async {
        let barcode = draft.barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !barcode.isEmpty else {
            barcodeLookupMessage = BarcodeProductLookupError.invalidBarcode.localizedDescription
            return
        }

        isLookingUpBarcode = true
        barcodeLookupMessage = nil
        defer { isLookingUpBarcode = false }

        do {
            let suggestion = try await barcodeLookupService.lookup(barcode: barcode)
            apply(suggestion)
            barcodeLookupMessage = successfulBarcodeLookupMessage
        } catch {
            barcodeLookupMessage = error.localizedDescription
        }
    }

    private func apply(_ suggestion: BarcodeProductSuggestion) {
        draft.barcode = suggestion.barcode

        if let name = suggestion.name,
           draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.name = name
        }

        if let description = suggestion.description,
           draft.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.description = description
        }

        if let imageURL = suggestion.imageURL,
           draft.imageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           selectedImage == nil {
            draft.imageURL = imageURL
        }
    }

    func clearImage() {
        selectedImage = nil
        draft.imageURL = ""
    }
}
