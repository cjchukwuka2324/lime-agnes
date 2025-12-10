import Foundation

// MARK: - GreenRoom Branding System
//
// This file provides a centralized source of truth for music-native terminology
// used throughout the GreenRoom social feed and user profiles.
//
// ARCHITECTURE SUMMARY:
// - GreenRoom UI: FeedView.swift (main feed), FeedCardView.swift (post cards),
//   PostDetailView.swift (thread view), PostComposerView.swift (composer)
// - Models: Post model (Rockout/Models/Feed/Post.swift) with likeCount, replyCount,
//   resharedPostId fields. Likes/comments/reposts tracked via counts and relationships.
// - Profile Views: ProfileView.swift (own profile), UserProfileDetailView.swift (other users)
// - Notifications: Messages generated in SQL triggers (sql/notification_triggers.sql)
//
// TERMINOLOGY:
// - Bar = Post (noun), "Drop a Bar" = create post (verb)
// - Echo = Repost/Reshare (noun), "Echo this Bar" = repost (verb)
// - Adlib = Reply/Comment (noun), "Adlib" = reply (verb)
// - Amp = Like/Reaction (noun), "Amp" = like (verb)

// MARK: - Core Terminology

struct GreenRoomBranding {
    // MARK: - Bar (Post)
    static let bar = "Bar"
    static let bars = "Bars"
    static let dropBar = "Drop a Bar"
    static let dropBarPlaceholder = "Drop a Bar…"
    static let droppedBar = "dropped a Bar"
    
    // MARK: - Echo (Repost/Reshare)
    static let echo = "Echo"
    static let echoes = "Echoes"
    static let echoBar = "Echo this Bar"
    static let echoed = "Echoed"
    static let echoedBar = "echoed your Bar"
    
    // MARK: - Adlib (Reply/Comment)
    static let adlib = "Adlib"
    static let adlibs = "Adlibs"
    static let adlibVerb = "Adlib"
    static let adlibbed = "Adlibbed"
    static let adlibbedOn = "adlibbed on your Bar"
    static let addAdlib = "Add an adlib…"
    static let addAdlibPlaceholder = "Add an adlib…"
    
    // MARK: - Amp (Like/Reaction)
    static let amp = "Amp"
    static let amps = "Amps"
    static let ampVerb = "Amp"
    static let amped = "Amped"
    static let ampedBar = "amped your Bar"
    
    // MARK: - Activity Text Helpers
    
    struct ActivityText {
        static func userDroppedBar(_ username: String) -> String {
            "\(username) dropped a Bar"
        }
        
        static func userEchoedBar(_ username: String) -> String {
            "\(username) echoed your Bar"
        }
        
        static func userAdlibbed(_ username: String) -> String {
            "\(username) adlibbed on your Bar"
        }
        
        static func userAmped(_ username: String) -> String {
            "\(username) amped your Bar"
        }
        
        static func userMentionedInBar(_ username: String) -> String {
            "\(username) mentioned you in a Bar"
        }
    }
    
    // MARK: - Count Formatting
    
    struct CountFormatter {
        static func bars(_ count: Int) -> String {
            count == 1 ? "\(count) Bar" : "\(count) Bars"
        }
        
        static func echoes(_ count: Int) -> String {
            count == 1 ? "\(count) Echo" : "\(count) Echoes"
        }
        
        static func adlibs(_ count: Int) -> String {
            count == 1 ? "\(count) Adlib" : "\(count) Adlibs"
        }
        
        static func amps(_ count: Int) -> String {
            count == 1 ? "\(count) Amp" : "\(count) Amps"
        }
    }
    
    // MARK: - Empty States
    
    struct EmptyStates {
        static let noBarsYet = "No Bars yet"
        static let noAdlibs = "No adlibs"
        static let noAdlibsYet = "No adlibs yet"
        static let noAmpsYet = "No Amps yet"
        static let noEchoesYet = "No Echoes yet"
        static let noBarsMessage = "This user hasn't dropped any Bars yet."
        static let noAdlibsMessage = "Start adlibbing on posts to see them here!"
        static let noAmpsMessage = "Amp posts to see them here!"
        static let loadingAdlibs = "Loading adlibs..."
        static let beFirstToAdlib = "Be the first to adlib!"
    }
    
    // MARK: - Composer Labels
    
    struct Composer {
        static let newBarTitle = "Drop a Bar"
        static let adlibTitle = "Adlib"
        static let dropButton = "Drop"
        static let adlibButton = "Adlib"
        static let whatOnMind = "Drop a Bar…"
        static let writeReply = "Add an adlib…"
    }
    
    // Convenience properties for direct access (for backward compatibility)
    static let composerTitleNew = Composer.newBarTitle
    static let composerTitleReply = Composer.adlibTitle
    static let composerButtonNew = Composer.dropButton
    static let composerButtonReply = Composer.adlibButton
    static let composerPlaceholderNew = Composer.whatOnMind
    static let composerPlaceholderReply = Composer.writeReply
    
    // MARK: - Section Headers
    
    struct Headers {
        static let adlibs = "Adlibs"
        static let bars = "Bars"
        static let echoes = "Echoes"
        static let amps = "Amps"
    }
    
    // Alias for backward compatibility
    struct SectionHeadings {
        static let adlibs = Headers.adlibs
        static let bars = Headers.bars
        static let echoes = Headers.echoes
        static let amps = Headers.amps
    }
    
    // MARK: - Action Labels
    
    struct Actions {
        static let beFirstToAdlib = "Be the first to adlib!"
        static let deleteBar = "Delete Bar"
        static let deleteBarMessage = "Are you sure you want to delete this Bar? This action cannot be undone."
    }
    
    // Convenience properties for accessibility and actions
    static let ampAction = amp
    static let adlibAction = adlib
    static let echoAction = echo
}

// MARK: - Notification Message Transformation
//
// Note: Notification messages are generated in SQL triggers (sql/notification_triggers.sql).
// The following transformations can be applied client-side for display, but ideally
// the SQL triggers should be updated to generate messages with the new terminology:
//
// - "liked your post" → "amped your Bar"
// - "replied to your post" → "adlibbed on your Bar"
// - "reposted your post" → "echoed your Bar"
// - "posted: ..." → "dropped a Bar: ..."
// - "mentioned you in a post" → "mentioned you in a Bar"

extension String {
    /// Transforms legacy notification messages to use new GreenRoom branding
    func transformedForGreenRoom() -> String {
        var transformed = self
        transformed = transformed.replacingOccurrences(of: "liked your post", with: "amped your Bar")
        transformed = transformed.replacingOccurrences(of: "replied to your post", with: "adlibbed on your Bar")
        transformed = transformed.replacingOccurrences(of: "reposted your post", with: "echoed your Bar")
        transformed = transformed.replacingOccurrences(of: "posted: ", with: "dropped a Bar: ")
        transformed = transformed.replacingOccurrences(of: "mentioned you in a post", with: "mentioned you in a Bar")
        return transformed
    }
}
