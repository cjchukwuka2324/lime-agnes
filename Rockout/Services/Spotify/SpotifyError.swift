//
//  SpotifyError.swift
//  Rockout
//
//  Created by Suino Ikhioda on 11/17/25.
//

import Foundation

enum SpotifyError: Error {
    case invalidRequest
    case invalidResponse
    case unauthorized
    case decodingFailed
    case tokenRefreshFailed
    case unknown(Error)
}
