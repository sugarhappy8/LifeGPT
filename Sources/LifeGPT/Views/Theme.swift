import SwiftUI

extension Color {
    static let lifeAccent = Color(red: 0.23, green: 0.40, blue: 0.35)
    static let lifePaper = Color(nsColor: NSColor(name: "LifePaper") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.12, green: 0.13, blue: 0.13, alpha: 1)
            : NSColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1)
    })
    static let lifeInk = Color.primary
}

struct LifeMark: View {
    var size: CGFloat = 42
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26).fill(Color.lifeAccent)
            Image(systemName: "book.pages").font(.system(size: size * 0.53, weight: .light)).foregroundStyle(.white)
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View { Text(text.uppercased()).font(.system(size: 10, weight: .semibold, design: .rounded)).tracking(1.6).foregroundStyle(.secondary) }
}

struct EmptyNote: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 20)
    }
}

struct NoticeBar: View {
    let text: String
    var isError = false
    var dismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isError ? "exclamationmark.circle" : "info.circle").foregroundStyle(isError ? Color.orange : Color.lifeAccent)
            Text(text).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss notice")
        }.padding(12).background(.quaternary.opacity(0.35)).clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

extension Int {
    var grouped: String { formatted(.number) }
}
