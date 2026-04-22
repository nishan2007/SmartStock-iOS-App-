//
//  ProductImageService.swift
//  SmartStock
//

import Foundation
import Auth
import Supabase
import UIKit

enum ProductImageService {
    private static let bucket = "Product Images"
    private static let maxBytes = 200 * 1024

    static func compressedJPEGData(from image: UIImage) throws -> Data {
        let normalized = image.normalizedForUpload()
        let maxDimension: CGFloat = 1200
        var targetImage = normalized.scaledToFit(maxDimension: maxDimension)
        var quality: CGFloat = 0.78

        for attempt in 0..<14 {
            if let data = targetImage.jpegData(compressionQuality: quality), data.count <= maxBytes {
                return data
            }

            quality -= 0.08
            if quality < 0.30 {
                quality = 0.70
                let nextDimension = max(360, max(targetImage.size.width, targetImage.size.height) * 0.82)
                targetImage = targetImage.scaledToFit(maxDimension: nextDimension)
            }

            if attempt == 13 {
                break
            }
        }

        throw ImageUploadError.compressionFailed
    }

    static func upload(image: UIImage) async throws -> String {
        let data = try compressedJPEGData(from: image)
        let session = try await supabase.auth.session
        let objectPath = "products/\(Int(Date().timeIntervalSince1970 * 1000))-product-image.jpg"
        let uploadURL = supabaseURL
            .appendingPathComponent("storage/v1/object")
            .appendingPathComponent(bucket)
            .appendingPathComponent(objectPath)

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue(supabasePublishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")

        let (_, response) = try await URLSession.shared.upload(for: request, from: data)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw ImageUploadError.uploadFailed
        }

        return supabaseURL
            .appendingPathComponent("storage/v1/object/public")
            .appendingPathComponent(bucket)
            .appendingPathComponent(objectPath)
            .absoluteString
    }
}

enum ImageUploadError: LocalizedError {
    case compressionFailed
    case uploadFailed

    var errorDescription: String? {
        switch self {
        case .compressionFailed:
            return "The image could not be compressed below 200 KB."
        case .uploadFailed:
            return "The product image could not be uploaded."
        }
    }
}

private extension UIImage {
    func normalizedForUpload() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func scaledToFit(maxDimension: CGFloat) -> UIImage {
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension else { return self }

        let scale = maxDimension / longestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
