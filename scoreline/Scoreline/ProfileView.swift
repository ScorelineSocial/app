import SwiftUI

struct ProfileView: View {
    @State private var me: MeDTO?
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Name
                Group {
                    if loading {
                        ProgressView().padding(.top, 24)
                    } else if let err = error {
                        VStack(spacing: 8) {
                            Text("Couldn’t load profile")
                                .font(.headline)
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Retry") { Task { await loadMe() } }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(.top, 16)
                    } else if let name = me?.name, !name.isEmpty {
                        Text(name)
                            .font(.title)
                            .bold()
                            .foregroundColor(.primary)
                            .padding(.top, 16)
                    } else {
                        Text("Unnamed Hero")
                            .font(.title)
                            .bold()
                            .foregroundColor(.secondary)
                            .padding(.top, 16)
                    }
                }

                // Coins / total points
                HStack(spacing: 10) {
                    Image("Coins")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)
                    Text("\(me?.totalPoints ?? 0) stones")
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundColor(.primary)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Total stones")
                .accessibilityValue("\(me?.totalPoints ?? 0)")

                // Avatar (default = Normal cat)
                Image("CatNormal")
                    .resizable()
                    .scaledToFit()
                    .shadow(radius: 6)

                Spacer(minLength: 20)
                
                // Inside VStack in ProfileView, below the avatar:

                NavigationLink {
                    AvatarShopView()
                } label: {
                    HStack {
                        Image(systemName: "bag.fill")
                        Text("Open Shop")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.95))
                            .shadow(radius: 4, x: 0, y: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadMe() }
    }

    private func loadMe() async {
        await MainActor.run {
            loading = true
            error = nil
        }
        do {
            let dto: MeDTO = try await APIClient.shared.getMe()
            await MainActor.run {
                self.me = dto
                self.loading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.loading = false
            }
        }
    }
}
