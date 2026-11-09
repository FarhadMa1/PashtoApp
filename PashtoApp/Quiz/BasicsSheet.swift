import PashtoCore
import SwiftUI
import UIKit

/// The system Done title. It is not an app string.
@MainActor
enum SystemDone {
    static var title: String {
        UIBarButtonItem(systemItem: .done).title ?? ""
    }
}

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
        VStack(spacing: 0) {
            sheetHeader
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

    private var sheetHeader: some View {
        ZStack {
            Text(verbatim: ApprovedBasicsCopy.title)
                .font(.headline.weight(.bold))
                .foregroundStyle(Lapis.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 88)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Spacer(minLength: 0)
                doneButton(ink: Lapis.primary, action: { dismiss() })
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Lapis.muted.opacity(0.55))
                .frame(height: 1)
                .accessibilityHidden(true)
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

    private func doneButton(ink: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: SystemDone.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
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
        VStack(spacing: 0) {
            header
            LapisScreen {
                face
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)
            } footer: {
                Button(action: onDone) {
                    Text(verbatim: SystemDone.title)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(StudyPrimaryButtonStyle())
            }
        }
        .background(StudyPalette.page.ignoresSafeArea())
        .onAppear { pronunciationFocused = true }
    }

    private var header: some View {
        ZStack {
            Text(verbatim: ApprovedBasicsCopy.title)
                .font(.headline.weight(.bold))
                .foregroundStyle(StudyPalette.headerInk)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 88)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Spacer(minLength: 0)
                Button(action: onDone) {
                    Text(verbatim: SystemDone.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(StudyPalette.headerInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(StudyPalette.header.ignoresSafeArea(edges: .top))
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
