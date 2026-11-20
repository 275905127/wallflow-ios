import SwiftUI

struct SourceEditor: View {
    private struct TestRun: Sendable {
        let id = UUID()
        let source: FeedSource
        var result: TestResult? = nil
    }

    private enum TestResult: Sendable {
        case loaded(Int)
        case failed(String)
    }

    @Environment(\.dismiss) private var dismiss
    @State private var draft: FeedSource
    @State private var testRun: TestRun?
    private let isNew: Bool
    private let onSave: (FeedSource) -> Void

    init(source: FeedSource, isNew: Bool, onSave: @escaping (FeedSource) -> Void) {
        _draft = State(initialValue: source)
        self.isNew = isNew
        self.onSave = onSave
    }

    private var nameIsEmpty: Bool {
        draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var endpointError: LocalizedStringKey? {
        let address = draft.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if address.isEmpty { return "请输入图源的 HTTPS 接口地址。" }
        guard !address.contains("\\"), let url = URL(string: address),
              url.scheme?.lowercased() == "https", url.host?.isEmpty == false else {
            return "请输入有效的 HTTPS 地址，例如 https://example.org/api。"
        }
        guard url.user == nil, url.password == nil else {
            return "地址不能包含用户名或密码。"
        }
        return nil
    }

    private var canUseDraft: Bool {
        !nameIsEmpty && endpointError == nil
    }

    private var currentTest: TestRun? {
        guard let testRun, testRun.source == draft else { return nil }
        return testRun
    }

    var body: some View {
        let request = currentTest
        NavigationStack {
            Form {
                detailsSection
                if draft.kind == .json {
                    jsonSection
                }
                testingSection
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "添加图源" : "编辑图源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        resetTest()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存并选用") {
                        guard canUseDraft else { return }
                        resetTest()
                        onSave(draft)
                    }
                    .disabled(!canUseDraft)
                }
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .onChange(of: draft) {
            if currentTest == nil { resetTest() }
        }
        .onDisappear(perform: resetTest)
        .task(id: request?.id) {
            if let request, request.result == nil { await runTest(request) }
        }
    }

    private var detailsSection: some View {
        Section {
            TextField("名称（必填）", text: $draft.name)
                .textInputAutocapitalization(.words)
            if nameIsEmpty {
                fieldError(draft.name.isEmpty ? "请输入图源名称。" : "名称不能只有空白。")
            }
            Picker("类型", selection: $draft.kind) {
                ForEach(FeedKind.allCases, id: \.self) { kind in
                    Text(kind.displayTitle).tag(kind)
                }
            }
            TextField("HTTPS 地址（必填）", text: $draft.endpoint)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if let endpointError {
                fieldError(endpointError)
            }
        } header: {
            Text("基本信息")
        } footer: {
            if draft.kind == .random {
                Text("接口应直接返回图片，或重定向到 HTTPS 图片地址。")
            }
        }
    }

    private var jsonSection: some View {
        Section {
            LabeledContent("列表路径") {
                TextField("根数组留空", text: $draft.listPath)
                    .accessibilityLabel("列表路径")
            }
            LabeledContent("原图字段") {
                TextField("例如 url", text: $draft.imagePath)
                    .accessibilityLabel("原图字段")
            }
            LabeledContent("缩略图字段") {
                TextField("可留空", text: $draft.thumbPath)
                    .accessibilityLabel("缩略图字段")
            }
        } header: {
            Text("JSON 字段映射")
        } footer: {
            Text("用点号分隔路径，例如 data.items 或 urls.full。图片地址的字符串数组无需原图字段；未提供缩略图时使用原图。")
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }

    private var testingSection: some View {
        Section {
            let test = currentTest
            if let test, test.result == nil {
                ProgressView("正在测试图源…")
                Button("取消测试", systemImage: "xmark.circle", action: resetTest)
            } else {
                Button("测试图源", systemImage: "network") {
                    guard canUseDraft else { return }
                    testRun = TestRun(source: draft)
                }
                .disabled(!canUseDraft)
            }
            if let result = test?.result {
                switch result {
                case .loaded(0):
                    Label("连接成功，接口没有返回图片", systemImage: "exclamationmark.circle")
                case .loaded(let count):
                    Label("测试成功，已解析 \(count) 张图片", systemImage: "checkmark.circle")
                case .failed(let message):
                    VStack(alignment: .leading) {
                        Label("测试失败", systemImage: "exclamationmark.circle")
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } header: {
            Text("连接测试")
        } footer: {
            Text("测试会请求此接口以检查响应，无需通过测试即可保存。")
        }
    }

    private func fieldError(_ message: LocalizedStringKey) -> some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private func resetTest() {
        testRun = nil
    }

    private func runTest(_ request: TestRun) async {
        guard !Task.isCancelled, currentTest?.id == request.id else { return }
        var completed = request
        do {
            let items = try await FeedLoader.load(request.source)
            completed.result = .loaded(items.count)
        } catch {
            completed.result = .failed(error.localizedDescription)
        }
        // Ignore completions after editing, cancelling or starting another test.
        guard !Task.isCancelled, currentTest?.id == request.id else { return }
        testRun = completed
    }
}
