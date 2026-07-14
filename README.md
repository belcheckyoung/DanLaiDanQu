# 弹来弹去 (DanLaiDanQu)

macOS / Windows 桌面弹幕外挂层：输入 Bilibili 视频链接，把 B 站弹幕以透明置顶悬浮层的形式覆盖在任意播放器（YouTube / Infuse / IINA / QuickTime…）上方。不播放、不下载视频，只做弹幕获取、渲染、时间轴校准和显示控制。
<img width="1512" height="949" alt="Snipaste_2026-07-10_12-25-23" src="https://github.com/user-attachments/assets/d643f154-9f3b-45e3-a5ba-a16b91ebd41f" />


## mac 版本

要求：macOS 26 (Tahoe)+，Xcode 26+。界面采用系统原生 Liquid Glass 设计（`NSGlassEffectView` 卡片、`.glass` 按钮、磨砂窗口背景）。

```bash
make run          # 构建 .app 并启动
make app          # 只构建 build/Danmaku Overlay.app
swift build       # 调试构建
open Package.swift  # 在 Xcode 中打开开发
```

命令行自检（不启动 GUI，验证 B 站接口链路）：

```bash
.build/debug/DanmakuOverlay --test-fetch "https://www.bilibili.com/video/BV..."
```

## Windows 版本

Windows 10/11 x64 原生版本位于 [`Windows/`](Windows/README.md)，采用 .NET 8 + WPF，功能包含透明置顶弹幕层、鼠标穿透、时间轴同步、分 P、显示与屏蔽设置、最近观看和全局快捷键。Release 安装包为自包含构建，用户无需预装 .NET Runtime。

- [下载 macOS v0.3.3 安装包](https://github.com/belcheckyoung/DanLaiDanQu/releases/tag/v0.3.3)
- [下载 Windows v0.2.0 安装包](https://github.com/belcheckyoung/DanLaiDanQu/releases/tag/windows-v0.2.0)
- [Windows 构建与开发说明](Windows/README.md)

## 使用流程（两步）

<img width="600" height="446" alt="image" src="https://github.com/user-attachments/assets/b9c6e794-4558-4def-b59a-d9543463c813" />

**第一步 · 选择弹幕源**：粘贴 B 站链接（支持 BV / av / 分 P `?p=` / b23.tv 短链）回车加载，或直接点历史记录里的一行继续看（自动恢复上次进度）。

<img width="600" height="485" alt="image" src="https://github.com/user-attachments/assets/9cde85ec-f2b7-4b28-9d4f-278c74d5d3cd" />

**第二步 · 同步播放**（加载成功后自动进入）：
1. 点「打开弹幕层」（或 ⌘⇧H），把弹幕层调到覆盖视频画面的位置
2. 点「5秒后从0同步」（⌘S）：弹幕层正中央显示 5 秒倒计时，归零瞬间在播放器里点视频播放；倒计时中再按取消
3. 用 ±1s/±5s 或精确偏移微调，对上后「⋯ → 保存偏移」，下次自动恢复
4. 「← 换个视频」返回第一步

进度条旁是「播放」按钮（⌘P）和「5秒后开始」开关：开关打开时点播放先倒计时再开始，关闭则立即开始；暂停永远立即生效。进度条可拖动跳转。

**不常用功能收在二级入口**：右上角「⋯」菜单（倍速 / 鼠标穿透 / 清屏 / 保存偏移 / 导入导出）；「显示与屏蔽设置…」（⌘,，也在应用菜单里）打开设置弹窗（字号 / 透明度 / 滚动时长 / 显示区域 / 密度 / 关键词与类型屏蔽）。全局快捷键 ⌘⇧0 / ⌘⇧空格 无倒计时，适合观影中即时操作。

### 全局快捷键

| 快捷键 | 功能 |
|---|---|
| ⌘⇧空格 | 播放 / 暂停弹幕 |
| ⌘⇧← / → | 弹幕后退 / 快进 1 秒 |
| ⌘⇧↓ / ↑ | 弹幕后退 / 快进 5 秒 |
| ⌘⇧0 | 将当前时刻设为视频 0 秒（从此刻同步） |
| ⌘⇧H | 打开 / 关闭弹幕层 |

### 弹幕层操作

- 「鼠标穿透」开启时点击直接落到下层播放器；关闭后显示粉色边框，可拖拽移动、调整弹幕层位置
- 系统原生全屏下置顶层可能不可见：改用「窗口最大化」观看，或导出 ASS 作为外挂字幕导入播放器

## 已知限制（MVP）

- 仅使用无需登录的公开接口，弹幕上限为实时弹幕池返回量（约 1000-6000 条/视频）；全量历史弹幕需登录态，MVP 不做
- 番剧 ep/ss 链接、互动视频暂不支持
- 时间轴为手动校准；YouTube 进度自动联动规划在 V1.0（浏览器扩展 + WebSocket）

## 架构

```
Sources/DanmakuOverlay/
├── App/        AppDelegate、AppController（状态与动作中枢）
├── Input/      主控制窗口（链接输入、同步控制、设置、导出）
├── Data/       链接解析、B 站客户端、弹幕 XML 解析、导出、SQLite
├── Time/       独立播放时钟（偏移/倍速）、Carbon 全局快捷键
├── Render/     CATextLayer + CADisplayLink 弹幕渲染、轨道碰撞检测
├── Display/    透明置顶 NSPanel（穿透/拖拽/位置记忆）
├── Filters/    关键词/正则/颜色/长度/重复屏蔽、密度降采样
└── Settings/   全局显示设置（SQLite 持久化）
```

数据存储在 `~/Library/Application Support/DanmakuOverlay/`（SQLite + 弹幕缓存 JSON）。

## 合规边界与声明

仅调用公开接口、不携带 Cookie、不下载视频、不绕过任何权限限制、对请求不做批量抓取。定位为个人观看辅助工具。

**本项目为独立第三方开源软件，与哔哩哔哩（Bilibili）及上海宽娱数码科技有限公司无任何关联、授权或合作关系。** "Bilibili" 仅用于描述本工具兼容的弹幕数据来源。弹幕内容的权利归原发送用户及平台所有，请仅将本工具用于个人观看辅助，勿用于数据批量抓取或商业用途。

## 许可证

本项目以 [GPL-3.0](LICENSE) 许可证开源。
