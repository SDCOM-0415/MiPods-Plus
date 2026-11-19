# AGENTS.md — MiPods-Plus 开发与协作规范

本文件为在本仓库中工作的 AI Coding Agent 与开发者提供统一的架构约束、兼容性红线、构建测试流程与开源合规规范。

---

## 1. 项目概览与模块划分

`MiPods-Plus` 是一个面向 **macOS 12.0+** 的小米 / Redmi 蓝牙耳机伴侣应用（Swift Package Manager，无 Xcode `.xcodeproj` 工程文件），输出 **Universal Binary (`arm64` + `x86_64`)**。

```text
Core/                         # 纯逻辑与蓝牙通信核心库（不依赖 SwiftUI / AppKit）
  MiPodsController.swift      # @MainActor 混合状态控制器（双通道调度、多设备切换、轮询与混合认证）
  Models.swift                # MiPodsState、DiscoveredDevice、TransportKind、能力位与枚举
  Protocol.swift              # FE DC BA ... EF 帧编解码、SAFER+ 认证、TLV/ConfigRecord、10 段 EQ 编解码
  BLETransport.swift          # CoreBluetooth BLE 0xAF00 传输层（含小米手机防误连过滤）
  RFCOMMTransport.swift       # IOBluetooth 经典蓝牙 RFCOMM 0xFD2D 传输层
  ClassicDiscovery.swift      # 经典蓝牙 Inquiry：发现配对模式耳机并发起配对（名称须含小米/Redmi 品牌）
App/                          # macOS 菜单栏与桌面 UI（AppKit + SwiftUI）
  MiPodsPlusApp.swift         # 应用入口、菜单栏图标/右键快捷菜单、Popover 管理
  PanelView.swift             # 主控制面板与多设备切换器
  HUDController.swift         # 类 AirPods 顶部悬浮连接胶囊 HUD 窗口控制
  HUDView.swift               # 顶部悬浮胶囊 HUD 视图
  ProximityPopupController.swift # 类 AirPods 靠近发现与一键连接大卡片弹窗控制
  ProximityPopupView.swift    # 类 AirPods 发现与电量卡片视图
  BatteryRing.swift           # 三色电量环组件
  TouchBarController.swift    # Touch Bar 快捷控制
  Compatibility.swift         # macOS 12–13 隔离兼容层（严禁污染 macOS 14+ 原生代码）
  CoreAdapters.swift          # UI 展示辅助扩展
  Titles.swift                # 本地化文案与标题映射
Tests/                        # 单元测试
  ProtocolTests.swift         # 协议帧、电量、ConfigRecord、EQ、SAFER+ 与设备模型单元测试
```

**分层红线**：
- `Core/`（Swift 模块 `MiPodsPlusCore`）严禁引入 `SwiftUI` 或 `AppKit`。
- `App/`（Swift 模块 `MiPodsPlusApp`）不得直接拼装蓝牙字节帧或操作 `CBPeripheral` / `IOBluetoothRFCOMMChannel`，所有控制操作必须通过 `MiPodsController` 暴露的方法下发。
- **扁平目录约定**：保持 `Core/`、`App/`、`Tests/` 三个顶层目录内部文件直接平铺，不要再拆多层子文件夹。

---

## 2. 蓝牙传输与协议核心约定

### 2.1 双通道架构（RFCOMM + BLE）
- **经典蓝牙 RFCOMM（`0xFD2D`）**：优先扫描系统已配对/已连接的经典蓝牙设备，匹配 SDP 服务 `0000FD2D-0000-1000-8000-00805F9B34FB`（或 16-bit `0xFD2D`），适配如 **Redmi Buds 6 青春版**等不通过 BLE `AF00` 暴露控制通道的机型。
- **BLE（`0xAF00`）**：结合 `retrieveConnectedPeripherals(withServices: [AF00])` 与广播扫描，适配支持 BLE 协议的机型。
- **严格隔离活动通道**：`MiPodsController` 通过 `activeTransportKind` 隔离事件源，切换设备或某通道已连接时，另一通道的异步回调必须被忽略，避免状态互相覆盖。
- **防误连小米手机/平板**：小米手机同样广播厂商 ID `0x038F`（常携带 `FDAA` / `FCC0` 服务但无 `AF00`）。修改 `BLETransport` 扫描过滤逻辑时，必须保留非耳机服务过滤、名称黑名单及发现服务后无 `AF00` 即断开拉黑机制。

### 2.2 混合认证策略（不可破坏）
1. 建立连接后，**必须先发送免认证命令**（`0x02` `GET_DEVICE_INFO`、`0x09` `GET_RUN_INFO`），确保所有机型都能先拿到基础电量与运行状态。
2. **禁止对未知机型无条件提前发送 `0x50` SAFER+ 握手**（部分机型如 M2529E1 耳夹式会因早期收到 `0x50` 进入静默状态）。仅对 `Buds` 系列或历史曾认证成功的设备自动触发认证，其余设备由用户在 UI 按需触发。
3. 所有扩展配置读写通过 `0xF3` (`getConfig`) / `0xF4` (`setConfig`) 及 `ConfigRecord` 完成，UI 根据设备实际返回的能力与配置动态渲染。

### 2.3 线程与主队列约定
- `MiPodsController` 标注为 `@MainActor`，所有状态变更必须在主线程执行。
- `RFCOMMTransport` 的 `IOBluetooth` 操作必须在主队列执行；在 `connect()` 内清理旧连接时须同步调用内部清理函数，避免嵌套 `DispatchQueue.main.async` 导致误关闭刚打开的通道。

---

## 3. macOS 兼容性与通用二进制红线

- **最低部署目标**：`Package.swift`（`.macOS("12.0")`）与 `Makefile`（`LSMinimumSystemVersion = 12.0`）必须保持一致。
- **隔离兼容原则**：针对 macOS 12–13 缺失的 API（如 `SMAppService`、新版 SwiftUI 修饰符、SF Symbols 等），**必须**通过 `#available(macOS 14.0, *)` / `#available(macOS 13.0, *)` 条件分支或封装在 `App/Compatibility.swift` 中实现降级，**不得为兼容旧系统而回退或劣化 macOS 14+ 的原生行为**。
- **通用二进制构建**：`Makefile` 默认 `SWIFT_FLAGS ?= -c release --arch arm64 --arch x86_64`，不要将其改回单架构调试构建；`PRODUCT` 路径必须通过 `swift build $(SWIFT_FLAGS) --show-bin-path` 动态获取，禁止硬编码 `.build/...`。

---

## 4. 构建、测试与 CI 规范

- **工具链要求**：在 macOS 上构建必须使用完整 **Xcode**（`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`），仅安装 Command Line Tools 会因缺少 SwiftUI 宏插件导致编译失败。
- **常用命令**：
  - `make test` / `swift test`：运行 `MiPodsPlusCoreTests` 单元测试。
  - `make app`：构建 Release 通用二进制并打包 `MiPods-Plus.app`。
  - `make demo`：以 `MIPODS_DEMO=1` 启动本地 UI 预览（无需实体耳机）。
- **CI 工作流（`.github/workflows/ci.yml`）**：
  - Runner 使用 `macos-latest`（不要使用已下线的 `macos-14` 等旧镜像标签）。
  - 每次修改后需确保 `swift test`、`make app`、`lipo -info`（验证同时包含 `arm64` 与 `x86_64`）以及产物 `MiPods-Plus-macOS-universal.zip` 上传全部通过。
- **Linux 远程环境说明**：若 Agent 运行在 Linux 环境下无法本地执行 `swift build`（缺少 macOS SDK / `CoreBluetooth` / `IOBluetooth`），推送后必须检查 GitHub Actions 运行结果以确认编译与单测通过。

---

## 5. 代码修改、测试与开源合规

- **测试要求**：凡修改 `Protocol.swift`、`Models.swift` 中的帧编解码、TLV 解析、EQ 编解码、SAFER+ 或设备 UUID 生成逻辑，必须在 `Tests/ProtocolTests.swift` 中补充或更新对应单元测试。
- **文档与注释**：保留与本次改动无关的既有注释；面向用户的界面文案与日志默认使用简体中文，保持简洁一致。
- **开源许可与致谢规范**：
  - 本项目采用 **AGPL-3.0** 许可（见 `LICENSE`）。
  - 在 `README.md` 或其他文档中提及致谢与协议参考时，**只允许链接原始上游开源仓库**：
    - `JackWPP/MiPods`
    - `LeoLee0812/buds-ctl`
    - `Tomiya233/MiEarphonePC`
  - **禁止**在致谢中链接个人 fork 仓库。
- **提交信息规范**：使用 Conventional Commits 风格（如 `feat:`、`fix:`、`docs:`、`refactor:`、`test:`、`chore:`），清晰描述改动目的。
