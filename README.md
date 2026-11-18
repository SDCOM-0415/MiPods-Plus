# MiPods-Plus

基于 [MiPods](https://github.com/SDCOM-0415/MiPods) 与 [buds-ctl](https://github.com/SDCOM-0415/buds-ctl) 合并二次开发的 macOS 小米/Redmi 耳机伴侣应用：

- **类 AirPods 桌面体验**（来自 `MiPods`）：菜单栏常驻电量、顶部悬浮连接 HUD（不抢焦点、覆盖全屏应用）、三色电量环、Touch Bar 快捷控制。
- **多设备发现与切换**：同时支持 `retrieveConnectedPeripherals(AF00)`（系统已连外设直连）与全量 BLE 广播扫描（匹配小米厂商 ID `0x038F` 或 `xiaomi` / `redmi` / `buds` 名称），可在面板顶部一键切换多副耳机并记忆偏好设备。
- **混合认证策略**：
  1. 连接后**先发免认证命令**（`0x02` `GET_DEVICE_INFO`、`0x09` `GET_RUN_INFO`），确保所有型号都能第一时间展示左右耳与充电盒电量，避免部分机型（如 M2529E1 耳夹式）因早期发 `0x50` 进入静默状态。
  2. 对 `Buds` 系列或曾认证成功的设备**自动完成 SAFER+ 双向握手**（`0x50`/`0x51`）；对其他机型保留**按需点击解锁**，一旦解锁即下发 `0xF3` 拉取完整能力。
- **全量 Buds 控制能力**（来自 `buds-ctl`）：按耳机实际能力动态渲染降噪模式、20 级降噪深度滑条、自适应降噪、通透档位、11 种 EQ（含哈曼音效）、空间音频与头部追踪、场景渲染、双设备、自动接听、免唤醒语音、自适应听感/音量、智能免摘、手势自定义与查找耳机响铃。

## 构建与运行（macOS 14+）

需要安装 **Xcode**（SwiftUI 宏需要完整 Xcode 工具链，仅装 Command Line Tools 会编译失败）：

```bash
git clone https://github.com/SDCOM-0415/MiPods-Plus.git
cd MiPods-Plus
make app     # 构建并打包为 MiPods-Plus.app
make run     # 运行
make test    # 运行协议单元测试
make install # 安装到 /Applications
```

> 首次启动未公证应用若被 Gatekeeper 拦截，可执行：
> ```bash
> xattr -dr com.apple.quarantine /Applications/MiPods-Plus.app
> ```

## 目录结构

```
Sources/
  MiPodsPlusCore/   协议层、SAFER+ 认证、多设备 BLE 传输与混合状态控制器
  MiPodsPlusApp/    菜单栏 App、类 AirPods HUD、Touch Bar 与多设备控制面板
Tests/
  MiPodsPlusCoreTests/  帧编解码、ConfigRecord、SAFER+ 与电量解析测试
```

## 致谢与许可

本项目以 **AGPL-3.0** 开源发布，见 [LICENSE](LICENSE)。

合并并致谢以下两个上游项目：
- [SDCOM-0415/MiPods](https://github.com/SDCOM-0415/MiPods)（原仓库 JackWPP/MiPods，AGPL-3.0）
- [SDCOM-0415/buds-ctl](https://github.com/SDCOM-0415/buds-ctl)（原仓库 LeoLee0812/buds-ctl，AGPL-3.0）
