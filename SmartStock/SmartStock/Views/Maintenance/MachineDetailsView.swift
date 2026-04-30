//
//  MachineDetailsView.swift
//  SmartStock
//

import SwiftUI

struct MachineDetailsView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    let machine: MaintenanceMachine

    @State private var associatedParts: [MaintenanceMachinePart] = []
    @State private var logs: [MaintenanceLog] = []
    @State private var tickets: [MaintenanceTicket] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if !canViewMaintenance {
                Section {
                    ContentUnavailableView(
                        "Machine Locked",
                        systemImage: "lock.shield",
                        description: Text("Your role does not have Maintenance access.")
                    )
                }
            } else {
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }

                machineSection
                datesSection
                notesSection
                partsSection
                logsSection
                ticketsSection
            }
        }
        .navigationTitle(machine.machineName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard canViewMaintenance else { return }
            await loadDetails()
        }
        .refreshable {
            guard canViewMaintenance else { return }
            await loadDetails()
        }
        .overlay {
            if isLoading {
                LoadingView(text: "Loading machine...")
                    .background(Color(.systemBackground).opacity(0.85))
            }
        }
    }

    private var canViewMaintenance: Bool {
        sessionManager.currentUser?.canAccess(.maintenanceManagement) == true
    }

    private var machineSection: some View {
        Section("Machine") {
            MachineDetailRow(label: "Name", value: machine.machineName)
            MachineDetailRow(label: "Status", value: machine.status.title)
            MachineDetailRow(label: "Store", value: machine.displayLocationName)
            MachineDetailRow(label: "Asset Tag", value: machine.assetTag)
            MachineDetailRow(label: "Serial Number", value: machine.serialNumber)
            MachineDetailRow(label: "Manufacturer", value: machine.manufacturer)
            MachineDetailRow(label: "Model", value: machine.model)
            MachineDetailRow(label: "Type", value: machine.machineType)
        }
    }

    private var datesSection: some View {
        Section("Dates") {
            MachineDetailRow(label: "Purchase Date", value: machine.purchaseDate)
            MachineDetailRow(label: "Warranty Expiration", value: machine.warrantyExpirationDate)
            MachineDetailRow(label: "Last Service", value: machine.lastServiceDate)
            MachineDetailRow(label: "Next Service", value: machine.nextServiceDate)
            MachineDetailRow(label: "Created", value: machine.createdAt)
            MachineDetailRow(label: "Updated", value: machine.updatedAt)
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        if let notes = machine.notes?.nilIfBlank {
            Section("Notes") {
                Text(notes)
                    .font(.body)
            }
        }
    }

    private var partsSection: some View {
        Section("Associated Parts") {
            if associatedParts.isEmpty {
                ContentUnavailableView("No Associated Parts", systemImage: "gearshape.2")
            } else {
                ForEach(associatedParts) { association in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(association.partName)
                            .font(.headline)
                        Text(association.partNumberText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let notes = association.notes?.nilIfBlank {
                            Text(notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var logsSection: some View {
        Section("Maintenance Logs") {
            if logs.isEmpty {
                ContentUnavailableView("No Logs", systemImage: "doc.text.magnifyingglass")
            } else {
                ForEach(logs) { log in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(log.summary?.nilIfBlank ?? log.displayServiceType)
                            .font(.headline)
                        Text(log.serviceDate?.nilIfBlank ?? log.createdAt?.nilIfBlank ?? "No date")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Text(log.displayServiceType)
                            if let technicianName = log.technicianName?.nilIfBlank {
                                Text("Tech: \(technicianName)")
                            }
                            if log.laborHours > 0 {
                                Text("Hours: \(log.laborHours.maintenanceNumberText)")
                            }
                            if log.totalCost > 0 {
                                Text("Cost: \(log.totalCost.maintenanceCurrencyText)")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if let details = log.details?.nilIfBlank {
                            Text(details)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let partsUsed = log.partsUsed?.nilIfBlank {
                            Text("Parts: \(partsUsed)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var ticketsSection: some View {
        Section("Tickets") {
            if tickets.isEmpty {
                ContentUnavailableView("No Tickets", systemImage: "ticket")
            } else {
                ForEach(tickets) { ticket in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(ticket.problemSummary?.nilIfBlank ?? "Ticket #\(ticket.id)")
                                .font(.headline)
                            Spacer()
                            Text(ticket.displayStatus)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        Text(ticket.openedAt?.nilIfBlank ?? "No open date")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
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

                        if let notes = ticket.notes?.nilIfBlank {
                            Text(notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func loadDetails() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let partsTask = MaintenanceService.shared.fetchMachineParts(machineId: machine.id)
            async let logsTask = MaintenanceService.shared.fetchLogs(machineId: machine.id)
            async let ticketsTask = MaintenanceService.shared.fetchTickets(machineId: machine.id)

            associatedParts = try await partsTask
            logs = try await logsTask
            tickets = try await ticketsTask
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct MachineDetailRow: View {
    let label: String
    let value: String?

    var body: some View {
        if let value = value?.nilIfBlank {
            LabeledContent(label, value: value)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Decimal {
    var maintenanceCurrencyText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: self)) ?? "$\(maintenanceNumberText)"
    }
}
