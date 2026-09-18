import SwiftUI
import Observation
import TasteTraceAPI
import TasteTraceCore
import TasteTraceUI

@Observable
@MainActor
final class WatchlistViewModel {
    var items: [WatchlistItem] = []
    var newIngredient = ""
    var error: String?
    private let env: AppEnvironment
    init(env: AppEnvironment) { self.env = env }

    func load() async {
        do { items = try await env.run { try await env.api.watchlist() }; await env.watchlist.replace(items) } catch let apiError as APIError { error = apiError.message } catch { self.error = error.localizedDescription }
    }

    func add() async {
        let name = newIngredient.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            _ = try await env.run { try await env.api.addToWatchlist(name) }
            newIngredient = ""
            await load()
        } catch let apiError as APIError { error = apiError.message } catch { self.error = error.localizedDescription }
    }

    func remove(_ item: WatchlistItem) async {
        do { try await env.run { try await env.api.removeFromWatchlist(id: item.id) }; await load() } catch let apiError as APIError { error = apiError.message } catch { self.error = error.localizedDescription }
    }
}

struct WatchlistView: View {
    @State private var model: WatchlistViewModel
    init(env: AppEnvironment) { _model = State(initialValue: WatchlistViewModel(env: env)) }

    var body: some View {
        @Bindable var model = model
        TTScreen {
            InfoBanner(emoji: "👀", title: "Sensitivity watchlist", message: "Ingredients here are flagged on the Verify Ingredients step whenever they show up in a meal you're logging.")
            HStack(spacing: 10) {
                TextField("Add an ingredient…", text: $model.newIngredient).font(TTFont.body).onSubmit { Task { await model.add() } }
                Button("Add") { Task { await model.add() } }.font(TTFont.bodySemibold).foregroundStyle(TTColor.primary).buttonStyle(.plain)
            }
            .padding(14)
            .background(TTColor.card, in: RoundedRectangle(cornerRadius: TTRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: TTRadius.card, style: .continuous).stroke(TTColor.cardBorder, lineWidth: 1))
            if model.items.isEmpty {
                Text("Nothing on the watchlist yet. Suspects from the digest can be tracked with one tap.").font(TTFont.body).foregroundStyle(TTColor.textSecondary)
            }
            ForEach(model.items) { item in
                TTCard(padding: 12) {
                    HStack(spacing: 12) {
                        EmojiCircle("🌾", size: 40, tint: TTColor.warningTint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.ingredient.capitalizedFirst).font(TTFont.bodySemibold).foregroundStyle(TTColor.navy)
                            Text("Added from \(item.source)\(item.confidenceMax.map { $0 > 0 ? " • up to \($0)% confidence" : "" } ?? "")").font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
                        }
                        Spacer()
                        Button { Task { await model.remove(item) } } label: { Image(systemName: "trash").foregroundStyle(TTColor.danger) }
                            .buttonStyle(.plain).accessibilityLabel("Remove \(item.ingredient)")
                    }
                }
            }
            ErrorText(model.error)
        }
        .navigationTitle("Watchlist")
        .task { await model.load() }
    }
}
