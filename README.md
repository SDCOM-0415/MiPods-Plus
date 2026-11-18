# MiPods-Plus

基于多个开源小米耳机控制项目合并二次开发的 macOS 小米/Redmi 耳机伴侣应用：

- **类 AirPods 桌面体验**：菜单栏常驻电量与模式图标、右键快捷菜单、顶部悬浮连接 HUD（不抢焦点、覆盖全屏应用）、三色电量环、Touch Bar 快捷控制。
- **多设备发现与切换**：同时结合 `retrieveConnectedPeripherals(AF00)`（系统已连外设直连）与全量 BLE 广播扫描（匹配小米厂商 ID `0x038F` 或 `xiaomi` / `redmi` / `buds` 名称），可在面板顶部一键切换多副耳机并记忆偏好设备。
- **混合认证策略**：
  1. 连接后**先发免认证命令**（`0x02` `GET_DEVICE_INFO`、`0x09` `GET_RUN_INFO`），确保所有型号都能第一时间展示左右耳与充电盒电量，避免部分机型（如 M2529E1 耳夹式）因早期发 `0x50` 进入静默状态。
  2. 对 `Buds` 系列或曾认证成功的设备**自动完成 SAFER+ 双向握手**（`0x50`/`0x51`）并拉取扩展配置（`0xF3`）；对其他机型提供**按需点击解锁**。
- **全量声学与日常控制**（按耳机上报能力动态渲染）：
  - 降噪 / 通透 / 抗风噪模式、20 级降噪深度滑条、自适应降噪、3 档通透模式
  - 11 种官方 EQ 预设 + **10 段自定义均衡器（`62Hz ~ 16kHz`，支持试听/保存/归零）**
  - 空间音频、头部追踪、场景沉浸声渲染
  - **低延迟游戏模式**、双设备连接、自动接听、语音免唤醒、自适应听感/音量、智能免摘
  - 手势自定义、**分耳精准查找（左耳 / 右耳 / 双耳响铃）**与开机自启

## 构建与运行（macOS 14+）

### 方式一：通过 GitHub Actions 下载构建产物

仓库已配置 [GitHub Actions 工作流](.github/workflows/ci.yml)（`macos-latest`）：每次推送到 `main` 会自动执行 `swift build`、`swift test` 并打包上传 `MiPods-Plus-macOS.zip` 产物，可在仓库 **Actions** 页面直接下载。

### 方式二：本地从源码构建

需要安装 **Xcode**（SwiftUI 宏需要完整 Xcode 工具链，仅装 Command Line Tools 会编译失败）：

```bash
git clone https://github.com/SDCOM-0415/MiPods-Plus.git
cd MiPods-Plus
make test    # 运行协议单元测试
make app     # 构建并打包为 MiPods-Plus.app
make run     # 运行
make install # 安装到 /Applications
```

> 首次启动未公证应用若被 Gatekeeper 拦截，可执行：
> ```bash
> xattr -dr com.apple.quarantine /Applications/MiPods-Plus.app
> ```

## 目录结构

```
Sources/
  MiPodsPlusCore/       协议层、SAFER+ 认证、10 段 EQ 编解码、多设备 BLE 传输与混合状态控制器
  MiPodsPlusApp/        菜单栏 App、右键快捷菜单、类 AirPods HUD、Touch Bar 与多设备控制面板
Tests/
  MiPodsPlusCoreTests/  帧编解码、ConfigRecord、自定义 EQ、SAFER+ 与电量解析测试
```

## 致谢与许可

本项目以 **AGPL-3.0** 开源发布，见 [LICENSE](LICENSE)。

功能与协议参考并致谢以下开源源仓库：
- [JackWPP/MiPods](https://github.com/JackWPP/MiPods)（AGPL-3.0）— AirPods 式悬浮 HUD、Touch Bar 面板、三色电量环、BLE 协议与 SAFER+ 实现
- [LeoLee0812/buds-ctl](https://github.com/LeoLee0812/buds-ctl)（AGPL-3.0）— 系统已连接外设复用、Buds 系列全量配置项读写与开机自启
- [Tomiya233/MiEarphonePC](https://github.com/Tomiya233/MiEarphonePC) — 10 段自定义 EQ（`0x37`）、低延迟游戏模式（`0x2F`）、分耳查找响铃及托盘右键快捷菜单交互思路
