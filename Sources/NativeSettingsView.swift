import SwiftUI

struct NativeSettingsView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let release = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(release) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("关于") {
                    LabeledContent("应用", value: "映壁 · WallFlow")
                    LabeledContent("版本", value: version)
                }
                Section {
                    Label("图源配置仅保存在本机", systemImage: "internaldrive")
                    Label("不需要登录", systemImage: "person.crop.circle")
                } header: {
                    Text("图源与隐私")
                } footer: {
                    Text("浏览时，设备直接向所选图源和图片服务器请求内容。测试时，设备会请求表单中的图源接口。")
                }
                Section {
                    if let url = URL(string: "https://wallhaven.cc/") {
                        Link(destination: url) {
                            Label("Wallhaven 官网", systemImage: "safari")
                        }
                    }
                } header: {
                    Text("图源网站")
                } footer: {
                    Text("应用不内置壁纸，图片权益归原权利人所有。")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }
}
