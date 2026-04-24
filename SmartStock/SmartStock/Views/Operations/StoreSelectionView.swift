//
//  StoreSelectionView.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/15/26.
//
import SwiftUI

struct StoreSelectionView: View {
    @EnvironmentObject var sessionManager: SessionManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Select Store")
                    .font(.title2)
                    .padding(.top)

                if sessionManager.isLoading {
                    ProgressView("Loading stores...")
                } else if let error = sessionManager.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else if sessionManager.availableStores.isEmpty {
                    Text("No stores found for this user.")
                        .foregroundColor(.secondary)
                } else {
                    List(sessionManager.availableStores) { store in
                        Button {
                            sessionManager.selectedStore = store
                        } label: {
                            Text(store.name)
                        }
                    }
                    .listStyle(.plain)
                }

                Spacer()
            }
            .navigationTitle("Stores")
            .task {
                if sessionManager.availableStores.isEmpty {
                    await sessionManager.loadUserStores()
                }
            }
        }
    }
}
