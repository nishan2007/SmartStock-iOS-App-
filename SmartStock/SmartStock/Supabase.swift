//
//  Supabase.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/15/26.
//

import Foundation
import Supabase

let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://wbffhygkttoaaodjcvuh.supabase.co")!,
    supabaseKey: "sb_publishable_L0x8yZuH_fncrmnNPojWxA_ErICc_-K",
    options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
            autoRefreshToken: true
        )
    )
)
