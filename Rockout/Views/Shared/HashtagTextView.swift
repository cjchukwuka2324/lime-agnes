import SwiftUI

/// A view that displays text with clickable hashtags
struct HashtagTextView: View {
    let text: String
    let font: Font
    let textColor: Color
    let hashtagColor: Color
    let onHashtagTap: ((String) -> Void)?
    
    init(
        text: String,
        font: Font = .body,
        textColor: Color = .white.opacity(0.95),
        hashtagColor: Color = Color(hex: "#1ED760"),
        onHashtagTap: ((String) -> Void)? = nil
    ) {
        self.text = text
        self.font = font
        self.textColor = textColor
        self.hashtagColor = hashtagColor
        self.onHashtagTap = onHashtagTap
    }
    
    var body: some View {
        let parts = parseTextWithHashtags(text)
        
        // Use a flow layout for text parts
        FlowLayout(spacing: 0) {
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
    }
    
    private func parseTextWithHashtags(_ text: String) -> [TextPart] {
        var parts: [TextPart] = []
        
        // Regex pattern for hashtags
        let pattern = #"(#[a-zA-Z0-9_]+)"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [TextPart(text: text, isHashtag: false)]
        }
        
        let nsString = text as NSString
        let range = NSRange(location: 0, length: nsString.length)
        var lastEnd = 0
        
        let matches = regex.matches(in: text, options: [], range: range)
        
        for match in matches {
            let matchRange = match.range
            
            // Add text before hashtag
            if matchRange.location > lastEnd {
                let beforeRange = NSRange(location: lastEnd, length: matchRange.location - lastEnd)
                let beforeText = nsString.substring(with: beforeRange)
                if !beforeText.isEmpty {
                    parts.append(TextPart(text: beforeText, isHashtag: false))
                }
            }
            
            // Add hashtag
            let hashtagText = nsString.substring(with: matchRange)
            parts.append(TextPart(text: hashtagText, isHashtag: true))
            
            lastEnd = matchRange.location + matchRange.length
        }
        
        // Add remaining text after last hashtag
        if lastEnd < nsString.length {
            let remainingRange = NSRange(location: lastEnd, length: nsString.length - lastEnd)
            let remainingText = nsString.substring(with: remainingRange)
            if !remainingText.isEmpty {
                parts.append(TextPart(text: remainingText, isHashtag: false))
            }
        }
        
        // If no hashtags found, return the original text
        if parts.isEmpty {
            parts.append(TextPart(text: text, isHashtag: false))
        }
        
        return parts
    }
}

/// A simple flow layout that wraps content naturally like text
struct FlowLayout: Layout {
    var spacing: CGFloat = 0
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
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
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    // Move to next line
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width
            }
            
            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(alignment: .leading, spacing: 20) {
            HashtagTextView(
                text: "Check out my new #songoftheday it's amazing! #music #spotify",
                onHashtagTap: { hashtag in
                    print("Tapped hashtag: \(hashtag)")
                }
            )
            
            HashtagTextView(
                text: "No hashtags here, just regular text."
            )
            
            HashtagTextView(
                text: "#firsthashtag starts the text"
            )
        }
        .padding()
    }
}

