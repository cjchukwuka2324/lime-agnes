//
//  SupabaseClient.swift
//  Rockout
//
//  Created by Suino Ikhioda on 11/17/25.
//

import Foundation
import Supabase

/// A singleton service for managing the Supabase client instance
final class SupabaseService {
    
    // MARK: - Singleton
    static let shared = SupabaseService()
    
    // MARK: - Properties
    let client: SupabaseClient
    
    // MARK: - Initialization
    private init() {
        // TODO: Replace with your actual Supabase URL and anon key
        // You can also load these from Info.plist or environment variables
        let supabaseURLString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? "https://wklzogrfdrqluwchoqsp.supabase.co"
        let supabaseKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndrbHpvZ3JmZHJxbHV3Y2hvcXNwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjMxMjAzNDcsImV4cCI6MjA3ODY5NjM0N30.HPrlq9hi2ab0YPsE5B8OibheLOmmNqmHKG2qRjt_3jY"
        
        guard let supabaseURL = URL(string: supabaseURLString),
              supabaseURLString != "https://wklzogrfdrqluwchoqsp.supabase.co",
              supabaseKey != "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndrbHpvZ3JmZHJxbHV3Y2hvcXNwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjMxMjAzNDcsImV4cCI6MjA3ODY5NjM0N30.HPrlq9hi2ab0YPsE5B8OibheLOmmNqmHKG2qRjt_3jY" else {
            fatalError("Missing Supabase configuration. Please set SUPABASE_URL and SUPABASE_ANON_KEY in Info.plist or update this file.")
        }
        
        self.client = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: supabaseKey
        )
    }
    
    // MARK: - Public Methods
    
    /// Get the Supabase client instance
    static func getClient() -> SupabaseClient {
        return shared.client
    }
}

