import SwiftUI

@MainActor
public struct AccountView: View {
    @ObservedObject private var syncService = RedisSyncService.shared
    @State private var email: String = ""
    @State private var isSaved: Bool = false
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Profile Avatar & Intro
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.12))
                            .frame(width: 76, height: 76)
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.red)
                    }
                    
                    VStack(spacing: 4) {
                        Text("Account")
                            .font(.system(size: 22, weight: .bold))
                        Text("Enter your email address to sync your alarms across your devices.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 32)
                
                // Email Card
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email Address")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        TextField("yourname@example.com", text: $email)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 14))
                            .onSubmit {
                                saveEmail()
                            }
                    }
                    
                    HStack(spacing: 12) {
                        Button("Save") {
                            saveEmail()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.regular)
                        
                        if isSaved {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                Text("Saved")
                            }
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.green)
                            .transition(.opacity)
                        }
                        
                        Spacer()
                    }
                }
                .padding(20)
                .frame(maxWidth: 480)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .onAppear {
            self.email = syncService.settings.email
        }
    }
    
    private func saveEmail() {
        let clean = email.trimmingCharacters(in: .whitespaces)
        var settings = syncService.settings
        settings.email = clean
        settings.isEnabled = !clean.isEmpty
        syncService.updateSettings(settings)
        
        withAnimation {
            isSaved = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                isSaved = false
            }
        }
    }
}
