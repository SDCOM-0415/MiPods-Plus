import Foundation

enum L10n {
    static let appName = "MiPods Plus"
    static let unknown = "—"

    static let statusConnected = "已连接"
    static let statusDisconnected = "未连接"
    static let statusConnecting = "连接中…"
    static let statusSearching = "正在搜索耳机…"

    static let actionRefresh = "刷新"
    static let actionRescan = "重新扫描"
    static let actionQuit = "退出"

    static let batteryLeft = "左耳"
    static let batteryRight = "右耳"
    static let batteryCase = "充电盒"

    static func batteryAccessibility(_ label: String, level: Int?, charging: Bool) -> String {
        guard let level else { return "\(label) 电量未知" }
        return charging ? "\(label) \(level)%，充电中" : "\(label) \(level)%"
    }

    static let modeTitle = "降噪模式"
    static let noModeSupport = "本耳机不支持主动降噪"
    static let noModeSupportDetail = "开放式耳夹结构或当前固件未上报降噪能力"

    static let recordingTitle = "本地录音"
    static let recordingAvailable = "耳机可本地录音"
    static let recordingUnavailable = "耳机当前不可本地录音"
    static let recordingUnknown = "录音状态未知"
    static let recordingLocalHint = "录音保存在耳机/充电盒内，需在手机端小米耳机 App 导出"

    static let infoUpdated = "更新于"

    static func relativeTime(from date: Date?, now: Date = Date()) -> String {
        guard let date else { return unknown }
        let seconds = Int(now.timeIntervalSince(date))
        switch seconds {
        case ..<2: return "刚刚"
        case ..<60: return "\(seconds) 秒前"
        case ..<3600: return "\(seconds / 60) 分钟前"
        default: return "\(seconds / 3600) 小时前"
        }
    }
}
