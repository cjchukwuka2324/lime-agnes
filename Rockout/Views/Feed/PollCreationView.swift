import SwiftUI

struct PollCreationView: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding var poll: Poll?
    
    @State private var question = ""
    @State private var pollType: String = "single"
    @State private var options: [String] = ["", ""] // Start with 2 options
    @State private var errorMessage: String?
    
    private let maxOptions = 4
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Poll Question
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Poll Question")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            TextField("Ask a question...", text: $question, axis: .vertical)
                                .textInputAutocapitalization(.sentences)
                                .foregroundColor(.white)
                                .padding()
                                .frame(minHeight: 80)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.15))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                        }
                        
                        // Poll Type Toggle
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Poll Type")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Picker("Type", selection: $pollType) {
                                Text("Single Choice").tag("single")
                                Text("Multiple Choice").tag("multiple")
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        // Options
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Options")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                Spacer()
                                
                                Text("\(options.count)/\(maxOptions)")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            
                            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                                HStack {
                                    TextField("Option \(index + 1)", text: Binding(
                                        get: { option },
                                        set: { newValue in
                                            options[index] = newValue
                                        }
                                    ))
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white.opacity(0.15))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                    )
                                    
                                    if options.count > 2 {
                                        Button {
                                            options.remove(at: index)
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .foregroundColor(.red)
                                                .font(.title3)
                                        }
                                    }
                                }
                            }
                            
                            if options.count < maxOptions {
                                Button {
                                    options.append("")
                                } label: {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                        Text("Add Option")
                                    }
                                    .font(.subheadline)
                                    .foregroundColor(Color(hex: "#1ED760"))
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white.opacity(0.1))
                                    )
                                }
                            }
                        }
                        
                        // Error Message
                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.horizontal)
                        }
                        
                        // Preview
                        if canCreatePoll {
                            pollPreview
                        }
                        
                        Spacer()
                    }
                    .padding()
                }
            }
            .navigationTitle("Create Poll")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        createPoll()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(canCreatePoll ? .white : .gray)
                    .disabled(!canCreatePoll)
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
    
    private var canCreatePoll: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        options.count >= 2 &&
        options.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    
    private var pollPreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preview")
                .font(.headline)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 12) {
                Text(question)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    HStack {
                        if pollType == "single" {
                            Image(systemName: "circle")
                                .foregroundColor(.white.opacity(0.7))
                        } else {
                            Image(systemName: "square")
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
                        Text(option)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.1))
                    )
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
        }
    }
    
    private func createPoll() {
        errorMessage = nil
        
        guard canCreatePoll else {
            errorMessage = "Please fill in the question and all options"
            return
        }
        
        let pollOptions = options.enumerated().map { index, text in
            PollOption(id: index, text: text.trimmingCharacters(in: .whitespacesAndNewlines), voteCount: 0)
        }
        
        let poll = Poll(
            id: UUID().uuidString, // Temporary ID, will be replaced with post ID
            question: question.trimmingCharacters(in: .whitespacesAndNewlines),
            options: pollOptions,
            type: pollType
        )
        
        self.poll = poll
        dismiss()
    }
}
