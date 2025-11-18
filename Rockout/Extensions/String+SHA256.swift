//
//  String+SHA256.swift
//  Rockout
//
//  Created by Suino Ikhioda on 11/18/25.
//

import Foundation
import CryptoKit

extension String {
    static func random(length: Int) -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
        return String((0..<length).compactMap { _ in chars.randomElement() })
    }

    func sha256Data() -> Data {
        Data(SHA256.hash(data: Data(self.utf8)))
    }

    func sha256Base64URL() -> String {
        sha256Data()
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
