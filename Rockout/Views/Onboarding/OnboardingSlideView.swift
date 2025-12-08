import SwiftUI

struct OnboardingSlideView<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Text(title)
                .font(.system(size: 38, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .minimumScaleFactor(0.7)
                .lineLimit(2)
                .tracking(1.5)
            
            Text(subtitle)
                .font(.title3)
                .foregroundColor(Color.brandLightGray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
                .lineLimit(3)
            
            Spacer()
            
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Spacer()
        }
        .padding(.vertical, 40)
    }
}

