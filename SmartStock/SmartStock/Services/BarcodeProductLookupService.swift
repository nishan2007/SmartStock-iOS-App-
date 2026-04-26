//
//  BarcodeProductLookupService.swift
//  SmartStock
//

import Foundation

struct BarcodeProductSuggestion {
    let barcode: String
    let name: String?
    let description: String?
    let imageURL: String?
}

enum BarcodeProductLookupError: LocalizedError {
    case invalidBarcode
    case notFound
    case invalidResponse
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .invalidBarcode:
            return "Enter or scan a barcode first."
        case .notFound:
            return "No public product details were found for that barcode."
        case .invalidResponse:
            return "Product lookup returned an invalid response."
        case .rateLimited:
            return "UPCitemdb free lookup limit was reached. Try again later."
        }
    }
}

struct BarcodeProductLookupService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func lookup(barcode: String) async throws -> BarcodeProductSuggestion {
        let trimmedBarcode = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBarcode.isEmpty else {
            throw BarcodeProductLookupError.invalidBarcode
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.upcitemdb.com"
        components.path = "/prod/trial/lookup"
        components.queryItems = [
            URLQueryItem(name: "upc", value: trimmedBarcode)
        ]

        guard let url = components.url else {
            throw BarcodeProductLookupError.invalidBarcode
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("SmartStock-iOS/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BarcodeProductLookupError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            throw BarcodeProductLookupError.rateLimited
        }

        if httpResponse.statusCode == 404 {
            throw BarcodeProductLookupError.notFound
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BarcodeProductLookupError.invalidResponse
        }

        let lookupResponse = try JSONDecoder().decode(UPCItemDBResponse.self, from: data)
        guard lookupResponse.code == "OK",
              let product = lookupResponse.items.first else {
            throw BarcodeProductLookupError.notFound
        }

        let name = product.title.trimmedNilIfEmpty
            ?? product.offers.compactMap { $0.title.trimmedNilIfEmpty }.first

        let description = [
            product.description.trimmedNilIfEmpty,
            product.brand.trimmedNilIfEmpty.map { "Brand: \($0)" },
            product.model.trimmedNilIfEmpty.map { "Model: \($0)" },
            product.category.trimmedNilIfEmpty.map { "Category: \($0)" },
            product.color.trimmedNilIfEmpty.map { "Color: \($0)" },
            product.size.trimmedNilIfEmpty.map { "Size: \($0)" }
        ]
            .compactMap { $0 }
            .joined(separator: "\n")
            .trimmedNilIfEmpty

        let imageURL = product.images.compactMap { $0.trimmedNilIfEmpty }.first

        guard name != nil || description != nil || imageURL != nil else {
            throw BarcodeProductLookupError.notFound
        }

        return BarcodeProductSuggestion(
            barcode: product.upc.trimmedNilIfEmpty
                ?? product.ean.trimmedNilIfEmpty
                ?? product.gtin.trimmedNilIfEmpty
                ?? trimmedBarcode,
            name: name,
            description: description,
            imageURL: imageURL
        )
    }
}

private struct UPCItemDBResponse: Decodable {
    let code: String
    let total: Int?
    let items: [UPCItemDBItem]
}

private struct UPCItemDBItem: Decodable {
    let ean: String?
    let upc: String?
    let gtin: String?
    let title: String?
    let description: String?
    let brand: String?
    let model: String?
    let color: String?
    let size: String?
    let category: String?
    let images: [String]
    let offers: [UPCItemDBOffer]
}

private struct UPCItemDBOffer: Decodable {
    let title: String?
}

private extension Optional where Wrapped == String {
    var trimmedNilIfEmpty: String? {
        guard let value = self else { return nil }
        return value.trimmedNilIfEmpty
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
