# 弹来弹去 Windows

Windows 10/11 x64 原生版本，使用 .NET 8 + WPF。安装包为自包含发布，不要求用户预装 .NET Runtime。

## 功能

- 支持 Bilibili BV / av / 分 P / b23.tv 短链
- 透明置顶弹幕层、鼠标穿透、拖动与缩放
- 独立播放时钟、进度条跳转、±1 秒/±5 秒微调、5 秒倒计时同步
- 字号、透明度、滚动时长、显示区域、弹幕密度设置
- 关键词、正则、顶部/底部/彩色/重复弹幕屏蔽
- 本地 XML 导入，XML / ASS / JSON 导出
- 0.1–4 倍速、24 小时弹幕缓存、系统托盘与关闭到托盘
- 自动保存设置、最近观看和每个视频的同步进度
- 全局快捷键：`Ctrl+Shift+Space`、方向键、`0`、`H`

数据与缓存保存在 `%LOCALAPPDATA%\DanLaiDanQu\`。

## 本地构建

要求 Windows 10/11 与 .NET 8 SDK：

```powershell
dotnet run --project Windows/tests/DanLaiDanQu.Core.SmokeTests -c Release
dotnet publish Windows/src/DanLaiDanQu.Windows/DanLaiDanQu.Windows.csproj `
  -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true `
  -p:IncludeNativeLibrariesForSelfExtract=true `
  -o Windows/artifacts/publish
```

安装包由 `Windows/installer/DanLaiDanQu.iss` 使用 Inno Setup 6 生成。GitHub Actions 工作流会完成测试、自包含发布、安装包构建及 Release 上传。

## 限制

- 仅使用无需登录的 Bilibili 公开接口，不携带 Cookie；需要登录或权限的视频无法加载。
- 时间轴由用户手动与外部播放器同步，软件本身不播放或下载视频。
- 全屏独占模式可能遮挡置顶窗口，建议使用无边框窗口或窗口最大化播放。
