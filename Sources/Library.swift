import SwiftUI

@main struct WallFlowApp: App {
    var body: some Scene { WindowGroup { Gallery() } }
}

@Observable @MainActor final class SourceLibrary {
    private(set) var custom: [FeedSource]
    private var current: UUID?
    var sources: [FeedSource] { custom }
    var selected: FeedSource? { sources.first { $0.id == current } ?? custom.first }
    init() {
        let defaults = UserDefaults.standard
        custom = (defaults.data(forKey: "sources").flatMap { try? JSONDecoder().decode([FeedSource].self, from: $0) }) ?? []
        current = defaults.string(forKey: "current").flatMap { UUID(uuidString: $0) }
    }
    func select(_ s: FeedSource) { current = s.id; UserDefaults.standard.set(s.id.uuidString, forKey: "current") }
    func save(_ s: FeedSource) {
        if let index = custom.firstIndex(where: { $0.id == s.id }) { custom[index] = s } else { custom.append(s) }
        persist(); select(s)
    }
    func remove(_ s: FeedSource) { custom.removeAll { $0.id == s.id }; if current == s.id { current = nil; UserDefaults.standard.removeObject(forKey: "current") }; persist() }
    private func persist() { if let data = try? JSONEncoder().encode(custom) { UserDefaults.standard.set(data, forKey: "sources") } }
}

struct SourceManager: View {
    let library: SourceLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var edit: FeedSource?
    var body: some View {
        NavigationStack {
            List {
                Section("已适配的网站 · 点按接入") {
                    ForEach(SiteCatalog.sources.filter { site in !library.custom.contains { $0.id == site.id } }) { site in
                        Button { library.save(site); dismiss() } label: {
                            Label(site.name, systemImage: "plus.circle")
                        }
                    }
                }
                Section("我的图源") {
                    ForEach(library.custom) { s in
                        row(s).swipeActions(allowsFullSwipe: false) {
                            Button("删除", role: .destructive) { library.remove(s) }
                            Button("编辑") { edit = s }.tint(.blue)
                        }
                    }
                    Button("添加图源", systemImage: "plus") { var s = FeedSource(); s.name = ""; edit = s }
                }
            }.navigationTitle("图源").toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(item: $edit) { s in SourceEditor(draft: s) { source in library.save(source); edit = nil } }
        }
    }
    private func row(_ s: FeedSource) -> some View {
        Button { library.select(s); dismiss() } label: {
            HStack { VStack(alignment: .leading) { Text(s.name); Text(s.kind == .json ? "JSON 列表" : "随机图片").font(.caption).foregroundStyle(.secondary) }; Spacer(); if library.selected?.id == s.id { Image(systemName: "checkmark").accessibilityLabel("已选择") } }
        }.buttonStyle(.plain)
    }
}

private struct SourceEditor: View {
    @State var draft: FeedSource
    let save: (FeedSource) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var testID: UUID?
    @State private var report = ""
    @State private var testing = false
    private var valid: Bool {
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let u = URL(string: draft.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return u.scheme?.lowercased() == "https" && u.host?.isEmpty == false && u.user == nil && u.password == nil
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("图源设置") {
                    TextField("图源名称", text: $draft.name)
                    Picker("类型", selection: $draft.kind) { Text("JSON 列表").tag(FeedKind.json); Text("随机图片").tag(FeedKind.random) }
                    TextField("https:// 图源地址", text: $draft.endpoint).keyboardType(.URL)
                }
                if draft.kind == .json {
                    Section { LabeledContent("列表路径") { TextField("根数组留空", text: $draft.listPath) }; LabeledContent("原图字段") { TextField("url", text: $draft.imagePath) }; LabeledContent("缩略图字段") { TextField("可留空", text: $draft.thumbPath) } }
                    footer: { Text("例如列表在 data.items，图片在每项的 urls.full，就分别填写这两个路径。字符串数组无需原图字段。") }
                } else { Text("接口需直接返回图片，或重定向至 HTTPS 图片地址。") }
                Section { Button(testing ? "测试中…" : "测试图源") { testing = true; report = ""; testID = UUID() }.disabled(!valid || testing)
                    if !report.isEmpty { Text(report).font(.footnote) }
                }
            }.autocorrectionDisabled().textInputAutocapitalization(.never)
            .onChange(of: draft) { testID = nil; testing = false; report = "" }
            .task(id: testID) {
                guard testID != nil else { return }
                do { let rows = try await FeedLoader.load(draft); try Task.checkCancellation(); report = "已解析 \(rows.count) 张图片。" }
                catch { guard !Task.isCancelled else { return }; report = error.localizedDescription }
                testing = false
            }
            .navigationTitle("配置图源").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存并选用") { save(draft) }.disabled(!valid) } }
        }
    }
}
