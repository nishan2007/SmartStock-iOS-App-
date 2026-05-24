//
//  ReceiptPrintingService.swift
//  SmartStock
//

import Foundation
import UIKit

enum ReceiptPrintFormat {
    case letter
    case fortyColumn
}

struct ReceiptPrintLineItem: Identifiable {
    let id = UUID()
    let name: String
    let sku: String?
    let quantity: Int
    let unitPrice: Double
    let discountAmount: Double

    var subtotal: Double { Double(quantity) * unitPrice }
    var total: Double { max(subtotal - discountAmount, 0) }
}

struct ReceiptPrintPayload {
    let saleId: Int
    let receiptNumber: String
    let date: Date
    let cashierName: String
    let deviceId: String
    let customerName: String?
    let storeName: String
    let paymentMethod: String
    let paymentStatus: String
    let amountPaid: Double
    let cashCollected: Double?
    let changeDue: Double?
    let subtotal: Double
    let discountAmount: Double
    let total: Double
    let items: [ReceiptPrintLineItem]
}

enum ReceiptPrintingService {
    @MainActor
    static func printReceipt(
        payload: ReceiptPrintPayload,
        preferences: CustomOrderCompanyPreferences,
        format: ReceiptPrintFormat
    ) {
        let controller = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = "\(payload.receiptNumber) Receipt"
        printInfo.outputType = .general
        controller.printInfo = printInfo
        controller.printFormatter = UIMarkupTextPrintFormatter(markupText: html(for: payload, preferences: preferences, format: format))
        controller.present(animated: true)
    }

    static func html(
        for payload: ReceiptPrintPayload,
        preferences: CustomOrderCompanyPreferences,
        format: ReceiptPrintFormat
    ) -> String {
        switch format {
        case .letter:
            return letterHTML(for: payload, preferences: preferences)
        case .fortyColumn:
            return fortyColumnHTML(for: payload, preferences: preferences)
        }
    }

    static func fortyColumnText(
        for payload: ReceiptPrintPayload,
        preferences: CustomOrderCompanyPreferences
    ) -> String {
        var rows: [String] = []
        let width = 40
        let rule = String(repeating: "-", count: width)

        if !preferences.receiptHeaderLine.trimmedReceiptText.isEmpty {
            rows.append(center(preferences.receiptHeaderLine, width: width))
        }
        rows.append(center(preferences.companyName, width: width))
        rows.append(center(payload.storeName, width: width))
        rows.append(rule)
        rows.append(pair("Receipt", payload.receiptNumber, width: width))
        if preferences.showSaleIdOnReceipt {
            rows.append(pair("Sale ID", "\(payload.saleId)", width: width))
        }
        rows.append(pair("Date", receiptDateFormatter.string(from: payload.date), width: width))
        rows.append(pair("Cashier", payload.cashierName, width: width))
        if preferences.showDeviceIdOnReceipt {
            rows.append(pair("Device", payload.deviceId, width: width))
        }
        if preferences.showCustomerOnReceipt {
            rows.append(pair("Customer", payload.customerName?.trimmedReceiptText.isEmpty == false ? payload.customerName! : "Walk-in", width: width))
        }
        rows.append(rule)

        for item in payload.items {
            rows.append(contentsOf: wrap(item.name, width: width))
            if preferences.showSkuOnReceipt, let sku = item.sku?.trimmedReceiptText, !sku.isEmpty {
                rows.append("  SKU: \(sku)".paddedOrTrimmed(to: width))
            }
            rows.append(pair("  \(item.quantity) x \(money(item.unitPrice))", money(item.total), width: width))
            if preferences.showItemDiscountsOnReceipt, item.discountAmount > 0 {
                rows.append(pair("  Item Discount", money(item.discountAmount), width: width))
            }
        }

        rows.append(rule)
        rows.append(pair("Subtotal", money(payload.subtotal), width: width))
        rows.append(pair("Discount", money(payload.discountAmount), width: width))
        rows.append(pair("Total", money(payload.total), width: width))
        rows.append(pair("Payment", payload.paymentMethod, width: width))
        if preferences.showPaymentStatusOnReceipt {
            rows.append(pair("Status", payload.paymentStatus, width: width))
        }
        rows.append(pair("Paid", money(payload.amountPaid), width: width))
        if let cashCollected = payload.cashCollected {
            rows.append(pair("Cash Collected", money(cashCollected), width: width))
        }
        if let changeDue = payload.changeDue {
            rows.append(pair("Change Due", money(changeDue), width: width))
        }
        rows.append(rule)
        if !preferences.receiptFooterLine.trimmedReceiptText.isEmpty {
            rows.append(center(preferences.receiptFooterLine, width: width))
        }

        return rows.joined(separator: "\n")
    }

    private static func letterHTML(
        for payload: ReceiptPrintPayload,
        preferences: CustomOrderCompanyPreferences
    ) -> String {
        let logo = receiptLogoHTML(preferences: preferences, maxWidth: 220)
        let itemRows = payload.items.map { item in
            """
            <tr>
              <td><strong>\(escape(item.name))</strong>\(skuHTML(item.sku, preferences: preferences))</td>
              <td class="numeric">\(item.quantity)</td>
              <td class="numeric">\(money(item.unitPrice))</td>
              <td class="numeric">\(preferences.showItemDiscountsOnReceipt && item.discountAmount > 0 ? money(item.discountAmount) : "")</td>
              <td class="numeric">\(money(item.total))</td>
            </tr>
            """
        }.joined()

        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif; color: #111; margin: 34px; }
            .header { text-align: center; margin-bottom: 22px; }
            .logo { display: block; margin: 0 auto 10px; max-height: 110px; object-fit: contain; }
            h1 { margin: 0; font-size: 24px; }
            .muted { color: #555; }
            .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 6px 28px; margin: 18px 0; font-size: 13px; }
            .row { display: flex; justify-content: space-between; gap: 16px; border-bottom: 1px solid #eee; padding: 4px 0; }
            table { width: 100%; border-collapse: collapse; margin-top: 18px; font-size: 13px; }
            th { text-align: left; border-bottom: 2px solid #111; padding: 8px 6px; }
            td { border-bottom: 1px solid #ddd; padding: 8px 6px; vertical-align: top; }
            .numeric { text-align: right; white-space: nowrap; }
            .totals { margin-left: auto; margin-top: 18px; width: 260px; font-size: 14px; }
            .total { font-size: 18px; font-weight: 700; border-top: 2px solid #111; }
            .footer { text-align: center; margin-top: 32px; }
            @page { size: letter; margin: 0.5in; }
          </style>
        </head>
        <body>
          <div class="header">
            \(logo)
            <h1>\(escape(preferences.companyName))</h1>
            <div>\(escape(payload.storeName))</div>
            <div class="muted">\(escape(preferences.receiptHeaderLine))</div>
          </div>
          <div class="grid">
            \(detail("Receipt", payload.receiptNumber))
            \(preferences.showSaleIdOnReceipt ? detail("Sale ID", "\(payload.saleId)") : "")
            \(detail("Date", receiptDateFormatter.string(from: payload.date)))
            \(detail("Cashier", payload.cashierName))
            \(preferences.showDeviceIdOnReceipt ? detail("Device", payload.deviceId) : "")
            \(preferences.showCustomerOnReceipt ? detail("Customer", payload.customerName?.trimmedReceiptText.isEmpty == false ? payload.customerName! : "Walk-in") : "")
          </div>
          <table>
            <thead><tr><th>Item</th><th class="numeric">Qty</th><th class="numeric">Unit</th><th class="numeric">Discount</th><th class="numeric">Total</th></tr></thead>
            <tbody>\(itemRows)</tbody>
          </table>
          <div class="totals">
            \(totalRow("Subtotal", money(payload.subtotal)))
            \(totalRow("Discount", money(payload.discountAmount)))
            \(totalRow("Payment", payload.paymentMethod))
            \(preferences.showPaymentStatusOnReceipt ? totalRow("Status", payload.paymentStatus) : "")
            \(totalRow("Paid", money(payload.amountPaid)))
            <div class="row total"><span>Total</span><span>\(money(payload.total))</span></div>
          </div>
          <div class="footer">\(escape(preferences.receiptFooterLine))</div>
        </body>
        </html>
        """
    }

    private static func fortyColumnHTML(
        for payload: ReceiptPrintPayload,
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
        <body>
          <div class="receipt">\(receiptLogoHTML(preferences: preferences, maxWidth: 180))\(escape(fortyColumnText(for: payload, preferences: preferences)))</div>
        </body>
        </html>
        """
    }

    private static func detail(_ title: String, _ value: String) -> String {
        "<div class=\"row\"><span>\(escape(title))</span><strong>\(escape(value))</strong></div>"
    }

    private static func totalRow(_ title: String, _ value: String) -> String {
        "<div class=\"row\"><span>\(escape(title))</span><span>\(escape(value))</span></div>"
    }

    private static func skuHTML(_ sku: String?, preferences: CustomOrderCompanyPreferences) -> String {
        guard preferences.showSkuOnReceipt, let sku = sku?.trimmedReceiptText, !sku.isEmpty else { return "" }
        return "<br><span class=\"muted\">SKU: \(escape(sku))</span>"
    }

    private static func receiptLogoHTML(preferences: CustomOrderCompanyPreferences, maxWidth: Int) -> String {
        let url = imageSource(preferences.receiptLogoURL)
        guard preferences.showReceiptLogo, !url.isEmpty else { return "" }
        return "<img class=\"logo\" src=\"\(url)\" style=\"max-width:\(maxWidth)px;\" />"
    }

    private static func imageSource(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmedReceiptText
        guard !trimmed.isEmpty else { return "" }
        if URL(string: trimmed) != nil {
            return escape(trimmed)
        }
        return escape(trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed)
    }

    private static func pair(_ left: String, _ right: String, width: Int) -> String {
        let left = left.trimmedReceiptText
        let right = right.trimmedReceiptText
        let available = max(width - right.count, 1)
        let clippedLeft = String(left.prefix(max(available - 1, 1)))
        let spaces = max(width - clippedLeft.count - right.count, 1)
        return clippedLeft + String(repeating: " ", count: spaces) + right
    }

    private static func center(_ value: String, width: Int) -> String {
        let text = String(value.trimmedReceiptText.prefix(width))
        let left = max((width - text.count) / 2, 0)
        return String(repeating: " ", count: left) + text
    }

    private static func wrap(_ value: String, width: Int) -> [String] {
        var words = value.trimmedReceiptText.split(separator: " ").map(String.init)
        var lines: [String] = []
        var current = ""

        while !words.isEmpty {
            let word = words.removeFirst()
            if current.isEmpty {
                current = word
            } else if current.count + 1 + word.count <= width {
                current += " " + word
            } else {
                lines.append(current.paddedOrTrimmed(to: width))
                current = word
            }
        }

        if !current.isEmpty {
            lines.append(current.paddedOrTrimmed(to: width))
        }
        return lines.isEmpty ? ["".paddedOrTrimmed(to: width)] : lines
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

    private static let receiptDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd hh:mm a"
        return formatter
    }()
}

private extension String {
    var trimmedReceiptText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func paddedOrTrimmed(to width: Int) -> String {
        let clipped = String(prefix(width))
        return clipped + String(repeating: " ", count: max(width - clipped.count, 0))
    }
}
