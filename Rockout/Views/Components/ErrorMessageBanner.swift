import SwiftUI

enum MessageType {
    case error
    case warning
    case success
    case info
    
    var iconName: String {
        switch self {
        case .error:
            return "exclamationmark.triangle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .info:
            return "info.circle.fill"
        }
    }
    
    var foregroundColor: Color {
        switch self {
        case .error:
            return .red
        case .warning:
            return .orange
        case .success:
            return .green
        case .info:
            return .blue
        }
    }
    
    var backgroundColor: Color {
        switch self {
        case .error:
            return .red.opacity(0.1)
        case .warning:
            return .orange.opacity(0.1)
        case .success:
            return .green.opacity(0.1)
        case .info:
            return .blue.opacity(0.1)
        }
    }
    
    var borderColor: Color {
        switch self {
        case .error:
            return .red.opacity(0.3)
        case .warning:
            return .orange.opacity(0.3)
        case .success:
            return .green.opacity(0.3)
        case .info:
            return .blue.opacity(0.3)
        }
    }
}

struct ErrorMessageBanner: View {
    let message: String
    let type: MessageType
    
    init(_ message: String, type: MessageType = .error) {
        self.message = message
        self.type = type
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: type.iconName)
                .foregroundColor(type.foregroundColor)
                .font(.system(size: 18))
            
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(type.foregroundColor)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(type.backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(type.borderColor, lineWidth: 1)
        )
    }
}

#Preview {
    VStack(spacing: 16) {
        ErrorMessageBanner("This is an error message", type: .error)
        ErrorMessageBanner("This is a warning message", type: .warning)
        ErrorMessageBanner("This is a success message", type: .success)
        ErrorMessageBanner("This is an info message", type: .info)
    }
    .padding()
    .background(Color.black)
}

