import SwiftUI

/// A view that displays text with clickable hashtags and @mentions
struct MentionHashtagTextView: View {
    let text: String
    let font: Font
    let textColor: Color
    let hashtagColor: Color
    let mentionColor: Color
    let onHashtagTap: ((String) -> Void)?
    let onMentionTap: ((String) -> Void)?
    
    init(
        text: String,
        font: Font = .body,
        textColor: Color = .white.opacity(0.95),
        hashtagColor: Color = Color(hex: "#1ED760"),
        mentionColor: Color = Color(hex: "#1ED760"),
        onHashtagTap: ((String) -> Void)? = nil,
        onMentionTap: ((String) -> Void)? = nil
    ) {
        self.text = text
        self.font = font
        self.textColor = textColor
        self.hashtagColor = hashtagColor
        self.mentionColor = mentionColor
        self.onHashtagTap = onHashtagTap
        self.onMentionTap = onMentionTap
    }
    
    var body: some View {
        let parts = parseTextWithHashtagsAndMentions(text)
        
        // Use a flow layout for text parts with proper spacing
        HashtagFlowLayout(spacing: 0) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                if part.isHashtag {
                    Text(part.text)
                        .font(font)
                        .fontWeight(.semibold)
                        .foregroundColor(hashtagColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .onTapGesture {
                            // Remove # from hashtag for navigation
                            let hashtag = String(part.text.dropFirst())
                            onHashtagTap?(hashtag)
                        }
                } else if part.isMention {
                    Text(part.text)
                        .font(font)
                        .fontWeight(.semibold)
                        .foregroundColor(mentionColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .contentShape(Rectangle()) // Make entire text area tappable
                        .onTapGesture {
                            // Remove @ from mention for navigation
                            let handle = String(part.text.dropFirst())
                            onMentionTap?(handle)
                        }
                } else {
                    // Regular text - ensure words don't break
                    Text(part.text)
                        .font(font)
                        .foregroundColor(textColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil) // Allow unlimited lines
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private struct TextPart: Identifiable {
        let id = UUID()
        let text: String
        let isHashtag: Bool
        let isMention: Bool
    }
    
    private func parseTextWithHashtagsAndMentions(_ text: String) -> [TextPart] {
        var parts: [TextPart] = []
        
        // Combined regex pattern for hashtags and mentions
        // Hashtags: # followed by alphanumeric and underscore (case-insensitive)
        // Mentions: @ followed by alphanumeric and underscore (allows any case for user input, min 3 chars)
        // Note: Usernames are stored lowercase, but users may type mentions in any case
        let pattern = #"(#[a-zA-Z0-9_]+|@[a-zA-Z0-9_]{3,})"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            // If regex fails, split by words to allow wrapping
            return splitTextIntoWords(text)
        }
        
        let nsString = text as NSString
        let range = NSRange(location: 0, length: nsString.length)
        var lastEnd = 0
        
        let matches = regex.matches(in: text, options: [], range: range)
        
        for match in matches {
            let matchRange = match.range
            
            // Add text before hashtag/mention - split by words for better wrapping
            if matchRange.location > lastEnd {
                let beforeRange = NSRange(location: lastEnd, length: matchRange.location - lastEnd)
                let beforeText = nsString.substring(with: beforeRange)
                if !beforeText.isEmpty {
                    // Split regular text by words to allow proper wrapping
                    let wordParts = splitTextIntoWords(beforeText)
                    parts.append(contentsOf: wordParts)
                }
            }
            
            // Add hashtag or mention
            let matchedText = nsString.substring(with: matchRange)
            let isHashtag = matchedText.hasPrefix("#")
            let isMention = matchedText.hasPrefix("@")
            parts.append(TextPart(text: matchedText, isHashtag: isHashtag, isMention: isMention))
            
            lastEnd = matchRange.location + matchRange.length
        }
        
        // Add remaining text after last hashtag/mention - split by words
        if lastEnd < nsString.length {
            let remainingRange = NSRange(location: lastEnd, length: nsString.length - lastEnd)
            let remainingText = nsString.substring(with: remainingRange)
            if !remainingText.isEmpty {
                let wordParts = splitTextIntoWords(remainingText)
                parts.append(contentsOf: wordParts)
            }
        }
        
        // If no hashtags/mentions found, split the whole text by words
        if parts.isEmpty {
            return splitTextIntoWords(text)
        }
        
        return parts
    }
    
    // Helper function to split text into words for better wrapping
    private func splitTextIntoWords(_ text: String) -> [TextPart] {
        // Split by whitespace but preserve the spaces
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        var parts: [TextPart] = []
        
        for (index, word) in words.enumerated() {
            if !word.isEmpty {
                // Add word
                parts.append(TextPart(text: word, isHashtag: false, isMention: false))
                // Add space after word (except for last word)
                if index < words.count - 1 {
                    parts.append(TextPart(text: " ", isHashtag: false, isMention: false))
                }
            } else if index < words.count - 1 {
                // Preserve multiple spaces/newlines
                parts.append(TextPart(text: " ", isHashtag: false, isMention: false))
            }
        }
        
        // If no words found, return the original text
        if parts.isEmpty {
            parts.append(TextPart(text: text, isHashtag: false, isMention: false))
        }
        
        return parts
    }
}

// Reuse the HashtagFlowLayout from HashtagTextView
private struct HashtagFlowLayout: Layout {
    var spacing: CGFloat = 0
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let proposedWidth = proposal.replacingUnspecifiedDimensions().width
        // If width is unspecified, use a reasonable default (screen width minus padding)
        // Ensure we have a valid width for wrapping
        let maxWidth = proposedWidth.isFinite && proposedWidth > 0 ? proposedWidth : (UIScreen.main.bounds.width - 60)
        let result = FlowResult(
            in: maxWidth,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Use the bounds width, ensuring it's valid and greater than 0
        let availableWidth = bounds.width > 0 ? bounds.width : (proposal.replacingUnspecifiedDimensions().width > 0 ? proposal.replacingUnspecifiedDimensions().width : UIScreen.main.bounds.width - 60)
        let result = FlowResult(
            in: availableWidth,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            let position = result.positions[index]
            // Calculate available width for this subview at its position
            let remainingWidth = availableWidth - position.x
            // Propose the available width so text can wrap
            let proposedWidth = max(remainingWidth, 0)
            subview.place(at: CGPoint(x: bounds.minX + position.x,
                                     y: bounds.minY + position.y),
                        proposal: ProposedViewSize(width: proposedWidth, height: nil))
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            // Ensure we have a valid width - use screen width minus padding as fallback
            let effectiveMaxWidth = maxWidth > 0 ? maxWidth : (UIScreen.main.bounds.width - 60)
            
            for subview in subviews {
                // First, measure the subview with unlimited width to get its natural (unwrapped) size
                // This tells us the minimum width needed for this word/text part
                let naturalSize = subview.sizeThatFits(ProposedViewSize(width: .infinity, height: nil))
                
                // Calculate available width on current line
                let availableWidthOnLine = max(0, effectiveMaxWidth - x)
                
                // CRITICAL: If the natural (unwrapped) size doesn't fit on current line, move to next line
                // This prevents words from being broken in the middle
                // Only move to next line if we're not already at the start (x > 0)
                if naturalSize.width > availableWidthOnLine && x > 0 {
                    // Move to next line - always start at x=0 for left alignment
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                
                // Now measure with the available width on the current line
                // For words, we want to propose at least their natural width to prevent breaking
                let proposedWidth = max(naturalSize.width, max(0, effectiveMaxWidth - x))
                let proposedSize = ProposedViewSize(width: proposedWidth, height: nil)
                let size = subview.sizeThatFits(proposedSize)
                
                // Place on current line - maintain left alignment
                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: effectiveMaxWidth, height: y + lineHeight)
        }
    }
}

