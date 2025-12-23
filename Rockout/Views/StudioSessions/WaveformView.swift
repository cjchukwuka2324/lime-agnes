import SwiftUI

struct WaveformView: View {
    let waveformData: WaveformData?
    let currentTime: TimeInterval
    let duration: TimeInterval
    let comments: [TrackComment]
    let onTap: (Double) -> Void // Callback with timestamp
    let onCommentTap: (TrackComment) -> Void // Callback when comment marker is tapped
    
    @State private var hoveredComment: TrackComment?
    
    private let barSpacing: CGFloat = 2
    private let minBarHeight: CGFloat = 2
    private let maxBarHeight: CGFloat = 60
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Waveform bars
                if let waveformData = waveformData, !waveformData.samples.isEmpty {
                    HStack(spacing: barSpacing) {
                        ForEach(Array(waveformData.samples.enumerated()), id: \.offset) { index, amplitude in
                            WaveformBar(
                                amplitude: amplitude,
                                index: index,
                                totalSamples: waveformData.samples.count,
                                currentTime: currentTime,
                                duration: duration,
                                maxHeight: maxBarHeight,
                                minHeight: minBarHeight
                            )
                        }
                    }
                    .frame(height: maxBarHeight)
                } else {
                    // Placeholder while loading
                    HStack(spacing: barSpacing) {
                        ForEach(0..<50, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 3, height: 20)
                        }
                    }
                    .frame(height: maxBarHeight)
                }
                
                // Current playback position indicator
                if duration > 0 {
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2)
                        .offset(x: playbackPositionX(geometry: geometry))
                }
                
                // Comment markers
                ForEach(comments) { comment in
                    CommentMarker(
                        comment: comment,
                        position: commentPositionX(comment: comment, geometry: geometry),
                        isHovered: hoveredComment?.id == comment.id,
                        onTap: {
                            onCommentTap(comment)
                        }
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let timestamp = timestampFromX(value.location.x, geometry: geometry)
                        onTap(timestamp)
                    }
            )
            .onTapGesture { location in
                let timestamp = timestampFromX(location.x, geometry: geometry)
                onTap(timestamp)
            }
        }
        .frame(height: maxBarHeight + 30) // Extra space for comment markers
    }
    
    private func playbackPositionX(geometry: GeometryProxy) -> CGFloat {
        guard duration > 0 else { return 0 }
        let progress = currentTime / duration
        return geometry.size.width * CGFloat(progress)
    }
    
    private func commentPositionX(comment: TrackComment, geometry: GeometryProxy) -> CGFloat {
        guard duration > 0 else { return 0 }
        let progress = comment.timestamp / duration
        return geometry.size.width * CGFloat(progress) - 6 // Center the 12px marker (half width)
    }
    
    private func timestampFromX(_ x: CGFloat, geometry: GeometryProxy) -> Double {
        guard duration > 0, geometry.size.width > 0 else { return 0 }
        let progress = max(0, min(1, x / geometry.size.width))
        let timestamp = Double(progress) * duration
        // Round to nearest 0.1 seconds
        return round(timestamp * 10) / 10.0
    }
}

struct WaveformBar: View {
    let amplitude: Float
    let index: Int
    let totalSamples: Int
    let currentTime: TimeInterval
    let duration: TimeInterval
    let maxHeight: CGFloat
    let minHeight: CGFloat
    
    private var barHeight: CGFloat {
        let height = minHeight + (maxHeight - minHeight) * CGFloat(amplitude)
        return max(minHeight, min(maxHeight, height))
    }
    
    private var isPlayed: Bool {
        guard duration > 0 else { return false }
        let sampleProgress = Double(index) / Double(totalSamples)
        let sampleTime = sampleProgress * duration
        return sampleTime <= currentTime
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(isPlayed ? Color(hex: "#1ED760") : Color.white.opacity(0.3))
            .frame(width: 3, height: barHeight)
    }
}

struct CommentMarker: View {
    let comment: TrackComment
    let position: CGFloat
    let isHovered: Bool
    let onTap: () -> Void
    
    private let waveformHeight: CGFloat = 60
    
    var body: some View {
        VStack(spacing: 4) {
            // Comment preview (shown on hover/long-press) - shown above marker
            if isHovered {
                CommentPreview(comment: comment)
                    .transition(.opacity.combined(with: .scale))
                    .offset(y: -8)
            }
            
            // Comment bubble/icon
            Circle()
                .fill(Color.white)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(Color(hex: "#1ED760"), lineWidth: 2)
                        .frame(width: 12, height: 12)
                )
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
        }
        .offset(x: position, y: -waveformHeight / 2 - 10) // Position above waveform
        .onTapGesture {
            onTap()
        }
    }
}

struct CommentPreview: View {
    let comment: TrackComment
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(comment.displayName)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Text(comment.content)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(2)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.8))
        )
        .frame(maxWidth: 150)
    }
}
