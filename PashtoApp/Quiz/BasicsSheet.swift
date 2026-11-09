import PashtoCore
import SwiftUI

private struct ShownBasicsCard: Identifiable {
    var card: StudyCard
    var id: ItemID { card.itemID }
}

/// One scrolling list of learn cards. Done closes the sheet. A row opens that card.
struct BasicsSheet: View {
    var cards: [StudyCard]

    @Environment(\.dismiss) private var dismiss
    @State private var shown: ShownBasicsCard?
    @ScaledMetric(relativeTo: .title2) private var pronunciationSize: CGFloat = 22
    @ScaledMetric(relativeTo: .body) private var englishSize: CGFloat = 15
    @ScaledMetric(relativeTo: .title3) private var pashtoSize: CGFloat = 20
    @ScaledMetric(relativeTo: .title3) private var pashtoColumn: CGFloat = 108
    @ScaledMetric(relativeTo: .body) private var rowMinHeight: CGFloat = 72

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                        row(card)
                        if index < cards.count - 1 {
                            Rectangle()
                                .fill(Lapis.muted.opacity(0.45))
                                .frame(height: 1)
                                .padding(.leading, 16)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Lapis.background.ignoresSafeArea())
            .navigationTitle(ApprovedBasicsCopy.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Lapis.background.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .fullScreenCover(item: $shown) { shown in
            BasicsReferenceCard(card: shown.card) {
                self.shown = nil
            }
        }
    }

    private func row(_ card: StudyCard) -> some View {
        Button {
            shown = ShownBasicsCard(card: card)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: card.pronunciation)
                        .font(.system(size: pronunciationSize, weight: .bold))
                        .foregroundStyle(StudyPalette.pronunciation)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.layoutDirection, .leftToRight)
                    Text(verbatim: card.meaning)
                        .font(.system(size: englishSize, weight: .regular))
                        .foregroundStyle(StudyPalette.pashto)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.layoutDirection, .leftToRight)
                }
                Text(verbatim: card.pashto)
                    .font(.system(size: pashtoSize, weight: .regular))
                    .foregroundStyle(StudyPalette.pashto)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.layoutDirection, .rightToLeft)
                    .frame(maxWidth: pashtoColumn, alignment: .trailing)
                Image(systemName: "chevron.forward")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Lapis.primary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: rowMinHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: rowLabel(card)))
        .accessibilityAddTraits(.isButton)
    }

    private func rowLabel(_ card: StudyCard) -> String {
        if card.meaning.isEmpty { return card.pronunciation }
        return "\(card.pronunciation). \(card.meaning)"
    }
}

/// One learn card, using the lesson card stack. Done closes it.
///
/// There is no progress bar, no Next, no Start practice, and no Skip.
struct BasicsReferenceCard: View {
    var card: StudyCard
    var onDone: () -> Void

    @AccessibilityFocusState private var pronunciationFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                face
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(StudyPalette.page.ignoresSafeArea())
            .navigationTitle(ApprovedBasicsCopy.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone() }
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
        }
        .background(StudyPalette.page.ignoresSafeArea())
        .onAppear { pronunciationFocused = true }
    }

    private var face: some View {
        StudyCardLines(
            card: card,
            showsMeaning: true,
            pronunciationFocused: $pronunciationFocused
        )
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(StudyPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

enum ApprovedBasicsCopy {
    static var title: String { String(localized: "basics.button") }
}
