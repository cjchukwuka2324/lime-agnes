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
        
        // Use a flow layout for text parts
        HashtagFlowLayout(spacing: 0) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                if part.isHashtag {
                    Text(part.text)
                        .font(font)
                        .fontWeight(.semibold)
                        .foregroundColor(hashtagColor)
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
                        .onTapGesture {
                            // Remove @ from mention for navigation
                            let handle = String(part.text.dropFirst())
                            onMentionTap?(handle)
                        }
                } else {
                    Text(part.text)
                        .font(font)
                        .foregroundColor(textColor)
                }
            }
        }
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
        // Hashtags: # followed by alphanumeric and underscore
        // Mentions: @ followed by alphanumeric and underscore (but not starting with @)
        let pattern = #"(#[a-zA-Z0-9_]+|@[a-zA-Z0-9_]+)"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [TextPart(text: text, isHashtag: false, isMention: false)]
        }
        
        let nsString = text as NSString
        let range = NSRange(location: 0, length: nsString.length)
        var lastEnd = 0
        
        let matches = regex.matches(in: text, options: [], range: range)
        
        for match in matches {
            let matchRange = match.range
            
            // Add text before hashtag/mention
            if matchRange.location > lastEnd {
                let beforeRange = NSRange(location: lastEnd, length: matchRange.location - lastEnd)
                let beforeText = nsString.substring(with: beforeRange)
                if !beforeText.isEmpty {
                    parts.append(TextPart(text: beforeText, isHashtag: false, isMention: false))
                }
            }
            
            // Add hashtag or mention
            let matchedText = nsString.substring(with: matchRange)
            let isHashtag = matchedText.hasPrefix("#")
            let isMention = matchedText.hasPrefix("@")
            parts.append(TextPart(text: matchedText, isHashtag: isHashtag, isMention: isMention))
            
            lastEnd = matchRange.location + matchRange.length
        }
        
        // Add remaining text after last hashtag/mention
        if lastEnd < nsString.length {
            let remainingRange = NSRange(location: lastEnd, length: nsString.length - lastEnd)
            let remainingText = nsString.substring(with: remainingRange)
            if !remainingText.isEmpty {
                parts.append(TextPart(text: remainingText, isHashtag: false, isMention: false))
            }
        }
        
        // If no hashtags/mentions found, return the original text
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
        let maxWidth = proposedWidth.isFinite && proposedWidth > 0 ? proposedWidth : (UIScreen.main.bounds.width - 60)
        let result = FlowResult(
            in: maxWidth,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let availableWidth = bounds.width > 0 ? bounds.width : (UIScreen.main.bounds.width - 60)
        let result = FlowResult(
            in: availableWidth,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                     y: bounds.minY + result.positions[index].y),
                        proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            let effectiveMaxWidth = maxWidth > 0 ? maxWidth : (UIScreen.main.bounds.width - 60)
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                // If adding this subview would exceed width, move to next line
                if x + size.width > effectiveMaxWidth && x > 0 {
                    // Move to next line
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: effectiveMaxWidth, height: y + lineHeight)
        }
    }
}

