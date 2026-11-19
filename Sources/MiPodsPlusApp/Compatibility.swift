import SwiftUI

/// Isolated backward-compatibility helpers for macOS 12–13 without altering
/// the native macOS 14+ code paths.
extension View {
    @ViewBuilder
    func onChangeCompat<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
        if #available(macOS 14.0, *) {
            self.onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            self.onChange(of: value, perform: action)
        }
    }
}

enum CompatSymbols {
    static var findEarbuds: String {
        if #available(macOS 13.0, *) {
            return "bell.and.waves.left.and.right"
        }
        return "bell.fill"
    }

    static var earbudsCase: String {
        if #available(macOS 13.0, *) {
            return "earbuds.case.fill"
        }
        return "earbuds"
    }

    static var discoveryCard: String {
        if #available(macOS 13.0, *) {
            return "sparkles.rectangle.stack"
        }
        return "sparkles"
    }
}
