//
//  TimeClockView.swift
//  SmartStock
//

import SwiftUI

struct TimeClockView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    private let service = OperationsService()

    @State private var activeEntry: TimeClockEntry?
    @State private var compensationProfile: TimeClockCompensationProfile?
    @State private var hoursWorkedThisPeriod: Double?
    @State private var lastPunch: Date?
    @State private var notes = ""
    @State private var isLoading = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Image(systemName: statusIconName)
                        .font(.system(size: 44))
                        .foregroundStyle(statusColor)

                    Text(statusTitle)
                        .font(.title3.weight(.bold))

                    Text(sessionManager.currentUser?.fullName ?? "Current user")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .padding(.horizontal, 16)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let successMessage {
                    Text(successMessage)
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let lastPunch {
                    Label(lastPunch.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let compensationProfile {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pay")
                            .font(.headline)

                        payRow(title: "Type", value: compensationProfile.compensationType.displayName)

                    if let payPeriod = compensationProfile.payPeriod, !payPeriod.isEmpty {
                        payRow(title: "Pay Period", value: payPeriod.replacingOccurrences(of: "_", with: " ").capitalized)
                    }

                    if let currentPayPeriodText = compensationProfile.currentPayPeriodText {
                        payRow(title: "Current Period", value: currentPayPeriodText)
                    }

                    if let rateLabel = compensationProfile.rateLabel, let rateAmount = compensationProfile.rateAmount {
                        payRow(title: rateLabel, value: currency(rateAmount))
                    }

                    if let payDate = compensationProfile.resolvedPayDate() {
                        payRow(title: "Pay Date", value: payDate.formatted(date: .abbreviated, time: .omitted))
                    }

                    if compensationProfile.compensationType == .hourly {
                        if let hoursWorkedThisPeriod {
                                payRow(title: "Hours This Period", value: String(format: "%.2f", hoursWorkedThisPeriod))
                            } else {
                                payRow(title: "Hours This Period", value: "Unavailable")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                if let activeEntry, isClockedIn {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Today")
                            .font(.headline)

                        statusRow(title: "Clock In", date: activeEntry.clockIn)
                        if let lunchStart = activeEntry.lunchStart {
                            statusRow(title: "Lunch Start", date: lunchStart)
                        }
                        if let lunchEnd = activeEntry.lunchEnd {
                            statusRow(title: "Lunch End", date: lunchEnd)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding()
        }
        .padding()
        .navigationTitle("Time Clock")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    TimeClockHistoryView()
                        .environmentObject(sessionManager)
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel("Time clock history")
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                if let primaryAction {
                    actionButton(for: primaryAction, prominent: true)
                }

                if let secondaryAction {
                    actionButton(for: secondaryAction, prominent: false)
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(.ultraThinMaterial)
        }
        .task {
            await loadCurrentState()
        }
    }

    private var isClockedIn: Bool {
        activeEntry?.isOpen == true
    }

    private var isOnLunch: Bool {
        guard let activeEntry else { return false }
        return activeEntry.lunchStart != nil && activeEntry.lunchEnd == nil && activeEntry.clockOut == nil
    }

    private var statusTitle: String {
        if isOnLunch { return "On Lunch" }
        return isClockedIn ? "Clocked In" : "Clocked Out"
    }

    private var statusIconName: String {
        if isOnLunch { return "fork.knife.circle.fill" }
        return isClockedIn ? "clock.badge.checkmark.fill" : "clock.fill"
    }

    private var statusColor: Color {
        if isOnLunch { return .orange }
        return isClockedIn ? .green : .orange
    }

    private var primaryAction: TimeClockAction? {
        if let activeEntry {
            if activeEntry.lunchStart == nil {
                return .startLunch
            }
            if activeEntry.lunchEnd == nil {
                return .endLunch
            }
            return .clockOut
        }
        return .clockIn
    }

    private var secondaryAction: TimeClockAction? {
        guard let activeEntry, activeEntry.lunchStart == nil else { return nil }
        return .clockOut
    }

    private func loadCurrentState() async {
        guard let user = sessionManager.currentUser else {
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            activeEntry = try await service.fetchOpenTimeClockEntry(userId: user.id)
            compensationProfile = try await service.fetchTimeClockCompensationProfile(userId: user.id)
            hoursWorkedThisPeriod = try await loadHoursWorkedThisPeriod(for: user.id, profile: compensationProfile)
            syncLastPunch()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func perform(_ action: TimeClockAction) {
        Task {
            await performAction(action)
        }
    }

    private func performAction(_ action: TimeClockAction) async {
        guard let user = sessionManager.currentUser else {
            errorMessage = "No signed in user found."
            return
        }

        isSubmitting = true
        errorMessage = nil
        successMessage = nil
        defer { isSubmitting = false }

        do {
            switch action {
            case .clockIn:
                let inserted = try await service.clockIn(user: user, store: sessionManager.selectedStore)
                self.activeEntry = inserted
                self.successMessage = "Clocked in successfully."
                syncLastPunch()
            case .startLunch:
                guard let activeEntry else { return }
                let updated = try await service.startLunch(entryId: activeEntry.clockId)
                self.activeEntry = updated
                self.successMessage = "Lunch started successfully."
                syncLastPunch()
            case .endLunch:
                guard let activeEntry else { return }
                let updated = try await service.endLunch(entryId: activeEntry.clockId)
                self.activeEntry = updated
                self.successMessage = "Lunch ended successfully."
                syncLastPunch()
            case .clockOut:
                guard let activeEntry else { return }
                let updated = try await service.clockOut(entryId: activeEntry.clockId)
                self.activeEntry = nil
                self.lastPunch = updated.clockOut
                self.successMessage = "Clocked out successfully."
            }

            notes = ""

            if let userId = sessionManager.currentUser?.id {
                hoursWorkedThisPeriod = try await loadHoursWorkedThisPeriod(for: userId, profile: compensationProfile)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func syncLastPunch() {
        if let activeEntry {
            lastPunch = activeEntry.lunchEnd ?? activeEntry.lunchStart ?? activeEntry.clockIn
        } else {
            lastPunch = nil
        }
    }

    @ViewBuilder
    private func actionButton(for action: TimeClockAction, prominent: Bool) -> some View {
        if prominent {
            Button {
                perform(action)
            } label: {
                if isSubmitting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label(action.title, systemImage: action.systemImage)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isLoading || isSubmitting)
        } else {
            Button {
                perform(action)
            } label: {
                if isSubmitting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label(action.title, systemImage: action.systemImage)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isLoading || isSubmitting)
        }
    }

    private func statusRow(title: String, date: Date) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(date.formatted(date: .omitted, time: .shortened))
                .fontWeight(.semibold)
        }
    }

    private func payRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }

    private func currency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    private func loadHoursWorkedThisPeriod(for userId: Int, profile: TimeClockCompensationProfile?) async throws -> Double? {
        guard
            let profile,
            profile.compensationType == .hourly,
            let interval = profile.payPeriodRange()
        else {
            return nil
        }

        return try await service.fetchWorkedHours(userId: userId, from: interval.start, to: interval.end)
    }
}

private enum TimeClockAction {
    case clockIn
    case startLunch
    case endLunch
    case clockOut

    var title: String {
        switch self {
        case .clockIn: return "Clock In"
        case .startLunch: return "Start Lunch"
        case .endLunch: return "End Lunch"
        case .clockOut: return "Clock Out"
        }
    }

    var systemImage: String {
        switch self {
        case .clockIn: return "rectangle.portrait.and.arrow.forward"
        case .startLunch: return "fork.knife"
        case .endLunch: return "arrow.uturn.backward.circle"
        case .clockOut: return "rectangle.portrait.and.arrow.right"
        }
    }
}
