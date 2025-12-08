import SwiftUI

struct OnboardingTextField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .never
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
                    .focused($isFocused)
            } else {
                TextField(placeholder, text: $text)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(autocapitalization)
                    .autocorrectionDisabled()
                    .focused($isFocused)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isFocused ? Color.brandPurple : Color.white.opacity(0.2),
                            lineWidth: isFocused ? 2 : 1
                        )
                )
        )
        .foregroundColor(.white)
        .shadow(color: isFocused ? Color.brandPurple.opacity(0.3) : Color.clear, radius: isFocused ? 8 : 0)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}


