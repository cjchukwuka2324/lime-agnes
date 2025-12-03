import SwiftUI

struct PollView: View {
    let postId: String
    @Binding var poll: Poll
    let isOwnPost: Bool
    
    @State private var isVoting = false
    @State private var errorMessage: String?
    
    private let pollVoteService = PollVoteService.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(poll.question)
                .font(.headline)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(poll.options.enumerated()), id: \.element.id) { index, option in
                    pollOptionView(option: option, index: index)
                }
            }
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            if poll.totalVotes > 0 {
                Text("\(poll.totalVotes) vote\(poll.totalVotes == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.top, 4)
            }
            
            if !poll.userVoteIndices.isEmpty {
                Text("Vote submitted • Votes are final")
                    .font(.caption)
                    .foregroundColor(Color(hex: "#1ED760").opacity(0.8))
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .task {
            await loadPollVotes()
        }
        .onAppear {
            // Reload votes when view appears (in case other users voted)
            Task {
                await loadPollVotes()
            }
        }
        .refreshable {
            // Allow pull-to-refresh to reload votes
            await loadPollVotes()
        }
    }
    
    private func pollOptionView(option: PollOption, index: Int) -> some View {
        let isSelected = poll.userVoteIndices.contains(index)
        let percentage = poll.totalVotes > 0 ? Double(option.voteCount) / Double(poll.totalVotes) : 0.0
        let hasVoted = !poll.userVoteIndices.isEmpty
        let isDisabled = isVoting || (isOwnPost && poll.userVoteIndices.isEmpty) || hasVoted
        
        return Button {
            if !hasVoted {
                Task {
                    await voteOnOption(index: index)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    // Selection indicator
                    Group {
                        if poll.type == "single" {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        } else {
                            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        }
                    }
                    .foregroundColor(isSelected ? Color(hex: "#1ED760") : .white.opacity(0.7))
                    
                    Text(option.text)
                        .font(.subheadline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    if poll.totalVotes > 0 {
                        HStack(spacing: 4) {
                            Text("\(option.voteCount)")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.white.opacity(0.9))
                            Text("(\(Int(percentage * 100))%)")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    } else {
                        Text("0")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                
                // Progress bar
                if poll.totalVotes > 0 {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.2))
                                .frame(height: 4)
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isSelected ? Color(hex: "#1ED760") : Color.white.opacity(0.5))
                                .frame(width: geometry.size.width * percentage, height: 4)
                        }
                    }
                    .frame(height: 4)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color(hex: "#1ED760").opacity(0.2) : Color.white.opacity(0.05))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isDisabled)
        .opacity(hasVoted && !isSelected ? 0.6 : 1.0)
    }
    
    private func voteOnOption(index: Int) async {
        // Prevent voting if user has already voted (votes are final)
        guard poll.userVoteIndices.isEmpty else {
            return
        }
        
        isVoting = true
        errorMessage = nil
        defer { isVoting = false }
        
        var newVoteIndices: Set<Int>
        
        if poll.type == "single" {
            // Single choice: select this option
            newVoteIndices = [index]
        } else {
            // Multiple choice: select this option
            newVoteIndices = [index]
        }
        
        do {
            try await pollVoteService.voteOnPoll(postId: postId, optionIndices: Array(newVoteIndices))
            await loadPollVotes()
        } catch {
            errorMessage = "Failed to vote: \(error.localizedDescription)"
        }
    }
    
    private func loadPollVotes() async {
        do {
            print("🔍 Loading poll votes for post \(postId)")
            let voteCounts = try await pollVoteService.getPollVotes(postId: postId)
            let userVotes = try await pollVoteService.getUserVote(postId: postId)
            
            print("🔍 Vote counts: \(voteCounts)")
            print("🔍 User votes: \(userVotes)")
            
            await MainActor.run {
                // Update poll with new vote counts and user votes
                let updatedOptions = poll.options.enumerated().map { (index, option) -> PollOption in
                    let newCount = voteCounts[index] ?? 0
                    if option.voteCount != newCount {
                        print("📊 Updating option \(index) vote count from \(option.voteCount) to \(newCount)")
                    }
                    return PollOption(
                        id: option.id,
                        text: option.text,
                        voteCount: newCount,
                        isSelected: userVotes.contains(index)
                    )
                }
                
                self.poll = Poll(
                    id: poll.id,
                    question: poll.question,
                    options: updatedOptions,
                    type: poll.type,
                    userVoteIndices: Set(userVotes)
                )
                
                print("✅ Poll updated. Total votes: \(self.poll.totalVotes)")
            }
        } catch {
            print("❌ Error loading poll votes: \(error)")
            await MainActor.run {
                errorMessage = "Failed to load votes: \(error.localizedDescription)"
            }
        }
    }
}
