//
//  TimeClockView.swift
//  SmartStock
//

import SwiftUI

struct TimeClockView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @State private var isClockedIn = false
    @State private var lastPunch: Date?
    @State private var notes = ""

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: isClockedIn ? "clock.badge.checkmark.fill" : "clock.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(isClockedIn ? .green : .orange)

                Text(isClockedIn ? "Clocked In" : "Clocked Out")
                    .font(.title2.weight(.bold))

                Text(sessionManager.currentUser?.fullName ?? "Current user")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            if let lastPunch {
                Label(lastPunch.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    .foregroundStyle(.secondary)
            }

            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(3...6)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button {
                isClockedIn.toggle()
                lastPunch = .now
                notes = ""
            } label: {
                Label(
                    isClockedIn ? "Clock Out" : "Clock In",
                    systemImage: isClockedIn ? "rectangle.portrait.and.arrow.right" : "rectangle.portrait.and.arrow.forward"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .padding()
        .navigationTitle("Time Clock")
    }
}
