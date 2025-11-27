import SwiftUI
import AuthenticationServices

struct ConnectSpotifyView: View {
    @EnvironmentObject var authService: SpotifyAuthService
    @State private var showAuthSession = false
    @State private var isIngesting = false
    @State private var ingestionError: String?
    
    var body: some View {
        VStack(spacing: 40) {
            Text("Connect your Spotify account")
                .font(.title)
                .bold()
            
            Text("Connect your Spotify account to access RockList features, see your listening stats, and discover your top artists.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button {
                if authService.startAuthorization() != nil {
                    // Use ASWebAuthenticationSession for better UX
                    showAuthSession = true
                }
            } label: {
                HStack {
                    Image(systemName: "music.note")
                    Text("Connect to Spotify")
                }
                .bold()
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(!authService.isAuthorized() == false && authService.accessToken != nil)
            
            if authService.isAuthorized() {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Spotify Connected")
                            .foregroundColor(.secondary)
                    }
                    .font(.subheadline)
                    
                    // Manual trigger button for testing/retry
                    Button {
                        Task {
                            isIngesting = true
                            ingestionError = nil
                            do {
                                try await RockListDataService.shared.performInitialBootstrapIngestion()
                                print("✅ Manual ingestion completed")
                            } catch {
                                ingestionError = error.localizedDescription
                                print("❌ Manual ingestion failed: \(error.localizedDescription)")
                            }
                            isIngesting = false
                        }
                    } label: {
                        HStack {
                            if isIngesting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text(isIngesting ? "Ingesting..." : "Sync RockList Data")
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .disabled(isIngesting)
                    
                    if let error = ingestionError {
                        Text("Error: \(error)")
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
        .padding()
        .sheet(isPresented: $showAuthSession) {
            if let url = authService.startAuthorization() {
                SpotifyAuthWebView(url: url)
            }
        }
    }
}

// Web authentication view for Spotify OAuth
struct SpotifyAuthWebView: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> ASWebAuthenticationSessionViewController {
        ASWebAuthenticationSessionViewController(url: url)
    }
    
    func updateUIViewController(_ uiViewController: ASWebAuthenticationSessionViewController, context: Context) {}
}

class ASWebAuthenticationSessionViewController: UIViewController {
    private var session: ASWebAuthenticationSession?
    private let url: URL
    
    init(url: URL) {
        self.url = url
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "rockout"
        ) { [weak self] callbackURL, error in
            DispatchQueue.main.async {
                self?.dismiss(animated: true) {
                    if let callbackURL = callbackURL {
                        Task {
                            do {
                                try await SpotifyAuthService.shared.handleRedirect(callbackURL)
                                
                                // After successful authentication, trigger initial bootstrap ingestion
                                if SpotifyAuthService.shared.isAuthorized() {
                                    let dataService = RockListDataService.shared
                                    do {
                                        try await dataService.performInitialBootstrapIngestion()
                                        print("✅ Initial RockList ingestion completed")
                                    } catch {
                                        print("⚠️ RockList ingestion error: \(error.localizedDescription)")
                                        // Don't block the UI - ingestion can happen in background
                                    }
                                }
                            } catch {
                                print("Spotify auth error: \(error.localizedDescription)")
                            }
                        }
                    }
                }
            }
        }
        
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        
        self.session = session
        session.start()
    }
}

extension ASWebAuthenticationSessionViewController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return view.window!
    }
}
