import SwiftUI

public struct RecallResultsView: View {
    let recallId: UUID
    
    public init(recallId: UUID) {
        self.recallId = recallId
    }
    
    @StateObject private var service = RecallService.shared
    @State private var recallEvent: RecallEvent?
    @State private var candidates: [RecallCandidate] = []
    @State private var crowdPostId: UUID?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isConfirming = false
    @State private var isPostingToGreenRoom = false
    @State private var showSources = false
    @State private var selectedCandidate: RecallCandidate?
    
    private let pollInterval: TimeInterval = 2.0
    private var pollTimer: Timer?
    
    public var body: some View {
        ZStack {
            // Background
            AnimatedGradientBackground()
                .ignoresSafeArea()
            
            if isLoading && recallEvent == nil {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if let event = recallEvent {
                ScrollView {
                    VStack(spacing: 24) {
                        // Status header
                        statusHeader(event)
                        
                        // Content based on status
                        switch event.status {
                        case .queued, .processing:
                            processingView
                        case .done:
                            if candidates.isEmpty {
                                emptyResultsView
                            } else {
                                candidatesView
                            }
                        case .needsCrowd:
                            needsCrowdView(event)
                        case .failed:
                            failedView(event)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Recall Results")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .onAppear {
            Task {
                await loadData()
                startPolling()
            }
        }
        .onDisappear {
            stopPolling()
        }
        .sheet(isPresented: $showSources) {
            if let candidate = selectedCandidate {
                SourcesView(candidate: candidate)
            }
        }
    }
    
    // MARK: - Status Header
    
    @ViewBuilder
    private func statusHeader(_ event: RecallEvent) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: statusIcon(event.status))
                    .foregroundColor(statusColor(event.status))
                Text(statusText(event.status))
                    .font(.headline)
                    .foregroundColor(.white)
            }
            
            if let confidence = event.confidence, event.status == .done {
                Text("\(Int(confidence * 100))% confidence")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.1))
        )
    }
    
    // MARK: - Processing View
    
    private var processingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
            
            Text("Searching the web...")
                .font(.title3)
                .foregroundColor(.white)
            
            Text("Finding your song using AI")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.1))
        )
    }
    
    // MARK: - Candidates View
    
    private var candidatesView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Found \(candidates.count) candidate\(candidates.count == 1 ? "" : "s")")
                .font(.title2.bold())
                .foregroundColor(.white)
            
            ForEach(candidates) { candidate in
                CandidateCard(
                    candidate: candidate,
                    onConfirm: {
                        Task {
                            await confirmCandidate(candidate)
                        }
                    },
                    onPostToGreenRoom: {
                        Task {
                            await postToGreenRoom(candidate)
                        }
                    },
                    onShowSources: {
                        selectedCandidate = candidate
                        showSources = true
                    }
                )
            }
        }
    }
    
    // MARK: - Needs Crowd View
    
    @ViewBuilder
    private func needsCrowdView(_ event: RecallEvent) -> some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)
                
                Text("We couldn't confirm a strong match")
                    .font(.title3.bold())
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text("We've asked the GreenRoom community for help")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.1))
            )
            
            if let postId = crowdPostId {
                Button {
                    // Navigate to post
                    NotificationCenter.default.post(
                        name: .navigateToPost,
                        object: nil,
                        userInfo: ["post_id": postId.uuidString]
                    )
                } label: {
                    HStack {
                        Image(systemName: "house.fill")
                        Text("View in GreenRoom")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(hex: "#1ED760"))
                    )
                }
            }
            
            // Show candidates anyway
            if !candidates.isEmpty {
                candidatesView
            }
        }
    }
    
    // MARK: - Failed View
    
    @ViewBuilder
    private func failedView(_ event: RecallEvent) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)
            
            Text("Failed to process recall")
                .font(.title3.bold())
                .foregroundColor(.white)
            
            if let error = event.errorMessage {
                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            
            Button {
                Task {
                    await retryProcessing()
                }
            } label: {
                Text("Retry")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(hex: "#1ED760"))
                    )
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.1))
        )
    }
    
    // MARK: - Empty Results View
    
    private var emptyResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.5))
            Text("No matches found")
                .font(.title3)
                .foregroundColor(.white)
        }
        .padding(40)
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
            Text("Loading...")
                .foregroundColor(.white)
        }
    }
    
    // MARK: - Error View
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)
            Text("Error")
                .font(.title3.bold())
                .foregroundColor(.white)
            Text(error)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    // MARK: - Helper Functions
    
    private func statusText(_ status: RecallStatus) -> String {
        switch status {
        case .queued: return "Queued"
        case .processing: return "Processing..."
        case .done: return "Done"
        case .needsCrowd: return "Needs Help"
        case .failed: return "Failed"
        }
    }
    
    private func statusIcon(_ status: RecallStatus) -> String {
        switch status {
        case .queued: return "clock"
        case .processing: return "hourglass"
        case .done: return "checkmark.circle.fill"
        case .needsCrowd: return "person.2.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
    
    private func statusColor(_ status: RecallStatus) -> Color {
        switch status {
        case .queued, .processing: return .white.opacity(0.6)
        case .done: return Color(hex: "#1ED760")
        case .needsCrowd: return .orange
        case .failed: return .red
        }
    }
    
    // MARK: - Data Loading
    
    private func loadData() async {
        do {
            recallEvent = try await service.fetchRecall(recallId: recallId)
            candidates = try await service.fetchCandidates(recallId: recallId)
            
            // Load crowd post if status is needs_crowd
            if recallEvent?.status == .needsCrowd {
                crowdPostId = try? await service.fetchCrowdPost(recallId: recallId)
            }
            
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
    // MARK: - Polling
    
    private func startPolling() {
        // Poll every 2 seconds while processing
        Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { timer in
            guard let event = recallEvent else {
                timer.invalidate()
                return
            }
            
            // Stop polling if done or failed
            if event.status == .done || event.status == .failed {
                timer.invalidate()
                return
            }
            
            Task {
                await loadData()
            }
        }
    }
    
    private func stopPolling() {
        // Timer will invalidate itself when status changes
    }
    
    // MARK: - Actions
    
    private func confirmCandidate(_ candidate: RecallCandidate) async {
        isConfirming = true
        defer { isConfirming = false }
        
        do {
            try await service.confirmRecall(
                recallId: recallId,
                title: candidate.title,
                artist: candidate.artist
            )
            
            // Reload data
            await loadData()
        } catch {
            errorMessage = "Failed to confirm: \(error.localizedDescription)"
        }
    }
    
    private func postToGreenRoom(_ candidate: RecallCandidate) async {
        isPostingToGreenRoom = true
        defer { isPostingToGreenRoom = false }
        
        // Use existing FeedService to create post
        let feedService = SupabaseFeedService.shared
        let postText = "🎵 Found this song: \"\(candidate.title)\" by \(candidate.artist)\n\n[Recall: Identified via AI search]"
        
        do {
            let post = try await feedService.createPost(
                text: postText,
                imageURLs: [],
                videoURL: nil,
                audioURL: nil,
                leaderboardEntry: nil,
                spotifyLink: nil,
                poll: nil,
                backgroundMusic: nil,
                mentionedUserIds: []
            )
            
            // Navigate to the post
            NotificationCenter.default.post(
                name: .navigateToFeed,
                object: nil
            )
            NotificationCenter.default.post(
                name: .navigateToPost,
                object: nil,
                userInfo: ["post_id": post.id]
            )
        } catch {
            errorMessage = "Failed to post: \(error.localizedDescription)"
        }
    }
    
    private func retryProcessing() async {
        do {
            try await service.processRecall(recallId: recallId)
            await loadData()
            startPolling()
        } catch {
            errorMessage = "Failed to retry: \(error.localizedDescription)"
        }
    }
}

// MARK: - Candidate Card

struct CandidateCard: View {
    let candidate: RecallCandidate
    let onConfirm: () -> Void
    let onPostToGreenRoom: () -> Void
    let onShowSources: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title and Artist
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.title)
                    .font(.title3.bold())
                    .foregroundColor(.white)
                
                Text(candidate.artist)
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.8))
            }
            
            // Confidence
            HStack {
                Text("\(Int(candidate.confidence * 100))% match")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                
                Spacer()
                
                // Confidence bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 8)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(confidenceColor)
                            .frame(width: geometry.size.width * CGFloat(candidate.confidence), height: 8)
                    }
                }
                .frame(height: 8)
                .frame(width: 100)
            }
            
            // Reason
            if let reason = candidate.reason {
                Text(reason)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            // Highlight snippet
            if let snippet = candidate.highlightSnippet {
                Text("\"\(snippet)\"")
                    .font(.caption.italic())
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.1))
                    )
            }
            
            // Actions
            HStack(spacing: 12) {
                Button {
                    onShowSources()
                } label: {
                    HStack {
                        Image(systemName: "link")
                        Text("Sources")
                    }
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.15))
                    )
                }
                
                Spacer()
                
                Button {
                    onPostToGreenRoom()
                } label: {
                    HStack {
                        Image(systemName: "house.fill")
                        Text("Post")
                    }
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.15))
                    )
                }
                
                Button {
                    onConfirm()
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Confirm")
                    }
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: "#1ED760"))
                    )
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.1))
        )
    }
    
    private var confidenceColor: Color {
        if candidate.confidence >= 0.8 {
            return Color(hex: "#1ED760")
        } else if candidate.confidence >= 0.6 {
            return .orange
        } else {
            return .yellow
        }
    }
}

// MARK: - Sources View

struct SourcesView: View {
    let candidate: RecallCandidate
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if candidate.sourceUrls.isEmpty {
                            Text("No sources available")
                                .foregroundColor(.white.opacity(0.7))
                                .padding()
                        } else {
                            ForEach(candidate.sourceUrls, id: \.self) { urlString in
                                if let url = URL(string: urlString) {
                                    Link(destination: url) {
                                        HStack {
                                            Image(systemName: "link")
                                            Text(urlString)
                                                .lineLimit(1)
                                            Spacer()
                                            Image(systemName: "arrow.up.right.square")
                                        }
                                        .foregroundColor(.white)
                                        .padding()
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.white.opacity(0.1))
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
}

