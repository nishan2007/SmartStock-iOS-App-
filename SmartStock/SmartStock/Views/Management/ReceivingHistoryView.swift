//
//  ReceivingHistoryView.swift
//  SmartStock
//

import SwiftUI
import Supabase

struct ReceivingHistoryView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @State private var rows: [ReceivingHistoryRow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if !canViewReceivingHistory {
                Section {
                    Text("You do not have permission to view receiving history.")
                        .foregroundStyle(.secondary)
                }
            } else if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }

            Section("Receiving History") {
                if !canViewReceivingHistory {
                    EmptyView()
                } else if isLoading {
                    ProgressView("Loading receiving history...")
                } else if rows.isEmpty {
                    ContentUnavailableView("No Receiving History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                } else {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(row.productName)
                                    .font(.headline)
                                Spacer()
                                Text(row.quantityText)
                                    .font(.headline)
                            }
                            Text("\(row.storeName) • \(row.sourceText)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let receiveId = row.receiveIdText {
                                Text("Receive ID: \(receiveId)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let enteredBy = row.enteredByText {
                                Text("Entered By: \(enteredBy)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let note = row.noteText {
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
        .navigationTitle("Receiving History")
        .task {
            guard canViewReceivingHistory else { return }
            await loadHistory()
        }
        .refreshable {
            guard canViewReceivingHistory else { return }
            await loadHistory()
        }
    }

    private var canViewReceivingHistory: Bool {
        sessionManager.currentUser?.canAccess(.viewReceivingHistory) == true
            || sessionManager.currentUser?.canAccess(.receiving) == true
    }

    private func loadHistory() async {
        guard let selectedStore = sessionManager.selectedStore else {
            rows = []
            errorMessage = "Select a store to view receiving history."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            rows = try await supabase
                .from("inventory_movements")
                .select("movement_id, change_qty, reason, note, created_at, receive_id, user_name, products(name), locations(name)")
                .in("reason", values: ["receive", "INVENTORY_ENTRY"])
                .eq("location_id", value: selectedStore.id)
                .order("created_at", ascending: false)
                .limit(200)
                .execute()
                .value
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
