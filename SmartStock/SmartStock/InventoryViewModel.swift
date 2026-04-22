//
//  InventoryViewModel.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/15/26.
//

import Foundation
import Combine

@MainActor
final class InventoryViewModel: ObservableObject {
    @Published var items: [InventoryItem] = []
    @Published var searchText: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedStatus: InventoryStockStatus?
    @Published var selectedLocationId: Int?

    private let service: InventoryService

    init(service: InventoryService = InventoryService()) {
        self.service = service
    }

    var filteredItems: [InventoryItem] {
        items
            .filter { item in
                let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                let matchesSearch: Bool

                if trimmed.isEmpty {
                    matchesSearch = true
                } else {
                    let query = trimmed.lowercased()
                    matchesSearch = item.name.lowercased().contains(query)
                        || item.sku.lowercased().contains(query)
                        || item.quantityText.contains(query)
                        || item.reorderLevelText.contains(query)
                        || String(item.productId).contains(query)
                        || (item.barcode?.lowercased().contains(query) ?? false)
                        || (item.categoryName?.lowercased().contains(query) ?? false)
                        || item.locationName.lowercased().contains(query)
                }

                let matchesStatus = selectedStatus == nil || item.status == selectedStatus
                let matchesLocation = selectedLocationId == nil || item.locationId == selectedLocationId

                return matchesSearch && matchesStatus && matchesLocation
            }
            .sorted { lhs, rhs in
                if lhs.locationName != rhs.locationName {
                    return lhs.locationName.localizedCaseInsensitiveCompare(rhs.locationName) == .orderedAscending
                }
                if lhs.status != rhs.status {
                    return statusSortOrder(lhs.status) < statusSortOrder(rhs.status)
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    var totalItemsCount: Int {
        filteredItems.count
    }

    var lowStockCount: Int {
        filteredItems.filter { $0.status == .lowStock }.count
    }

    var outOfStockCount: Int {
        filteredItems.filter { $0.status == .outOfStock || $0.status == .negative }.count
    }

    var locations: [(id: Int, name: String)] {
        Array(
            Dictionary(grouping: items, by: { $0.locationId })
                .compactMap { key, value in
                    guard let first = value.first else { return nil }
                    return (id: key, name: first.locationName)
                }
        )
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func loadInventory(locationId: Int? = nil) async {
        isLoading = true
        errorMessage = nil

        do {
            items = try await service.fetchInventory(for: locationId)
            if let locationId {
                selectedLocationId = locationId
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func refresh(locationId: Int? = nil) async {
        await loadInventory(locationId: locationId)
    }

    func selectAllLocations() {
        selectedLocationId = nil
    }

    private func statusSortOrder(_ status: InventoryStockStatus) -> Int {
        switch status {
        case .negative:
            return 0
        case .outOfStock:
            return 1
        case .lowStock:
            return 2
        case .inStock:
            return 3
        case .notTracked:
            return 4
        }
    }
}
