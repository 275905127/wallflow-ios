# 映壁 · WallFlow

原生 SwiftUI 在线壁纸图源浏览器。不打包壁纸，不需要注册账号。首次打开选择「接入图源」，点已适配的网站即可加入「我的图源」。缩略图与原图从所选网站加载，受网站可用性与限流约束。图片权益归原权利人所有。

## 自定义接入

在图源管理中点「添加图源」。支持两类公开 HTTPS GET 接口：

- **JSON 列表**：例如响应 `{"data":{"items":[{"urls":{"full":"https://example.org/a.jpg","small":"https://example.org/t.jpg"}}]}}`，填列表 `data.items`、原图 `urls.full`、缩略图 `urls.small`。顶层数组的列表路径留空；原图字符串数组不需要原图字段。支持相对图片地址。缩略图可省略。
- **随机图片**：接口直接返回图片，或重定向到 HTTPS 图片；点击换图再次请求。不是返回图片地址的 JSON 对象。

已有配置可以侧滑编辑或删除。规则只存本机，不同步；不要把密钥嵌进地址。普通网页不是 JSON 接口，未适配的 HTML 网站不能仅靠粘贴主页接入。

## 构建

XcodeGen，Swift 6 模式，iOS 26.0 起。Actions 锁定 Xcode 27.1 (27A9275) 和 iphoneos27.1 (24A94232)，发布的 IPA 未签名，需自行签名安装。顶栏使用系统 `safeAreaBar` 和 `scrollEdgeEffectStyle(.soft, for: .top)`。
