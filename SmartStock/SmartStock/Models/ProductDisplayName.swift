import Foundation

func displayProductName(name: String, size: String?) -> String {
    let trimmedSize = (size ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedSize.isEmpty ? name : "\(name) (\(trimmedSize))"
}
