//
// TimeClockView.swift
// SmartStock
//

import SwiftUI

struct TimeClockView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    private let service = OperationsService()
  
    @State private var activeEntry: TimeClockEntry?
    @State private var todaysEntries: [TimeClockEntry] = []
    @State private var compensationProfile: TimeClockCompensationProfile?
    @State private var hoursWorkedThisPeriod: Double?
    @State private var notes = ""
    @State private var isLoading = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var showClockOutConfirmation = false
    @State private var showShiftEndedAlert = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Status Header
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
                  
                    // MARK: - Today Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Today")
                                .font(.headline)
                            Spacer()
                            if let lastPunchDate = lastPunchDate {
                                Label(lastPunchDate.formatted(date: .abbreviated, time: .omitted),
                                      systemImage: "calendar")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            }
                        }
                        
                        if todaysEntries.isEmpty {
                            Text("No punches recorded today")
                                .foregroundStyle(.secondary)
                                .italic()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(todaysEntries, id: \.clockId) { entry in
                                VStack(alignment: .leading, spacing: 6) {
                                    statusRow(title: "Clocked In", date: entry.clockIn)
                                    if let lunchStart = entry.lunchStart {
                                        statusRow(title: "Lunch Started", date: lunchStart)
                                    }
                                    if let lunchEnd = entry.lunchEnd {
                                        statusRow(title: "Lunch Ended", date: lunchEnd)
                                    }
                                    if let clockOut = entry.clockOut {
                                        statusRow(title: "Clocked Out", date: clockOut)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                  
                    if let compensationProfile {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Summary")
                                .font(.headline)
                            
                            
                            
                            if let currentPayPeriodText = compensationProfile.currentPayPeriodText {
                                payRow(title: "Period", value: currentPayPeriodText)
                            }
                            
                            if let payPeriod = compensationProfile.payPeriod, !payPeriod.isEmpty {
                                payRow(title: "Frequency", value: payPeriod.replacingOccurrences(of: "_", with: " ").capitalized)
                            }
                            
                            payRow(title: "Compensation", value: compensationProfile.compensationType.displayName)

                            if let rateLabel = compensationProfile.rateLabel, let rateAmount = compensationProfile.rateAmount {
                                payRow(title: rateLabel, value: currency(rateAmount))
                            }
                            
                           
                            
                            if compensationProfile.compensationType == .hourly {
                                if let hoursWorkedThisPeriod {
                                    payRow(title: "Total Hours", value: String(format: "%.2f hours", hoursWorkedThisPeriod))
                                } else {
                                    payRow(title: "Total Hours, value: ",value: "Unavailable")
                                }
                            }
                            
                            // NEW: Total Pay for the Period (All Types)
                            if let totalPay = totalPayThisPeriod {
                                payRow(title: "Total Pay", value: currency(totalPay))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.green)
                            }
                            
                            if let payDate = compensationProfile.resolvedPayDate() {
                                payRow(title: "Pay Date", value: payDate.formatted(date: .abbreviated, time: .omitted))
                            }
                           
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                  
                    // Notes
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                  
                    if let successMessage {
                        Text(successMessage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 8)
                    }
                }
                .padding()
            }
            .navigationTitle("Time Clock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Time Clock")
                        .font(.headline)
                }
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
            // Modern Clock Out Confirmation
            .confirmationDialog(
                "End Shift?",
                isPresented: $showClockOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Yes, Clock Out", role: .destructive) {
                    Task { await performClockOut() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                VStack(spacing: 8) {
                    Text("This will end your current shift.")
                    if let hours = hoursWorkedThisPeriod {
                        Text(String(format: "Total hours today: %.2f", hours))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // Shift Already Ended Alert
            .alert("Shift Ended", isPresented: $showShiftEndedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("You have already clocked out for today.\nYou cannot clock back in.")
            }
            .task {
                await loadCurrentState()
            }
        }
    }
  
    // MARK: - Computed Properties
    private var isClockedIn: Bool { activeEntry?.isOpen == true }
    
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
    
    private var lastPunchDate: Date? {
        guard let latest = todaysEntries.max(by: { $0.clockIn < $1.clockIn }) else { return nil }
        return latest.clockOut ?? latest.lunchEnd ?? latest.lunchStart ?? latest.clockIn
    }
    
    // MARK: - Total Pay Calculation (Salary + Daily + Hourly)
    private var totalPayThisPeriod: Double? {
        guard let profile = compensationProfile,
              let rate = profile.rateAmount,
              let interval = profile.payPeriodRange() else {
            return nil
        }
        
        let calendar = Calendar.current
        let daysInPeriod = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 0
        
        switch profile.compensationType {
        case .hourly:
            guard let hours = hoursWorkedThisPeriod else { return nil }
            
            // Round hours to 2 decimal places first
            let roundedHours = (hours * 100).rounded() / 100
            
            // Then multiply by rate
            let rawPay = rate * roundedHours
            
            // Round final pay to 2 decimal places
            return (rawPay * 100).rounded() / 100
            
        case .daily:
            return rate * Double(daysInPeriod)
            
        case .salary:
            // Assuming rateAmount is annual salary
            let daysInYear = 365.0
            let dailyRate = rate / daysInYear
            return dailyRate * Double(daysInPeriod)
            
        default:
            return nil
        }
    }
    
    private var primaryAction: TimeClockAction? {
        if let activeEntry {
            if activeEntry.lunchStart == nil { return .startLunch }
            if activeEntry.lunchEnd == nil { return .endLunch }
            return .clockOut
        }
        return .clockIn
    }
    
    private var secondaryAction: TimeClockAction? {
        guard let activeEntry, activeEntry.lunchStart == nil else { return nil }
        return .clockOut
    }
    
    // MARK: - Data Loading
    private func loadCurrentState() async {
        guard let user = sessionManager.currentUser else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            activeEntry = try await service.fetchOpenTimeClockEntry(userId: user.id)
            todaysEntries = try await service.fetchTimeClockEntriesForToday(userId: user.id)
            compensationProfile = try await service.fetchTimeClockCompensationProfile(userId: user.id)
            hoursWorkedThisPeriod = try await loadHoursWorkedThisPeriod(for: user.id, profile: compensationProfile)
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
        guard let user = sessionManager.currentUser else { return }
        
        isSubmitting = true
        errorMessage = nil
        successMessage = nil
        defer { isSubmitting = false }
        
        do {
            switch action {
            case .clockIn:
                    if activeEntry == nil && !todaysEntries.isEmpty {
                        // Prevent clocking back in after clocking out
                        showShiftEndedAlert = true
                        return
                    }
                    let inserted = try await service.clockIn(user: user, store: sessionManager.selectedStore)
                    self.activeEntry = inserted
                    successMessage = "Clocked in successfully."
            
                
            case .startLunch:
                guard let entry = activeEntry else { return }
                let updated = try await service.startLunch(entryId: entry.clockId)
                self.activeEntry = updated
                successMessage = "Lunch started successfully."
                
            case .endLunch:
                guard let entry = activeEntry else { return }
                let updated = try await service.endLunch(entryId: entry.clockId)
                self.activeEntry = updated
                successMessage = "Lunch ended successfully."
                
            case .clockOut:
                showClockOutConfirmation = true   // Show confirmation
                return   // Don't clock out yet
            }
            
            notes = ""
            if let userId = sessionManager.currentUser?.id {
                todaysEntries = try await service.fetchTimeClockEntriesForToday(userId: userId)
                activeEntry = try await service.fetchOpenTimeClockEntry(userId: userId)
                hoursWorkedThisPeriod = try await loadHoursWorkedThisPeriod(for: userId, profile: compensationProfile)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func performClockOut() async {
        guard let user = sessionManager.currentUser, let entry = activeEntry else { return }
        
        isSubmitting = true
        defer { isSubmitting = false }
        
        do {
            _ = try await service.clockOut(entryId: entry.clockId)
            self.activeEntry = nil
            successMessage = "Clocked out successfully."
            
            notes = ""
            if let userId = sessionManager.currentUser?.id {
                todaysEntries = try await service.fetchTimeClockEntriesForToday(userId: userId)
                activeEntry = try await service.fetchOpenTimeClockEntry(userId: userId)
                hoursWorkedThisPeriod = try await loadHoursWorkedThisPeriod(for: userId, profile: compensationProfile)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    // MARK: - View Builders
    @ViewBuilder
    private func actionButton(for action: TimeClockAction, prominent: Bool) -> some View {
        if prominent {
            Button { perform(action) } label: {
                if isSubmitting {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Label(action.title, systemImage: action.systemImage)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isLoading || isSubmitting)
        } else {
            Button { perform(action) } label: {
                if isSubmitting {
                    ProgressView().frame(maxWidth: .infinity)
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
        guard let profile,
              profile.compensationType == .hourly,
              let interval = profile.payPeriodRange() else {
            return nil
        }
        return try await service.fetchWorkedHours(userId: userId, from: interval.start, to: interval.end)
    }
}

// MARK: - TimeClockAction
private enum TimeClockAction {
    case clockIn, startLunch, endLunch, clockOut
    
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
