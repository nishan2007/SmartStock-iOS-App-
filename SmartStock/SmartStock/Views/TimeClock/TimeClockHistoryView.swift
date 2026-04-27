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
            
            // Enhanced Liquid Glass Calendar
            CalendarGridView(
                currentDate: currentDate,
                entries: entries,
                compensationProfile: compensationProfile,
                selectedDate: $selectedDate
            )
            .padding(.horizontal)
            
            if let selectedDate = selectedDate {
                SelectedDayDetailView(
                    date: selectedDate,
                    entries: entries,
                    compensationProfile: compensationProfile
                )
                .padding(.horizontal)
                .padding(.top, 8)
                .transition(.opacity)
            }
            
            Spacer()
        }
        .navigationTitle("Time Clock History")
        .task { await loadHistory() }
        .refreshable { await loadHistory() }
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

// MARK: - Enhanced Liquid Glass Calendar
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
            HStack(spacing: 0) {
                ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { weekday in
                    Text(weekday)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 4)
            
            let rows = days.chunked(into: 7)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, week in
                HStack(spacing: 6) {
                    ForEach(week, id: \.self) { date in
                        if date == Date.distantPast {
                            Color.clear.aspectRatio(1, contentMode: .fit)
                        } else {
                            DayCell(
                                date: date,
                                entry: entryFor(date: date),
                                isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate ?? Date.distantPast)
                            )
                            .onTapGesture { selectedDate = date }
                        }
                    }
                }
                
                if index < rows.count - 1 {
                    Divider().padding(.horizontal, 8)
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
    
    private func entryFor(date: Date) -> TimeClockEntry? {
        entries.first { Calendar.current.isDate($0.clockIn, inSameDayAs: date) }
    }
}

// MARK: - Day Cell
struct DayCell: View {
    let date: Date
    let entry: TimeClockEntry?
    let isSelected: Bool
    
    private var isFuture: Bool {
        date > Calendar.current.startOfDay(for: Date())
    }
    
    private var hours: Double {
        entry?.workedHours() ?? 0
    }
    
    var body: some View {
        VStack(spacing: 3) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(isFuture ? .secondary : .primary)
            
            Spacer(minLength: 2)
            
            if let entry = entry, hours > 0 {
                MiniTimelineBar(entry: entry)
                    .frame(maxWidth: 48)
                
                Text(String(format: "%.1fh", hours))
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else {
                Color.clear.frame(height: 26)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.25) : .clear)   // Increased opacity
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 2.5)
        }
    }
}

// MARK: - Mini Timeline Bar
struct MiniTimelineBar: View {
    let entry: TimeClockEntry
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                
                if let lunchStart = entry.lunchStart, let lunchEnd = entry.lunchEnd, let clockOut = entry.clockOut {
                    let total = clockOut.timeIntervalSince(entry.clockIn)
                    let before = lunchStart.timeIntervalSince(entry.clockIn)
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
        .frame(height: 6)
    }
}

// MARK: - Selected Day Detail (also enhanced glass)
struct SelectedDayDetailView: View {
    let date: Date
    let entries: [TimeClockEntry]
    let compensationProfile: TimeClockCompensationProfile?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(date.formatted(.dateTime.day().month(.wide).year()))
                .font(.headline)
            
            if let entry = entries.first(where: { Calendar.current.isDate($0.clockIn, inSameDayAs: date) }) {
                VStack(alignment: .leading, spacing: 10) {
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
                    
                    DetailRow(title: "Hours Worked", value: String(format: "%.2f hours", entry.workedHours()))
                    
                    if let rate = compensationProfile?.rateAmount,
                       compensationProfile?.compensationType == .hourly {
                        let earned = entry.workedHours() * rate
                        DetailRow(title: "Wages Earned", value: String(format: "$%.2f", earned))
                    }
                }
            } else {
                Text("No shift recorded for this day")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 30)
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .glassEffect(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
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
