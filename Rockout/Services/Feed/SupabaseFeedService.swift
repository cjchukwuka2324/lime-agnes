import Foundation
import Supabase

final class SupabaseFeedService: FeedService {
    static let shared = SupabaseFeedService()
    
    private let supabase = SupabaseService.shared.client
    private let social = SupabaseSocialGraphService.shared
    
    private init() {}
    
    // MARK: - Data Models
    
    struct FeedPostRow: Decodable {
        // Core fields (required)
        let id: UUID
        let user_id: UUID
        let text: String
        let created_at: String
        let like_count: Int
        let is_liked_by_current_user: Bool
        let reply_count: Int
        let author_display_name: String
        // These fields might be missing if SQL function is old version - provide fallbacks
        let author_handle: String
        let author_avatar_initials: String
        
        // Optional media fields
        let image_urls: [String]?
        let video_url: String?
        let audio_url: String?
        let parent_post_id: UUID?
        let leaderboard_entry_id: String?
        let leaderboard_artist_name: String?
        let leaderboard_rank: Int?
        let leaderboard_percentile_label: String?
        let leaderboard_minutes_listened: Int?
        let reshared_post_id: UUID?
        let author_profile_picture_url: String?
        
        // Social media handles
        let instagram: String?
        let twitter: String?
        let tiktok: String?
        
        // New optional fields (Spotify, Poll, Background Music)
        // These might not be present if SQL function hasn't been updated
        let spotify_link_url: String?
        let spotify_link_type: String?
        let spotify_link_data: [String: AnyCodable]?
        let poll_question: String?
        let poll_type: String?
        let poll_options: AnyCodable? // Changed to AnyCodable to handle both array and dictionary
        let background_music_spotify_id: String?
        let background_music_data: [String: AnyCodable]?
        
        // Custom decoding to handle missing new fields gracefully
        enum CodingKeys: String, CodingKey {
            case id, user_id, text, created_at, like_count, is_liked_by_current_user, reply_count
            case author_display_name, author_handle, author_avatar_initials
            case image_urls, video_url, audio_url, parent_post_id
            case leaderboard_entry_id, leaderboard_artist_name, leaderboard_rank
            case leaderboard_percentile_label, leaderboard_minutes_listened, reshared_post_id
            case author_profile_picture_url
            case instagram, twitter, tiktok
            case spotify_link_url, spotify_link_type, spotify_link_data
            case poll_question, poll_type, poll_options
            case background_music_spotify_id, background_music_data
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            // Required fields
            id = try container.decode(UUID.self, forKey: .id)
            user_id = try container.decode(UUID.self, forKey: .user_id)
            text = try container.decode(String.self, forKey: .text)
            created_at = try container.decode(String.self, forKey: .created_at)
            like_count = try container.decode(Int.self, forKey: .like_count)
            is_liked_by_current_user = try container.decode(Bool.self, forKey: .is_liked_by_current_user)
            reply_count = try container.decode(Int.self, forKey: .reply_count)
            author_display_name = try container.decode(String.self, forKey: .author_display_name)
            
            // These fields might be missing if SQL function is old version - provide fallbacks
            if let handle = try? container.decode(String.self, forKey: .author_handle) {
                author_handle = handle
            } else {
                // Fallback: generate handle from display name or user ID
                let fallbackHandle = "@\(author_display_name.lowercased().replacingOccurrences(of: " ", with: ""))"
                author_handle = fallbackHandle.isEmpty ? "@user" : fallbackHandle
                print("⚠️ author_handle missing, using fallback: \(author_handle)")
            }
            
            if let initials = try? container.decode(String.self, forKey: .author_avatar_initials) {
                author_avatar_initials = initials
            } else {
                // Fallback: generate initials from display name
                let words = author_display_name.components(separatedBy: " ").filter { !$0.isEmpty }
                if words.count >= 2 {
                    author_avatar_initials = String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
                } else if let firstWord = words.first {
                    author_avatar_initials = String(firstWord.prefix(2)).uppercased()
                } else {
                    author_avatar_initials = "U"
                }
                print("⚠️ author_avatar_initials missing, using fallback: \(author_avatar_initials)")
            }
            
            // Optional fields
            image_urls = try container.decodeIfPresent([String].self, forKey: .image_urls)
            video_url = try container.decodeIfPresent(String.self, forKey: .video_url)
            audio_url = try container.decodeIfPresent(String.self, forKey: .audio_url)
            parent_post_id = try container.decodeIfPresent(UUID.self, forKey: .parent_post_id)
            leaderboard_entry_id = try container.decodeIfPresent(String.self, forKey: .leaderboard_entry_id)
            leaderboard_artist_name = try container.decodeIfPresent(String.self, forKey: .leaderboard_artist_name)
            leaderboard_rank = try container.decodeIfPresent(Int.self, forKey: .leaderboard_rank)
            leaderboard_percentile_label = try container.decodeIfPresent(String.self, forKey: .leaderboard_percentile_label)
            leaderboard_minutes_listened = try container.decodeIfPresent(Int.self, forKey: .leaderboard_minutes_listened)
            reshared_post_id = try container.decodeIfPresent(UUID.self, forKey: .reshared_post_id)
            author_profile_picture_url = try container.decodeIfPresent(String.self, forKey: .author_profile_picture_url)
            
            // Social media handles
            instagram = try container.decodeIfPresent(String.self, forKey: .instagram)
            twitter = try container.decodeIfPresent(String.self, forKey: .twitter)
            tiktok = try container.decodeIfPresent(String.self, forKey: .tiktok)
            
            // New optional fields - decode with defaults if missing
            spotify_link_url = try container.decodeIfPresent(String.self, forKey: .spotify_link_url)
            spotify_link_type = try container.decodeIfPresent(String.self, forKey: .spotify_link_type)
            spotify_link_data = try container.decodeIfPresent([String: AnyCodable].self, forKey: .spotify_link_data)
            poll_question = try container.decodeIfPresent(String.self, forKey: .poll_question)
            poll_type = try container.decodeIfPresent(String.self, forKey: .poll_type)
            
            // poll_options can be either an array or a dictionary - decode as AnyCodable
            if container.contains(.poll_options) {
                do {
                    if try container.decodeNil(forKey: .poll_options) {
                        poll_options = nil
                    } else {
                        poll_options = try container.decode(AnyCodable.self, forKey: .poll_options)
                    }
                } catch {
                    print("⚠️ Failed to decode poll_options: \(error)")
                    poll_options = nil
                }
            } else {
                poll_options = nil
            }
            
            background_music_spotify_id = try container.decodeIfPresent(String.self, forKey: .background_music_spotify_id)
            background_music_data = try container.decodeIfPresent([String: AnyCodable].self, forKey: .background_music_data)
        }
    }
    
    // MARK: - Helper Functions
    
    /// Parse hashtags from text using regex
    /// Returns array of unique hashtags (without # symbol, lowercase)
    private func parseHashtags(from text: String) -> [String] {
        // Regex pattern: # followed by alphanumeric and underscore
        let pattern = #"#([a-zA-Z0-9_]+)"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        
        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        var hashtags: [String] = []
        for match in matches {
            if match.numberOfRanges > 1 {
                let hashtagRange = match.range(at: 1) // Capture group 1 (without #)
                let hashtag = nsString.substring(with: hashtagRange).lowercased()
                if !hashtags.contains(hashtag) { // Deduplicate
                    hashtags.append(hashtag)
                }
            }
        }
        
        return hashtags
    }
    
    /// Link post to hashtags via RPC
    private func linkPostToHashtags(postId: String, hashtags: [String]) async throws {
        guard !hashtags.isEmpty else { return }
        
        struct LinkHashtagsParams: Encodable {
            let p_post_id: String
            let p_hashtags: [String]
        }
        
        let params = LinkHashtagsParams(p_post_id: postId, p_hashtags: hashtags)
        
        do {
            _ = try await supabase
                .rpc("link_post_to_hashtags", params: params)
                .execute()
            print("✅ Linked post \(postId) to \(hashtags.count) hashtags: \(hashtags.joined(separator: ", "))")
        } catch {
            print("⚠️ Failed to link hashtags: \(error.localizedDescription)")
            // Don't throw - hashtag linking is non-critical
        }
    }
    
    /// Extracts the Spotify artist ID from a composite leaderboard entry ID
    /// Format is "artistId-userUUID" where UUID has format 8-4-4-4-12
    private func extractArtistId(from compositeId: String) -> String {
        // If the composite ID contains a UUID pattern (has 5 parts after a dash), extract artist ID
        // UUID format: 8-4-4-4-12 (e.g., "12345678-1234-1234-1234-123456789012")
        let parts = compositeId.split(separator: "-")
        
        // Helper to check if a character is a hex digit
        func isHexDigit(_ char: Character) -> Bool {
            return ("0"..."9").contains(char) || ("a"..."f").contains(char) || ("A"..."F").contains(char)
        }
        
        // Check if last 5 parts form a UUID pattern (all are hex digits with correct lengths)
        if parts.count >= 6 {
            let lastFiveParts = Array(parts.suffix(5))
            let isUUID = lastFiveParts.enumerated().allSatisfy { index, part in
                let expectedLength = index == 4 ? 12 : (index == 0 ? 8 : 4)
                return part.count == expectedLength && part.allSatisfy { isHexDigit($0) }
            }
            
            if isUUID {
                // Extract artist ID (everything before the UUID)
                let artistIdParts = parts.dropLast(5)
                return artistIdParts.joined(separator: "-")
            }
        }
        
        // Fallback: if no clear UUID pattern, try simpler extraction
        // Spotify artist IDs are typically 22 characters (base62), no dashes
        // If there's a dash, the part before might be artist ID, after might be UUID
        if parts.count >= 2 {
            // Check if we can identify UUID pattern in last parts
            if parts.count >= 6 {
                // Likely has UUID, try extracting
                let artistIdParts = parts.dropLast(5)
                if !artistIdParts.isEmpty {
                    return artistIdParts.joined(separator: "-")
                }
            }
            // Simple case: artistId-uuid, take first part
            return String(parts.first ?? "")
        }
        
        // No separator or can't determine, return as-is (might be just artist ID)
        return compositeId
    }
    
    // MARK: - RPC Parameter Structs
    
    private struct GetFeedPostsParams: Encodable {
        let p_feed_type: String
        let p_region: String?
        let p_limit: Int
        let p_offset: Int
    }
    
    private struct GetFeedPostsPaginatedParams: Encodable {
        let p_feed_type: String
        let p_region: String?
        let p_limit: Int
        let p_cursor: String? // ISO8601 timestamp
    }
    
    private struct CreatePostParams: Encodable {
        let p_text: String
        let p_image_urls: [String]
        let p_video_url: String?
        let p_audio_url: String?
        let p_parent_post_id: String?
        let p_leaderboard_entry_id: String?
        let p_leaderboard_artist_name: String?
        let p_leaderboard_rank: Int?
        let p_leaderboard_percentile_label: String?
        let p_leaderboard_minutes_listened: Int?
        let p_reshared_post_id: String?
        let p_spotify_link_url: String?
        let p_spotify_link_type: String?
        let p_spotify_link_data: [String: AnyCodable]?
        let p_poll_question: String?
        let p_poll_type: String?
        let p_poll_options: [String: AnyCodable]?
        let p_background_music_spotify_id: String?
        let p_background_music_data: [String: AnyCodable]?
    }
    
    // Helper for decoding polls from JSONB
    private func decodePoll(
        question: String?,
        typeString: String?,
        optionsData: AnyCodable?,
        postId: String
    ) -> Poll? {
        guard let question = question,
              let typeString = typeString,
              let optionsData = optionsData else {
            return nil
        }
        
        // Try to decode options - handle both structures
        var optionsArray: [[String: Any]] = []
        
        // First try: optionsData is a dictionary with "options" key
        if let optionsDict = optionsData.value as? [String: Any],
           let optionsCodable = optionsDict["options"] as? AnyCodable,
           let wrappedOptions = optionsCodable.value as? [[String: Any]] {
            optionsArray = wrappedOptions
        }
        // Second try: optionsData is a dictionary, check if "options" key exists
        else if let optionsDict = optionsData.value as? [String: Any],
                let optionsValue = optionsDict["options"],
                let wrappedOptions = (optionsValue as? AnyCodable)?.value as? [[String: Any]] ?? (optionsValue as? [[String: Any]]) {
            optionsArray = wrappedOptions
        }
        // Second try: optionsData itself is an array
        else if let directArray = optionsData.value as? [[String: Any]] {
            optionsArray = directArray
        }
        // Third try: convert dictionary values to their underlying values and try to find array
        else if let optionsDict = optionsData.value as? [String: Any] {
            // Convert AnyCodable dictionary to regular dictionary
            // Be careful: .value might contain __SwiftValue which can't be serialized
            // Instead of using .value directly, try to extract the underlying JSON-serializable value
            var regularDict: [String: Any] = [:]
            for (key, value) in optionsDict {
                // Handle value which could be AnyCodable or direct value
                let actualValue: Any
                if let codable = value as? AnyCodable {
                    actualValue = codable.value
                } else {
                    actualValue = value
                }
                
                // Try to extract a JSON-serializable value
                if let stringValue = actualValue as? String {
                    regularDict[key] = stringValue
                } else if let intValue = actualValue as? Int {
                    regularDict[key] = intValue
                } else if let doubleValue = actualValue as? Double {
                    regularDict[key] = doubleValue
                } else if let boolValue = actualValue as? Bool {
                    regularDict[key] = boolValue
                } else if let arrayValue = actualValue as? [Any] {
                    // Recursively convert array elements
                    regularDict[key] = arrayValue.map { item -> Any in
                        if let itemCodable = item as? AnyCodable {
                            // Extract JSON-serializable value from AnyCodable
                            if let stringVal = itemCodable.value as? String { return stringVal }
                            if let intVal = itemCodable.value as? Int { return intVal }
                            if let doubleVal = itemCodable.value as? Double { return doubleVal }
                            if let boolVal = itemCodable.value as? Bool { return boolVal }
                            if let dictVal = itemCodable.value as? [String: Any] { return dictVal }
                            if let arrayVal = itemCodable.value as? [Any] { return arrayVal }
                            // If we can't extract, return empty dict to avoid __SwiftValue
                            return [String: Any]()
                        }
                        return item
                    }
                } else if let dictValue = actualValue as? [String: Any] {
                    regularDict[key] = dictValue
                } else {
                    // Skip values that can't be serialized (e.g., __SwiftValue)
                    print("⚠️ Warning: Skipping non-serializable value for key '\(key)' in poll_options")
                }
            }
            
            if let wrapped = regularDict["options"] as? [[String: Any]] {
                optionsArray = wrapped
            } else if let optionsValue = regularDict["options"] as? [Any] {
                // Try to convert array of Any to array of [String: Any]
                optionsArray = optionsValue.compactMap { item -> [String: Any]? in
                    if let dict = item as? [String: Any] {
                        return dict
                    }
                    return nil
                }
            }
        }
        
        guard !optionsArray.isEmpty else {
            print("⚠️ Poll options array is empty for post \(postId)")
            return nil
        }
        
        let options = optionsArray.enumerated().compactMap { index, optionDict -> PollOption? in
            guard let text = optionDict["text"] as? String else { return nil }
            let votes = (optionDict["votes"] as? Int) ?? 0
            return PollOption(id: index, text: text, voteCount: votes)
        }
        
        guard !options.isEmpty else {
            print("⚠️ No valid poll options decoded for post \(postId)")
            return nil
        }
        
        let decodedPoll = Poll(
            id: postId,
            question: question,
            options: options,
            type: typeString
        )
        print("📊 Decoded poll: \(question) with \(options.count) options")
        return decodedPoll
    }
    
    // Helper for encoding JSONB fields
    struct AnyCodable: Codable {
        let value: Any
        
        init(_ value: Any) {
            self.value = value
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let bool = try? container.decode(Bool.self) {
                value = bool
            } else if let int = try? container.decode(Int.self) {
                value = int
            } else if let double = try? container.decode(Double.self) {
                value = double
            } else if let string = try? container.decode(String.self) {
                value = string
            } else if let array = try? container.decode([AnyCodable].self) {
                value = array.map { $0.value }
            } else if let dict = try? container.decode([String: AnyCodable].self) {
                value = dict.mapValues { $0.value }
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch value {
            case let bool as Bool:
                try container.encode(bool)
            case let int as Int:
                try container.encode(int)
            case let double as Double:
                try container.encode(double)
            case let string as String:
                try container.encode(string)
            case let array as [Any]:
                try container.encode(array.map { AnyCodable($0) })
            case let dict as [String: Any]:
                try container.encode(dict.mapValues { AnyCodable($0) })
            case is NSNull:
                try container.encodeNil()
            default:
                // For types that can't be directly serialized (like __SwiftValue),
                // we need to handle them more carefully
                // First, check if the value is already a valid JSON type
                if value is NSNull {
                    try container.encodeNil()
                } else if let stringValue = value as? String {
                    try container.encode(stringValue)
                } else if let numberValue = value as? NSNumber {
                    // NSNumber can represent Int, Double, Bool
                    if CFGetTypeID(numberValue) == CFBooleanGetTypeID() {
                        try container.encode(numberValue.boolValue)
                    } else {
                        // Check if it's an integer by comparing intValue with doubleValue
                        let intVal = numberValue.intValue
                        let doubleVal = numberValue.doubleValue
                        if Double(intVal) == doubleVal {
                            try container.encode(intVal)
                        } else {
                            try container.encode(doubleVal)
                        }
                    }
                } else {
                    // For other types, try to serialize as JSON, but catch errors gracefully
                    do {
                        // Test if it's valid JSON by trying to serialize it
                        // This will throw if the value contains __SwiftValue or other non-serializable types
                        let jsonData = try JSONSerialization.data(withJSONObject: value)
                        let jsonObject = try JSONSerialization.jsonObject(with: jsonData)
                        try container.encode(AnyCodable(jsonObject))
                    } catch {
                        // If serialization fails (e.g., __SwiftValue), encode as null
                        // This prevents the app from crashing when encountering non-serializable types
                        print("⚠️ Warning: Could not encode AnyCodable value of type \(type(of: value)): \(error). Encoding as null.")
                        try container.encodeNil()
                    }
                }
            }
        }
    }
    
    private struct DeletePostParams: Encodable {
        let p_post_id: String
    }
    
    private struct TogglePostLikeParams: Encodable {
        let p_post_id: String
    }
    
    // MARK: - Fetch Home Feed (Paginated)
    
    func fetchHomeFeed(feedType: FeedType, region: String?, cursor: Date? = nil, limit: Int = 20) async throws -> (posts: [Post], nextCursor: String?, hasMore: Bool) {
        let feedTypeString = feedType == .following ? "following" : "for_you"
        
        // Get user's region from profile if not provided
        var userRegion = region
        if userRegion == nil && feedType == .forYou {
            // Try to get region from user profile stored in Supabase
            do {
                // Check profiles table for region
                let profileResponse = try await supabase
                    .from("profiles")
                    .select("region")
                    .eq("id", value: supabase.auth.currentUser?.id.uuidString ?? "")
                    .single()
                    .execute()
                
                struct ProfileRegion: Decodable {
                    let region: String?
                }
                
                if let profile = try? JSONDecoder().decode(ProfileRegion.self, from: profileResponse.data) {
                    userRegion = profile.region
                }
            } catch {
                // Region will remain nil, algorithm will still work (shows all posts)
            }
        }
        
        // Convert cursor to ISO8601 string
        let cursorString: String?
        if let cursor = cursor {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            cursorString = formatter.string(from: cursor)
        } else {
            cursorString = nil
        }
        
        // Use paginated RPC function
        let params = GetFeedPostsPaginatedParams(
            p_feed_type: feedTypeString,
            p_region: userRegion,
            p_limit: limit,
            p_cursor: cursorString
        )
        
        print("🔍 Calling get_feed_posts_paginated with params: feed_type=\(feedTypeString), region=\(userRegion ?? "nil"), limit=\(limit), cursor=\(cursorString ?? "nil")")
        
        let responseData: Data
        do {
            let response = try await supabase
                .rpc("get_feed_posts_paginated", params: params)
                .select("*")
                .execute()
            responseData = response.data
            print("✅ RPC call succeeded, response data size: \(responseData.count) bytes")
            
            // Log first 500 chars of response for debugging
            if let responseString = String(data: responseData, encoding: .utf8) {
                print("🔍 Response preview: \(responseString.prefix(500))")
            }
        } catch let error as DecodingError {
            // If Supabase is trying to auto-decode and failing, we need to work around it
            print("❌ Decoding error at RPC call level: \(error)")
            switch error {
            case .typeMismatch(let type, let context):
                print("❌ Type mismatch: expected \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                print("❌ Debug: \(context.debugDescription)")
                print("⚠️ This suggests Supabase is trying to auto-decode the response. The RPC function returns a TABLE (array), but Supabase might be expecting a different type.")
            default:
                print("❌ Other decoding error: \(error)")
            }
            // Try to get raw response data by making a direct HTTP call or using a workaround
            // For now, rethrow the error - we'll need to investigate the Supabase client behavior
            throw NSError(domain: "SupabaseFeedService", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to call get_feed_posts RPC: \(error.localizedDescription). This may be a Supabase client issue with TABLE-returning RPC functions."
            ])
        } catch {
            print("❌ RPC call failed: \(error)")
            if let supabaseError = error as? PostgrestError {
                print("❌ Postgrest error: \(supabaseError.message ?? "unknown")")
                print("❌ Error code: \(supabaseError.code ?? "unknown")")
            }
            throw error
        }
        
        // Debug: Print full response to see what we're getting
        if let responseString = String(data: responseData, encoding: .utf8) {
            print("🔍 Full feed response length: \(responseString.count) characters")
            
            // Check if response looks truncated (doesn't end with ])
            if !responseString.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("]") {
                print("⚠️ WARNING: Response doesn't end with ']' - might be truncated!")
                // Try to find where it breaks
                if let lastBrace = responseString.lastIndex(of: "}") {
                    let afterLastBrace = String(responseString[responseString.index(after: lastBrace)...])
                    print("⚠️ After last complete object: '\(afterLastBrace.prefix(200))'")
                }
            }
            
            // Check if JSON is valid
            do {
                let jsonObject = try JSONSerialization.jsonObject(with: responseData)
                print("✅ JSON is valid")
                if let array = jsonObject as? [Any] {
                    print("✅ Response is an array with \(array.count) items")
                    if let firstItem = array.first as? [String: Any] {
                        print("🔍 First post has \(firstItem.keys.count) keys: \(firstItem.keys.sorted().joined(separator: ", "))")
                        // Check for missing required fields
                        let requiredFields = ["id", "user_id", "text", "created_at", "like_count", "is_liked_by_current_user", "reply_count", "author_display_name", "author_handle", "author_avatar_initials"]
                        let missingFields = requiredFields.filter { firstItem[$0] == nil }
                        if !missingFields.isEmpty {
                            print("⚠️ Missing required fields: \(missingFields.joined(separator: ", "))")
                        }
                        // Check for new optional fields
                        let newFields = ["spotify_link_url", "spotify_link_type", "spotify_link_data", "poll_question", "poll_type", "poll_options", "background_music_spotify_id", "background_music_data"]
                        let presentNewFields = newFields.filter { firstItem[$0] != nil }
                        print("🔍 New fields present: \(presentNewFields.joined(separator: ", "))")
                        
                        // Check author_display_name value
                        if let displayName = firstItem["author_display_name"] as? String {
                            print("🔍 author_display_name value: '\(displayName)' (length: \(displayName.count))")
                        }
                    }
                } else {
                    print("⚠️ Response is not an array")
                }
            } catch {
                print("⚠️ JSON is NOT valid - response might be truncated or malformed")
                print("⚠️ JSON parsing error: \(error)")
                if responseString.count > 2000 {
                    print("🔍 First 1000 chars: \(responseString.prefix(1000))")
                    print("🔍 Last 1000 chars: \(responseString.suffix(1000))")
                } else {
                    print("🔍 Full response: \(responseString)")
                }
            }
        } else {
            print("⚠️ Could not convert response data to string")
        }
        
        let rows: [FeedPostRow]
        do {
            rows = try JSONDecoder().decode([FeedPostRow].self, from: responseData)
            print("✅ Successfully decoded \(rows.count) feed posts")
        } catch {
            // Debug: print the actual response and error details
            if let responseString = String(data: responseData, encoding: .utf8) {
                print("⚠️ Failed to decode FeedPostRow. Response length: \(responseString.count)")
                // Try to find where JSON breaks
                if let brokenIndex = responseString.range(of: "\"author_display_name\":\"", options: [])?.upperBound {
                    let afterDisplayName = String(responseString[brokenIndex...])
                    if let nextQuote = afterDisplayName.firstIndex(of: "\"") {
                        let displayNameValue = String(afterDisplayName[..<nextQuote])
                        print("🔍 author_display_name value: '\(displayNameValue)'")
                        let afterValue = String(afterDisplayName[afterDisplayName.index(after: nextQuote)...])
                        print("🔍 After author_display_name: '\(afterValue.prefix(200))'")
                    } else {
                        print("⚠️ author_display_name value is not properly closed - JSON is truncated!")
                    }
                }
            }
            print("⚠️ Decoding error: \(error)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    print("⚠️ Missing key: \(key.stringValue) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .typeMismatch(let type, let context):
                    print("⚠️ Type mismatch: expected \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .valueNotFound(let type, let context):
                    print("⚠️ Value not found: \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .dataCorrupted(let context):
                    print("⚠️ Data corrupted at path: \(context.codingPath.map { $0.stringValue }.joined(separator: ".")), description: \(context.debugDescription)")
                @unknown default:
                    print("⚠️ Unknown decoding error")
                }
            }
            throw NSError(domain: "FeedService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to decode feed data: \(error.localizedDescription)"])
        }
        
        // Parse dates
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // Collect all parent post IDs that we need to fetch
        let parentPostIds = Set(rows.compactMap { $0.parent_post_id })
        
        // Fetch parent posts if we have any replies
        var parentPostsMap: [String: PostSummary] = [:]
        if !parentPostIds.isEmpty {
            do {
                let parentIdsArray = Array(parentPostIds)
                let parentResponse = try await supabase
                    .from("posts")
                    .select("""
                        id,
                        user_id,
                        text,
                        image_urls,
                        video_url,
                        audio_url
                    """)
                    .in("id", values: parentIdsArray.map { $0.uuidString })
                    .is("deleted_at", value: nil)
                    .execute()
                
                struct ParentPostRow: Decodable {
                    let id: UUID
                    let user_id: UUID
                    let text: String
                    let image_urls: [String]?
                    let video_url: String?
                    let audio_url: String?
                }
                
                // First decode the parent posts to get user IDs
                let parentPosts: [ParentPostRow] = try JSONDecoder().decode([ParentPostRow].self, from: parentResponse.data)
                
                // Get parent post authors by USER ID (not post ID)
                let parentUserIds = Set(parentPosts.map { $0.user_id })
                var parentAuthorsMap: [String: UserSummary] = [:]
                
                if !parentUserIds.isEmpty {
                    let parentUsersResponse = try await supabase
                        .from("profiles")
                        .select("""
                            id,
                            display_name,
                            first_name,
                            last_name,
                            username,
                            profile_picture_url
                        """)
                        .in("id", values: Array(parentUserIds))
                        .limit(1000)
                        .execute()
                    
                    struct ParentProfileRow: Decodable {
                        let id: UUID
                        let display_name: String?
                        let first_name: String?
                        let last_name: String?
                        let username: String?
                        let profile_picture_url: String?
                    }
                    
                    let parentProfiles: [ParentProfileRow] = try JSONDecoder().decode([ParentProfileRow].self, from: parentUsersResponse.data)
                    
                    for profile in parentProfiles {
                        let displayName = profile.display_name ??
                            (profile.first_name != nil && profile.last_name != nil ?
                             "\(profile.first_name!) \(profile.last_name!)" :
                             profile.username?.capitalized ?? "User")
                        
                        let handle = profile.username.map { "@\($0)" } ?? "@user"
                        
                        let initials: String = {
                            if let firstName = profile.first_name, let lastName = profile.last_name {
                                return "\(String(firstName.prefix(1)))\(String(lastName.prefix(1)))".uppercased()
                            } else if let displayName = profile.display_name {
                                return String(displayName.prefix(2)).uppercased()
                            } else if let username = profile.username {
                                return String(username.prefix(2)).uppercased()
                            }
                            return "U"
                        }()
                        
                        let pictureURL = profile.profile_picture_url.flatMap { URL(string: $0) }
                        
                        parentAuthorsMap[profile.id.uuidString] = UserSummary(
                            id: profile.id.uuidString,
                            displayName: displayName,
                            handle: handle,
                            avatarInitials: initials,
                            profilePictureURL: pictureURL,
                            isFollowing: false
                        )
                    }
                }
                
                for parentRow in parentPosts {
                    let parentId = parentRow.id.uuidString
                    // Look up author by USER ID, not post ID
                    let author = parentAuthorsMap[parentRow.user_id.uuidString] ?? UserSummary(
                        id: parentRow.user_id.uuidString,
                        displayName: "User",
                        handle: "@user",
                        avatarInitials: "U",
                        profilePictureURL: nil,
                        isFollowing: false
                    )
                    
                    let imageURLs = (parentRow.image_urls ?? []).compactMap { URL(string: $0) }
                    let videoURL = parentRow.video_url.flatMap { URL(string: $0) }
                    
                    parentPostsMap[parentId] = PostSummary(
                        id: parentId,
                        text: parentRow.text,
                        createdAt: Date(), // Parent post summary doesn't need exact timestamp
                        author: author,
                        imageURLs: imageURLs,
                        videoURL: videoURL
                    )
                }
            } catch {
                print("⚠️ Error fetching parent posts: \(error)")
                // Continue without parent post summaries
            }
        }
        
        let posts = rows.map { row -> Post in
            let imageURLs = (row.image_urls ?? []).compactMap { URL(string: $0) }
            let videoURL = row.video_url.flatMap { URL(string: $0) }
            let audioURL = row.audio_url.flatMap { URL(string: $0) }
            
            // Parse created_at date
            let createdAt = formatter.date(from: row.created_at) ?? Date()
            
            let author = UserSummary(
                id: row.user_id.uuidString,
                displayName: row.author_display_name,
                handle: row.author_handle,
                avatarInitials: row.author_avatar_initials,
                profilePictureURL: row.author_profile_picture_url.flatMap { URL(string: $0) },
                isFollowing: false // Will be updated by SocialGraphService
            )
            
            let leaderboardEntry: LeaderboardEntrySummary? = {
                guard let entryId = row.leaderboard_entry_id,
                      let artistName = row.leaderboard_artist_name,
                      let rank = row.leaderboard_rank,
                      let percentile = row.leaderboard_percentile_label,
                      let minutes = row.leaderboard_minutes_listened else {
                    return nil
                }
                
                // Extract artist ID from composite entry ID
                let artistId = extractArtistId(from: entryId)
                print("🎵 Extracted artist ID '\(artistId)' from composite ID '\(entryId)'")
                
                return LeaderboardEntrySummary(
                    id: entryId,
                    userId: row.user_id.uuidString,
                    userDisplayName: row.author_display_name,
                    artistId: artistId,
                    artistName: artistName,
                    artistImageURL: nil,
                    rank: rank,
                    percentileLabel: percentile,
                    minutesListened: minutes
                )
            }()
            
            // Get parent post summary if this is a reply
            let parentPostSummary: PostSummary? = {
                if let parentId = row.parent_post_id?.uuidString {
                    return parentPostsMap[parentId]
                }
                return nil
            }()
            
            // Decode Spotify link
            let spotifyLink: SpotifyLink? = {
                if row.spotify_link_url == nil {
                    print("⚠️ spotify_link_url is nil for post \(row.id.uuidString)")
                }
                if row.spotify_link_type == nil {
                    print("⚠️ spotify_link_type is nil for post \(row.id.uuidString)")
                }
                if row.spotify_link_data == nil {
                    print("⚠️ spotify_link_data is nil for post \(row.id.uuidString)")
                }
                
                guard let url = row.spotify_link_url,
                      let type = row.spotify_link_type,
                      let data = row.spotify_link_data else {
                    return nil
                }
                
                let name = (data["name"]?.value as? String) ?? ""
                let artist = data["artist"]?.value as? String
                let owner = data["owner"]?.value as? String
                let imageURLString = data["imageURL"]?.value as? String
                let imageURL = imageURLString.flatMap { URL(string: $0) }
                
                let link = SpotifyLink(
                    id: (data["id"]?.value as? String) ?? "",
                    url: url,
                    type: type,
                    name: name,
                    artist: artist,
                    owner: owner,
                    imageURL: imageURL
                )
                print("🎵 Decoded Spotify link: \(link.name) (\(link.type)) for post \(row.id.uuidString)")
                return link
            }()
            
            // Decode poll
            let poll: Poll? = decodePoll(
                question: row.poll_question,
                typeString: row.poll_type,
                optionsData: row.poll_options,
                postId: row.id.uuidString
            )
            
            // Decode background music
            let backgroundMusic: BackgroundMusic? = {
                // Debug: Log when we have background music fields
                if row.background_music_spotify_id != nil || row.background_music_data != nil {
                    print("🔍 Found background music fields for post \(row.id.uuidString): spotifyId=\(row.background_music_spotify_id ?? "nil"), data=\(row.background_music_data != nil ? "exists" : "nil")")
                }
                
                guard let spotifyId = row.background_music_spotify_id,
                      let data = row.background_music_data else {
                    return nil
                }
                
                let name = (data["name"]?.value as? String) ?? ""
                let artist = (data["artist"]?.value as? String) ?? ""
                let previewURLString = data["previewURL"]?.value as? String
                let previewURL = previewURLString.flatMap { URL(string: $0) }
                let imageURLString = data["imageURL"]?.value as? String
                let imageURL = imageURLString.flatMap { URL(string: $0) }
                
                let bgMusic = BackgroundMusic(
                    spotifyId: spotifyId,
                    name: name,
                    artist: artist,
                    previewURL: previewURL,
                    imageURL: imageURL
                )
                
                print("🎵 Decoded background music: \(name) by \(artist) (previewURL: \(previewURL != nil ? "exists" : "nil")) for post \(row.id.uuidString)")
                
                return bgMusic
            }()
            
            return Post(
                id: row.id.uuidString,
                text: row.text,
                createdAt: createdAt,
                author: author,
                imageURLs: imageURLs,
                videoURL: videoURL,
                audioURL: audioURL,
                likeCount: row.like_count,
                replyCount: row.reply_count,
                isLiked: row.is_liked_by_current_user,
                parentPostId: row.parent_post_id?.uuidString,
                parentPost: parentPostSummary,
                leaderboardEntry: leaderboardEntry,
                resharedPostId: row.reshared_post_id?.uuidString,
                spotifyLink: spotifyLink,
                poll: poll,
                backgroundMusic: backgroundMusic
            )
        }
        
        // TODO: Merge posts into FeedStore when implemented
        // await MainActor.run {
        //     var existingPostIds = Set(FeedStore.shared.posts.map { $0.id })
        //     for post in posts {
        //         if let index = FeedStore.shared.posts.firstIndex(where: { $0.id == post.id }) {
        //             // Update existing post
        //             FeedStore.shared.posts[index] = post
        //         } else {
        //             // Add new post (insert at appropriate position to maintain chronological order)
        //             let insertIndex = FeedStore.shared.posts.firstIndex { $0.createdAt < post.createdAt } ?? FeedStore.shared.posts.count
        //             FeedStore.shared.posts.insert(post, at: insertIndex)
        //         }
        //     }
        //     // Sort by date descending
        //     FeedStore.shared.posts.sort { $0.createdAt > $1.createdAt }
        // }
        
        // Determine if there are more pages
        // If we got exactly 'limit' posts, there might be more
        let hasMore = posts.count == limit
        
        // Calculate next cursor (last post's createdAt)
        let nextCursor: String? = hasMore ? posts.last?.createdAt.description : nil
        
        return (posts: posts, nextCursor: nextCursor, hasMore: hasMore)
    }
    
    // MARK: - Create Post
    
    func createPost(
        text: String,
        imageURLs: [URL],
        videoURL: URL?,
        audioURL: URL?,
        leaderboardEntry: LeaderboardEntrySummary?,
        spotifyLink: SpotifyLink?,
        poll: Poll?,
        backgroundMusic: BackgroundMusic?
    ) async throws -> Post {
        let imageURLStrings = imageURLs.map { $0.absoluteString }
        
        // Encode Spotify link data
        let spotifyLinkData: [String: AnyCodable]? = spotifyLink.map { link in
            [
                "id": AnyCodable(link.id),
                "url": AnyCodable(link.url),
                "type": AnyCodable(link.type),
                "name": AnyCodable(link.name),
                "artist": AnyCodable(link.artist ?? ""),
                "owner": AnyCodable(link.owner ?? ""),
                "imageURL": AnyCodable(link.imageURL?.absoluteString ?? "")
            ]
        }
        
        // Encode poll options
        let pollOptionsData: [String: AnyCodable]? = poll.map { poll in
            let optionsArray: [[String: Any]] = poll.options.enumerated().map { index, option in
                [
                    "index": index,
                    "text": option.text,
                    "votes": option.voteCount
                ]
            }
            return ["options": AnyCodable(optionsArray)]
        }
        
        // Encode background music data
        let backgroundMusicData: [String: AnyCodable]? = backgroundMusic.map { music in
            [
                "spotifyId": AnyCodable(music.spotifyId),
                "name": AnyCodable(music.name),
                "artist": AnyCodable(music.artist),
                "previewURL": AnyCodable(music.previewURL?.absoluteString ?? ""),
                "imageURL": AnyCodable(music.imageURL?.absoluteString ?? "")
            ]
        }
        
        let params = CreatePostParams(
            p_text: text,
            p_image_urls: imageURLStrings,
            p_video_url: videoURL?.absoluteString,
            p_audio_url: audioURL?.absoluteString,
            p_parent_post_id: nil,
            p_leaderboard_entry_id: leaderboardEntry?.id,
            p_leaderboard_artist_name: leaderboardEntry?.artistName,
            p_leaderboard_rank: leaderboardEntry?.rank,
            p_leaderboard_percentile_label: leaderboardEntry?.percentileLabel,
            p_leaderboard_minutes_listened: leaderboardEntry?.minutesListened,
            p_reshared_post_id: nil,
            p_spotify_link_url: spotifyLink?.url,
            p_spotify_link_type: spotifyLink?.type,
            p_spotify_link_data: spotifyLinkData,
            p_poll_question: poll?.question,
            p_poll_type: poll?.type,
            p_poll_options: pollOptionsData,
            p_background_music_spotify_id: backgroundMusic?.spotifyId,
            p_background_music_data: backgroundMusicData
        )
        
        print("📤 Calling create_post RPC with params:")
        print("📤 p_spotify_link_url: \(params.p_spotify_link_url ?? "nil")")
        print("📤 p_spotify_link_type: \(params.p_spotify_link_type ?? "nil")")
        print("📤 p_spotify_link_data: \(params.p_spotify_link_data != nil ? "exists" : "nil")")
        print("🎵 p_background_music_spotify_id: \(params.p_background_music_spotify_id ?? "nil")")
        print("🎵 p_background_music_data: \(params.p_background_music_data != nil ? "exists" : "nil")")
        if let bgMusic = backgroundMusic {
            print("🎵 Background music object: name=\(bgMusic.name), artist=\(bgMusic.artist), spotifyId=\(bgMusic.spotifyId), previewURL=\(bgMusic.previewURL?.absoluteString ?? "nil")")
        } else {
            print("🎵 Background music object is nil")
        }
        
        // Call RPC to create post
        let response = try await supabase
            .rpc("create_post", params: params)
            .execute()
        
        print("📥 RPC create_post response received")
        
        // Parse UUID from response - Supabase RPC returns UUID in various formats
        let postId: String
        do {
            // Try different parsing strategies
            let rawData = response.data
            
            // Strategy 1: Try to decode as plain UUID string
            if let uuidString = try? JSONDecoder().decode(String.self, from: rawData) {
                postId = uuidString
            }
            // Strategy 2: Try to decode as UUID type
            else if let uuid = try? JSONDecoder().decode(UUID.self, from: rawData) {
                postId = uuid.uuidString
            }
            // Strategy 3: Parse as raw string and clean
            else if let rawString = String(data: rawData, encoding: .utf8) {
                var cleaned = rawString.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                // Remove JSON quotes if present
                if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") {
                    cleaned = String(cleaned.dropFirst().dropLast())
                }
                // Validate it's a UUID
                guard let uuid = UUID(uuidString: cleaned) else {
                    print("⚠️ Failed to parse UUID. Raw response: \(rawString)")
                    throw NSError(domain: "FeedService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid UUID format in response"])
                }
                postId = uuid.uuidString
            } else {
                print("⚠️ Failed to convert response data to string")
                throw NSError(domain: "FeedService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to parse response"])
            }
        } catch let error as NSError {
            print("⚠️ Error parsing post ID: \(error.localizedDescription)")
            throw error
        }
        
        // Small delay to ensure post is committed
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Parse and link hashtags (non-blocking)
        let hashtags = parseHashtags(from: text)
        if !hashtags.isEmpty {
            print("🏷️ Found \(hashtags.count) hashtags: \(hashtags.joined(separator: ", "))")
            try await linkPostToHashtags(postId: postId, hashtags: hashtags)
        }
        
        // Fetch the created post directly from database
        print("🔍 Fetching created post with ID: \(postId)")
        let postsResponse = try await supabase
            .from("posts")
            .select("id, user_id, text, image_urls, video_url, audio_url, parent_post_id, leaderboard_entry_id, leaderboard_artist_name, leaderboard_rank, leaderboard_percentile_label, leaderboard_minutes_listened, reshared_post_id, created_at, updated_at, deleted_at, spotify_link_url, spotify_link_type, spotify_link_data, poll_question, poll_type, poll_options, background_music_spotify_id, background_music_data")
            .eq("id", value: postId)
            .single()
            .execute()
        
        if let responseString = String(data: postsResponse.data, encoding: .utf8) {
            print("🔍 Post data from database: \(responseString.prefix(500))")
        }
        
        // Decode the post row - handle all possible fields
        struct PostRow: Decodable {
            let id: UUID
            let user_id: UUID
            let text: String
            let image_urls: [String]?
            let video_url: String?
            let audio_url: String?
            let parent_post_id: UUID?
            let leaderboard_entry_id: String?
            let leaderboard_artist_name: String?
            let leaderboard_rank: Int?
            let leaderboard_percentile_label: String?
            let leaderboard_minutes_listened: Int?
            let reshared_post_id: UUID?
            let created_at: String
            let updated_at: String?
            let deleted_at: String?
            let spotify_link_url: String?
            let spotify_link_type: String?
            let spotify_link_data: [String: AnyCodable]?
            let poll_question: String?
            let poll_type: String?
            let poll_options: AnyCodable? // Changed to AnyCodable to handle both array and dictionary
            let background_music_spotify_id: String?
            let background_music_data: [String: AnyCodable]?
            
            enum CodingKeys: String, CodingKey {
                case id, user_id, text, created_at, updated_at, deleted_at
                case image_urls, video_url, audio_url, parent_post_id
                case leaderboard_entry_id, leaderboard_artist_name, leaderboard_rank
                case leaderboard_percentile_label, leaderboard_minutes_listened, reshared_post_id
                case spotify_link_url, spotify_link_type, spotify_link_data
                case poll_question, poll_type, poll_options
                case background_music_spotify_id, background_music_data
            }
            
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                
                // Required fields
                id = try container.decode(UUID.self, forKey: .id)
                user_id = try container.decode(UUID.self, forKey: .user_id)
                text = try container.decode(String.self, forKey: .text)
                created_at = try container.decode(String.self, forKey: .created_at)
                
                // Optional fields
                updated_at = try container.decodeIfPresent(String.self, forKey: .updated_at)
                deleted_at = try container.decodeIfPresent(String.self, forKey: .deleted_at)
                image_urls = try container.decodeIfPresent([String].self, forKey: .image_urls)
                video_url = try container.decodeIfPresent(String.self, forKey: .video_url)
                audio_url = try container.decodeIfPresent(String.self, forKey: .audio_url)
                parent_post_id = try container.decodeIfPresent(UUID.self, forKey: .parent_post_id)
                leaderboard_entry_id = try container.decodeIfPresent(String.self, forKey: .leaderboard_entry_id)
                leaderboard_artist_name = try container.decodeIfPresent(String.self, forKey: .leaderboard_artist_name)
                leaderboard_rank = try container.decodeIfPresent(Int.self, forKey: .leaderboard_rank)
                leaderboard_percentile_label = try container.decodeIfPresent(String.self, forKey: .leaderboard_percentile_label)
                leaderboard_minutes_listened = try container.decodeIfPresent(Int.self, forKey: .leaderboard_minutes_listened)
                reshared_post_id = try container.decodeIfPresent(UUID.self, forKey: .reshared_post_id)
                spotify_link_url = try container.decodeIfPresent(String.self, forKey: .spotify_link_url)
                spotify_link_type = try container.decodeIfPresent(String.self, forKey: .spotify_link_type)
                spotify_link_data = try container.decodeIfPresent([String: AnyCodable].self, forKey: .spotify_link_data)
                poll_question = try container.decodeIfPresent(String.self, forKey: .poll_question)
                poll_type = try container.decodeIfPresent(String.self, forKey: .poll_type)
                background_music_spotify_id = try container.decodeIfPresent(String.self, forKey: .background_music_spotify_id)
                background_music_data = try container.decodeIfPresent([String: AnyCodable].self, forKey: .background_music_data)
                
                // Handle poll_options which can be an array or a dictionary
                if container.contains(.poll_options) {
                    do {
                        if try container.decodeNil(forKey: .poll_options) {
                            poll_options = nil
                        } else {
                            poll_options = try container.decode(AnyCodable.self, forKey: .poll_options)
                        }
                    } catch {
                        print("⚠️ Failed to decode poll_options in createPost: \(error)")
                        poll_options = nil
                    }
                } else {
                    poll_options = nil
                }
            }
        }
        
        let postRow: PostRow
        do {
            postRow = try JSONDecoder().decode(PostRow.self, from: postsResponse.data)
        } catch {
            // Debug: print the actual response
            if let responseString = String(data: postsResponse.data, encoding: .utf8) {
                print("⚠️ Failed to decode PostRow. Response: \(responseString)")
            }
            throw NSError(domain: "FeedService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to decode post data: \(error.localizedDescription)"])
        }
        
        // Get author info
        let currentUser = await social.currentUser()
        let allUsers = await social.allUsers()
        let author = allUsers.first(where: { $0.id == postRow.user_id.uuidString }) ?? UserSummary(
            id: postRow.user_id.uuidString,
            displayName: currentUser.displayName,
            handle: currentUser.handle,
            avatarInitials: currentUser.avatarInitials,
            profilePictureURL: currentUser.profilePictureURL,
            isFollowing: false
        )
        
        // Parse date - handle both string and ISO8601 formats
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let createdAt = formatter.date(from: postRow.created_at) ?? Date()
        
        // Create Post object
        let imageURLs = (postRow.image_urls ?? []).compactMap { URL(string: $0) }
        let videoURL = postRow.video_url.flatMap { URL(string: $0) }
        let audioURL = postRow.audio_url.flatMap { URL(string: $0) }
        
        // Decode Spotify link
        let spotifyLink: SpotifyLink? = {
            print("🔍 Decoding Spotify link for post \(postRow.id.uuidString) in createPost")
            print("🔍 spotify_link_url: \(postRow.spotify_link_url ?? "nil")")
            print("🔍 spotify_link_type: \(postRow.spotify_link_type ?? "nil")")
            print("🔍 spotify_link_data: \(postRow.spotify_link_data != nil ? "exists" : "nil")")
            
            guard let url = postRow.spotify_link_url,
                  let type = postRow.spotify_link_type,
                  let data = postRow.spotify_link_data else {
                print("⚠️ Missing Spotify link data for post \(postRow.id.uuidString)")
                return nil
            }
            
            let name = (data["name"]?.value as? String) ?? ""
            let artist = data["artist"]?.value as? String
            let owner = data["owner"]?.value as? String
            let imageURLString = data["imageURL"]?.value as? String
            let imageURL = imageURLString.flatMap { URL(string: $0) }
            
            let link = SpotifyLink(
                id: (data["id"]?.value as? String) ?? "",
                url: url,
                type: type,
                name: name,
                artist: artist,
                owner: owner,
                imageURL: imageURL
            )
            print("✅ Successfully decoded Spotify link: \(link.name) (\(link.type)) for post \(postRow.id.uuidString)")
            return link
        }()
        
        // Decode poll
        let poll: Poll? = decodePoll(
            question: postRow.poll_question,
            typeString: postRow.poll_type,
            optionsData: postRow.poll_options,
            postId: postRow.id.uuidString
        )
        
        // Decode background music
        let backgroundMusic: BackgroundMusic? = {
            guard let spotifyId = postRow.background_music_spotify_id,
                  let data = postRow.background_music_data else {
                return nil
            }
            
            let name = (data["name"]?.value as? String) ?? ""
            let artist = (data["artist"]?.value as? String) ?? ""
            let previewURLString = data["previewURL"]?.value as? String
            let previewURL = previewURLString.flatMap { URL(string: $0) }
            let imageURLString = data["imageURL"]?.value as? String
            let imageURL = imageURLString.flatMap { URL(string: $0) }
            
            return BackgroundMusic(
                spotifyId: spotifyId,
                name: name,
                artist: artist,
                previewURL: previewURL,
                imageURL: imageURL
            )
        }()
        
        let createdPost = Post(
            id: postRow.id.uuidString,
            text: postRow.text,
            createdAt: createdAt,
            author: author,
            imageURLs: imageURLs,
            videoURL: videoURL,
            audioURL: audioURL,
            likeCount: 0,
            replyCount: 0,
            isLiked: false,
            parentPostId: postRow.parent_post_id?.uuidString,
            parentPost: nil,
            leaderboardEntry: leaderboardEntry,
            resharedPostId: postRow.reshared_post_id?.uuidString,
            spotifyLink: spotifyLink,
            poll: poll,
            backgroundMusic: backgroundMusic
        )
        
        print("✅ Created Post object with spotifyLink: \(createdPost.spotifyLink?.name ?? "nil")")
        
        // TODO: Update FeedStore when implemented
        // await MainActor.run {
        //     FeedStore.shared.posts.insert(createdPost, at: 0)
        //     print("✅ Added post to FeedStore. Total posts: \(FeedStore.shared.posts.count)")
        // }
        
        return createdPost
    }
    
    // MARK: - Reply
    
    func reply(
        to parentPost: Post,
        text: String,
        imageURLs: [URL],
        videoURL: URL?,
        audioURL: URL?,
        spotifyLink: SpotifyLink? = nil,
        poll: Poll? = nil,
        backgroundMusic: BackgroundMusic? = nil
    ) async throws -> Post {
        let imageURLStrings = imageURLs.map { $0.absoluteString }
        
        // Encode Spotify link data
        let spotifyLinkData: [String: AnyCodable]? = spotifyLink.map { link in
            [
                "id": AnyCodable(link.id),
                "url": AnyCodable(link.url),
                "type": AnyCodable(link.type),
                "name": AnyCodable(link.name),
                "artist": AnyCodable(link.artist ?? ""),
                "owner": AnyCodable(link.owner ?? ""),
                "imageURL": AnyCodable(link.imageURL?.absoluteString ?? "")
            ]
        }
        
        // Encode poll options
        let pollOptionsData: [String: AnyCodable]? = poll.map { poll in
            let optionsArray: [[String: Any]] = poll.options.enumerated().map { index, option in
                [
                    "index": index,
                    "text": option.text,
                    "votes": option.voteCount
                ]
            }
            return ["options": AnyCodable(optionsArray)]
        }
        
        // Encode background music data
        let backgroundMusicData: [String: AnyCodable]? = backgroundMusic.map { music in
            [
                "spotifyId": AnyCodable(music.spotifyId),
                "name": AnyCodable(music.name),
                "artist": AnyCodable(music.artist),
                "previewURL": AnyCodable(music.previewURL?.absoluteString ?? ""),
                "imageURL": AnyCodable(music.imageURL?.absoluteString ?? "")
            ]
        }
        
        let params = CreatePostParams(
            p_text: text,
            p_image_urls: imageURLStrings,
            p_video_url: videoURL?.absoluteString,
            p_audio_url: audioURL?.absoluteString,
            p_parent_post_id: parentPost.id,
            p_leaderboard_entry_id: nil,
            p_leaderboard_artist_name: nil,
            p_leaderboard_rank: nil,
            p_leaderboard_percentile_label: nil,
            p_leaderboard_minutes_listened: nil,
            p_reshared_post_id: nil,
            p_spotify_link_url: spotifyLink?.url,
            p_spotify_link_type: spotifyLink?.type,
            p_spotify_link_data: spotifyLinkData,
            p_poll_question: poll?.question,
            p_poll_type: poll?.type,
            p_poll_options: pollOptionsData,
            p_background_music_spotify_id: backgroundMusic?.spotifyId,
            p_background_music_data: backgroundMusicData
        )
        
        // Call RPC to create reply
        let response = try await supabase
            .rpc("create_post", params: params)
            .execute()
        
        // Parse UUID from response
        let postId: String
        do {
            let rawData = response.data
            if let uuidString = try? JSONDecoder().decode(String.self, from: rawData) {
                postId = uuidString
            } else if let uuid = try? JSONDecoder().decode(UUID.self, from: rawData) {
                postId = uuid.uuidString
            } else if let rawString = String(data: rawData, encoding: .utf8) {
                var cleaned = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") {
                    cleaned = String(cleaned.dropFirst().dropLast())
                }
                guard let uuid = UUID(uuidString: cleaned) else {
                    throw NSError(domain: "FeedService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid UUID format"])
                }
                postId = uuid.uuidString
            } else {
                throw NSError(domain: "FeedService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to parse response"])
            }
        } catch let error as NSError {
            throw error
        }
        
        // Small delay to ensure post is committed
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Parse and link hashtags (non-blocking)
        let hashtags = parseHashtags(from: text)
        if !hashtags.isEmpty {
            print("🏷️ Found \(hashtags.count) hashtags in reply: \(hashtags.joined(separator: ", "))")
            try await linkPostToHashtags(postId: postId, hashtags: hashtags)
        }
        
        // Fetch the created reply directly from database
        let postsResponse = try await supabase
            .from("posts")
            .select("*")
            .eq("id", value: postId)
            .single()
            .execute()
        
        struct PostRow: Decodable {
            let id: UUID
            let user_id: UUID
            let text: String
            let image_urls: [String]?
            let video_url: String?
            let audio_url: String?
            let parent_post_id: UUID?
            let leaderboard_entry_id: String?
            let leaderboard_artist_name: String?
            let leaderboard_rank: Int?
            let leaderboard_percentile_label: String?
            let leaderboard_minutes_listened: Int?
            let reshared_post_id: UUID?
            let created_at: String
            let updated_at: String?
            let deleted_at: String?
            let spotify_link_url: String?
            let spotify_link_type: String?
            let spotify_link_data: [String: AnyCodable]?
            let poll_question: String?
            let poll_type: String?
            let poll_options: AnyCodable? // Changed to AnyCodable to handle both array and dictionary
            let background_music_spotify_id: String?
            let background_music_data: [String: AnyCodable]?
            
            enum CodingKeys: String, CodingKey {
                case id, user_id, text, created_at, updated_at, deleted_at
                case image_urls, video_url, audio_url, parent_post_id
                case leaderboard_entry_id, leaderboard_artist_name, leaderboard_rank
                case leaderboard_percentile_label, leaderboard_minutes_listened, reshared_post_id
                case spotify_link_url, spotify_link_type, spotify_link_data
                case poll_question, poll_type, poll_options
                case background_music_spotify_id, background_music_data
            }
            
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                
                // Required fields
                id = try container.decode(UUID.self, forKey: .id)
                user_id = try container.decode(UUID.self, forKey: .user_id)
                text = try container.decode(String.self, forKey: .text)
                created_at = try container.decode(String.self, forKey: .created_at)
                
                // Optional fields
                updated_at = try container.decodeIfPresent(String.self, forKey: .updated_at)
                deleted_at = try container.decodeIfPresent(String.self, forKey: .deleted_at)
                image_urls = try container.decodeIfPresent([String].self, forKey: .image_urls)
                video_url = try container.decodeIfPresent(String.self, forKey: .video_url)
                audio_url = try container.decodeIfPresent(String.self, forKey: .audio_url)
                parent_post_id = try container.decodeIfPresent(UUID.self, forKey: .parent_post_id)
                leaderboard_entry_id = try container.decodeIfPresent(String.self, forKey: .leaderboard_entry_id)
                leaderboard_artist_name = try container.decodeIfPresent(String.self, forKey: .leaderboard_artist_name)
                leaderboard_rank = try container.decodeIfPresent(Int.self, forKey: .leaderboard_rank)
                leaderboard_percentile_label = try container.decodeIfPresent(String.self, forKey: .leaderboard_percentile_label)
                leaderboard_minutes_listened = try container.decodeIfPresent(Int.self, forKey: .leaderboard_minutes_listened)
                reshared_post_id = try container.decodeIfPresent(UUID.self, forKey: .reshared_post_id)
                spotify_link_url = try container.decodeIfPresent(String.self, forKey: .spotify_link_url)
                spotify_link_type = try container.decodeIfPresent(String.self, forKey: .spotify_link_type)
                spotify_link_data = try container.decodeIfPresent([String: AnyCodable].self, forKey: .spotify_link_data)
                poll_question = try container.decodeIfPresent(String.self, forKey: .poll_question)
                poll_type = try container.decodeIfPresent(String.self, forKey: .poll_type)
                background_music_spotify_id = try container.decodeIfPresent(String.self, forKey: .background_music_spotify_id)
                background_music_data = try container.decodeIfPresent([String: AnyCodable].self, forKey: .background_music_data)
                
                // Handle poll_options which can be an array or a dictionary
                if container.contains(.poll_options) {
                    do {
                        if try container.decodeNil(forKey: .poll_options) {
                            poll_options = nil
                        } else {
                            poll_options = try container.decode(AnyCodable.self, forKey: .poll_options)
                        }
                    } catch {
                        print("⚠️ Failed to decode poll_options in createPost: \(error)")
                        poll_options = nil
                    }
                } else {
                    poll_options = nil
                }
            }
        }
        
        let postRow: PostRow
        do {
            postRow = try JSONDecoder().decode(PostRow.self, from: postsResponse.data)
        } catch {
            // Debug: print the actual response
            if let responseString = String(data: postsResponse.data, encoding: .utf8) {
                print("⚠️ Failed to decode PostRow. Response: \(responseString)")
            }
            throw NSError(domain: "FeedService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to decode post data: \(error.localizedDescription)"])
        }
        
        // Get author info
        let currentUser = await social.currentUser()
        let allUsers = await social.allUsers()
        let author = allUsers.first(where: { $0.id == postRow.user_id.uuidString }) ?? UserSummary(
            id: postRow.user_id.uuidString,
            displayName: currentUser.displayName,
            handle: currentUser.handle,
            avatarInitials: currentUser.avatarInitials,
            profilePictureURL: currentUser.profilePictureURL,
            isFollowing: false
        )
        
        // Parse date - handle both string and ISO8601 formats
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let createdAt = formatter.date(from: postRow.created_at) ?? Date()
        
        // Decode Spotify link
        let spotifyLink: SpotifyLink? = {
            guard let url = postRow.spotify_link_url,
                  let type = postRow.spotify_link_type,
                  let data = postRow.spotify_link_data else {
                return nil
            }
            
            let name = (data["name"]?.value as? String) ?? ""
            let artist = data["artist"]?.value as? String
            let owner = data["owner"]?.value as? String
            let imageURLString = data["imageURL"]?.value as? String
            let imageURL = imageURLString.flatMap { URL(string: $0) }
            
            return SpotifyLink(
                id: (data["id"]?.value as? String) ?? "",
                url: url,
                type: type,
                name: name,
                artist: artist,
                owner: owner,
                imageURL: imageURL
            )
        }()
        
        // Decode poll
        let poll: Poll? = decodePoll(
            question: postRow.poll_question,
            typeString: postRow.poll_type,
            optionsData: postRow.poll_options,
            postId: postRow.id.uuidString
        )
        
        // Decode background music
        let backgroundMusic: BackgroundMusic? = {
            guard let spotifyId = postRow.background_music_spotify_id,
                  let data = postRow.background_music_data else {
                return nil
            }
            
            let name = (data["name"]?.value as? String) ?? ""
            let artist = (data["artist"]?.value as? String) ?? ""
            let previewURLString = data["previewURL"]?.value as? String
            let previewURL = previewURLString.flatMap { URL(string: $0) }
            let imageURLString = data["imageURL"]?.value as? String
            let imageURL = imageURLString.flatMap { URL(string: $0) }
            
            return BackgroundMusic(
                spotifyId: spotifyId,
                name: name,
                artist: artist,
                previewURL: previewURL,
                imageURL: imageURL
            )
        }()
        
        // Handle leaderboard entry if present
        let leaderboardEntry: LeaderboardEntrySummary? = {
            guard let entryId = postRow.leaderboard_entry_id,
                  let artistName = postRow.leaderboard_artist_name,
                  let rank = postRow.leaderboard_rank,
                  let percentile = postRow.leaderboard_percentile_label,
                  let minutes = postRow.leaderboard_minutes_listened else {
                return nil
            }
            
            let artistId = extractArtistId(from: entryId)
            
            return LeaderboardEntrySummary(
                id: entryId,
                userId: postRow.user_id.uuidString,
                userDisplayName: author.displayName,
                artistId: artistId,
                artistName: artistName,
                artistImageURL: nil,
                rank: rank,
                percentileLabel: percentile,
                minutesListened: minutes
            )
        }()
        
        // Create Post object
        let imageURLs = (postRow.image_urls ?? []).compactMap { URL(string: $0) }
        let videoURL = postRow.video_url.flatMap { URL(string: $0) }
        let audioURL = postRow.audio_url.flatMap { URL(string: $0) }
        
        let createdReply = Post(
            id: postRow.id.uuidString,
            text: postRow.text,
            createdAt: createdAt,
            author: author,
            imageURLs: imageURLs,
            videoURL: videoURL,
            audioURL: audioURL,
            likeCount: 0,
            replyCount: 0,
            isLiked: false,
            parentPostId: postRow.parent_post_id?.uuidString,
            parentPost: nil,
            leaderboardEntry: nil,
            resharedPostId: nil,
            spotifyLink: spotifyLink,
            poll: poll,
            backgroundMusic: backgroundMusic
        )
        
        // TODO: Update FeedStore when implemented
        // await MainActor.run {
        //     FeedStore.shared.posts.insert(createdReply, at: 0)
        // }
        
        return createdReply
    }
    
    // MARK: - Delete Post
    
    func deletePost(postId: String) async throws {
        let params = DeletePostParams(p_post_id: postId)
        try await supabase
            .rpc("delete_post", params: params)
            .execute()
        
        // TODO: Remove from FeedStore when implemented
        // await MainActor.run {
        //     FeedStore.shared.posts.removeAll { $0.id == postId }
        // }
    }
    
    // MARK: - Toggle Like
    
    func toggleLike(postId: String) async throws -> Bool {
        let params = TogglePostLikeParams(p_post_id: postId)
        
        // Call the RPC function (returns BOOLEAN indicating if liked)
        let response: Bool = try await supabase
            .rpc("toggle_post_like", params: params)
            .single()
            .execute()
            .value
        
        print("✅ Like toggled for post \(postId), now liked: \(response)")
        
        return response
    }
    
    // MARK: - Fetch Post By ID
    
    func fetchPostById(_ postId: String) async throws -> Post {
        print("🔍 Fetching post by ID: \(postId)")
        
        guard let postUUID = UUID(uuidString: postId) else {
            throw NSError(domain: "FeedService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid post ID"])
        }
        
        // Call the get_post_by_id RPC function
        struct GetPostByIdParams: Encodable {
            let p_post_id: UUID
        }
        
        let response = try await supabase
            .rpc("get_post_by_id", params: GetPostByIdParams(p_post_id: postUUID))
            .execute()
        
        // Decode the response using FeedPostRow
        let rows: [FeedPostRow] = try JSONDecoder().decode([FeedPostRow].self, from: response.data)
        
        guard let row = rows.first else {
            throw NSError(domain: "FeedService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Post not found"])
        }
        
        // Parse date
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let createdAt = formatter.date(from: row.created_at) ?? Date()
        
        // Convert FeedPostRow to Post
        let author = UserSummary(
            id: row.user_id.uuidString,
            displayName: row.author_display_name,
            handle: row.author_handle,
            avatarInitials: row.author_avatar_initials,
            profilePictureURL: row.author_profile_picture_url.flatMap { URL(string: $0) },
            isFollowing: false,
            region: nil,
            followersCount: 0,
            followingCount: 0,
            instagramHandle: row.instagram,
            twitterHandle: row.twitter,
            tiktokHandle: row.tiktok
        )
        
        // Parse leaderboard entry if present
        let leaderboardEntry: LeaderboardEntrySummary? = {
            guard let entryId = row.leaderboard_entry_id,
                  let artistName = row.leaderboard_artist_name,
                  let rank = row.leaderboard_rank else {
                return nil
            }
            
            return LeaderboardEntrySummary(
                id: entryId,
                userId: row.user_id.uuidString,
                userDisplayName: row.author_display_name,
                artistId: "", // Not available in this context
                artistName: artistName,
                artistImageURL: nil,
                rank: rank,
                percentileLabel: row.leaderboard_percentile_label ?? "",
                minutesListened: row.leaderboard_minutes_listened ?? 0
            )
        }()
        
        // Parse Spotify link if present
        let spotifyLink: SpotifyLink? = {
            guard let urlString = row.spotify_link_url,
                  let type = row.spotify_link_type else {
                return nil
            }
            
            // Extract name and artist from data if available
            let name = row.spotify_link_data?["name"]?.value as? String ?? ""
            let artist = row.spotify_link_data?["artist"]?.value as? String
            let imageURLString = row.spotify_link_data?["imageURL"]?.value as? String
            let imageURL = imageURLString.flatMap { URL(string: $0) }
            
            return SpotifyLink(
                id: urlString, // Use URL as ID for now
                url: urlString,
                type: type,
                name: name,
                artist: artist,
                owner: nil,
                imageURL: imageURL
            )
        }()
        
        // Parse poll if present
        let poll: Poll? = {
            guard let question = row.poll_question,
                  let type = row.poll_type,
                  let optionsData = row.poll_options else {
                return nil
            }
            
            // Decode poll options from JSONB
            let decoder = JSONDecoder()
            guard let optionsArray = try? decoder.decode([[String: AnyCodable]].self, from: JSONEncoder().encode(optionsData)) else {
                return nil
            }
            
            let options = optionsArray.enumerated().compactMap { (index, dict) -> PollOption? in
                guard let text = dict["text"]?.value as? String else { return nil }
                let voteCount = dict["votes"]?.value as? Int ?? 0
                return PollOption(
                    id: index,
                    text: text,
                    voteCount: voteCount,
                    isSelected: false
                )
            }
            
            return Poll(
                id: row.id.uuidString,
                question: question,
                options: options,
                type: type,
                userVoteIndices: []
            )
        }()
        
        // Parse background music if present
        let backgroundMusic: BackgroundMusic? = {
            guard let spotifyId = row.background_music_spotify_id else {
                return nil
            }
            
            // Extract name and artist from data if available
            let name = row.background_music_data?["name"]?.value as? String ?? ""
            let artist = row.background_music_data?["artist"]?.value as? String ?? ""
            let previewURLString = row.background_music_data?["previewURL"]?.value as? String
            let previewURL = previewURLString.flatMap { URL(string: $0) }
            let imageURLString = row.background_music_data?["imageURL"]?.value as? String
            let imageURL = imageURLString.flatMap { URL(string: $0) }
            
            return BackgroundMusic(
                spotifyId: spotifyId,
                name: name,
                artist: artist,
                previewURL: previewURL,
                imageURL: imageURL
            )
        }()
        
        return Post(
            id: row.id.uuidString,
            text: row.text,
            createdAt: createdAt,
            author: author,
            imageURLs: row.image_urls?.compactMap { URL(string: $0) } ?? [],
            videoURL: row.video_url.flatMap { URL(string: $0) },
            audioURL: row.audio_url.flatMap { URL(string: $0) },
            likeCount: Int(row.like_count),
            replyCount: Int(row.reply_count),
            isLiked: row.is_liked_by_current_user,
            parentPostId: row.parent_post_id?.uuidString,
            parentPost: nil,
            leaderboardEntry: leaderboardEntry,
            resharedPostId: row.reshared_post_id?.uuidString,
            spotifyLink: spotifyLink,
            poll: poll,
            backgroundMusic: backgroundMusic
        )
    }
    
    // MARK: - Fetch Thread
    
    func fetchThread(for postId: String) async throws -> (root: Post, replies: [Post]) {
        // Step 1: Fetch the clicked post directly by ID using fetchPostById
        let clickedPost = try await fetchPostById(postId)
        print("✅ Fetched clicked post: \(clickedPost.id)")
        
        // Step 2: Determine the root post by traversing parent chain
        var currentPost = clickedPost
        var visitedIds = Set<String>()
        
        // Traverse up the parent chain to find the root
        while let parentId = currentPost.parentPostId {
            if visitedIds.contains(parentId) {
                // Circular reference detected - break to avoid infinite loop
                print("⚠️ Circular reference detected in post chain, using current post as root")
                break
            }
            visitedIds.insert(parentId)
            
            // Fetch the parent post
            do {
                currentPost = try await fetchPostById(parentId)
                print("✅ Fetched parent post: \(currentPost.id)")
            } catch {
                print("⚠️ Could not fetch parent \(parentId), using current post as root")
                break
            }
        }
        
        let rootPost = currentPost
        print("✅ Found root post: \(rootPost.id)")
        
        // Step 3: Fetch ALL replies for the root post
        // Use fetchRepliesByUser or a dedicated thread fetch
        let allReplies = try await fetchReplies(for: rootPost.id)
        
        print("✅ Fetched thread: root=\(rootPost.id), total replies=\(allReplies.count)")
        
        return (rootPost, allReplies)
    }
    
    // MARK: - Fetch Replies
    
    func fetchReplies(for postId: String) async throws -> [Post] {
        // Fetch all posts to find the entire reply tree
        let feedResult = try await fetchHomeFeed(feedType: .forYou, region: nil, cursor: nil, limit: 200)
        let allPosts = feedResult.posts
        
        // Build a set of all post IDs that are part of this thread (including nested replies)
        var threadPostIds = Set<String>()
        var postsToCheck = [postId]
        
        // Recursively find all nested replies
        while !postsToCheck.isEmpty {
            let currentId = postsToCheck.removeFirst()
            
            // Find all posts that are direct replies to currentId
            let directReplies = allPosts.filter { $0.parentPostId == currentId }
            for reply in directReplies {
                if !threadPostIds.contains(reply.id) {
                    threadPostIds.insert(reply.id)
                    postsToCheck.append(reply.id) // Check for nested replies
                }
            }
        }
        
        // Return all posts that are part of the thread
        let replies = allPosts.filter { threadPostIds.contains($0.id) }
        print("✅ Found \(replies.count) total replies (including nested) for post \(postId)")
        return replies
    }
    
    // MARK: - Create Leaderboard Comment
    
    func createLeaderboardComment(
        entry: LeaderboardEntrySummary,
        text: String
    ) async throws -> Post {
        return try await createPost(
            text: text,
            imageURLs: [],
            videoURL: nil,
            audioURL: nil,
            leaderboardEntry: entry,
            spotifyLink: nil,
            poll: nil,
            backgroundMusic: nil
        )
    }
    
    // MARK: - Like/Unlike (Legacy)
    
    func likePost(_ postId: String) async throws -> Bool {
        return try await toggleLike(postId: postId)
    }
    
    func unlikePost(_ postId: String) async throws -> Bool {
        return try await toggleLike(postId: postId)
    }
    
    // MARK: - Fetch Posts by User
    
    func fetchPostsByUser(_ userId: String) async throws -> [Post] {
        guard let userIdUUID = UUID(uuidString: userId) else {
            throw NSError(domain: "FeedService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid user ID"])
        }
        
        print("🔍 fetchPostsByUser called for userId: \(userId) (UUID: \(userIdUUID))")
        
        // Query posts directly from database for this user (only posts, not replies)
        let response = try await supabase
            .from("posts")
            .select("""
                id,
                user_id,
                text,
                image_urls,
                video_url,
                audio_url,
                parent_post_id,
                leaderboard_entry_id,
                leaderboard_artist_name,
                leaderboard_rank,
                leaderboard_percentile_label,
                leaderboard_minutes_listened,
                reshared_post_id,
                created_at,
                spotify_link_url,
                spotify_link_type,
                spotify_link_data,
                poll_question,
                poll_type,
                poll_options,
                background_music_spotify_id,
                background_music_data
            """)
            .eq("user_id", value: userIdUUID)
            .is("parent_post_id", value: nil) // Only posts, not replies
            .is("deleted_at", value: nil)
            .order("created_at", ascending: false)
            .limit(1000)
            .execute()
        
        print("🔍 fetchPostsByUser: Database query executed, response data size: \(response.data.count) bytes")
        
        struct PostRow: Decodable {
            let id: UUID
            let user_id: UUID
            let text: String
            let image_urls: [String]?
            let video_url: String?
            let audio_url: String?
            let parent_post_id: UUID?
            let leaderboard_entry_id: String?
            let leaderboard_artist_name: String?
            let leaderboard_rank: Int?
            let leaderboard_percentile_label: String?
            let leaderboard_minutes_listened: Int?
            let reshared_post_id: UUID?
            let created_at: String
            let spotify_link_url: String?
            let spotify_link_type: String?
            let spotify_link_data: [String: AnyCodable]?
            let poll_question: String?
            let poll_type: String?
            let poll_options: AnyCodable? // Changed to AnyCodable to handle both array and dictionary
            let background_music_spotify_id: String?
            let background_music_data: [String: AnyCodable]?
            
            enum CodingKeys: String, CodingKey {
                case id, user_id, text, created_at
                case image_urls, video_url, audio_url, parent_post_id
                case leaderboard_entry_id, leaderboard_artist_name, leaderboard_rank
                case leaderboard_percentile_label, leaderboard_minutes_listened, reshared_post_id
                case spotify_link_url, spotify_link_type, spotify_link_data
                case poll_question, poll_type, poll_options
                case background_music_spotify_id, background_music_data
            }
            
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                
                // Required fields
                id = try container.decode(UUID.self, forKey: .id)
                user_id = try container.decode(UUID.self, forKey: .user_id)
                // text might be NULL in database, provide fallback
                text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
                created_at = try container.decode(String.self, forKey: .created_at)
                
                // Optional fields
                image_urls = try container.decodeIfPresent([String].self, forKey: .image_urls)
                video_url = try container.decodeIfPresent(String.self, forKey: .video_url)
                audio_url = try container.decodeIfPresent(String.self, forKey: .audio_url)
                parent_post_id = try container.decodeIfPresent(UUID.self, forKey: .parent_post_id)
                leaderboard_entry_id = try container.decodeIfPresent(String.self, forKey: .leaderboard_entry_id)
                leaderboard_artist_name = try container.decodeIfPresent(String.self, forKey: .leaderboard_artist_name)
                leaderboard_rank = try container.decodeIfPresent(Int.self, forKey: .leaderboard_rank)
                leaderboard_percentile_label = try container.decodeIfPresent(String.self, forKey: .leaderboard_percentile_label)
                leaderboard_minutes_listened = try container.decodeIfPresent(Int.self, forKey: .leaderboard_minutes_listened)
                reshared_post_id = try container.decodeIfPresent(UUID.self, forKey: .reshared_post_id)
                spotify_link_url = try container.decodeIfPresent(String.self, forKey: .spotify_link_url)
                spotify_link_type = try container.decodeIfPresent(String.self, forKey: .spotify_link_type)
                spotify_link_data = try container.decodeIfPresent([String: AnyCodable].self, forKey: .spotify_link_data)
                poll_question = try container.decodeIfPresent(String.self, forKey: .poll_question)
                poll_type = try container.decodeIfPresent(String.self, forKey: .poll_type)
                background_music_spotify_id = try container.decodeIfPresent(String.self, forKey: .background_music_spotify_id)
                background_music_data = try container.decodeIfPresent([String: AnyCodable].self, forKey: .background_music_data)
                
                // Handle poll_options which can be an array or a dictionary
                if container.contains(.poll_options) {
                    do {
                        if try container.decodeNil(forKey: .poll_options) {
                            poll_options = nil
                        } else {
                            poll_options = try container.decode(AnyCodable.self, forKey: .poll_options)
                        }
                    } catch {
                        print("⚠️ Failed to decode poll_options in fetchPostsByUser: \(error)")
                        poll_options = nil
                    }
                } else {
                    poll_options = nil
                }
            }
        }
        
        var rows: [PostRow]
        do {
            // First, check if response is empty
            if response.data.isEmpty {
                print("⚠️ fetchPostsByUser: Empty response from database")
                return []
            }
            
            // Try to decode
            rows = try JSONDecoder().decode([PostRow].self, from: response.data)
            print("🔍 fetchPostsByUser: Successfully decoded \(rows.count) posts from database")
        } catch let decodingError as DecodingError {
            // More detailed error logging
            print("❌ Decoding error in fetchPostsByUser:")
            switch decodingError {
            case .typeMismatch(let type, let context):
                print("   Type mismatch: expected \(type), path: \(context.codingPath)")
            case .valueNotFound(let type, let context):
                print("   Value not found: \(type), path: \(context.codingPath)")
            case .keyNotFound(let key, let context):
                print("   Key not found: \(key.stringValue), path: \(context.codingPath)")
            case .dataCorrupted(let context):
                print("   Data corrupted: \(context.debugDescription)")
            @unknown default:
                print("   Unknown decoding error: \(decodingError)")
            }
            
            if let responseString = String(data: response.data, encoding: .utf8) {
                print("🔍 Response preview (first 1000 chars): \(responseString.prefix(1000))")
                // Try to parse as JSON to see structure
                if let json = try? JSONSerialization.jsonObject(with: response.data) as? [[String: Any]],
                   let firstItem = json.first {
                    print("🔍 First item keys: \(firstItem.keys.sorted())")
                }
            }
            throw NSError(domain: "FeedService", code: 500, userInfo: [
                NSLocalizedDescriptionKey: "Failed to decode posts: \(decodingError.localizedDescription)"
            ])
        } catch {
            print("❌ Failed to decode PostRow in fetchPostsByUser: \(error)")
            if let responseString = String(data: response.data, encoding: .utf8) {
                print("🔍 Response preview: \(responseString.prefix(500))")
            }
            throw error
        }
        
        print("🔍 fetchPostsByUser: Found \(rows.count) raw posts from database for user \(userId)")
        
        // Note: We already filtered for parent_post_id IS NULL in the query, but let's ensure we only have posts (not replies)
        rows = rows.filter { $0.parent_post_id == nil }
        
        print("🔍 fetchPostsByUser: After filtering, \(rows.count) posts (excluding replies)")
        
        // Get user profile info
        let userProfileResponse = try await supabase
            .from("profiles")
            .select("""
                id,
                display_name,
                first_name,
                last_name,
                username,
                profile_picture_url
            """)
            .eq("id", value: userIdUUID)
            .limit(1)
            .execute()
        
        struct ProfileRow: Decodable {
            let id: UUID
            let display_name: String?
            let first_name: String?
            let last_name: String?
            let username: String?
            let profile_picture_url: String?
            
        }
        
        // Handle case where profile might not exist
        let profile: ProfileRow
        do {
            let profiles: [ProfileRow] = try JSONDecoder().decode([ProfileRow].self, from: userProfileResponse.data)
            if let firstProfile = profiles.first {
                profile = firstProfile
            } else {
                // Profile doesn't exist - decode a minimal JSON structure
                let fallbackJSON = """
                [{"id": "\(userIdUUID.uuidString)", "display_name": null, "first_name": null, "last_name": null, "username": null, "profile_picture_url": null}]
                """.data(using: .utf8)!
                let fallbackProfiles: [ProfileRow] = try JSONDecoder().decode([ProfileRow].self, from: fallbackJSON)
                profile = fallbackProfiles.first!
            }
        } catch {
            print("⚠️ Failed to decode profile for user \(userId): \(error)")
            // Create fallback profile
            let fallbackJSON = """
            [{"id": "\(userIdUUID.uuidString)", "display_name": null, "first_name": null, "last_name": null, "username": null, "profile_picture_url": null}]
            """.data(using: .utf8)!
            let fallbackProfiles: [ProfileRow] = try JSONDecoder().decode([ProfileRow].self, from: fallbackJSON)
            profile = fallbackProfiles.first!
        }
        
        // Get like counts and current user's like status
        let currentUserId = supabase.auth.currentUser?.id.uuidString
        let postIds = rows.map { $0.id.uuidString }
        
        var likeCounts: [String: Int] = [:]
        var userLikes: Set<String> = []
        
        if !postIds.isEmpty {
            // Get like counts
            let likesResponse = try await supabase
                .from("post_likes")
                .select("post_id")
                .in("post_id", values: postIds.map { UUID(uuidString: $0)! })
                .execute()
            
            struct LikeRow: Decodable {
                let post_id: UUID
            }
            
            let likes: [LikeRow] = try JSONDecoder().decode([LikeRow].self, from: likesResponse.data)
            
            for like in likes {
                let postId = like.post_id.uuidString
                likeCounts[postId, default: 0] += 1
            }
            
            // Get current user's likes
            if let currentUserId = currentUserId, let currentUserIdUUID = UUID(uuidString: currentUserId) {
                let userLikesResponse = try await supabase
                    .from("post_likes")
                    .select("post_id")
                    .eq("user_id", value: currentUserIdUUID)
                    .in("post_id", values: postIds.map { UUID(uuidString: $0)! })
                    .execute()
                
                let userLikesData: [LikeRow] = try JSONDecoder().decode([LikeRow].self, from: userLikesResponse.data)
                userLikes = Set(userLikesData.map { $0.post_id.uuidString })
            }
        }
        
        // Get reply counts
        var replyCounts: [String: Int] = [:]
        if !postIds.isEmpty {
            let repliesResponse = try await supabase
                .from("posts")
                .select("parent_post_id")
                .in("parent_post_id", values: postIds.map { UUID(uuidString: $0)! })
                .is("deleted_at", value: nil)
                .execute()
            
            struct ReplyRow: Decodable {
                let parent_post_id: UUID
            }
            
            let replies: [ReplyRow] = try JSONDecoder().decode([ReplyRow].self, from: repliesResponse.data)
            
            for reply in replies {
                let postId = reply.parent_post_id.uuidString
                replyCounts[postId, default: 0] += 1
            }
        }
        
        // Build display name and handle
        let displayName = profile.display_name ??
            (profile.first_name != nil && profile.last_name != nil ?
             "\(profile.first_name!) \(profile.last_name!)" :
             profile.username?.capitalized ?? "User")
        
        let handle = profile.username.map { "@\($0)" } ?? "@user"
        
        let initials: String = {
            if let firstName = profile.first_name, let lastName = profile.last_name {
                return "\(String(firstName.prefix(1)))\(String(lastName.prefix(1)))".uppercased()
            } else if let displayName = profile.display_name {
                return String(displayName.prefix(2)).uppercased()
            } else if let username = profile.username {
                return String(username.prefix(2)).uppercased()
            }
            return "U"
        }()
        
        let pictureURL = profile.profile_picture_url.flatMap { URL(string: $0) }
        
        let author = UserSummary(
            id: userId,
            displayName: displayName,
            handle: handle,
            avatarInitials: initials,
            profilePictureURL: pictureURL,
            isFollowing: false
        )
        
        // Parse dates
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // Convert to Post objects
        let posts = rows.map { row -> Post in
            let imageURLs = (row.image_urls ?? []).compactMap { URL(string: $0) }
            let videoURL = row.video_url.flatMap { URL(string: $0) }
            let audioURL = row.audio_url.flatMap { URL(string: $0) }
            let createdAt = formatter.date(from: row.created_at) ?? Date()
            
            let leaderboardEntry: LeaderboardEntrySummary? = {
                guard let entryId = row.leaderboard_entry_id,
                      let artistName = row.leaderboard_artist_name,
                      let rank = row.leaderboard_rank,
                      let percentile = row.leaderboard_percentile_label,
                      let minutes = row.leaderboard_minutes_listened else {
                    return nil
                }
                
                let artistId = extractArtistId(from: entryId)
                
                return LeaderboardEntrySummary(
                    id: entryId,
                    userId: userId,
                    userDisplayName: displayName,
                    artistId: artistId,
                    artistName: artistName,
                    artistImageURL: nil,
                    rank: rank,
                    percentileLabel: percentile,
                    minutesListened: minutes
                )
            }()
            
            // Decode new fields (same pattern as fetchHomeFeed)
            let spotifyLink: SpotifyLink? = {
                guard let url = row.spotify_link_url,
                      let type = row.spotify_link_type,
                      let data = row.spotify_link_data else {
                    return nil
                }
                
                let name = (data["name"]?.value as? String) ?? ""
                let artist = data["artist"]?.value as? String
                let owner = data["owner"]?.value as? String
                let imageURLString = data["imageURL"]?.value as? String
                let imageURL = imageURLString.flatMap { URL(string: $0) }
                
                return SpotifyLink(
                    id: (data["id"]?.value as? String) ?? "",
                    url: url,
                    type: type,
                    name: name,
                    artist: artist,
                    owner: owner,
                    imageURL: imageURL
                )
            }()
            
            let poll: Poll? = decodePoll(
                question: row.poll_question,
                typeString: row.poll_type,
                optionsData: row.poll_options,
                postId: row.id.uuidString
            )
            
            let backgroundMusic: BackgroundMusic? = {
                guard let spotifyId = row.background_music_spotify_id,
                      let data = row.background_music_data else {
                    return nil
                }
                
                let name = (data["name"]?.value as? String) ?? ""
                let artist = (data["artist"]?.value as? String) ?? ""
                let previewURLString = data["previewURL"]?.value as? String
                let previewURL = previewURLString.flatMap { URL(string: $0) }
                let imageURLString = data["imageURL"]?.value as? String
                let imageURL = imageURLString.flatMap { URL(string: $0) }
                
                return BackgroundMusic(
                    spotifyId: spotifyId,
                    name: name,
                    artist: artist,
                    previewURL: previewURL,
                    imageURL: imageURL
                )
            }()
            
            return Post(
                id: row.id.uuidString,
                text: row.text,
                createdAt: createdAt,
                author: author,
                imageURLs: imageURLs,
                videoURL: videoURL,
                audioURL: audioURL,
                likeCount: likeCounts[row.id.uuidString] ?? 0,
                replyCount: replyCounts[row.id.uuidString] ?? 0,
                isLiked: userLikes.contains(row.id.uuidString),
                parentPostId: nil,
                parentPost: nil,
                leaderboardEntry: leaderboardEntry,
                resharedPostId: row.reshared_post_id?.uuidString,
                spotifyLink: spotifyLink,
                poll: poll,
                backgroundMusic: backgroundMusic
            )
        }
        
        print("✅ fetchPostsByUser: Successfully converted \(posts.count) posts for user \(userId)")
        return posts
    }
    
    // MARK: - Fetch Replies by User
    
    func fetchRepliesByUser(_ userId: String) async throws -> [Post] {
        guard let userIdUUID = UUID(uuidString: userId) else {
            throw NSError(domain: "FeedService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid user ID"])
        }
        
        // Query replies directly from database for this user (only replies, not posts)
        let response = try await supabase
            .from("posts")
            .select("""
                id,
                user_id,
                text,
                image_urls,
                video_url,
                audio_url,
                parent_post_id,
                leaderboard_entry_id,
                leaderboard_artist_name,
                leaderboard_rank,
                leaderboard_percentile_label,
                leaderboard_minutes_listened,
                reshared_post_id,
                created_at,
                spotify_link_url,
                spotify_link_type,
                spotify_link_data,
                poll_question,
                poll_type,
                poll_options,
                background_music_spotify_id,
                background_music_data
            """)
            .eq("user_id", value: userIdUUID)
            .is("deleted_at", value: nil)
            .order("created_at", ascending: false)
            .limit(1000)
            .execute()
        
        struct PostRow: Decodable {
            let id: UUID
            let user_id: UUID
            let text: String
            let image_urls: [String]?
            let video_url: String?
            let audio_url: String?
            let parent_post_id: UUID?
            let leaderboard_entry_id: String?
            let leaderboard_artist_name: String?
            let leaderboard_rank: Int?
            let leaderboard_percentile_label: String?
            let leaderboard_minutes_listened: Int?
            let reshared_post_id: UUID?
            let created_at: String
            let spotify_link_url: String?
            let spotify_link_type: String?
            let spotify_link_data: [String: AnyCodable]?
            let poll_question: String?
            let poll_type: String?
            let poll_options: AnyCodable? // Changed to AnyCodable to handle both array and dictionary
            let background_music_spotify_id: String?
            let background_music_data: [String: AnyCodable]?
            
            enum CodingKeys: String, CodingKey {
                case id, user_id, text, created_at
                case image_urls, video_url, audio_url, parent_post_id
                case leaderboard_entry_id, leaderboard_artist_name, leaderboard_rank
                case leaderboard_percentile_label, leaderboard_minutes_listened, reshared_post_id
                case spotify_link_url, spotify_link_type, spotify_link_data
                case poll_question, poll_type, poll_options
                case background_music_spotify_id, background_music_data
            }
            
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                
                // Required fields
                id = try container.decode(UUID.self, forKey: .id)
                user_id = try container.decode(UUID.self, forKey: .user_id)
                // text might be NULL in database, provide fallback
                text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
                created_at = try container.decode(String.self, forKey: .created_at)
                
                // Optional fields
                image_urls = try container.decodeIfPresent([String].self, forKey: .image_urls)
                video_url = try container.decodeIfPresent(String.self, forKey: .video_url)
                audio_url = try container.decodeIfPresent(String.self, forKey: .audio_url)
                parent_post_id = try container.decodeIfPresent(UUID.self, forKey: .parent_post_id)
                leaderboard_entry_id = try container.decodeIfPresent(String.self, forKey: .leaderboard_entry_id)
                leaderboard_artist_name = try container.decodeIfPresent(String.self, forKey: .leaderboard_artist_name)
                leaderboard_rank = try container.decodeIfPresent(Int.self, forKey: .leaderboard_rank)
                leaderboard_percentile_label = try container.decodeIfPresent(String.self, forKey: .leaderboard_percentile_label)
                leaderboard_minutes_listened = try container.decodeIfPresent(Int.self, forKey: .leaderboard_minutes_listened)
                reshared_post_id = try container.decodeIfPresent(UUID.self, forKey: .reshared_post_id)
                spotify_link_url = try container.decodeIfPresent(String.self, forKey: .spotify_link_url)
                spotify_link_type = try container.decodeIfPresent(String.self, forKey: .spotify_link_type)
                spotify_link_data = try container.decodeIfPresent([String: AnyCodable].self, forKey: .spotify_link_data)
                poll_question = try container.decodeIfPresent(String.self, forKey: .poll_question)
                poll_type = try container.decodeIfPresent(String.self, forKey: .poll_type)
                background_music_spotify_id = try container.decodeIfPresent(String.self, forKey: .background_music_spotify_id)
                background_music_data = try container.decodeIfPresent([String: AnyCodable].self, forKey: .background_music_data)
                
                // Handle poll_options which can be an array or a dictionary
                if container.contains(.poll_options) {
                    do {
                        if try container.decodeNil(forKey: .poll_options) {
                            poll_options = nil
                        } else {
                            poll_options = try container.decode(AnyCodable.self, forKey: .poll_options)
                        }
                    } catch {
                        print("⚠️ Failed to decode poll_options in fetchRepliesByUser: \(error)")
                        poll_options = nil
                    }
                } else {
                    poll_options = nil
                }
            }
        }
        
        var rows: [PostRow]
        do {
            rows = try JSONDecoder().decode([PostRow].self, from: response.data)
            print("🔍 fetchRepliesByUser: Successfully decoded \(rows.count) replies from database")
        } catch {
            print("❌ Failed to decode PostRow in fetchRepliesByUser: \(error)")
            if let responseString = String(data: response.data, encoding: .utf8) {
                print("🔍 Response preview: \(responseString.prefix(500))")
            }
            throw error
        }
        
        // Filter to only replies (parent_post_id IS NOT NULL)
        rows = rows.filter { $0.parent_post_id != nil }
        
        // Get user profile info
        let userProfileResponse = try await supabase
            .from("profiles")
            .select("""
                id,
                display_name,
                first_name,
                last_name,
                username,
                profile_picture_url
            """)
            .eq("id", value: userIdUUID)
            .limit(1)
            .execute()
        
        struct ProfileRow: Decodable {
            let id: UUID
            let display_name: String?
            let first_name: String?
            let last_name: String?
            let username: String?
            let profile_picture_url: String?
            
        }
        
        // Handle case where profile might not exist
        let profile: ProfileRow
        do {
            let profiles: [ProfileRow] = try JSONDecoder().decode([ProfileRow].self, from: userProfileResponse.data)
            if let firstProfile = profiles.first {
                profile = firstProfile
            } else {
                // Profile doesn't exist - decode a minimal JSON structure
                let fallbackJSON = """
                [{"id": "\(userIdUUID.uuidString)", "display_name": null, "first_name": null, "last_name": null, "username": null, "profile_picture_url": null}]
                """.data(using: .utf8)!
                let fallbackProfiles: [ProfileRow] = try JSONDecoder().decode([ProfileRow].self, from: fallbackJSON)
                profile = fallbackProfiles.first!
            }
        } catch {
            print("⚠️ Failed to decode profile for user \(userId): \(error)")
            // Create fallback profile
            let fallbackJSON = """
            [{"id": "\(userIdUUID.uuidString)", "display_name": null, "first_name": null, "last_name": null, "username": null, "profile_picture_url": null}]
            """.data(using: .utf8)!
            let fallbackProfiles: [ProfileRow] = try JSONDecoder().decode([ProfileRow].self, from: fallbackJSON)
            profile = fallbackProfiles.first!
        }
        
        // Get like counts and current user's like status
        let currentUserId = supabase.auth.currentUser?.id.uuidString
        let postIds = rows.map { $0.id.uuidString }
        
        var likeCounts: [String: Int] = [:]
        var userLikes: Set<String> = []
        
        if !postIds.isEmpty {
            // Get like counts
            let likesResponse = try await supabase
                .from("post_likes")
                .select("post_id")
                .in("post_id", values: postIds.map { UUID(uuidString: $0)! })
                .execute()
            
            struct LikeRow: Decodable {
                let post_id: UUID
            }
            
            let likes: [LikeRow] = try JSONDecoder().decode([LikeRow].self, from: likesResponse.data)
            
            for like in likes {
                let postId = like.post_id.uuidString
                likeCounts[postId, default: 0] += 1
            }
            
            // Get current user's likes
            if let currentUserId = currentUserId, let currentUserIdUUID = UUID(uuidString: currentUserId) {
                let userLikesResponse = try await supabase
                    .from("post_likes")
                    .select("post_id")
                    .eq("user_id", value: currentUserIdUUID)
                    .in("post_id", values: postIds.map { UUID(uuidString: $0)! })
                    .execute()
                
                let userLikesData: [LikeRow] = try JSONDecoder().decode([LikeRow].self, from: userLikesResponse.data)
                userLikes = Set(userLikesData.map { $0.post_id.uuidString })
            }
        }
        
        // Build display name and handle
        let displayName = profile.display_name ??
            (profile.first_name != nil && profile.last_name != nil ?
             "\(profile.first_name!) \(profile.last_name!)" :
             profile.username?.capitalized ?? "User")
        
        let handle = profile.username.map { "@\($0)" } ?? "@user"
        
        let initials: String = {
            if let firstName = profile.first_name, let lastName = profile.last_name {
                return "\(String(firstName.prefix(1)))\(String(lastName.prefix(1)))".uppercased()
            } else if let displayName = profile.display_name {
                return String(displayName.prefix(2)).uppercased()
            } else if let username = profile.username {
                return String(username.prefix(2)).uppercased()
            }
            return "U"
        }()
        
        let pictureURL = profile.profile_picture_url.flatMap { URL(string: $0) }
        
        let author = UserSummary(
            id: userId,
            displayName: displayName,
            handle: handle,
            avatarInitials: initials,
            profilePictureURL: pictureURL,
            isFollowing: false
        )
        
        // Parse dates
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // Convert to Post objects
        return rows.map { row -> Post in
            let imageURLs = (row.image_urls ?? []).compactMap { URL(string: $0) }
            let videoURL = row.video_url.flatMap { URL(string: $0) }
            let audioURL = row.audio_url.flatMap { URL(string: $0) }
            let createdAt = formatter.date(from: row.created_at) ?? Date()
            
            let leaderboardEntry: LeaderboardEntrySummary? = {
                guard let entryId = row.leaderboard_entry_id,
                      let artistName = row.leaderboard_artist_name,
                      let rank = row.leaderboard_rank,
                      let percentile = row.leaderboard_percentile_label,
                      let minutes = row.leaderboard_minutes_listened else {
                    return nil
                }
                
                let artistId = extractArtistId(from: entryId)
                
                return LeaderboardEntrySummary(
                    id: entryId,
                    userId: userId,
                    userDisplayName: displayName,
                    artistId: artistId,
                    artistName: artistName,
                    artistImageURL: nil,
                    rank: rank,
                    percentileLabel: percentile,
                    minutesListened: minutes
                )
            }()
            
            // Decode new fields (same pattern as fetchHomeFeed)
            let spotifyLink: SpotifyLink? = {
                guard let url = row.spotify_link_url,
                      let type = row.spotify_link_type,
                      let data = row.spotify_link_data else {
                    return nil
                }
                
                let name = (data["name"]?.value as? String) ?? ""
                let artist = data["artist"]?.value as? String
                let owner = data["owner"]?.value as? String
                let imageURLString = data["imageURL"]?.value as? String
                let imageURL = imageURLString.flatMap { URL(string: $0) }
                
                return SpotifyLink(
                    id: (data["id"]?.value as? String) ?? "",
                    url: url,
                    type: type,
                    name: name,
                    artist: artist,
                    owner: owner,
                    imageURL: imageURL
                )
            }()
            
            let poll: Poll? = decodePoll(
                question: row.poll_question,
                typeString: row.poll_type,
                optionsData: row.poll_options,
                postId: row.id.uuidString
            )
            
            let backgroundMusic: BackgroundMusic? = {
                guard let spotifyId = row.background_music_spotify_id,
                      let data = row.background_music_data else {
                    return nil
                }
                
                let name = (data["name"]?.value as? String) ?? ""
                let artist = (data["artist"]?.value as? String) ?? ""
                let previewURLString = data["previewURL"]?.value as? String
                let previewURL = previewURLString.flatMap { URL(string: $0) }
                let imageURLString = data["imageURL"]?.value as? String
                let imageURL = imageURLString.flatMap { URL(string: $0) }
                
                return BackgroundMusic(
                    spotifyId: spotifyId,
                    name: name,
                    artist: artist,
                    previewURL: previewURL,
                    imageURL: imageURL
                )
            }()
            
            return Post(
                id: row.id.uuidString,
                text: row.text,
                createdAt: createdAt,
                author: author,
                imageURLs: imageURLs,
                videoURL: videoURL,
                audioURL: audioURL,
                likeCount: likeCounts[row.id.uuidString] ?? 0,
                replyCount: 0, // Replies don't have reply counts
                isLiked: userLikes.contains(row.id.uuidString),
                parentPostId: row.parent_post_id?.uuidString,
                parentPost: nil,
                leaderboardEntry: leaderboardEntry,
                resharedPostId: row.reshared_post_id?.uuidString,
                spotifyLink: spotifyLink,
                poll: poll,
                backgroundMusic: backgroundMusic
            )
        }
    }
    
    // MARK: - Fetch Liked Posts by User
    
    func fetchLikedPostsByUser(_ userId: String) async throws -> [Post] {
        // Fetch all posts liked by this user
        let response = try await supabase
            .from("post_likes")
            .select("post_id")
            .eq("user_id", value: userId)
            .execute()
        
        struct LikeRow: Decodable {
            let post_id: UUID
        }
        
        let likes: [LikeRow] = try JSONDecoder().decode([LikeRow].self, from: response.data)
        let likedPostIds = Set(likes.map { $0.post_id.uuidString })
        
        let feedResult = try await fetchHomeFeed(feedType: .forYou, region: nil, cursor: nil, limit: 100)
        return feedResult.posts.filter { likedPostIds.contains($0.id) }
    }
    
    // MARK: - Refresh Current User Profile in Posts
    
    func refreshCurrentUserProfileInPosts() async {
        // This is handled by Supabase queries which always fetch fresh profile data
        // No need to manually refresh
    }
}



