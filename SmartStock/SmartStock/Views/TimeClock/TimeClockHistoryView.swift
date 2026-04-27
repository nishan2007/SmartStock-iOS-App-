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
    
    @State private var currentDate = Date()
    @State private var selectedDate: Date?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Month Header
                HStack {
                    Button { changeMonth(by: -1) } label: {
                        Image(systemName: "chevron.left").font(.title3).padding(8)
                    }
                    
                    Spacer()
                    Text(currentDate.formatted(.dateTime.month(.wide).year()))
                        .font(.headline)
                    
                    Spacer()
                    
                    Button { changeMonth(by: 1) } label: {
                        Image(systemName: "chevron.right").font(.title3).padding(8)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                
                // Calendar
                CalendarGridView(
                    currentDate: currentDate,
                    entries: entries,
                    compensationProfile: compensationProfile,
                    selectedDate: $selectedDate
                )
                .padding(.horizontal)
                
                Spacer(minLength: 40)
            }
        }
        .navigationTitle("Time Clock History")
        .task { await loadHistory() }
        .refreshable { await loadHistory() }
        
        // MARK: - Modern Bottom Sheet Modal
        .sheet(isPresented: Binding(
            get: { selectedDate != nil },
            set: { if !$0 { selectedDate = nil } }
        )) {
            if let date = selectedDate {
                SelectedDayDetailView(
                    date: date,
                    entries: entries,
                    compensationProfile: compensationProfile
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationBackground(.ultraThinMaterial)
            }
        }
    }
    
    private func loadHistory() async {
        guard let user = sessionManager.currentUser else { return }
        
        isLoading = true
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
    
    private func changeMonth(by months: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: months, to: currentDate) {
            currentDate = newDate
            selectedDate = nil
        }
    }
}

// MARK: - Calendar Grid (Fixed with LazyVGrid)
struct CalendarGridView: View {
    let currentDate: Date
    let entries: [TimeClockEntry]
    let compensationProfile: TimeClockCompensationProfile?
    @Binding var selectedDate: Date?
    
    private var days: [Date] {
        let calendar = Calendar.current
        let startOfMonth = calendar.startOfMonth(for: currentDate)
        let daysInMonth = calendar.range(of: .day, in: .month, for: currentDate)!.count
        let firstWeekday = calendar.component(.weekday, from: startOfMonth) - 1
        
        var days: [Date] = []
        for _ in 0..<firstWeekday { days.append(Date.distantPast) }
        for day in 1...daysInMonth {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth) {
                days.append(date)
            }
        }
        return days
    }
    
    var body: some View {
        VStack(spacing: 10) {
            // Weekday headers
            HStack(spacing: 6) {
                ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { weekday in
                    Text(weekday)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 4)
            
            // Perfect 7-column grid
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7),
                spacing: 8
            ) {
                ForEach(days, id: \.self) { date in
                    if date == Date.distantPast {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                    } else {
                        DayCell(
                            date: date,
                            entries: entriesFor(date: date),           // ← changed
                            isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate ?? Date.distantPast)
                        )
                        .onTapGesture { selectedDate = date }
                    }
                }
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .glassEffect(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(.white.opacity(0.4), lineWidth: 1)
                }
        }
        .shadow(color: .black.opacity(0.12), radius: 20, y: 10)
    }
    
    private func entriesFor(date: Date) -> [TimeClockEntry] {
        entries.filter { Calendar.current.isDate($0.clockIn, inSameDayAs: date) }
    }
}

// MARK: - Day Cell (Now more compact)
struct DayCell: View {
    let date: Date
    let entries: [TimeClockEntry]
    let isSelected: Bool
    
    private var isFuture: Bool {
        date > Calendar.current.startOfDay(for: Date())
    }
    
    private var totalHours: Double {
        entries.reduce(0) { $0 + $1.workedHours() }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Day number
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(isFuture ? .secondary : .primary)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)                    // slightly less top padding
            
            Spacer(minLength: 0)
            
            // Compact bottom section
            Group {
                if !entries.isEmpty && totalHours > 0 {
                    VStack(spacing: 2) {             // tighter spacing between bar and hours
                        MiniTimelineBar(entries: entries)
                            .frame(maxWidth: 48)
                        
                        Text(String(format: "%.1fh", totalHours))
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                } else {
                    Color.clear
                }
            }
            .frame(height: 34)                       // much more compact bottom area
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.25) : .clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 2.5)
        }
    }
}


// MARK: - Mini Timeline Bar (now supports multiple sessions + gaps)
struct MiniTimelineBar: View {
    let entries: [TimeClockEntry]
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background for the full day span
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                
                let sortedEntries = entries.sorted { $0.clockIn < $1.clockIn }
                
                if let firstIn = sortedEntries.first?.clockIn,
                   let lastOut = sortedEntries.last?.clockOut ?? sortedEntries.last?.clockIn {
                    
                    let totalSpan = lastOut.timeIntervalSince(firstIn)
                    
                    // ✅ Fixed: added id: \.clockIn
                    ForEach(sortedEntries, id: \.clockIn) { entry in
                        // Calculate position and width for this shift
                        let startOffset = entry.clockIn.timeIntervalSince(firstIn)
                        let workedDuration = entry.workedHours() * 3600 // seconds
                        
                        let xOffset = CGFloat(startOffset / totalSpan) * geo.size.width
                        let width = max(CGFloat(workedDuration / totalSpan) * geo.size.width, 2)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.green)
                            .frame(width: width)
                            .offset(x: xOffset)
                    }
                } else if let singleEntry = sortedEntries.first {
                    // Fallback to original single-entry behavior (with lunch support)
                    if let lunchStart = singleEntry.lunchStart,
                       let lunchEnd = singleEntry.lunchEnd,
                       let clockOut = singleEntry.clockOut {
                        let total = clockOut.timeIntervalSince(singleEntry.clockIn)
                        let before = lunchStart.timeIntervalSince(singleEntry.clockIn)
                        let lunch = lunchEnd.timeIntervalSince(lunchStart)
                        
                        let beforeWidth = CGFloat(before / total) * geo.size.width
                        let lunchWidth = CGFloat(lunch / total) * geo.size.width
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.green)
                            .frame(width: beforeWidth)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.4))
                            .frame(width: lunchWidth)
                            .offset(x: beforeWidth)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.green)
                            .frame(width: geo.size.width - beforeWidth - lunchWidth)
                            .offset(x: beforeWidth + lunchWidth)
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.green)
                            .frame(width: geo.size.width)
                    }
                }
            }
        }
        .frame(height: 6)
    }
}
// MARK: - Session Card (More compact & modern)
struct SessionCard: View {
    let entry: TimeClockEntry
    let compensationProfile: TimeClockCompensationProfile?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {   // tighter spacing
            DetailRow(title: "Clocked In", value: entry.clockIn.formatted(date: .omitted, time: .shortened))
            
            if let lunchStart = entry.lunchStart {
                DetailRow(title: "Lunch Started", value: lunchStart.formatted(date: .omitted, time: .shortened))
            }
            if let lunchEnd = entry.lunchEnd {
                DetailRow(title: "Lunch Ended", value: lunchEnd.formatted(date: .omitted, time: .shortened))
            }
            if let clockOut = entry.clockOut {
                DetailRow(title: "Clocked Out", value: clockOut.formatted(date: .omitted, time: .shortened))
            } else {
                DetailRow(title: "Clocked Out", value: "Still Open")
            }
        }
        .padding(.vertical, 10)      // reduced vertical padding
        .padding(.horizontal)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
        }
    }
}

struct DetailRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
    }
}
// MARK: - Selected Day Detail (Scrollable Bottom Sheet - Fixed Drag Indicator)
struct SelectedDayDetailView: View {
    let date: Date
    let entries: [TimeClockEntry]
    let compensationProfile: TimeClockCompensationProfile?
    
    private var dayEntries: [TimeClockEntry] {
        entries
            .filter { Calendar.current.isDate($0.clockIn, inSameDayAs: date) }
            .sorted { $0.clockIn < $1.clockIn }
    }
    
    private var totalHours: Double {
        dayEntries.reduce(0) { $0 + $1.workedHours() }
    }
    
    private var roundedHours: Double {
        (totalHours * 100).rounded() / 100
    }
    
    private var totalWages: Double {
        guard let rate = compensationProfile?.rateAmount,
              compensationProfile?.compensationType == .hourly else {
            return 0
        }
        return roundedHours * rate
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Centered Date + extra top padding to clear drag indicator
                Text(date.formatted(.dateTime.day().month(.wide).year()))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 16)                    // ← This fixes the overlap
                
                // Total section
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Worked")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        
                        Text("Earned")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(String(format: "%.2f hours", roundedHours))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        if totalWages > 0 {
                            Text(String(format: "$%.2f", totalWages))
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .padding(.horizontal)
                
                Divider()
                    .padding(.horizontal)
                
                if dayEntries.isEmpty {
                    Text("No shift recorded for this day")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 60)
                } else {
                    VStack(spacing: 8) {
                        ForEach(dayEntries, id: \.clockIn) { entry in
                            SessionCard(entry: entry, compensationProfile: compensationProfile)
                        }
                    }
                    .padding(.horizontal)
                }
                
                Spacer(minLength: 40)
            }
            .padding(.bottom, 20)
        }
    }
}

// MARK: - Helpers
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: self.dateComponents([.year, .month], from: date))!
    }
}
