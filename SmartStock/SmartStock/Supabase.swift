//
//  Supabase.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/15/26.
//

import Foundation
import Supabase

let supabaseURL = URL(string: "https://wbffhygkttoaaodjcvuh.supabase.co")!
let supabasePublishableKey = "sb_publishable_L0x8yZuH_fncrmnNPojWxA_ErICc_-K"

let supabase = SupabaseClient(
    supabaseURL: supabaseURL,
    supabaseKey: supabasePublishableKey,
    options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
            autoRefreshToken: true
        )
    )
)
