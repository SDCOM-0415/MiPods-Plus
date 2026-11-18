import Foundation

// MARK: - Multi-device Discovery

public struct DiscoveredDevice: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var rssi: Int?
    public var isSystemConnected: Bool
    public var lastSeen: Date
    public var mfrHex: String?

    public init(id: UUID, name: String, rssi: Int? = nil, isSystemConnected: Bool = false, lastSeen: Date = Date(), mfrHex: String? = nil) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.isSystemConnected = isSystemConnected
        self.lastSeen = lastSeen
        self.mfrHex = mfrHex
    }

    public var isBudsSeries: Bool {
        name.localizedCaseInsensitiveContains("buds")
    }
}

// MARK: - Battery

public struct BatteryLevel: Sendable, Equatable {
    public var percent: Int?
    public var isCharging: Bool
    public var isPresent: Bool

    public static let unknown = BatteryLevel(percent: nil, isCharging: false, isPresent: false)

    public init(raw: UInt8) {
        if raw == 0xFF {
            self.percent = nil
            self.isCharging = false
            self.isPresent = false
            return
        }
        self.percent = Int(raw & 0x7F)
        self.isCharging = (raw & 0x80) != 0
        self.isPresent = true
    }

    public init(percent: Int?, isCharging: Bool, isPresent: Bool = true) {
        self.percent = percent
        self.isCharging = isCharging
        self.isPresent = isPresent
    }

    public var displayPercent: String { percent.map { "\($0)%" } ?? "--" }
}

// MARK: - Noise & Audio Models

public enum NoiseMode: Int, Sendable, CaseIterable, Equatable {
    case off = 0x00
    case anc = 0x01
    case transparency = 0x02
    case windNoise = 0x03

    public init?(rawByte: UInt8) {
        self.init(rawValue: Int(rawByte))
    }

    public var rawByte: UInt8 { UInt8(rawValue) }

    public var displayTitle: String {
        switch self {
        case .off: return "普通"
        case .anc: return "降噪"
        case .transparency: return "通透"
        case .windNoise: return "抗风噪"
        }
    }
}

public enum TransparencyLevel: UInt8, Sendable, CaseIterable, Equatable {
    case standard = 0x00
    case voice = 0x01
    case ambient = 0x02

    public var displayTitle: String {
        switch self {
        case .standard: return "标准"
        case .voice: return "人声增强"
        case .ambient: return "环境增强"
        }
    }
}

public enum EQPreset: UInt8, Sendable, CaseIterable, Equatable {
    case `default` = 0x00
    case voice = 0x01
    case bass = 0x05
    case treble = 0x06
    case volume = 0x07
    case custom = 0x0A
    case classic = 0x0B
    case legend = 0x0C
    case soothing = 0x0D
    case harman = 0x0E
    case harmanMaster = 0x0F

    public var displayTitle: String {
        switch self {
        case .default: return "默认"
        case .voice: return "人声增强"
        case .bass: return "低音增强"
        case .treble: return "高音增强"
        case .volume: return "音量增强"
        case .custom: return "自定义"
        case .classic: return "经典听感"
        case .legend: return "传奇听感"
        case .soothing: return "低音舒缓"
        case .harman: return "哈曼 AudioEFX"
        case .harmanMaster: return "哈曼大师"
        }
    }
}

public enum SpatialScene: UInt8, Sendable, CaseIterable, Equatable {
    case off = 0x00
    case standard = 0x01
    case music = 0x02
    case video = 0x03
    case game = 0x04
    case book = 0x05

    public var displayTitle: String {
        switch self {
        case .off: return "关闭"
        case .standard: return "标准"
        case .music: return "音乐"
        case .video: return "视频"
        case .game: return "游戏"
        case .book: return "听书"
        }
    }
}

public enum GestureType: UInt8, Sendable, CaseIterable, Equatable {
    case doubleTap = 1
    case tripleTap = 2
    case longPress = 3
    case singleTap = 4
    case swipe = 5

    public var displayTitle: String {
        switch self {
        case .singleTap: return "单击"
        case .doubleTap: return "双击"
        case .tripleTap: return "三击"
        case .longPress: return "长按"
        case .swipe: return "滑动"
        }
    }
}

public enum GestureAction: UInt8, Sendable, CaseIterable, Equatable {
    case xiaoai = 0
    case playPause = 1
    case previous = 2
    case next = 3
    case volumeUp = 4
    case volumeDown = 5
    case switchANC = 6
    case gameMode = 7
    case none = 8
    case photo = 9
    case recordTranslate = 10
    case adjustVolume = 11
    case simultaneousTranslate = 12

    public var displayTitle: String {
        switch self {
        case .xiaoai: return "小爱同学"
        case .playPause: return "播放/暂停"
        case .previous: return "上一首"
        case .next: return "下一首"
        case .volumeUp: return "音量+"
        case .volumeDown: return "音量-"
        case .switchANC: return "切换降噪模式"
        case .gameMode: return "游戏模式"
        case .none: return "无"
        case .photo: return "拍照"
        case .recordTranslate: return "录音/翻译"
        case .adjustVolume: return "调节音量"
        case .simultaneousTranslate: return "同传翻译"
        }
    }
}

public enum FreeTalkDuration: UInt8, Sendable, CaseIterable, Equatable {
    case off = 0
    case sec5 = 5
    case sec10 = 10
    case sec15 = 15
    case always = 255

    public var displayTitle: String {
        switch self {
        case .off: return "关闭"
        case .sec5: return "5秒"
        case .sec10: return "10秒"
        case .sec15: return "15秒"
        case .always: return "始终"
        }
    }
}

public struct Capabilities: OptionSet, Sendable, Equatable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let hasANC = Capabilities(rawValue: 1 << 0)
    public static let hasTransparency = Capabilities(rawValue: 1 << 1)
    public static let hasWearingDetection = Capabilities(rawValue: 1 << 2)
    public static let hasRecording = Capabilities(rawValue: 1 << 3)
    public static let hasFindMyEarbuds = Capabilities(rawValue: 1 << 4)
    public static let hasEqualizer = Capabilities(rawValue: 1 << 5)
    public static let hasWindNoise = Capabilities(rawValue: 1 << 6)
    public static let hasANCLevel = Capabilities(rawValue: 1 << 7)
    public static let hasTransparencyLevel = Capabilities(rawValue: 1 << 8)
    public static let hasSpatialAudio = Capabilities(rawValue: 1 << 9)
    public static let hasSceneMode = Capabilities(rawValue: 1 << 10)
    public static let hasGesture = Capabilities(rawValue: 1 << 11)
    public static let hasDualDevice = Capabilities(rawValue: 1 << 12)
    public static let hasAutoAnswer = Capabilities(rawValue: 1 << 13)
    public static let hasHotword = Capabilities(rawValue: 1 << 14)
    public static let hasFreeTalk = Capabilities(rawValue: 1 << 15)
    public static let hasAdaptiveANC = Capabilities(rawValue: 1 << 16)
    public static let hasPersonalANC = Capabilities(rawValue: 1 << 17)
    public static let hasAdaptiveSense = Capabilities(rawValue: 1 << 18)
    public static let hasAdaptiveVolume = Capabilities(rawValue: 1 << 19)

    public static let none: Capabilities = []
}

// MARK: - Device Info & Run Info

public struct DeviceInfo: Sendable, Equatable {
    public var modelName: String?
    public var firmware: String?
    public var vendorID: String?
    public var productID: String?
    public var voiceCodec: UInt8?
    public var deviceType: UInt8?
    public var left = BatteryLevel.unknown
    public var right = BatteryLevel.unknown
    public var caseBattery = BatteryLevel.unknown

    public init() {}

    static func version(_ a: UInt8, _ b: UInt8) -> String {
        "\(a >> 4).\(a & 0xF).\(b >> 4).\(b & 0xF)"
    }

    public static func parse(_ payload: [UInt8]) -> DeviceInfo {
        var info = DeviceInfo()
        for entry in TLV.parse(payload) {
            switch entry.index {
            case 0x00:
                let name = String(decoding: entry.data, as: UTF8.self)
                    .trimmingCharacters(in: .controlCharacters)
                    .trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { info.modelName = name }
            case 0x01 where entry.data.count >= 2:
                info.firmware = version(entry.data[0], entry.data[1])
            case 0x03 where entry.data.count >= 4:
                info.vendorID = String(format: "%02X%02X", entry.data[0], entry.data[1])
                info.productID = String(format: "%02X%02X", entry.data[2], entry.data[3])
            case 0x07 where entry.data.count >= 3:
                info.left = BatteryLevel(raw: entry.data[0])
                info.right = BatteryLevel(raw: entry.data[1])
                info.caseBattery = BatteryLevel(raw: entry.data[2])
            case 0x08:
                info.voiceCodec = entry.data.first
            case 0x0D:
                info.deviceType = entry.data.first
            default:
                break
            }
        }
        return info
    }
}

public struct RunInfo: Sendable, Equatable {
    public var noiseMode: NoiseMode?
    public var autoPlayEnabled: Bool?
    public var gameModeEnabled: Bool?
    public var hotwordEnabled: Bool?
    public var mtu: Int?

    public init() {}

    public static func parse(_ payload: [UInt8]) -> RunInfo {
        var info = RunInfo()
        for entry in TLV.parse(payload) {
            switch entry.index {
            case 0x02 where entry.data.count >= 2:
                info.mtu = Int(entry.data[0]) << 8 | Int(entry.data[1])
            case 0x05 where entry.data.count >= 3 && entry.data[1] == 0x02:
                info.hotwordEnabled = entry.data[2] == 0x01
            case 0x09:
                if let value = entry.data.first { info.noiseMode = NoiseMode(rawByte: value) }
            case 0x0A:
                if let value = entry.data.first { info.autoPlayEnabled = value == 0x00 }
            case 0x0B:
                if let value = entry.data.first { info.gameModeEnabled = value == 0x00 }
            default:
                break
            }
        }
        return info
    }
}

public enum StatusUpdate: Sendable, Equatable {
    case battery(left: BatteryLevel, right: BatteryLevel, caseBattery: BatteryLevel)
    case localRecording(Bool)
    case noiseMode(NoiseMode)
    case unknown(index: UInt8, data: [UInt8])

    public static func parse(_ payload: [UInt8]) -> [StatusUpdate] {
        TLV.parse(payload).map { entry in
            switch entry.index {
            case 0x00, 0x04:
                guard entry.data.count >= 3 else {
                    return .unknown(index: entry.index, data: entry.data)
                }
                return .battery(left: BatteryLevel(raw: entry.data[0]),
                                right: BatteryLevel(raw: entry.data[1]),
                                caseBattery: BatteryLevel(raw: entry.data[2]))
            case 0x02:
                return .localRecording((entry.data.first ?? 0) != 0)
            case 0x03:
                if let mode = entry.data.first.flatMap(NoiseMode.init(rawByte:)) {
                    return .noiseMode(mode)
                }
                return .unknown(index: entry.index, data: entry.data)
            default:
                return .unknown(index: entry.index, data: entry.data)
            }
        }
    }
}
