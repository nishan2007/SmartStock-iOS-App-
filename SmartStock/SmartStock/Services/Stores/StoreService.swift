//
//  StoreService.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/16/26.
//

//
//  StoreService.swift
//  SmartStock
//

import Foundation
import Supabase

final class StoreService {
    static let shared = StoreService()

    private let client = supabase
    private let decoder: JSONDecoder

    private init() {
        self.decoder = JSONDecoder()
    }

    func fetchStores() async throws -> [Store] {
        let response = try await client
            .from("locations")
            .select("location_id, name, address, created_at")
            .order("name", ascending: true)
            .execute()

        let rows = try decoder.decode([StoreRowDTO].self, from: response.data)

        return rows.map {
            Store(
                id: $0.location_id,
                name: $0.name,
                address: $0.address,
                createdAt: nil
            )
        }
    }
}

private struct StoreRowDTO: Decodable {
    let location_id: Int
    let name: String
    let address: String?
    let created_at: String?
}
