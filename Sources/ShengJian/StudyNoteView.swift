import SwiftUI
import ShengJianCore

struct StudyNoteView: View {
    let markdown: String
    var vaultPath: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            ForEach(Array(MarkdownBlocks.parse(markdown).enumerated()), id: \.offset) { _, block in
                render(block)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private func render(_ block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, value):
            inline(value).font(.system(size: level <= 2 ? 20 : 16, weight: .semibold)).padding(.top, level <= 2 ? 12 : 5)
        case let .paragraph(value): inline(value).font(.system(size: 14)).lineSpacing(7)
        case let .quote(value):
            HStack(alignment: .top, spacing: 12) { RoundedRectangle(cornerRadius: 1).fill(.secondary.opacity(0.3)).frame(width: 3); inline(value).font(.system(size: 13)).lineSpacing(6) }.fixedSize(horizontal: false, vertical: true)
        case let .callout(kind, title, value, collapsed):
            StudyCallout(kind: kind, title: title, text: value, initiallyCollapsed: collapsed, vaultPath: vaultPath)
        case let .listItem(marker, value):
            HStack(alignment: .top, spacing: 10) { Text(marker).foregroundStyle(.secondary).frame(minWidth: 14, alignment: .trailing); inline(value).frame(maxWidth: .infinity, alignment: .leading) }.font(.system(size: 14)).lineSpacing(5)
        case let .code(value):
            ScrollView(.horizontal) { Text(value).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).padding(12) }.background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
        case let .table(header, rows):
            ScrollView(.horizontal) {
                Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow { ForEach(Array(header.enumerated()), id: \.offset) { _, cell in tableCell(cell, header: true) } }
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow { ForEach(Array(row.enumerated()), id: \.offset) { _, cell in tableCell(cell, header: false) } }
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).stroke(.primary.opacity(0.10)))
            }
        case .rule: Divider().opacity(0.5)
        }
    }
    private func inline(_ text: String) -> some View {
        let formatted = KnowledgeLinks.previewMarkdown(text, vaultPath: vaultPath)
        return Text((try? AttributedString(markdown: formatted, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(formatted)).textSelection(.enabled)
    }
    private func tableCell(_ text: String, header: Bool) -> some View {
        inline(text).font(.system(size: 12, weight: header ? .semibold : .regular)).lineSpacing(4)
            .padding(10).frame(minWidth: 120, maxWidth: 240, maxHeight: .infinity, alignment: .topLeading)
            .background(.primary.opacity(header ? 0.06 : 0.015)).overlay(Rectangle().stroke(.primary.opacity(0.06), lineWidth: 0.5))
    }
}

private struct StudyCallout: View {
    let kind: String
    let title: String
    let text: String
    let initiallyCollapsed: Bool
    let vaultPath: String?
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if initiallyCollapsed {
                DisclosureGroup(isExpanded: $expanded) { StudyNoteView(markdown: text, vaultPath: vaultPath).padding(.top, 7) } label: { Text(title).font(.system(size: 13, weight: .medium)) }
            } else {
                Text(title.isEmpty ? kind : title).font(.system(size: 12, weight: .semibold))
                StudyNoteView(markdown: text, vaultPath: vaultPath)
            }
        }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(kind.lowercased() == "warning" ? Color.orange.opacity(0.07) : Color.green.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
    }
}
