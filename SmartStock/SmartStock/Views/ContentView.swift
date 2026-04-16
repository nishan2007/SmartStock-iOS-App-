//
//  ContentView.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/15/26.
//
import SwiftUI
import Supabase

struct ContentView: View {
    @StateObject private var sessionManager = SessionManager()

    var body: some View {
        Group {
            if sessionManager.isLoading && sessionManager.currentUser == nil {
                ProgressView("Loading...")
            } else if sessionManager.currentUser == nil {
                LoginView()
                    .environmentObject(sessionManager)
            } else if sessionManager.selectedStore == nil {
                StoreSelectionView()
                    .environmentObject(sessionManager)
            } else {
                MainMenuView()
                    .environmentObject(sessionManager)
            }
        }
        .task {
            await sessionManager.restoreSession()
        }
    }
}
