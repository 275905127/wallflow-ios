import SwiftUI

struct ManagedSourceRow: View {
    let source: FeedSource
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void
    @State private var confirmingRemoval = false

    private var symbol: String {
        if isSelected { return "checkmark.circle.fill" }
        return source.kind == .json ? "list.bullet" : "shuffle"
    }

    var body: some View {
        HStack {
            Button(action: onSelect) {
                SourceRowLabel(source: source, symbol: symbol)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityValue(isSelected ? Text("当前图源") : Text(""))
            .contextMenu {
                editAction
                Button("删除", systemImage: "trash", role: .destructive, action: confirmRemoval)
            }

            Menu {
                editAction
                Button("删除", systemImage: "trash", role: .destructive, action: confirmRemoval)
            } label: {
                Label("管理 \(source.name)", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .confirmationDialog("删除图源？", isPresented: $confirmingRemoval, titleVisibility: .visible) {
                Button("删除图源", role: .destructive, action: onRemove)
                Button("取消", role: .cancel) { }
            } message: {
                Text("将从「我的图源」中移除“\(source.name)”。")
            }
        }
        .swipeActions(allowsFullSwipe: false) {
            // Don't animate the row away before the user confirms removal.
            Button("删除", systemImage: "trash", action: confirmRemoval)
                .tint(.red)
            editAction
        }
    }

    private var editAction: some View {
        Button("编辑", systemImage: "pencil", action: onEdit)
    }

    private func confirmRemoval() {
        confirmingRemoval = true
    }
}

struct SourceRowLabel: View {
    let source: FeedSource
    let symbol: String

    var body: some View {
        Label {
            VStack(alignment: .leading) {
                Text(source.name)
                Text(source.kind.displayTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol)
        }
    }
}

extension FeedKind {
    var displayTitle: LocalizedStringKey {
        switch self {
        case .json: "JSON 列表"
        case .random: "随机图片"
        }
    }
}
