import SwiftUI
import Supabase

struct RecallHistoryView: View {
    @StateObject private var viewModel = RecallHistoryViewModel()
    @Environment(\.dismiss) private var dismiss
    let onSelectRecall: (UUID) -> Void
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if viewModel.isLoading && viewModel.recalls.isEmpty {
                    ProgressView()
                        .tint(.white)
                } else if viewModel.recalls.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("No recalls yet")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Text("Start a new recall to see it here")
                            .font(.subheadline)
                            .foregroundColor(.gray.opacity(0.7))
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                    ForEach(viewModel.recalls) { recall in
                        RecallHistoryRow(recall: recall, viewModel: viewModel) {
                            onSelectRecall(recall.id)
                        }
                    }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Recent Recalls")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .searchable(text: $viewModel.searchText, prompt: "Search recalls")
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                await viewModel.loadRecalls()
            }
        }
    }
}

struct RecallHistoryRow: View {
    let recall: RecallHistoryItem
    let onTap: () -> Void
    @State private var isSaved = false
    @ObservedObject var viewModel: RecallHistoryViewModel
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon based on input type
                Image(systemName: iconForInputType(recall.inputType))
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 4) {
                    // Title or query text
                    Text(recall.displayTitle)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    // Subtitle
                    if let subtitle = recall.displaySubtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                    
                    // Status and date
                    HStack(spacing: 8) {
                        StatusBadge(status: recall.status)
                        Text(recall.formattedDate)
                            .font(.caption)
                            .foregroundColor(.gray.opacity(0.7))
                    }
                }
                
                Spacer()
                
                // Save button
                Button(action: {
                    Task {
                        if isSaved {
                            try? await RecallActionsService.shared.unsave(recallId: recall.id)
                        } else {
                            try? await RecallActionsService.shared.save(
                                recallId: recall.id,
                                title: recall.topTitle,
                                artist: recall.topArtist
                            )
                        }
                        isSaved.toggle()
                    }
                }) {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .foregroundColor(isSaved ? Color(hex: "#1ED760") : .gray)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: {
                Task {
                    await viewModel.deleteRecall(recall.id)
                }
            }) {
                Label("Delete", systemImage: "trash")
            }
        }
        .task {
            isSaved = (try? await RecallActionsService.shared.isSaved(recallId: recall.id)) ?? false
        }
    }
    
    private func iconForInputType(_ type: String) -> String {
        switch type {
        case "voice", "background", "hum":
            return "mic.fill"
        case "image":
            return "photo.fill"
        default:
            return "text.bubble.fill"
        }
    }
}

struct StatusBadge: View {
    let status: String
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(status.capitalized)
                .font(.caption)
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.2))
        .cornerRadius(8)
    }
    
    private var statusColor: Color {
        switch status {
        case "done":
            return Color(hex: "#1ED760")
        case "processing", "queued":
            return .yellow
        case "failed":
            return .red
        default:
            return .gray
        }
    }
}

// MARK: - View Model

@MainActor
class RecallHistoryViewModel: ObservableObject {
    @Published var recalls: [RecallHistoryItem] = []
    @Published var isLoading = false
    @Published var searchText = ""
    
    private let supabase = SupabaseService.shared.client
    
    func loadRecalls() async {
        isLoading = true
        defer { isLoading = false }
        
        guard let userId = supabase.auth.currentUser?.id else {
            return
        }
        
        do {
            let response = try await supabase
                .from("recalls")
                .select("*")
                .eq("user_id", value: userId.uuidString)
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let items = try decoder.decode([RecallHistoryItem].self, from: response.data)
            
            recalls = items
        } catch {
            print("Error loading recalls: \(error)")
        }
    }
    
    func refresh() async {
        await loadRecalls()
    }
    
    func deleteRecall(_ id: UUID) async {
        do {
            try await supabase
                .from("recalls")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
            
            recalls.removeAll { $0.id == id }
        } catch {
            print("Error deleting recall: \(error)")
        }
    }
    
    var filteredRecalls: [RecallHistoryItem] {
        if searchText.isEmpty {
            return recalls
        }
        return recalls.filter { recall in
            recall.displayTitle.localizedCaseInsensitiveContains(searchText) ||
            recall.displaySubtitle?.localizedCaseInsensitiveContains(searchText) ?? false
        }
    }
}

// MARK: - Model

struct RecallHistoryItem: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let inputType: String
    let queryText: String?
    let status: String
    let topTitle: String?
    let topArtist: String?
    let topConfidence: Double?
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case inputType = "input_type"
        case queryText = "query_text"
        case status
        case topTitle = "top_title"
        case topArtist = "top_artist"
        case topConfidence = "top_confidence"
        case createdAt = "created_at"
    }
    
    var displayTitle: String {
        if let title = topTitle, let artist = topArtist {
            return "\(title) by \(artist)"
        }
        return queryText ?? "Untitled Recall"
    }
    
    var displaySubtitle: String? {
        if topTitle != nil {
            return queryText
        }
        return nil
    }
    
    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
}

// MARK: - Preview

#Preview {
    RecallHistoryView(onSelectRecall: { _ in })
}

