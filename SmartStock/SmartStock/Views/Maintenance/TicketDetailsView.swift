//
//  TicketDetailsView.swift
//  SmartStock
//

import SwiftUI

struct TicketDetailsView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    let initialTicket: MaintenanceTicket
    let onTicketChanged: () async -> Void

    @State private var ticket: MaintenanceTicket
    @State private var machine: MaintenanceMachine?
    @State private var resolutionSummary = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    init(initialTicket: MaintenanceTicket, onTicketChanged: @escaping () async -> Void) {
        self.initialTicket = initialTicket
        self.onTicketChanged = onTicketChanged
        _ticket = State(initialValue: initialTicket)
    }

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section("Ticket") {
                DetailRow(title: "Status", value: ticket.displayStatus)
                DetailRow(title: "Priority", value: ticket.displayPriority)
                DetailRow(title: "Opened", value: ticket.displayOpenedAt)
                DetailRow(title: "Created By", value: ticket.displayOpenedBy)
                DetailRow(title: "Assigned To", value: ticket.assignedToName?.nilIfBlank ?? "Unassigned")
                if let dueDate = ticket.dueDate?.nilIfBlank {
                    DetailRow(title: "Due", value: dueDate)
                }
            }

            Section("Problem") {
                Text(ticket.problemSummary?.nilIfBlank ?? "Ticket #\(ticket.id)")
                    .font(.headline)

                if let notes = ticket.notes?.nilIfBlank {
                    Text(notes)
                        .foregroundStyle(.secondary)
                }
            }

            if let machine {
                Section("Machine") {
                    MachineSummaryRow(machine: machine)
                    DetailRow(title: "Store", value: machine.displayLocationName)
                    if let assetTag = machine.assetTag?.nilIfBlank {
                        DetailRow(title: "Asset Tag", value: assetTag)
                    }
                    if let serialNumber = machine.serialNumber?.nilIfBlank {
                        DetailRow(title: "Serial", value: serialNumber)
                    }
                }
            } else if ticket.machineId != nil {
                Section("Machine") {
                    Text("Machine details unavailable.")
                        .foregroundStyle(.secondary)
                }
            }

            if let resolutionSummary = ticket.resolutionSummary?.nilIfBlank {
                Section("Resolution") {
                    Text(resolutionSummary)
                }
            }

            if !ticket.isResolvedOrClosed {
                Section("Actions") {
                    Button {
                        Task { await assignToMe() }
                    } label: {
                        Label("Assign to Me", systemImage: "person.crop.circle.badge.checkmark")
                    }
                    .disabled(isWorking)

                    Button {
                        Task { await updateStatus(.inProgress) }
                    } label: {
                        Label("Mark In Progress", systemImage: "clock.arrow.circlepath")
                    }
                    .disabled(isWorking || ticket.status == MaintenanceTicketStatus.inProgress.rawValue)

                    Button {
                        Task { await updateStatus(.waitingParts) }
                    } label: {
                        Label("Waiting on Parts", systemImage: "shippingbox")
                    }
                    .disabled(isWorking || ticket.status == MaintenanceTicketStatus.waitingParts.rawValue)
                }

                Section("Resolve") {
                    TextField("Resolution summary", text: $resolutionSummary, axis: .vertical)
                        .lineLimit(3...8)

                    Button {
                        Task { await updateStatus(.resolved, resolutionSummary: resolutionSummary) }
                    } label: {
                        Label("Mark Resolved", systemImage: "checkmark.circle.fill")
                    }
                    .disabled(isWorking || resolutionSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section("Close") {
                Button(role: .destructive) {
                    Task { await updateStatus(.canceled) }
                } label: {
                    Label("Cancel Ticket", systemImage: "xmark.circle")
                }
                .disabled(isWorking || ticket.status == MaintenanceTicketStatus.canceled.rawValue)
            }
        }
        .navigationTitle("Ticket #\(ticket.id)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadMachine()
        }
        .refreshable {
            await refreshTicket()
            await loadMachine()
        }
        .overlay {
            if isWorking {
                LoadingView(text: "Updating ticket...")
                    .background(Color(.systemBackground).opacity(0.85))
            }
        }
    }

    private func assignToMe() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            try await MaintenanceService.shared.assignTicket(
                ticketId: ticket.id,
                technicianName: sessionManager.currentUser?.fullName
            )
            await refreshTicket()
            await onTicketChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateStatus(
        _ status: MaintenanceTicketStatus,
        resolutionSummary: String? = nil
    ) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            try await MaintenanceService.shared.updateTicketStatus(
                ticketId: ticket.id,
                status: status,
                resolutionSummary: resolutionSummary
            )
            await refreshTicket()
            await onTicketChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshTicket() async {
        do {
            if let refreshed = try await MaintenanceService.shared.fetchTicket(id: ticket.id) {
                ticket = refreshed
                resolutionSummary = refreshed.resolutionSummary ?? ""
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMachine() async {
        guard let machineId = ticket.machineId else { return }

        do {
            machine = try await MaintenanceService.shared.fetchMachine(id: machineId)
        } catch {
            machine = nil
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
