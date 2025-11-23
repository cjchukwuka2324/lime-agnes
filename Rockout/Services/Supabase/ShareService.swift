import Foundation
import Supabase

final class ShareService {
    static let shared = ShareService()
    private init() {}
    
    private let supabase = SupabaseService.shared.client
    
    // MARK: - Create Share Link
    func createShareLink(
        for resourceType: String, // "album" or "track"
        resourceId: UUID,
        password: String? = nil,
        expiresAt: Date? = nil
    ) async throws -> ShareableLink {
        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString
        
        // Generate unique share token
        let shareToken = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        
        let dto = ShareableLinkDTO(
            resource_type: resourceType,
            resource_id: resourceId.uuidString,
            share_token: shareToken,
            created_by: userId,
            password: password,
            expires_at: expiresAt?.ISO8601Format()
        )
        
        let response = try await supabase
            .from("shareable_links")
            .insert(dto)
            .select()
            .single()
            .execute()
        
        return try JSONDecoder().decode(ShareableLink.self, from: response.data)
    }
    
    // MARK: - Get Share Link
    func getShareLink(for resourceType: String, resourceId: UUID) async throws -> ShareableLink? {
        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString
        
        do {
            let response = try await supabase
                .from("shareable_links")
                .select()
                .eq("resource_type", value: resourceType)
                .eq("resource_id", value: resourceId.uuidString)
                .eq("created_by", value: userId)
                .eq("is_active", value: true)
                .limit(1)
                .single()
                .execute()
            
            return try JSONDecoder().decode(ShareableLink.self, from: response.data)
        } catch {
            // No link found, return nil
            return nil
        }
    }
    
    // MARK: - Get Share Link by Token
    func getShareLinkByToken(_ token: String) async throws -> ShareableLink? {
        do {
            let response = try await supabase
                .from("shareable_links")
                .select()
                .eq("share_token", value: token)
                .eq("is_active", value: true)
                .limit(1)
                .single()
                .execute()
            
            return try JSONDecoder().decode(ShareableLink.self, from: response.data)
        } catch {
            // No link found, return nil
            return nil
        }
    }
    
    // MARK: - Record Listener
    func recordListener(
        shareLinkId: UUID,
        resourceType: String,
        resourceId: UUID,
        duration: Double? = nil
    ) async throws {
        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString
        
        let listenerData = ListenerDTO(
            share_link_id: shareLinkId.uuidString,
            resource_type: resourceType,
            resource_id: resourceId.uuidString,
            listener_id: userId,
            duration_listened: duration
        )
        
        try await supabase
            .from("listeners")
            .insert(listenerData)
            .execute()
        
        // Increment access count - fetch current link first
        let response = try await supabase
            .from("shareable_links")
            .select()
            .eq("id", value: shareLinkId.uuidString)
            .single()
            .execute()
        
        if let link = try? JSONDecoder().decode(ShareableLink.self, from: response.data) {
            let newCount = link.access_count + 1
            try await supabase
                .from("shareable_links")
                .update(["access_count": newCount])
                .eq("id", value: shareLinkId.uuidString)
                .execute()
        }
    }
    
    // MARK: - Get Listeners
    func getListeners(for shareLinkId: UUID) async throws -> [ListenerRecord] {
        let response = try await supabase
            .from("listeners")
            .select()
            .eq("share_link_id", value: shareLinkId.uuidString)
            .order("listened_at", ascending: false)
            .execute()
        
        return try JSONDecoder().decode([ListenerRecord].self, from: response.data)
    }
    
    // MARK: - Revoke Share Link
    func revokeShareLink(_ link: ShareableLink) async throws {
        try await supabase
            .from("shareable_links")
            .update(["is_active": false])
            .eq("id", value: link.id.uuidString)
            .execute()
    }
    
    // MARK: - Generate Share URL
    func generateShareURL(for link: ShareableLink) -> String {
        return "rockout://share/\(link.share_token)"
    }
}

