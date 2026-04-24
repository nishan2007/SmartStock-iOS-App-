//
//  TimeClockHistoryView.swift
//  SmartStock
//

import SwiftUI

struct TimeClockHistoryView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    private let service = OperationsService()

    @State private var entries: [TimeClockEntry] = []
    @State private var compensationProfile: TimeClockCompensationProfile?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            if isLoading {
                Section {
                    ProgressView("Loading time clock history...")
                }
            } else if entries.isEmpty {
                Section {
                    ContentUnavailableView("No Time Clock History", systemImage: "clock.arrow.circlepath")
                }
            } else {
                ForEach(entries, id: \.clockId) { entry in
                    Section(entryTitle(for: entry)) {
                        historyRow("Clock In", value: timestampText(for: entry.clockIn))

                        if let lunchStart = entry.lunchStart {
                            historyRow("Lunch Start", value: timestampText(for: lunchStart))
                        }

                        if let lunchEnd = entry.lunchEnd {
                            historyRow("Lunch End", value: timestampText(for: lunchEnd))
                        }

                        if let clockOut = entry.clockOut {
                            historyRow("Clock Out", value: timestampText(for: clockOut))
                        } else {
                            historyRow("Clock Out", value: "Open Shift")
                        }

                        historyRow("Total Hours", value: String(format: "%.2f", entry.workedHours()))

                        if let locationName = entry.locationName, !locationName.isEmpty {
                            historyRow("Store", value: locationName)
                        }

                        if isHourly, let earned = earnedAmount(for: entry) {
                            historyRow("Earned", value: currency(earned))
                        }
                    }
                }
            }
        }
        .navigationTitle("Time Clock History")
        .task {
            await loadHistory()
        }
        .refreshable {
            await loadHistory()
        }
    }

    private var isHourly: Bool {
        compensationProfile?.compensationType == .hourly
    }

    private func loadHistory() async {
        guard let user = sessionManager.currentUser else {
            isLoading = false
            errorMessage = "No signed in user found."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let historyTask = service.fetchTimeClockHistory(userId: user.id)
            async let payTask = service.fetchTimeClockCompensationProfile(userId: user.id)
            entries = try await historyTask
            compensationProfile = try await payTask
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func historyRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
    }

    private func entryTitle(for entry: TimeClockEntry) -> String {
        entry.clockIn.formatted(date: .abbreviated, time: .omitted)
    }

    private func timestampText(for date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func earnedAmount(for entry: TimeClockEntry) -> Double? {
        guard let rate = compensationProfile?.rateAmount else { return nil }
        return entry.workedHours() * rate
    }

    private func currency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }
}
