//
//  IssuesView.swift
//  SmartStock
//

import SwiftUI

struct IssuesView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @State private var draft = MaintenanceIssueDraft()
    @State private var machines: [MaintenanceMachine] = []
    @State private var isLoadingMachines = false
    @State private var machineLoadError: String?
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var didSubmit = false

    var body: some View {
        Form {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            if didSubmit {
                Section {
                    Label("Issue Submitted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Maintenance will see this ticket in the Maintenance Tickets list.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Issue") {
                TextField("What do you need help with?", text: $draft.problemSummary, axis: .vertical)
                    .lineLimit(2...4)

                Picker("Priority", selection: $draft.priority) {
                    ForEach(MaintenanceTicketPriority.allCases) { priority in
                        Text(priority.title).tag(priority)
                    }
                }
            }

            Section("Machine") {
                if isLoadingMachines {
                    ProgressView("Loading machines...")
                } else if let machineLoadError {
                    Text(machineLoadError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Related Machine", selection: $draft.machineId) {
                        Text("No Machine").tag(Optional<Int>.none)
                        ForEach(machines) { machine in
                            Text(machinePickerLabel(machine)).tag(Optional(machine.id))
                        }
                    }
                }
            }

            Section("Details") {
                TextField("Add details, steps, location, or anything maintenance should know", text: $draft.notes, axis: .vertical)
                    .lineLimit(5...10)
            }

            Section {
                Button {
                    Task { await submitIssue() }
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Submit Issue", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isSubmitting || draft.problemSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("Issues")
        .task {
            await loadMachines()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    PreviousIssueTicketsView()
                        .environmentObject(sessionManager)
                } label: {
                    Label("Previous Tickets", systemImage: "clock.arrow.circlepath")
                }
            }
        }
    }

    private func loadMachines() async {
        isLoadingMachines = true
        machineLoadError = nil
        defer { isLoadingMachines = false }

        do {
            machines = try await MaintenanceService.shared.fetchIssueMachines()
        } catch {
            machineLoadError = "Machine selection is unavailable."
        }
    }

    private func submitIssue() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await MaintenanceService.shared.createIssueTicket(
                draft: draft,
                user: sessionManager.currentUser
            )
            draft = MaintenanceIssueDraft()
            didSubmit = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func machinePickerLabel(_ machine: MaintenanceMachine) -> String {
        if let assetTag = machine.assetTag?.nilIfBlank {
            return "\(machine.machineName) (\(assetTag))"
        }

        return machine.machineName
    }
}

private struct PreviousIssueTicketsView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @State private var tickets: [MaintenanceTicket] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section("Previous Tickets") {
                if isLoading {
                    ProgressView("Loading tickets...")
                } else if tickets.isEmpty {
                    ContentUnavailableView("No Tickets", systemImage: "ticket")
                } else {
                    ForEach(tickets) { ticket in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(ticket.problemSummary?.nilIfBlank ?? "Ticket #\(ticket.id)")
                                    .font(.headline)
                                Spacer()
                                Text(ticket.displayStatus)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(statusColor(for: ticket))
                            }

                            Text(ticket.displayOpenedAt)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                Text("Created by: \(ticket.displayOpenedBy)")
                                if let machineId = ticket.machineId {
                                    Text("Machine #\(machineId)")
                                }
                                Text("Priority: \(ticket.displayPriority)")
                                if let assignedToName = ticket.assignedToName?.nilIfBlank {
                                    Text("Assigned: \(assignedToName)")
                                }
                                if let dueDate = ticket.dueDate?.nilIfBlank {
                                    Text("Due: \(dueDate)")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            if let resolutionSummary = ticket.resolutionSummary?.nilIfBlank {
                                Text("Resolution: \(resolutionSummary)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Previous Tickets")
        .task {
            await loadTickets()
        }
        .refreshable {
            await loadTickets()
        }
    }

    private func loadTickets() async {
        guard let userId = sessionManager.currentUser?.id else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            tickets = try await MaintenanceService.shared.fetchTickets(openedByUserId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func statusColor(for ticket: MaintenanceTicket) -> Color {
        switch ticket.status {
        case "OPEN", "IN_PROGRESS", "WAITING_PARTS":
            return .orange
        case "RESOLVED", "CLOSED":
            return .green
        case "CANCELED":
            return .secondary
        default:
            return .secondary
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
