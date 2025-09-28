//
//  AvatarShopView.swift
//  Scoreline
//
//  Created by Mehul Jasti on 9/28/25.
//

import SwiftUI

// MARK: - Lightweight DTOs used by APIClient calls from this view
// If you already have these in another file, you can delete these definitions.
// Replace the local OwnedAvatarsDTO struct with:
typealias OwnedAvatarsDTO = APIClient.OwnedAvatarsDTO


struct PurchaseAvatarResponse: Decodable {
    let cost: Int
    let newTotalPoints: Int
}

struct AvatarShopView: View {
    // Server data
    @State private var me: MeDTO?
    @State private var owned: Set<String> = []   // avatar_keys like "CatHat", "CatBow", "BaldLeaf" etc.
    @State private var loading = true
    @State private var error: String?

    // UI state
    enum Base: String, CaseIterable { case cat = "Cat", bald = "Bald" }
    @State private var base: Base = .cat
    @State private var selectedItem: ShopItem = ShopCatalog.items.first!

    // Toast
    @State private var toast: (message: String, show: Bool) = ("", false)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.bgTop, Palette.bgBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            if loading {
                ProgressView().tint(Palette.amethyst)
            } else if let err = error {
                VStack(spacing: 10) {
                    Text("Shop unavailable").font(.headline)
                    Text(err).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Retry") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.amethyst)
                }
                .padding()
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        header(stones: me?.totalPoints ?? 0)
                        previewCard
                        catalogSection
                    }
                    .padding(16)
                }
                .navigationTitle("Avatar Shop")
                .navigationBarTitleDisplayMode(.inline)
            }

            if toast.show { ToastView(text: toast.message) }
        }
        .task { await load() }
    }

    // MARK: - Header (stones & base selector)
    private func header(stones: Int) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image("Coins")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                Text("\(stones) stones")
                    .font(.headline)
                    .monospacedDigit()
            }
            Spacer()
            Picker("Base", selection: $base) {
                Text("Cat").tag(Base.cat)
                Text("Bald").tag(Base.bald)
            }
            .pickerStyle(.segmented)
            .tint(Palette.amethyst)
            .frame(maxWidth: 220)
        }
    }

    // MARK: - Preview
    private var composedKey: String {
        // Resulting avatar key is e.g. "CatHat", "CatBow", "BaldLeaf", etc.
        "\(base.rawValue)\(selectedItem.suffix)"
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preview")
                .font(.headline)
                .foregroundStyle(Palette.ink)

            // You have pre-composed images for each combo in Assets:
            // e.g. "CatHat", "CatBow", "CatLeaf", "CatMason", and "BaldHat", ...
            Image(composedKey)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 240)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.95))
                        .shadow(color: Palette.shadow, radius: 6, x: 0, y: 2)
                )

            let hasIt = owned.contains(composedKey)
            let cost = selectedItem.cost
            let stones = me?.totalPoints ?? 0
            let canBuy = !hasIt && stones >= cost

            HStack {
                if hasIt {
                    Label("Owned", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    HStack(spacing: 8) {
                        Image("Coins").resizable().scaledToFit().frame(width: 18, height: 18)
                        Text("\(cost) stones")
                            .font(.subheadline)
                            .foregroundStyle(Palette.inkTertiary)
                    }
                }
                Spacer()
                Button(hasIt ? "Use" : "Purchase") {
                    Task { await buyOrUseCurrent() }
                }
                .buttonStyle(.borderedProminent)
                .tint(hasIt ? Palette.mintSoft : (canBuy ? Palette.amethyst : Palette.roseSoft))
                .disabled(!hasIt && !canBuy)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [Palette.cardTop, Palette.cardBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: Palette.shadow, radius: 6, x: 0, y: 2)
        )
    }

    // MARK: - Catalog
    private var catalogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Items")
                .font(.headline)
                .foregroundStyle(Palette.ink)

            // Two-column grid
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(ShopCatalog.items) { item in
                    ItemCard(
                        item: item,
                        isSelected: item.id == selectedItem.id,
                        select: { selectedItem = item },
                        ownedForCat: owned.contains("Cat\(item.suffix)"),
                        ownedForBald: owned.contains("Bald\(item.suffix)"),
                        cost: item.cost
                    )
                }
            }
        }
    }

    // MARK: - Actions
    private func load() async {
        await MainActor.run {
            loading = true
            error = nil
        }
        do {
            async let meReq: MeDTO = APIClient.shared.getMe()
            async let ownReq: OwnedAvatarsDTO = APIClient.shared.getOwnedAvatars()

            let (meDTO, ownedDTO) = try await (meReq, ownReq)
            await MainActor.run {
                self.me = meDTO
                self.owned = Set(ownedDTO.avatars)
                self.loading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.loading = false
            }
        }
    }

    private func buyOrUseCurrent() async {
        let key = composedKey
        let hasIt = owned.contains(key)

        if hasIt {
            showToast("Equipped \(key)")
            return
        }

        // Attempt purchase
        do {
            // If your API returns PurchaseAvatarResponse, this will decode to it.
            // We intentionally don't mutate `me.totalPoints` here since it's immutable.
            let cost = selectedItem.cost
            _ = try await APIClient.shared.purchaseAvatar(avatarKey: key, cost: cost)

            await MainActor.run {
                // Optimistic local update of ownership for immediate UI feedback
                self.owned.insert(key)
                self.showToast("Purchased \(key)")
            }

            // Refresh from server to update stones and any other profile fields accurately
            await load()
        } catch {
            await MainActor.run {
                self.showToast("Purchase failed")
            }
        }
    }

    private func showToast(_ msg: String) {
        toast = (msg, true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { toast.show = false }
        }
    }
}

// MARK: - Item models

private struct ShopItem: Identifiable, Hashable {
    let id: String
    let name: String
    let suffix: String   // "Hat", "Bow", "Leaf", "Mason"
    let cost: Int        // stones
}

private enum ShopCatalog {
    // Everyone starts owning Hat via server seeding (CatHat, BaldHat)
    static let items: [ShopItem] = [
        .init(id: "hat",   name: "Hat",   suffix: "Hat",   cost: 0),
        .init(id: "bow",   name: "Bow",   suffix: "Bow",   cost: 50),
        .init(id: "leaf",  name: "Leaf",  suffix: "Leaf",  cost: 75),
        .init(id: "mason", name: "Mason", suffix: "Mason", cost: 100),
    ]
}

// MARK: - Item card

private struct ItemCard: View {
    let item: ShopItem
    let isSelected: Bool
    let select: () -> Void
    let ownedForCat: Bool
    let ownedForBald: Bool
    let cost: Int

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(item.name)
                        .font(.subheadline).bold()
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    if ownedForCat || ownedForBald {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    }
                }
                HStack(spacing: 6) {
                    Image("Coins").resizable().scaledToFit().frame(width: 16, height: 16)
                    Text(cost == 0 ? "Free" : "\(cost)")
                        .font(.caption).foregroundStyle(Palette.inkTertiary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Palette.badgeLavender : Color.white.opacity(0.95))
                    .shadow(color: Palette.shadow, radius: 4, x: 0, y: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Toast

private struct ToastView: View {
    let text: String
    var body: some View {
        VStack {
            Spacer()
            Text(text)
                .font(.subheadline).bold()
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.black.opacity(0.8))
                .clipShape(Capsule())
                .padding(.bottom, 24)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.25), value: text)
    }
}
