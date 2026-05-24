//
//  CustomOrderSlipPrintingService.swift
//  SmartStock
//

import Foundation
import UIKit

enum CustomOrderSlipPrintFormat {
    case letter
    case fortyColumn
}

struct CustomOrderSlipPayload {
    let order: CustomOrder
    let customerAccountNumber: String?
    let storeName: String
    let deviceName: String
    let cashierName: String
}

enum CustomOrderSlipPrintingService {
    @MainActor
    static func printSlip(
        payload: CustomOrderSlipPayload,
        preferences: CustomOrderCompanyPreferences,
        format: CustomOrderSlipPrintFormat
    ) {
        let controller = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = "\(payload.order.displayNumber) Custom Order Slip"
        printInfo.outputType = .general
        controller.printInfo = printInfo
        controller.printFormatter = UIMarkupTextPrintFormatter(markupText: html(for: payload, preferences: preferences, format: format))
        controller.present(animated: true)
    }

    static func html(
        for payload: CustomOrderSlipPayload,
        preferences: CustomOrderCompanyPreferences,
        format: CustomOrderSlipPrintFormat
    ) -> String {
        switch format {
        case .letter:
            return letterHTML(for: payload, preferences: preferences)
        case .fortyColumn:
            return fortyColumnHTML(for: payload, preferences: preferences)
        }
    }

    static func fortyColumnText(
        for payload: CustomOrderSlipPayload,
        preferences: CustomOrderCompanyPreferences
    ) -> String {
        let width = 40
        let rule = String(repeating: "-", count: width)
        let order = payload.order
        var rows: [String] = [
            center(preferences.companyName, width: width),
            center(preferences.customOrderSlipTitle.uppercased(), width: width)
        ]

        appendOptional(preferences.customOrderSlipContactLine, to: &rows, width: width)
        appendOptional(preferences.customOrderSlipEmailLine, to: &rows, width: width)
        rows.append(rule)
        rows.append(colon("CUSTOMER", order.customerName, width: width))
        if preferences.customOrderSlipShowCustomerPhone { rows.append(colon("PHONE", order.customerPhone, width: width)) }
        if preferences.customOrderSlipShowCustomerAccount { rows.append(colon("ACCOUNT", payload.customerAccountNumber?.emptySlipFallback ?? "None", width: width)) }
        rows.append(colon("DATE", displayDate(order.createdAt), width: width))
        if preferences.customOrderSlipShowDueDate { rows.append(colon("DUE", displayDate(order.dueDate), width: width)) }
        if preferences.customOrderSlipShowOrderNumber { rows.append(colon("ORDER", order.displayNumber, width: width)) }
        if preferences.customOrderSlipShowStore { rows.append(colon("STORE", payload.storeName, width: width)) }
        if preferences.customOrderSlipShowCashier { rows.append(colon("CASHIER", payload.cashierName, width: width)) }
        if preferences.customOrderSlipShowDevice { rows.append(colon("DEVICE", payload.deviceName, width: width)) }
        if preferences.customOrderSlipShowTakenBy { rows.append(colon("TAKEN BY", order.takenByName?.emptySlipFallback ?? payload.cashierName, width: width)) }

        if preferences.customOrderSlipShowLineItems {
            rows.append(rule)
            rows.append("DETAILS")
            for (index, line) in order.lines.enumerated() {
                let price = preferences.customOrderSlipShowPricing ? " \(money(line.lineTotal))" : ""
                rows.append(contentsOf: wrap("\(index + 1). \(line.displayName)\(price)", width: width))
                appendPlain(line.customizationDetails, to: &rows, width: width)
                appendPlain(line.orderInstructions, to: &rows, width: width)
                for addon in line.printAddons {
                    appendPlain([addon.materialName, addon.presetName].compactMap { $0 }.joined(separator: " / "), to: &rows, width: width)
                    appendPlain(addon.printDescription, to: &rows, width: width)
                }
            }
        }

        if let notes = order.orderNotes, !notes.trimmedSlipText.isEmpty {
            rows.append(contentsOf: wrap("Notes: \(notes)", width: width))
        }

        rows.append(rule)
        for _ in 0..<max(preferences.customOrderSlipBlankDetailLines, 0) {
            rows.append(String(repeating: "_", count: width))
        }

        if preferences.customOrderSlipShowPaymentSummary {
            rows.append(rule)
            rows.append(colon("PAYMENT", order.paymentMethod ?? "UNPAID", width: width))
            rows.append(colon("STATUS", order.paymentStatus.rawValue, width: width))
            rows.append(colon("PAID", money(order.amountPaid), width: width))
            rows.append(colon("BALANCE", money(order.balanceDue), width: width))
            rows.append(colon("TOTAL", money(order.totalAmount), width: width))
        }

        if preferences.customOrderSlipShowPaymentReference {
            appendPlain(order.paymentReference.map { "REFERENCE: \($0)" }, to: &rows, width: width)
        }

        if preferences.customOrderSlipShowSignatures {
            rows.append("")
            rows.append("Customer: __________________________")
            rows.append("Staff:    __________________________")
        }

        appendOptional(preferences.customOrderSlipFooterNote, to: &rows, width: width)
        return rows.joined(separator: "\n")
    }

    private static func letterHTML(
        for payload: CustomOrderSlipPayload,
        preferences: CustomOrderCompanyPreferences
    ) -> String {
        let order = payload.order
        let logo = logoHTML(preferences: preferences, maxWidth: 210)
        let itemRows = preferences.customOrderSlipShowLineItems ? order.lines.map { line in
            """
            <tr>
              <td><strong>\(escape(line.displayName))</strong>\(detailHTML(line.customizationDetails))\(detailHTML(line.orderInstructions))</td>
              <td class="numeric">\(quantityText(line.quantity))</td>
              <td class="numeric">\(preferences.customOrderSlipShowPricing ? money(line.unitPrice) : "")</td>
              <td class="numeric">\(preferences.customOrderSlipShowPricing ? money(line.lineTotal) : "")</td>
            </tr>
            """
        }.joined() : ""
        let blankRows = (0..<max(preferences.customOrderSlipBlankDetailLines, 0)).map { _ in "<div class=\"blank-line\"></div>" }.joined()

        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif; color: #111; margin: 34px; }
            .header { text-align: center; margin-bottom: 18px; }
            .logo { display: block; margin: 0 auto 10px; max-height: 100px; object-fit: contain; }
            h1 { margin: 0; font-size: 25px; }
            .muted { color: #555; font-size: 12px; }
            .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 0 28px; border: 2px solid #111; border-bottom: 0; }
            .cell { min-height: 30px; border-bottom: 1px solid #111; padding: 7px 9px; display: flex; justify-content: space-between; gap: 14px; }
            .label { color: #555; }
            table { width: 100%; border-collapse: collapse; margin-top: 18px; font-size: 13px; }
            th, td { border: 1px solid #111; padding: 8px; vertical-align: top; }
            th { text-align: left; background: #f2f2f2; }
            .numeric { text-align: right; white-space: nowrap; }
            .blank-line { height: 28px; border-bottom: 1px solid #111; }
            .totals { margin-left: auto; margin-top: 18px; width: 270px; border: 2px solid #111; border-bottom: 0; }
            .total-row { display: flex; justify-content: space-between; border-bottom: 1px solid #111; padding: 7px 9px; }
            .signatures { display: grid; grid-template-columns: 1fr 1fr; gap: 28px; margin-top: 34px; }
            .sig { border-top: 1px solid #111; padding-top: 6px; }
            .footer { text-align: center; margin-top: 26px; font-size: 12px; }
            @page { size: letter; margin: 0.5in; }
          </style>
        </head>
        <body>
          <div class="header">
            \(logo)
            <h1>\(escape(preferences.customOrderSlipTitle))</h1>
            <div><strong>\(escape(preferences.companyName))</strong></div>
            <div class="muted">\(escape(preferences.customOrderSlipContactLine))</div>
            <div class="muted">\(escape(preferences.customOrderSlipEmailLine))</div>
          </div>
          <div class="grid">
            \(cell("Order", preferences.customOrderSlipShowOrderNumber ? order.displayNumber : ""))
            \(cell("Customer", order.customerName))
            \(cell("Phone", preferences.customOrderSlipShowCustomerPhone ? order.customerPhone : ""))
            \(cell("Account", preferences.customOrderSlipShowCustomerAccount ? payload.customerAccountNumber?.emptySlipFallback ?? "None" : ""))
            \(cell("Order Date", displayDate(order.createdAt)))
            \(cell("Due Date", preferences.customOrderSlipShowDueDate ? displayDate(order.dueDate) : ""))
            \(cell("Store", preferences.customOrderSlipShowStore ? payload.storeName : ""))
            \(cell("Device", preferences.customOrderSlipShowDevice ? payload.deviceName : ""))
            \(cell("Cashier", preferences.customOrderSlipShowCashier ? payload.cashierName : ""))
            \(cell("Taken By", preferences.customOrderSlipShowTakenBy ? order.takenByName?.emptySlipFallback ?? payload.cashierName : ""))
          </div>
          \(preferences.customOrderSlipShowLineItems ? tableHTML(itemRows: itemRows, showPricing: preferences.customOrderSlipShowPricing) : "")
          <h3>Details</h3>
          \(blankRows)
          \(notesHTML(order.orderNotes))
          \(preferences.customOrderSlipShowPaymentSummary ? totalsHTML(order: order, showReference: preferences.customOrderSlipShowPaymentReference) : "")
          \(preferences.customOrderSlipShowSignatures ? "<div class=\"signatures\"><div class=\"sig\">Customer Signature</div><div class=\"sig\">Staff Signature</div></div>" : "")
          <div class="footer">\(escape(preferences.customOrderSlipFooterNote))</div>
        </body>
        </html>
        """
    }

    private static func fortyColumnHTML(
        for payload: CustomOrderSlipPayload,
        preferences: CustomOrderCompanyPreferences
    ) -> String {
        """
        <!doctype html>
        <html>
        <head>
          <style>
            body { margin: 0; color: #000; }
            .receipt { width: 280px; padding: 8px 6px; font: 12px "Courier New", monospace; white-space: pre-wrap; }
            .logo { display: block; margin: 0 auto 6px; max-width: 180px; max-height: 70px; object-fit: contain; }
            @page { margin: 0.08in; }
          </style>
        </head>
        <body><div class="receipt">\(logoHTML(preferences: preferences, maxWidth: 180))\(escape(fortyColumnText(for: payload, preferences: preferences)))</div></body>
        </html>
        """
    }

    private static func tableHTML(itemRows: String, showPricing: Bool) -> String {
        let priceHeaders = showPricing ? "<th class=\"numeric\">Unit</th><th class=\"numeric\">Total</th>" : "<th></th><th></th>"
        return "<table><thead><tr><th>Item / Details</th><th class=\"numeric\">Qty</th>\(priceHeaders)</tr></thead><tbody>\(itemRows)</tbody></table>"
    }

    private static func totalsHTML(order: CustomOrder, showReference: Bool) -> String {
        """
        <div class="totals">
          \(totalRow("Payment", order.paymentMethod ?? "UNPAID"))
          \(totalRow("Status", order.paymentStatus.rawValue))
          \(totalRow("Paid", money(order.amountPaid)))
          \(totalRow("Balance", money(order.balanceDue)))
          \(totalRow("Total", money(order.totalAmount)))
          \(showReference ? totalRow("Reference", order.paymentReference ?? "") : "")
        </div>
        """
    }

    private static func cell(_ label: String, _ value: String) -> String {
        "<div class=\"cell\"><span class=\"label\">\(escape(label))</span><strong>\(escape(value))</strong></div>"
    }

    private static func totalRow(_ label: String, _ value: String) -> String {
        "<div class=\"total-row\"><span>\(escape(label))</span><strong>\(escape(value))</strong></div>"
    }

    private static func detailHTML(_ value: String?) -> String {
        guard let value = value?.trimmedSlipText, !value.isEmpty else { return "" }
        return "<br><span class=\"muted\">\(escape(value))</span>"
    }

    private static func notesHTML(_ notes: String?) -> String {
        guard let notes = notes?.trimmedSlipText, !notes.isEmpty else { return "" }
        return "<h3>Order Notes</h3><p>\(escape(notes))</p>"
    }

    private static func logoHTML(preferences: CustomOrderCompanyPreferences, maxWidth: Int) -> String {
        let url = imageSource(preferences.receiptLogoURL)
        guard preferences.customOrderSlipShowLogo, !url.isEmpty else { return "" }
        return "<img class=\"logo\" src=\"\(url)\" style=\"max-width:\(maxWidth)px;\" />"
    }

    private static func imageSource(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmedSlipText
        guard !trimmed.isEmpty else { return "" }
        if URL(string: trimmed) != nil {
            return escape(trimmed)
        }
        return escape(trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed)
    }

    private static func appendOptional(_ value: String?, to rows: inout [String], width: Int) {
        guard let value = value?.trimmedSlipText, !value.isEmpty else { return }
        rows.append(center(value, width: width))
    }

    private static func appendIndented(_ value: String?, to rows: inout [String], width: Int) {
        guard let value = value?.trimmedSlipText, !value.isEmpty else { return }
        rows.append(contentsOf: wrap("  \(value)", width: width))
    }

    private static func appendPlain(_ value: String?, to rows: inout [String], width: Int) {
        guard let value = value?.trimmedSlipText, !value.isEmpty else { return }
        rows.append(contentsOf: wrap(value, width: width))
    }

    private static func colon(_ label: String, _ value: String, width: Int) -> String {
        "\(label): \(value)".paddedSlipLine(to: width)
    }

    private static func pair(_ left: String, _ right: String, width: Int) -> String {
        let right = right.trimmedSlipText
        let available = max(width - right.count, 1)
        let clippedLeft = String(left.trimmedSlipText.prefix(max(available - 1, 1)))
        let spaces = max(width - clippedLeft.count - right.count, 1)
        return clippedLeft + String(repeating: " ", count: spaces) + right
    }

    private static func center(_ value: String, width: Int) -> String {
        let text = String(value.trimmedSlipText.prefix(width))
        let left = max((width - text.count) / 2, 0)
        return String(repeating: " ", count: left) + text
    }

    private static func wrap(_ value: String, width: Int) -> [String] {
        var words = value.trimmedSlipText.split(separator: " ").map(String.init)
        var lines: [String] = []
        var current = ""
        while !words.isEmpty {
            let word = words.removeFirst()
            if current.isEmpty {
                current = word
            } else if current.count + 1 + word.count <= width {
                current += " " + word
            } else {
                lines.append(current.paddedSlipLine(to: width))
                current = word
            }
        }
        if !current.isEmpty { lines.append(current.paddedSlipLine(to: width)) }
        return lines
    }

    private static func displayDate(_ rawValue: String?) -> String {
        guard let date = Sale.parseDate(rawValue) else { return rawValue?.emptySlipFallback ?? "Not set" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private static func quantityText(_ quantity: Double) -> String {
        quantity.rounded() == quantity ? String(format: "%.0f", quantity) : String(format: "%.2f", quantity)
    }

    private static func money(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

private extension String {
    var trimmedSlipText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var emptySlipFallback: String {
        let trimmed = trimmedSlipText
        return trimmed.isEmpty ? "Not set" : trimmed
    }

    func paddedSlipLine(to width: Int) -> String {
        let clipped = String(prefix(width))
        return clipped + String(repeating: " ", count: max(width - clipped.count, 0))
    }
}
