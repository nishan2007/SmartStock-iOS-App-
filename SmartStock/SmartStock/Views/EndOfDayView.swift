//
//  EndOfDayView.swift
//  SmartStock
//

import SwiftUI

struct EndOfDayView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @State private var countedCash = ""
    @State private var notes = ""
    @State private var includeInventorySnapshot = true

    var body: some View {
        Form {
            Section("Store") {
                Label(sessionManager.selectedStore?.name ?? "No store selected", systemImage: "storefront")
                Label(Date.now.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
            }

            Section("Closeout") {
                TextField("Counted cash", text: $countedCash)
                    .keyboardType(.decimalPad)
                Toggle("Include inventory snapshot", isOn: $includeInventorySnapshot)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section {
                Button {
                    countedCash = ""
                    notes = ""
                    includeInventorySnapshot = true
                } label: {
                    Label("Close Day", systemImage: "checkmark.seal.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("End of Day")
    }
}
