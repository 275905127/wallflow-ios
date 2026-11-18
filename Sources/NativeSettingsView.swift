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
                Section("图源与隐私") {
                    Text("图源配置保存在本机。浏览时由设备直接向所选图源和图片服务器请求内容。")
                    Text("不内置壁纸，不需要登录。图片权益归原权利人所有。")
                    if let url = URL(string: "https://wallhaven.cc/") {
                        Link("Wallhaven 官网", destination: url)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }
}
