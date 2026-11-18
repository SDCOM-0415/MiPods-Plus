import Foundation
import SwiftUI
import MiPodsPlusCore

extension MiPodsState {

    var leftLevel: Int? { Self.normalize(leftBattery) }
    var rightLevel: Int? { Self.normalize(rightBattery) }
    var caseLevel: Int? { Self.normalize(caseBattery) }

    private static func normalize(_ raw: Int?) -> Int? {
        guard let raw, (0...100).contains(raw) else { return nil }
        return raw
    }

    var isChargingLeft: Bool { isLeftCharging }
    var isChargingRight: Bool { isRightCharging }
    var isChargingCase: Bool { isCaseCharging }

    var noiseModeTitle: String {
        guard canSwitchNoiseMode else { return NoiseMode.off.displayTitle }
        return noiseMode.displayTitle
    }

    var availableNoiseModes: [NoiseMode] {
        var modes: [NoiseMode] = [.off]
        if capabilities.contains(.hasANC) { modes.append(.anc) }
        if capabilities.contains(.hasTransparency) { modes.append(.transparency) }
        if capabilities.contains(.hasWindNoise) { modes.append(.windNoise) }
        return modes.count > 1 ? modes : []
    }

    var canSwitchNoiseMode: Bool { !availableNoiseModes.isEmpty }

    var displayName: String {
        if !deviceName.trimmingCharacters(in: .whitespaces).isEmpty { return deviceName }
        if !modelName.trimmingCharacters(in: .whitespaces).isEmpty { return modelName }
        return L10n.appName
    }

    var compactBatteryText: String {
        [leftLevel, rightLevel, caseLevel]
            .map { $0.map(String.init) ?? L10n.unknown }
            .joined(separator: " / ")
    }

    var lowestBattery: Int? {
        [leftLevel, rightLevel, caseLevel].compactMap { $0 }.min()
    }

    var isAnyCharging: Bool { isChargingLeft || isChargingRight || isChargingCase }
}

extension NoiseMode {
    var localizedTitle: String { displayTitle }

    var symbolName: String {
        switch self {
        case .anc: return "waveform.path.ecg"
        case .transparency: return "ear"
        case .windNoise: return "wind"
        case .off: return "speaker.slash"
        }
    }
}
