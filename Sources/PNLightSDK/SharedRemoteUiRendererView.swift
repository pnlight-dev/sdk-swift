import UIKit
import CoreHaptics
import DivKit
import DivKitExtensions
import LayoutKit
import Lottie
import PNLight
import VGSL

private final class PNLightLottieAnimationViewFactory: AsyncSourceAnimatableViewFactory {
    func createAsyncSourceAnimatableView(
        withMode mode: AnimationRepeatMode,
        repeatCount count: Float
    ) -> AsyncSourceAnimatableView {
        PNLightLottieAnimationView(repeatMode: mode, repeatCount: count)
    }
}

private final class PNLightLottieAnimationView: UIView, AsyncSourceAnimatableView {
    private let animationView = LottieAnimationView()
    private let repeatMode: AnimationRepeatMode
    private let repeatCount: Float

    init(repeatMode: AnimationRepeatMode, repeatCount: Float) {
        self.repeatMode = repeatMode
        self.repeatCount = max(repeatCount, 0)
        super.init(frame: .zero)
        clipsToBounds = true
        isUserInteractionEnabled = false
        animationView.isUserInteractionEnabled = false
        addSubview(animationView)
        applyPlaybackMode()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var contentMode: UIView.ContentMode {
        didSet {
            animationView.contentMode = contentMode
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        animationView.frame = bounds
    }

    func play() {
        animationView.play()
    }

    func pause() {
        animationView.pause()
    }

    @MainActor
    func setSourceAsync(_ source: AnimationSourceType) async {
        guard let source = source as? LottieAnimationSourceType else {
            animationView.animation = nil
            return
        }

        do {
            let animation: LottieAnimation
            switch source {
            case let .json(dictionary):
                animation = try LottieAnimation(dictionary: dictionary)
            case let .data(data):
                animation = try JSONDecoder().decode(LottieAnimation.self, from: data)
            }
            animationView.animation = animation
            applyPlaybackMode()
        } catch {
            animationView.animation = nil
            NSLog("[PNLight][Lottie] Failed to decode animation: %@", "\(error)")
        }
    }

    private func applyPlaybackMode() {
        switch (repeatMode, repeatCount) {
        case (.restart, 0):
            animationView.loopMode = .loop
        case (.reverse, 0):
            animationView.loopMode = .autoReverse
        case let (.restart, count):
            animationView.loopMode = .repeat(count)
        case let (.reverse, count):
            animationView.loopMode = .repeatBackwards(count)
        }
    }
}

private func makePNLightLottieExtensionHandler() -> DivExtensionHandler {
    let requestPerformer = URLRequestPerformer(urlTransform: nil)
    let requester = NetworkURLResourceRequester(performer: requestPerformer)
    return LottieExtensionHandler(
        factory: PNLightLottieAnimationViewFactory(),
        requester: requester
    )
}

/// Lenient readers for DivKit `custom_props` values, which arrive as loosely
/// typed `Any` (numbers may be `Int`, `Double`, `NSNumber`, or numeric strings).
enum CustomPropReader {
    static func string(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty else { return nil }
        return value
    }

    static func double(_ value: Any?) -> Double? {
        switch value {
        case let value as Double: return value
        case let value as Int: return Double(value)
        case let value as NSNumber: return value.doubleValue
        case let value as String: return Double(value)
        default: return nil
        }
    }

    static func cgFloat(_ value: Any?) -> CGFloat? {
        double(value).map { CGFloat($0) }
    }

    static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let value as Bool: return value
        case let value as NSNumber: return value.boolValue
        case let value as Int: return value != 0
        case let value as String:
            switch value.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        default: return nil
        }
    }

    static func dictionary(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    /// DivKit hands `custom_props` to the factory verbatim, without evaluating
    /// expressions. Resolving them here (recursively) lets any prop bind to a
    /// card variable — e.g. `"loading": "@{is_purchasing}"`. Resolving through
    /// the context's resolver also registers the variable dependency, so DivKit
    /// re-renders the card whenever that variable changes.
    static func resolvingExpressions(
        _ props: [String: Any],
        with resolver: ExpressionResolver
    ) -> [String: Any] {
        props.mapValues { resolve($0, with: resolver) }
    }

    private static func resolve(_ value: Any, with resolver: ExpressionResolver) -> Any {
        switch value {
        case let value as String:
            guard value.contains("@{") else { return value }
            return resolver.resolve(value) ?? value
        case let value as [String: Any]:
            return value.mapValues { resolve($0, with: resolver) }
        case let value as [Any]:
            return value.map { resolve($0, with: resolver) }
        default:
            return value
        }
    }

    /// Accepts DivKit's `#AARRGGBB` colors and the common `#RRGGBB` shorthand.
    static func color(_ value: Any?) -> UIColor? {
        guard var hex = string(value) else { return nil }
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }

        let alpha: UInt64
        let red: UInt64
        let green: UInt64
        let blue: UInt64

        switch hex.count {
        case 6:
            alpha = 255
            guard let rgb = UInt64(hex, radix: 16) else { return nil }
            red = (rgb >> 16) & 0xFF
            green = (rgb >> 8) & 0xFF
            blue = rgb & 0xFF
        case 8:
            guard let argb = UInt64(hex, radix: 16) else { return nil }
            alpha = (argb >> 24) & 0xFF
            red = (argb >> 16) & 0xFF
            green = (argb >> 8) & 0xFF
            blue = argb & 0xFF
        default:
            return nil
        }

        return UIColor(
            red: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: CGFloat(alpha) / 255
        )
    }
}

private let pnlightNativeButtonActionsKey = "__pnlight_actions"

/// DivKit's custom-block API exposes `custom_props` but not the surrounding
/// element's standard `actions` array. Preserve that array in an internal prop
/// before parsing so PNLight's native buttons can dispatch it through the
/// card's own `DivActionHandler`.
private enum PNLightNativeButtonActionPreserver {
    static func preserve(in data: Data) -> (data: Data, root: [String: Any]?) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (data, nil)
        }

        let (preservedValue, changed) = preserveValue(root)
        guard let preservedRoot = preservedValue as? [String: Any] else {
            return (data, root)
        }
        guard changed,
              JSONSerialization.isValidJSONObject(preservedRoot),
              let preservedData = try? JSONSerialization.data(withJSONObject: preservedRoot) else {
            return (data, preservedRoot)
        }
        return (preservedData, preservedRoot)
    }

    private static func preserveValue(_ value: Any) -> (Any, Bool) {
        if let dictionary = value as? [String: Any] {
            var result: [String: Any] = [:]
            var changed = false
            for (key, child) in dictionary {
                let (preservedChild, childChanged) = preserveValue(child)
                result[key] = preservedChild
                changed = changed || childChanged
            }

            guard CustomPropReader.string(result["type"]) == "custom",
                  let customType = CustomPropReader.string(result["custom_type"]),
                  customType == NativeButtonBlockFactory.ctaCustomType ||
                    customType == NativeButtonBlockFactory.iconCustomType,
                  let actions = result["actions"] as? [[String: Any]],
                  actions.isEmpty == false else {
                return (result, changed)
            }

            var props = result["custom_props"] as? [String: Any] ?? [:]
            props[pnlightNativeButtonActionsKey] = actions
            result["custom_props"] = props
            return (result, true)
        }

        if let array = value as? [Any] {
            var changed = false
            let result = array.map { child -> Any in
                let (preservedChild, childChanged) = preserveValue(child)
                changed = changed || childChanged
                return preservedChild
            }
            return (result, changed)
        }

        return (value, false)
    }
}

/// Maps a DivKit layout trait onto a `GenericViewBlock.Trait`, using the native
/// view's intrinsic size when the markup requests `wrap_content`.
private func blockTrait(
    from trait: LayoutTrait,
    intrinsicSize: CGFloat
) -> GenericViewBlock.Trait {
    switch trait {
    case let .fixed(value): return .fixed(value)
    case .intrinsic: return .fixed(intrinsicSize)
    case .weighted: return .resizable
    }
}

/// Renders `pnlight.circular_loader` as a native `UIActivityIndicatorView`.
private final class CircularLoaderBlockFactory {
    static let customType = "pnlight.circular_loader"
    private static let defaultAccessibilityLabel = "Loading"

    func makeBlock(
        props: [String: Any],
        data: DivCustomData,
        context: DivBlockModelingContext
    ) -> Block {
        let style = activityIndicatorStyle(from: props["style"])
        let indicator = UIActivityIndicatorView(style: style)
        indicator.color = CustomPropReader.color(props["color"]) ?? .label
        indicator.hidesWhenStopped = false
        indicator.accessibilityLabel = CustomPropReader.string(props["accessibility_label"])
            ?? Self.defaultAccessibilityLabel
        indicator.isAccessibilityElement = true
        indicator.startAnimating()

        let intrinsicSize = indicator.intrinsicContentSize
        return GenericViewBlock(
            content: .view(indicator),
            width: blockTrait(from: data.widthTrait, intrinsicSize: intrinsicSize.width),
            height: blockTrait(from: data.heightTrait, intrinsicSize: intrinsicSize.height)
        )
    }

    private func activityIndicatorStyle(from value: Any?) -> UIActivityIndicatorView.Style {
        switch CustomPropReader.string(value)?.lowercased() {
        case "large": return .large
        default: return .medium
        }
    }
}

// MARK: - Native buttons

/// An ordered tap-action sequence parsed by DivKit and executed by the same
/// handler as actions attached to ordinary DivKit elements.
private struct NativeButtonActionSequence {
    private let actionHandler: DivActionHandler
    private let params: [UserInterfaceAction.DivActionParams]

    static func make(
        from value: Any?,
        context: DivBlockModelingContext
    ) -> NativeButtonActionSequence? {
        guard let actionHandler = context.actionHandler,
              let actions = value as? [[String: Any]],
              actions.isEmpty == false else {
            return nil
        }

        let params = actions.compactMap { action -> UserInterfaceAction.DivActionParams? in
            let envelope: [String: Any] = [
                "kind": "divAction",
                "json": action,
                "path": context.path.description,
                "divActionSource": UserInterfaceAction.DivActionSource.tap.rawValue,
            ]
            guard JSONSerialization.isValidJSONObject(envelope),
                  let data = try? JSONSerialization.data(withJSONObject: envelope),
                  let payload = try? JSONDecoder().decode(
                      UserInterfaceAction.Payload.self,
                      from: data
                  ),
                  case let .divAction(params) = payload else {
context.addError(message: "Invalid action on PNLight native button at \(context.path)")
                return nil
            }
            return params
        }

        guard params.isEmpty == false else { return nil }
        return NativeButtonActionSequence(actionHandler: actionHandler, params: params)
    }

    func execute(sender: AnyObject?) {
        params.forEach {
            actionHandler.handle(params: $0, sender: sender)
        }
    }
}

/// Keeps repeating native-button animations on a shared media-time phase.
/// DivKit can recreate a custom block when an unrelated variable changes; if
/// every new view starts at animation time zero, frequent timer ticks look like
/// a burst of button presses.
private func synchronizeRepeatingAnimation(
    _ animation: CAAnimation,
    on layer: CALayer,
    duration: CFTimeInterval
) {
    guard duration > 0 else { return }
    let localNow = layer.convertTime(CACurrentMediaTime(), from: nil)
    animation.beginTime = localNow - localNow.truncatingRemainder(dividingBy: duration)
}

/// Fully-resolved styling and behavior for the native button components,
/// parsed from DivKit `custom_props`. Every field has a sensible default so
/// markup can set as little or as much as it wants.
private struct NativeButtonConfig {
    /// Which component is being built. Only the defaults differ — a `.cta` is a
    /// wide labelled bar that shimmers and pulses; an `.icon` is a small
    /// circular SF Symbol button that only reacts to presses.
    enum Kind {
        case cta
        case icon
    }

    struct Shimmer {
        var isEnabled = true
        /// The moving highlight color; alpha controls how bright the streak is.
        var color = UIColor.white.withAlphaComponent(0.45)
        /// Seconds for one streak to travel across the button.
        var duration: CFTimeInterval = 1.4
        /// Seconds to wait after each streak before the next one.
        var pause: CFTimeInterval = 1.1
        /// Streak thickness as a fraction of the button width (0...1).
        var bandWidth: CGFloat = 0.3
        /// Streak tilt in degrees (0 = vertical streak, matching the reference CTA).
        var angle: CGFloat = 16
    }

    /// Continuous "attention" pulse played while the button is idle.
    struct IdleBounce {
        var isEnabled = true
        var scale: CGFloat = 1.03
        /// Full cycle length in seconds (quick pulse, then rest).
        var period: CFTimeInterval = 2.6
    }

    /// Spring press feedback played on touch-down / release.
    struct PressBounce {
        var isEnabled = true
        var scale: CGFloat = 0.96
    }

    /// Native Liquid Glass fill (iOS 26+). Everything here degrades to the solid
    /// `backgroundColor` on older systems, so markup never branches on version.
    struct Glass {
        enum Style {
            case regular
            case clear
        }

        var isEnabled = false
        var style = Style.regular
        /// Filled rather than see-through — the primary-action treatment.
        var isProminent = false
        /// Tints the material. Defaults to an explicit `backgroundColor`, if the
        /// markup set one.
        var tint: UIColor?
    }

    var title = ""
    var backgroundColor = UIColor.systemBlue
    /// When set, the fill is drawn as a horizontal gradient from
    /// `backgroundColor` to this color.
    var backgroundGradientEndColor: UIColor?
    var titleColor = UIColor.white
    var cornerRadius: CGFloat = 14
    /// Ignores `cornerRadius` and pills the button to its own height. The
    /// default for icon buttons, giving a true circle.
    var isCircular = false
    var font = UIFont.systemFont(ofSize: 18, weight: .semibold)
    var horizontalPadding: CGFloat = 24
    var verticalPadding: CGFloat = 16

    /// SF Symbol name, e.g. `"xmark"` or `"shield.lefthalf.filled"`.
    var icon: String?
    var iconSize: CGFloat = 20
    var iconWeight: UIImage.SymbolWeight = .semibold
    /// Defaults to `titleColor`.
    var iconColor: UIColor?
    /// Gap between the icon and the title when a button has both.
    var iconSpacing: CGFloat = 8

    var shimmer = Shimmer()
    var idleBounce = IdleBounce()
    var pressBounce = PressBounce()
    var glass = Glass()

    /// Non-interactive and dimmed. Suppresses shimmer and bounce.
    var isDisabled = false
    /// Non-interactive, title swapped for a native spinner. Suppresses shimmer
    /// and bounce. Takes visual precedence over `isDisabled`.
    var isLoading = false
    var disabledAlpha: CGFloat = 0.45
    /// Defaults to `backgroundColor` (dimmed by `disabledAlpha`).
    var disabledBackgroundColor: UIColor?
    /// Defaults to `titleColor`.
    var disabledTitleColor: UIColor?
    /// Defaults to `titleColor`.
    var loadingIndicatorColor: UIColor?
    var loadingIndicatorStyle: UIActivityIndicatorView.Style = .medium
    /// Action fired on tap. A custom-scheme URL is routed to `onAction`; an
    /// http(s) URL is opened. Falls back to emitting `logId` on its own.
    var url: String?
    var logId: String?
    var accessibilityLabel: String?
}

extension NativeButtonConfig {
    /// Defaults that differ between the two components. A CTA is a loud, wide
    /// bar; an icon button is a quiet, small circle that only reacts to touch.
    static func defaults(for kind: Kind) -> NativeButtonConfig {
        var config = NativeButtonConfig()
        guard kind == .icon else { return config }

        config.backgroundColor = .secondarySystemFill
        config.titleColor = .label
        config.isCircular = true
        config.horizontalPadding = 12
        config.verticalPadding = 12
        config.shimmer.isEnabled = false
        config.idleBounce.isEnabled = false
        return config
    }

    static func make(from props: [String: Any], kind: Kind) -> NativeButtonConfig {
        var config = defaults(for: kind)

        config.title = CustomPropReader.string(props["title"]) ?? ""
        let chosenBackgroundColor = CustomPropReader.color(props["background_color"])
        config.backgroundColor = chosenBackgroundColor ?? config.backgroundColor
        config.backgroundGradientEndColor = CustomPropReader.color(props["background_color_end"])
        let chosenTitleColor = CustomPropReader.color(props["title_color"])
        config.titleColor = chosenTitleColor ?? config.titleColor
        config.horizontalPadding = CustomPropReader.cgFloat(props["horizontal_padding"]) ?? config.horizontalPadding
        config.verticalPadding = CustomPropReader.cgFloat(props["vertical_padding"]) ?? config.verticalPadding

        // An explicit radius opts out of the icon button's circular default.
        if let cornerRadius = CustomPropReader.cgFloat(props["corner_radius"]) {
            config.cornerRadius = cornerRadius
            config.isCircular = false
        }

        let fontSize = CustomPropReader.cgFloat(props["font_size"]) ?? 18
        config.font = UIFont.systemFont(ofSize: fontSize, weight: fontWeight(props["font_weight"]))

        config.icon = CustomPropReader.string(props["icon"])
        config.iconSize = CustomPropReader.cgFloat(props["icon_size"]) ?? config.iconSize
        config.iconWeight = symbolWeight(props["icon_weight"])
        config.iconColor = CustomPropReader.color(props["icon_color"])
        config.iconSpacing = CustomPropReader.cgFloat(props["icon_spacing"]) ?? config.iconSpacing

        config.glass = glass(
            from: props["glass"],
            base: config.glass,
            // Icon buttons are chrome, so they pick up the system material for
            // free — but only when the markup didn't choose a fill of its own.
            // An explicit color means "I want this exact button", and silently
            // dissolving it into glass on newer systems would break that.
            isDefaultOn: kind == .icon
                && chosenBackgroundColor == nil
                && config.backgroundGradientEndColor == nil,
            defaultTint: chosenBackgroundColor
        )

        // Glass is a light, busy material: white-on-glass rarely reads, and a
        // travelling highlight over it looks like a rendering glitch.
        if config.glass.isEnabled {
            if chosenTitleColor == nil { config.titleColor = .label }
            if props["shimmer"] == nil { config.shimmer.isEnabled = false }
        }

        config.shimmer = shimmer(from: props["shimmer"], base: config.shimmer)
        let bounce = self.bounce(
            from: props["bounce"],
            idleBase: config.idleBounce,
            pressBase: config.pressBounce
        )
        config.idleBounce = bounce.idle
        config.pressBounce = bounce.press

        config.isDisabled = CustomPropReader.bool(props["disabled"]) ?? false
        config.isLoading = CustomPropReader.bool(props["loading"]) ?? false
        config.disabledAlpha = CustomPropReader.cgFloat(props["disabled_alpha"]) ?? config.disabledAlpha
        config.disabledBackgroundColor = CustomPropReader.color(props["disabled_background_color"])
        config.disabledTitleColor = CustomPropReader.color(props["disabled_title_color"])
        config.loadingIndicatorColor = CustomPropReader.color(props["loading_indicator_color"])
        config.loadingIndicatorStyle = indicatorStyle(props["loading_indicator_style"])

        config.url = CustomPropReader.string(props["url"])
        config.logId = CustomPropReader.string(props["log_id"])
        config.accessibilityLabel = CustomPropReader.string(props["accessibility_label"])

        return config
    }

    /// `glass` accepts a bool shorthand or an object:
    /// `{ "enabled": true, "style": "clear", "tint": "#8034C759", "prominent": true }`.
    private static func glass(
        from value: Any?,
        base: Glass,
        isDefaultOn: Bool,
        defaultTint: UIColor?
    ) -> Glass {
        // There is no material to render below iOS 26, and the solid fill stands
        // in for it — so the whole feature collapses to `false` on old systems.
        guard #available(iOS 26.0, *) else { return Glass() }

        var glass = base
        glass.isEnabled = isDefaultOn
        glass.tint = defaultTint

        if let isEnabled = CustomPropReader.bool(value) {
            glass.isEnabled = isEnabled
        } else if let props = CustomPropReader.dictionary(value) {
            glass.isEnabled = CustomPropReader.bool(props["enabled"]) ?? true
            glass.style = CustomPropReader.string(props["style"])?.lowercased() == "clear"
                ? .clear
                : .regular
            glass.isProminent = CustomPropReader.bool(props["prominent"]) ?? glass.isProminent
            glass.tint = CustomPropReader.color(props["tint"]) ?? glass.tint
        }

        return glass
    }

    private static func indicatorStyle(_ value: Any?) -> UIActivityIndicatorView.Style {
        switch CustomPropReader.string(value)?.lowercased() {
        case "large": return .large
        default: return .medium
        }
    }

    private static func fontWeight(_ value: Any?) -> UIFont.Weight {
        switch CustomPropReader.string(value)?.lowercased() {
        case "regular": return .regular
        case "medium": return .medium
        case "semibold": return .semibold
        case "bold": return .bold
        case "heavy": return .heavy
        case "black": return .black
        default: return .semibold
        }
    }

    private static func symbolWeight(_ value: Any?) -> UIImage.SymbolWeight {
        switch CustomPropReader.string(value)?.lowercased() {
        case "ultralight": return .ultraLight
        case "thin": return .thin
        case "light": return .light
        case "regular": return .regular
        case "medium": return .medium
        case "semibold": return .semibold
        case "bold": return .bold
        case "heavy": return .heavy
        case "black": return .black
        default: return .semibold
        }
    }

    /// `shimmer` may be a bool shorthand (`true`/`false`) or a props object.
    private static func shimmer(from value: Any?, base: Shimmer) -> Shimmer {
        var config = base
        if let flag = CustomPropReader.bool(value) {
            config.isEnabled = flag
            return config
        }
        guard let dict = CustomPropReader.dictionary(value) else { return config }
        if let enabled = CustomPropReader.bool(dict["enabled"]) { config.isEnabled = enabled }
        if let color = CustomPropReader.color(dict["color"]) { config.color = color }
        if let duration = CustomPropReader.double(dict["duration"]) { config.duration = max(0.1, duration) }
        if let pause = CustomPropReader.double(dict["pause"] ?? dict["delay"]) { config.pause = max(0, pause) }
        if let bandWidth = CustomPropReader.cgFloat(dict["band_width"]) {
            config.bandWidth = min(1, max(0.05, bandWidth))
        }
        if let angle = CustomPropReader.cgFloat(dict["angle"]) { config.angle = angle }
        return config
    }

    /// `bounce` may be a bool shorthand (toggles both) or an object with
    /// optional `idle` and `press` entries (each a bool or a props object).
    private static func bounce(
        from value: Any?,
        idleBase: IdleBounce,
        pressBase: PressBounce
    ) -> (idle: IdleBounce, press: PressBounce) {
        var idle = idleBase
        var press = pressBase
        if let flag = CustomPropReader.bool(value) {
            idle.isEnabled = flag
            press.isEnabled = flag
            return (idle, press)
        }
        guard let dict = CustomPropReader.dictionary(value) else { return (idle, press) }
        idle = idleBounce(from: dict["idle"], base: idle)
        press = pressBounce(from: dict["press"], base: press)
        return (idle, press)
    }

    private static func idleBounce(from value: Any?, base: IdleBounce) -> IdleBounce {
        var config = base
        if let flag = CustomPropReader.bool(value) {
            config.isEnabled = flag
            return config
        }
        guard let dict = CustomPropReader.dictionary(value) else { return config }
        if let enabled = CustomPropReader.bool(dict["enabled"]) { config.isEnabled = enabled }
        if let scale = CustomPropReader.cgFloat(dict["scale"]) { config.scale = scale }
        if let period = CustomPropReader.double(dict["period"]) { config.period = max(0.1, period) }
        return config
    }

    private static func pressBounce(from value: Any?, base: PressBounce) -> PressBounce {
        var config = base
        if let flag = CustomPropReader.bool(value) {
            config.isEnabled = flag
            return config
        }
        guard let dict = CustomPropReader.dictionary(value) else { return config }
        if let enabled = CustomPropReader.bool(dict["enabled"]) { config.isEnabled = enabled }
        if let scale = CustomPropReader.cgFloat(dict["scale"]) { config.scale = scale }
        return config
    }
}

/// A native, animated button backing both `pnlight.cta_button` and
/// `pnlight.icon_button`: solid/gradient fill, an optional SF Symbol, a
/// repeating shimmer streak, an idle attention pulse, and a spring press
/// bounce. Taps are forwarded to `onTap`, which the renderer routes into the
/// action pipeline.
private final class NativeButtonView: UIControl {
    private enum AnimationKey {
        static let shimmer = "pnlight.button.shimmer"
        static let idle = "pnlight.button.idle"
    }

    private static let loadingAccessibilityLabel = "Loading"

    private let config: NativeButtonConfig
    private let onTap: (_ sender: UIView, _ url: String?, _ logId: String?) -> Void

    /// Carries the idle attention pulse, and nothing else. Keeping the transform
    /// off the custom view itself lets DivKit continue laying that view out
    /// without resetting an in-flight animation. This view deliberately does
    /// not clip, so the pulse can grow beyond the button's allocated bounds.
    private let pulseView = UIView()
    /// Carries the fill, shimmer, and content. The press bounce transforms this
    /// view; the idle pulse transforms `pulseView`, so the two never fight over
    /// the same layer's transform.
    private let contentView = UIView()
    /// Centers the icon and/or title; handles either alone or both together.
    private let contentStack = UIStackView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let gradientLayer = CAGradientLayer()
    private let shimmerLayer = CAGradientLayer()

    /// `loading` and `disabled` both make the button inert: no taps, no shimmer,
    /// no bounce.
    private var isInactive: Bool { config.isDisabled || config.isLoading }

    private var iconImage: UIImage? {
        guard let icon = config.icon else { return nil }
        let symbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: config.iconSize,
            weight: config.iconWeight
        )
        return UIImage(systemName: icon, withConfiguration: symbolConfiguration)?
            .withRenderingMode(.alwaysTemplate)
    }

    init(
        config: NativeButtonConfig,
        onTap: @escaping (_ sender: UIView, _ url: String?, _ logId: String?) -> Void
    ) {
        self.config = config
        self.onTap = onTap
        super.init(frame: .zero)
        setupSubviews()
        setupActions()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var intrinsicContentSize: CGSize {
        var contentWidth: CGFloat = 0
        var contentHeight: CGFloat = 0

        if let iconImage {
            contentWidth += iconImage.size.width
            contentHeight = max(contentHeight, iconImage.size.height)
        }

        if !config.title.isEmpty {
            let textSize = (config.title as NSString).size(withAttributes: [.font: config.font])
            contentWidth += ceil(textSize.width) + (iconImage == nil ? 0 : config.iconSpacing)
            contentHeight = max(contentHeight, ceil(textSize.height))
        }

        var size = CGSize(
            width: contentWidth + config.horizontalPadding * 2,
            height: contentHeight + config.verticalPadding * 2
        )

        // A circular button has to be square, or `wrap_content` would yield an
        // oval (SF Symbols are rarely square).
        if config.isCircular {
            let side = max(size.width, size.height)
            size = CGSize(width: side, height: side)
        }

        return size
    }

    private func setupSubviews() {
        backgroundColor = .clear
        clipsToBounds = false
        isEnabled = !isInactive

        // A disabled override color replaces the gradient entirely.
        let disabledFill = config.isDisabled ? config.disabledBackgroundColor : nil
        let fillColor = disabledFill ?? config.backgroundColor
        let titleColor = (config.isDisabled ? config.disabledTitleColor : nil) ?? config.titleColor
        let usesGradient = config.backgroundGradientEndColor != nil && disabledFill == nil

        contentView.isUserInteractionEnabled = false
        contentView.backgroundColor = usesGradient ? .clear : fillColor
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true
        contentView.alpha = config.isDisabled ? config.disabledAlpha : 1
        pulseView.isUserInteractionEnabled = false
        pulseView.clipsToBounds = false
        addSubview(pulseView)
        pulseView.addSubview(contentView)

        if usesGradient, let endColor = config.backgroundGradientEndColor {
            gradientLayer.colors = [config.backgroundColor.cgColor, endColor.cgColor]
            gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
            contentView.layer.addSublayer(gradientLayer)
        }

        let clear = config.shimmer.color.withAlphaComponent(0).cgColor
        shimmerLayer.colors = [clear, config.shimmer.color.cgColor, clear]
        shimmerLayer.locations = [0, 0.5, 1]
        let tilt = tan(config.shimmer.angle * .pi / 180)
        shimmerLayer.startPoint = CGPoint(x: 0, y: 0.5 - tilt / 2)
        shimmerLayer.endPoint = CGPoint(x: 1, y: 0.5 + tilt / 2)
        shimmerLayer.isHidden = !config.shimmer.isEnabled || isInactive
        contentView.layer.addSublayer(shimmerLayer)

        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.spacing = config.iconSpacing
        contentStack.isUserInteractionEnabled = false
        contentStack.isHidden = config.isLoading
        contentView.addSubview(contentStack)

        if let iconImage {
            iconView.image = iconImage
            iconView.tintColor = config.iconColor ?? titleColor
            iconView.contentMode = .scaleAspectFit
            iconView.setContentCompressionResistancePriority(.required, for: .horizontal)
            contentStack.addArrangedSubview(iconView)
        }

        if !config.title.isEmpty {
            titleLabel.text = config.title
            titleLabel.textColor = titleColor
            titleLabel.font = config.font
            titleLabel.textAlignment = .center
            titleLabel.numberOfLines = 1
            titleLabel.adjustsFontSizeToFitWidth = true
            titleLabel.minimumScaleFactor = 0.6
            // Let the label shrink rather than push the stack past the button.
            titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            contentStack.addArrangedSubview(titleLabel)
        }

        if config.isLoading {
            activityIndicator.style = config.loadingIndicatorStyle
            activityIndicator.color = config.loadingIndicatorColor ?? titleColor
            activityIndicator.hidesWhenStopped = false
            activityIndicator.startAnimating()
            contentView.addSubview(activityIndicator)
        }

        isAccessibilityElement = true
        accessibilityTraits = isInactive ? [.button, .notEnabled] : .button
        accessibilityLabel = resolvedAccessibilityLabel
    }

    /// Icon-only buttons have no title to fall back on, so the SF Symbol name is
    /// used as a last resort — markup should still set `accessibility_label`.
    private var resolvedAccessibilityLabel: String? {
        if let label = config.accessibilityLabel { return label }
        if config.isLoading { return Self.loadingAccessibilityLabel }
        return config.title.isEmpty ? config.icon : config.title
    }

    private func setupActions() {
        addTarget(self, action: #selector(handlePressDown), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(handlePressUpInside), for: .touchUpInside)
        addTarget(
            self,
            action: #selector(handlePressUp),
            for: [.touchUpOutside, .touchCancel, .touchDragExit]
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Drive layout through bounds/center so in-flight transforms on
        // `pulseView` / `contentView` survive (setting `.frame` under a
        // transform is UB).
        pulseView.bounds = CGRect(origin: .zero, size: bounds.size)
        pulseView.center = CGPoint(x: bounds.midX, y: bounds.midY)

        contentView.bounds = CGRect(origin: .zero, size: bounds.size)
        contentView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        contentView.layer.cornerRadius = config.isCircular
            ? min(contentView.bounds.width, contentView.bounds.height) / 2
            : config.cornerRadius

        gradientLayer.frame = contentView.bounds
        shimmerLayer.frame = contentView.bounds

        let available = CGSize(
            width: max(0, contentView.bounds.width - config.horizontalPadding * 2),
            height: max(0, contentView.bounds.height - config.verticalPadding * 2)
        )
        var stackSize = contentStack.systemLayoutSizeFitting(available)
        stackSize.width = min(stackSize.width, available.width)
        stackSize.height = min(stackSize.height, available.height)
        contentStack.frame = CGRect(
            x: (contentView.bounds.width - stackSize.width) / 2,
            y: (contentView.bounds.height - stackSize.height) / 2,
            width: stackSize.width,
            height: stackSize.height
        )

        activityIndicator.center = CGPoint(
            x: contentView.bounds.midX,
            y: contentView.bounds.midY
        )
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopAnimations()
        } else {
            startAnimations()
        }
    }

    @objc private func handleAppDidBecomeActive() {
        // CoreAnimation drops attached animations when the app backgrounds.
        guard window != nil else { return }
        startAnimations()
    }

    private func startAnimations() {
        // A loading or disabled CTA should sit still.
        guard !isInactive else { return }

        if config.shimmer.isEnabled {
            let bandWidth = Double(config.shimmer.bandWidth)
            let start: [Double] = [-bandWidth, -bandWidth / 2, 0]
            let end: [Double] = [1, 1 + bandWidth / 2, 1 + bandWidth]
            let total = config.shimmer.duration + config.shimmer.pause
            let sweepFraction = total > 0 ? config.shimmer.duration / total : 1

            let animation = CAKeyframeAnimation(keyPath: "locations")
            animation.values = [start, end, end].map { $0.map(NSNumber.init(value:)) }
            animation.keyTimes = [0, NSNumber(value: sweepFraction), 1]
            animation.timingFunctions = [
                CAMediaTimingFunction(name: .easeInEaseOut),
                CAMediaTimingFunction(name: .linear),
            ]
            animation.duration = total
            animation.repeatCount = .infinity
            synchronizeRepeatingAnimation(animation, on: shimmerLayer, duration: total)
            shimmerLayer.removeAnimation(forKey: AnimationKey.shimmer)
            shimmerLayer.add(animation, forKey: AnimationKey.shimmer)
        }

        if config.idleBounce.isEnabled {
            let scale = config.idleBounce.scale
            let animation = CAKeyframeAnimation(keyPath: "transform.scale")
            animation.values = [1.0, scale, 1.0, 1.0]
            animation.keyTimes = [0, 0.18, 0.36, 1.0]
            animation.timingFunctions = [
                CAMediaTimingFunction(name: .easeOut),
                CAMediaTimingFunction(name: .easeIn),
                CAMediaTimingFunction(name: .linear),
            ]
            animation.duration = config.idleBounce.period
            animation.repeatCount = .infinity
            synchronizeRepeatingAnimation(
                animation,
                on: pulseView.layer,
                duration: config.idleBounce.period
            )
            pulseView.layer.removeAnimation(forKey: AnimationKey.idle)
            pulseView.layer.add(animation, forKey: AnimationKey.idle)
        }
    }

    private func stopAnimations() {
        shimmerLayer.removeAnimation(forKey: AnimationKey.shimmer)
        pulseView.layer.removeAnimation(forKey: AnimationKey.idle)
    }

    @objc private func handlePressDown() {
        animatePress(to: config.pressBounce.isEnabled ? config.pressBounce.scale : 1, isDown: true)
    }

    @objc private func handlePressUpInside() {
        animatePress(to: 1, isDown: false)
        onTap(self, config.url, config.logId)
    }

    @objc private func handlePressUp() {
        animatePress(to: 1, isDown: false)
    }

    private func animatePress(to scale: CGFloat, isDown: Bool) {
        guard config.pressBounce.isEnabled else { return }
        UIView.animate(
            withDuration: isDown ? 0.12 : 0.35,
            delay: 0,
            usingSpringWithDamping: isDown ? 0.9 : 0.55,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.contentView.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
    }
}

/// The Liquid Glass variant, built on a real `UIButton` with a native glass
/// configuration.
///
/// Painting a `UIGlassEffect` into a `UIVisualEffectView` behind our own content
/// gets the *look* but never the *feel* — the material's press deformation, its
/// highlight tracking, and the way neighbouring glass elements morph together
/// are all owned by `UIButton`, not by the effect. So the glass path hands the
/// whole control to UIKit and maps `custom_props` onto its configuration.
@available(iOS 26.0, *)
private final class NativeGlassButtonView: UIView {
    private static let idleAnimationKey = "pnlight.button.idle"
    private static let loadingAccessibilityLabel = "Loading"

    private let config: NativeButtonConfig
    private let onTap: (_ sender: UIView, _ url: String?, _ logId: String?) -> Void
    /// Isolates the idle transform from both DivKit's host view and UIKit's
    /// press deformation on the glass button.
    private let pulseView = UIView()
    private let button: UIButton

    init(
        config: NativeButtonConfig,
        onTap: @escaping (_ sender: UIView, _ url: String?, _ logId: String?) -> Void
    ) {
        self.config = config
        self.onTap = onTap
        self.button = UIButton(configuration: Self.makeConfiguration(for: config))
        super.init(frame: .zero)

        // `loading` and `disabled` both make the button inert. UIKit draws its
        // own disabled glass, so `disabled_alpha` is left to the system here.
        button.isEnabled = !(config.isDisabled || config.isLoading)
        button.accessibilityLabel = resolvedAccessibilityLabel
        button.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                self.onTap(self, self.config.url, self.config.logId)
            },
            for: .touchUpInside
        )
        // Constraints rather than manual framing: UIKit resolves the capsule
        // radius and the material's shadow path from the button's own layout.
        // Neither wrapper clips, so the idle pulse can render beyond the
        // component bounds.
        clipsToBounds = false
        pulseView.clipsToBounds = false
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pulseView)
        pulseView.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: pulseView.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: pulseView.trailingAnchor),
            button.topAnchor.constraint(equalTo: pulseView.topAnchor),
            button.bottomAnchor.constraint(equalTo: pulseView.bottomAnchor),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private static func makeConfiguration(for config: NativeButtonConfig) -> UIButton.Configuration {
        var configuration: UIButton.Configuration
        switch (config.glass.style, config.glass.isProminent) {
        case (.regular, false): configuration = .glass()
        case (.regular, true): configuration = .prominentGlass()
        case (.clear, false): configuration = .clearGlass()
        case (.clear, true): configuration = .prominentClearGlass()
        }

        // Matches the non-glass button: the spinner replaces the content rather
        // than crowding in beside it.
        if config.isLoading {
            configuration.showsActivityIndicator = true
            if let color = config.loadingIndicatorColor {
                configuration.activityIndicatorColorTransformer = .init { _ in color }
            }
        } else {
            if !config.title.isEmpty {
                var attributes = AttributeContainer()
                attributes.font = config.font
                configuration.attributedTitle = AttributedString(config.title, attributes: attributes)
            }

            if let icon = config.icon {
                configuration.image = UIImage(systemName: icon)
                configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
                    pointSize: config.iconSize,
                    weight: config.iconWeight
                )
                configuration.imagePadding = config.iconSpacing
                if let iconColor = config.iconColor {
                    configuration.imageColorTransformer = .init { _ in iconColor }
                }
            }
        }

        configuration.baseForegroundColor = config.titleColor
        // Prominent glass fills with this; regular glass tints the material.
        configuration.baseBackgroundColor = config.glass.tint
        // `.capsule` derives its own radius; leaving `background.cornerRadius`
        // set alongside it leaves the material and its shadow on different shapes.
        if config.isCircular {
            configuration.cornerStyle = .capsule
        } else {
            configuration.cornerStyle = .fixed
            configuration.background.cornerRadius = config.cornerRadius
        }
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: config.verticalPadding,
            leading: config.horizontalPadding,
            bottom: config.verticalPadding,
            trailing: config.horizontalPadding
        )
        return configuration
    }

    private var resolvedAccessibilityLabel: String? {
        if let label = config.accessibilityLabel { return label }
        if config.isLoading { return Self.loadingAccessibilityLabel }
        return config.title.isEmpty ? config.icon : config.title
    }

    override var intrinsicContentSize: CGSize {
        var size = button.intrinsicContentSize
        // A circular button has to be square, or `wrap_content` would yield an
        // oval (SF Symbols are rarely square).
        if config.isCircular {
            let side = max(size.width, size.height)
            size = CGSize(width: side, height: side)
        }
        return size
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Use bounds/center so a layout pass cannot reset the pulse transform.
        pulseView.bounds = CGRect(origin: .zero, size: bounds.size)
        pulseView.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stopIdleBounce() } else { startIdleBounce() }
    }

    @objc private func handleAppDidBecomeActive() {
        // CoreAnimation drops attached animations when the app backgrounds.
        guard window != nil else { return }
        startIdleBounce()
    }

    /// The press bounce is UIKit's to draw here, but the idle attention pulse
    /// still isn't — it scales the intermediate wrapper, leaving both DivKit's
    /// custom-view frame and the button's own transform free.
    private func startIdleBounce() {
        guard config.idleBounce.isEnabled, button.isEnabled else { return }
        let animation = CAKeyframeAnimation(keyPath: "transform.scale")
        animation.values = [1.0, config.idleBounce.scale, 1.0, 1.0]
        animation.keyTimes = [0, 0.18, 0.36, 1.0]
        animation.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeIn),
            CAMediaTimingFunction(name: .linear),
        ]
        animation.duration = config.idleBounce.period
        animation.repeatCount = .infinity
        synchronizeRepeatingAnimation(
            animation,
            on: pulseView.layer,
            duration: config.idleBounce.period
        )
        pulseView.layer.removeAnimation(forKey: Self.idleAnimationKey)
        pulseView.layer.add(animation, forKey: Self.idleAnimationKey)
    }

    private func stopIdleBounce() {
        pulseView.layer.removeAnimation(forKey: Self.idleAnimationKey)
    }
}

private struct NativePrependListItem: Equatable {
    let title: String
    let body: String
    let iconPreview: String

    var image: UIImage? {
        guard let comma = iconPreview.firstIndex(of: ","),
              iconPreview[..<comma].contains(";base64"),
              let data = Data(base64Encoded: String(iconPreview[iconPreview.index(after: comma)...])) else {
            return nil
        }
        return UIImage(data: data)
    }
}

private struct NativePrependListStyle: Equatable {
    var statusText = ""
    var cardBackgroundColor = UIColor(
        red: 254.0 / 255.0,
        green: 254.0 / 255.0,
        blue: 254.0 / 255.0,
        alpha: 1
    )
    var titleColor = UIColor(red: 28.0 / 255.0, green: 28.0 / 255.0, blue: 30.0 / 255.0, alpha: 1)
    var bodyColor = UIColor(red: 58.0 / 255.0, green: 58.0 / 255.0, blue: 60.0 / 255.0, alpha: 1)
    var statusColor = UIColor.systemRed
    var cornerRadius: CGFloat = 20
    var titleFontSize: CGFloat = 14
    var titleFontWeight = UIFont.Weight.bold
    var bodyFontSize: CGFloat = 12
    var bodyFontWeight = UIFont.Weight.light
    var statusFontSize: CGFloat = 12
    var statusFontWeight = UIFont.Weight.semibold
    var listHorizontalPadding: CGFloat = 4
    var rowSpacing: CGFloat = 15
    var bottomPadding: CGFloat = 20
    var rowHorizontalPadding: CGFloat = 16
    var rowVerticalPadding: CGFloat = 16
    var iconSize: CGFloat = 20
    var iconTextSpacing: CGFloat = 13
    var textStatusSpacing: CGFloat = 13
    var animationDuration: TimeInterval = 0.36
    var slideDistance: CGFloat = 8
    var fadesNewRows = true
    var slidesNewRows = true
    var showsScrollIndicator = false

    static func make(from props: [String: Any]) -> NativePrependListStyle {
        var style = NativePrependListStyle()
        style.statusText = props["status_text"] as? String ?? style.statusText
        style.cardBackgroundColor = CustomPropReader.color(props["card_background_color"])
            ?? style.cardBackgroundColor
        style.titleColor = CustomPropReader.color(props["title_color"]) ?? style.titleColor
        style.bodyColor = CustomPropReader.color(props["body_color"]) ?? style.bodyColor
        style.statusColor = CustomPropReader.color(props["status_color"]) ?? style.statusColor
        style.cornerRadius = nonnegative(props["corner_radius"], default: style.cornerRadius)
        style.titleFontSize = positive(props["title_font_size"], default: style.titleFontSize)
        style.titleFontWeight = fontWeight(props["title_font_weight"], default: style.titleFontWeight)
        style.bodyFontSize = positive(props["body_font_size"], default: style.bodyFontSize)
        style.bodyFontWeight = fontWeight(props["body_font_weight"], default: style.bodyFontWeight)
        style.statusFontSize = positive(props["status_font_size"], default: style.statusFontSize)
        style.statusFontWeight = fontWeight(props["status_font_weight"], default: style.statusFontWeight)
        style.listHorizontalPadding = nonnegative(
            props["list_horizontal_padding"],
            default: style.listHorizontalPadding
        )
        style.rowSpacing = nonnegative(props["row_spacing"], default: style.rowSpacing)
        style.bottomPadding = nonnegative(props["bottom_padding"], default: style.bottomPadding)
        style.rowHorizontalPadding = nonnegative(
            props["row_horizontal_padding"],
            default: style.rowHorizontalPadding
        )
        style.rowVerticalPadding = nonnegative(
            props["row_vertical_padding"],
            default: style.rowVerticalPadding
        )
        style.iconSize = nonnegative(props["icon_size"], default: style.iconSize)
        style.iconTextSpacing = nonnegative(props["icon_text_spacing"], default: style.iconTextSpacing)
        style.textStatusSpacing = nonnegative(
            props["text_status_spacing"],
            default: style.textStatusSpacing
        )
        style.animationDuration = max(
            0,
            CustomPropReader.double(props["animation_duration"]) ?? style.animationDuration
        )
        style.slideDistance = nonnegative(props["slide_distance"], default: style.slideDistance)
        style.fadesNewRows = CustomPropReader.bool(props["fade"]) ?? style.fadesNewRows
        style.slidesNewRows = CustomPropReader.bool(props["slide"]) ?? style.slidesNewRows
        style.showsScrollIndicator = CustomPropReader.bool(props["shows_scroll_indicator"])
            ?? style.showsScrollIndicator
        return style
    }

    private static func positive(_ value: Any?, default defaultValue: CGFloat) -> CGFloat {
        max(1, CustomPropReader.cgFloat(value) ?? defaultValue)
    }

    private static func nonnegative(_ value: Any?, default defaultValue: CGFloat) -> CGFloat {
        max(0, CustomPropReader.cgFloat(value) ?? defaultValue)
    }

    private static func fontWeight(_ value: Any?, default defaultWeight: UIFont.Weight) -> UIFont.Weight {
        switch CustomPropReader.string(value)?.lowercased() {
        case "ultralight": return .ultraLight
        case "thin": return .thin
        case "light": return .light
        case "regular": return .regular
        case "medium": return .medium
        case "semibold": return .semibold
        case "bold": return .bold
        case "heavy": return .heavy
        case "black": return .black
        default: return defaultWeight
        }
    }
}

private final class NativePrependListRowView: UIView {
    private static let unconstrainedSize = CGSize(
        width: CGFloat.greatestFiniteMagnitude,
        height: CGFloat.greatestFiniteMagnitude
    )

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let statusLabel = UILabel()

    private let style: NativePrependListStyle

    init(item: NativePrependListItem, style: NativePrependListStyle) {
        self.style = style
        super.init(frame: .zero)

        backgroundColor = style.cardBackgroundColor
        layer.cornerRadius = style.cornerRadius
        layer.cornerCurve = .continuous
        clipsToBounds = true

        iconView.image = item.image
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .secondaryLabel

        titleLabel.text = item.title
        titleLabel.font = .systemFont(ofSize: style.titleFontSize, weight: style.titleFontWeight)
        titleLabel.textColor = style.titleColor
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping

        bodyLabel.text = item.body
        bodyLabel.font = .systemFont(ofSize: style.bodyFontSize, weight: style.bodyFontWeight)
        bodyLabel.textColor = style.bodyColor
        bodyLabel.numberOfLines = 0
        bodyLabel.lineBreakMode = .byWordWrapping

        statusLabel.text = style.statusText
        statusLabel.font = .systemFont(ofSize: style.statusFontSize, weight: style.statusFontWeight)
        statusLabel.textColor = style.statusColor
        statusLabel.numberOfLines = 1

        [iconView, titleLabel, bodyLabel, statusLabel].forEach(addSubview)

        isAccessibilityElement = true
        accessibilityLabel = [item.title, item.body, style.statusText]
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func fittingHeight(for width: CGFloat) -> CGFloat {
        let statusWidth = ceil(statusLabel.sizeThatFits(Self.unconstrainedSize).width)
        let textWidth = max(
            0,
            width
                - style.rowHorizontalPadding
                - style.iconSize
                - style.iconTextSpacing
                - style.textStatusSpacing
                - statusWidth
                - style.rowHorizontalPadding
        )
        let constraint = CGSize(width: textWidth, height: .greatestFiniteMagnitude)
        let titleHeight = ceil(titleLabel.sizeThatFits(constraint).height)
        let bodyHeight = ceil(bodyLabel.sizeThatFits(constraint).height)
        let contentHeight = max(
            style.iconSize,
            titleHeight + bodyHeight,
            ceil(statusLabel.intrinsicContentSize.height)
        )
        return contentHeight + style.rowVerticalPadding * 2
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let statusSize = statusLabel.sizeThatFits(Self.unconstrainedSize)
        let statusWidth = ceil(statusSize.width)
        let statusHeight = ceil(statusSize.height)
        let statusX = bounds.width - style.rowHorizontalPadding - statusWidth
        let textX = style.rowHorizontalPadding + style.iconSize + style.iconTextSpacing
        let textWidth = max(0, statusX - style.textStatusSpacing - textX)
        let constraint = CGSize(width: textWidth, height: .greatestFiniteMagnitude)
        let titleHeight = ceil(titleLabel.sizeThatFits(constraint).height)
        let bodyHeight = ceil(bodyLabel.sizeThatFits(constraint).height)
        let textHeight = titleHeight + bodyHeight
        let textY = floor((bounds.height - textHeight) / 2)

        iconView.frame = CGRect(
            x: style.rowHorizontalPadding,
            y: floor((bounds.height - style.iconSize) / 2),
            width: style.iconSize,
            height: style.iconSize
        )
        titleLabel.frame = CGRect(x: textX, y: textY, width: textWidth, height: titleHeight)
        bodyLabel.frame = CGRect(
            x: textX,
            y: textY + titleHeight,
            width: textWidth,
            height: bodyHeight
        )
        statusLabel.frame = CGRect(
            x: statusX,
            y: floor((bounds.height - statusHeight) / 2),
            width: statusWidth,
            height: statusHeight
        )
    }
}

/// A persistent UIKit list used when DivKit gallery cells cannot retain enough
/// identity to animate variable-driven prepends on iOS.
private final class NativePrependListView: UIView {
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private var rows: [NativePrependListRowView] = []
    private var items: [NativePrependListItem] = []
    private var targetCount = 0
    private var displayedCount = 0
    private var reducedMotion = false
    private var style = NativePrependListStyle()
    private var hasCompletedInitialLayout = false
    private var lastLayoutWidth: CGFloat = 0
    private var isAnimatingRows = false

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .clear
        clipsToBounds = true
        scrollView.backgroundColor = .clear
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        scrollView.contentInsetAdjustmentBehavior = .never
        addSubview(scrollView)
        scrollView.addSubview(contentView)

        isAccessibilityElement = false
        accessibilityElementsHidden = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        count: Int,
        items: [NativePrependListItem],
        reducedMotion: Bool,
        style: NativePrependListStyle
    ) {
        let itemsChanged = self.items != items
        let styleChanged = self.style != style
        self.items = items
        self.reducedMotion = reducedMotion
        self.style = style
        scrollView.showsVerticalScrollIndicator = style.showsScrollIndicator
        targetCount = min(max(count, 0), items.count)

        guard hasCompletedInitialLayout, bounds.width > 0, window != nil else {
            setNeedsLayout()
            return
        }

        if itemsChanged || styleChanged || targetCount < displayedCount || targetCount - displayedCount > 1 {
            rebuildRows(count: targetCount)
            layoutRowsImmediately()
        } else if targetCount > displayedCount {
            prependNextRow(animated: !reducedMotion)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds

        let widthChanged = abs(lastLayoutWidth - bounds.width) > 0.5
        guard !isAnimatingRows || widthChanged else { return }

        if !hasCompletedInitialLayout || widthChanged {
            rebuildRows(count: targetCount)
            hasCompletedInitialLayout = true
            lastLayoutWidth = bounds.width
        }
        layoutRowsImmediately()
    }

    private func rebuildRows(count: Int) {
        rows.forEach { $0.removeFromSuperview() }
        displayedCount = min(max(count, 0), items.count)
        rows = (0..<displayedCount).reversed().map { itemIndex in
            let row = NativePrependListRowView(item: items[itemIndex], style: style)
            contentView.addSubview(row)
            return row
        }
    }

    private func prependNextRow(animated: Bool) {
        guard displayedCount < targetCount, displayedCount < items.count else { return }

        let newRow = NativePrependListRowView(item: items[displayedCount], style: style)
        displayedCount += 1
        rows.insert(newRow, at: 0)
        contentView.addSubview(newRow)

        let finalFrames = calculatedFrames()
        updateContentGeometry(frames: finalFrames)

        newRow.frame = finalFrames[0]
        newRow.alpha = animated && style.fadesNewRows ? 0 : 1
        newRow.transform = animated && style.slidesNewRows
            ? CGAffineTransform(translationX: 0, y: -style.slideDistance)
            : .identity
        newRow.layoutIfNeeded()

        guard animated else {
            apply(frames: finalFrames)
            return
        }

        isAnimatingRows = true
        UIView.animate(
            withDuration: style.animationDuration,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            self.apply(frames: finalFrames)
            newRow.alpha = 1
            newRow.transform = .identity
        } completion: { [weak self] _ in
            self?.isAnimatingRows = false
        }
    }

    private func layoutRowsImmediately() {
        let frames = calculatedFrames()
        updateContentGeometry(frames: frames)
        apply(frames: frames)
    }

    private func calculatedFrames() -> [CGRect] {
        let rowWidth = max(0, bounds.width - style.listHorizontalPadding * 2)
        var y: CGFloat = 0
        return rows.map { row in
            let height = row.fittingHeight(for: rowWidth)
            let frame = CGRect(x: style.listHorizontalPadding, y: y, width: rowWidth, height: height)
            y += height + style.rowSpacing
            return frame
        }
    }

    private func updateContentGeometry(frames: [CGRect]) {
        let lastMaxY = frames.last?.maxY ?? 0
        let contentHeight = max(bounds.height, lastMaxY + style.bottomPadding)
        contentView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: contentHeight)
        scrollView.contentSize = CGSize(width: bounds.width, height: contentHeight)
        if scrollView.contentOffset.y != 0 {
            scrollView.setContentOffset(.zero, animated: false)
        }
    }

    private func apply(frames: [CGRect]) {
        for (row, frame) in zip(rows, frames) {
            row.frame = frame
            row.layoutIfNeeded()
        }
    }
}

private final class NativePrependListBlockFactory {
    static let customType = "pnlight.animated_prepend_list"
    static let legacyCustomType = "pnlight.animated_threat_list"
    private static let maxCachedViewCount = 32

    // The factory lives for the renderer's lifetime. Keeping these views strongly
    // guarantees that DivKit remodelling cannot discard the row animation state
    // between two count-variable updates. The bounded LRU order prevents remote
    // payloads with varying instance IDs from retaining views without limit.
    private var cachedViews: [String: NativePrependListView] = [:]
    private var cachedViewOrder: [String] = []

    private func view(for instanceId: String) -> NativePrependListView {
        if let cached = cachedViews[instanceId] {
            cachedViewOrder.removeAll { $0 == instanceId }
            cachedViewOrder.append(instanceId)
            return cached
        }

        let view = NativePrependListView()
        cachedViews[instanceId] = view
        cachedViewOrder.append(instanceId)

        if cachedViewOrder.count > Self.maxCachedViewCount {
            let evictedId = cachedViewOrder.removeFirst()
            cachedViews.removeValue(forKey: evictedId)
        }

        return view
    }

    func makeBlock(
        props: [String: Any],
        data: DivCustomData,
        context: DivBlockModelingContext
    ) -> Block {
        let instanceId = CustomPropReader.string(props["instance_id"])
            ?? "pnlight.animated_prepend_list.default"
        if props["instance_id"] == nil {
            context.addWarning(message: "pnlight.animated_prepend_list should provide instance_id")
        }

        let rawItems = props["items"] as? [Any] ?? []
        let items = rawItems.compactMap { value -> NativePrependListItem? in
            guard let item = value as? [String: Any],
                  let title = CustomPropReader.string(item["title"]),
                  let body = CustomPropReader.string(item["body"]),
                  let iconPreview = CustomPropReader.string(item["icon_preview"]) else {
                return nil
            }
            return NativePrependListItem(title: title, body: body, iconPreview: iconPreview)
        }
        if items.isEmpty {
            context.addError(message: "pnlight.animated_prepend_list requires non-empty items")
        } else if items.count != rawItems.count {
            context.addError(message: "pnlight.animated_prepend_list contains an invalid item")
        }

        let view = view(for: instanceId)

        let count = Int(CustomPropReader.double(props["count"]) ?? 0)
        let reducedMotion = CustomPropReader.bool(props["reduced_motion"]) ?? false
        let style = NativePrependListStyle.make(from: props)
        view.update(count: count, items: items, reducedMotion: reducedMotion, style: style)

        return GenericViewBlock(
            content: .view(view),
            width: blockTrait(from: data.widthTrait, intrinsicSize: 0),
            height: blockTrait(from: data.heightTrait, intrinsicSize: 0)
        )
    }
}

/// Renders `pnlight.cta_button` and `pnlight.icon_button`, forwarding taps to
/// `onTap`.
private final class NativeOverflowContainerView: UIView {
    private let contentView: UIView
    private weak var overflowBoundary: UIView?
    private var overflowUpdateScheduled = false

    init(contentView: UIView, overflowBoundary: UIView?) {
        self.contentView = contentView
        self.overflowBoundary = overflowBoundary
        super.init(frame: .zero)

        backgroundColor = .clear
        clipsToBounds = false
        addSubview(contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        contentView.intrinsicContentSize
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        allowOverflowThroughDivKitWrappers()
        scheduleOverflowUpdate()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        allowOverflowThroughDivKitWrappers()
        scheduleOverflowUpdate()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentView.bounds = CGRect(origin: .zero, size: bounds.size)
        contentView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        allowOverflowThroughDivKitWrappers()
        scheduleOverflowUpdate()
    }

    /// DivKit wraps every `custom` block in a clipping `ContainerBlock`, even
    /// when the native content itself does not clip. Open only the wrappers on
    /// this component's branch; retain gallery/scroll clipping and never cross
    /// the renderer's DivView boundary.
    private func allowOverflowThroughDivKitWrappers() {
        var ancestor = superview
        while let view = ancestor, view !== overflowBoundary, !(view is UIScrollView) {
            view.clipsToBounds = false
            ancestor = view.superview
        }
    }

    /// DivKit configures the outer ContainerBlock after attaching its child,
    /// which can turn clipping back on after `didMoveToSuperview`. Re-apply at
    /// the end of that run-loop turn, once the wrapper configuration is done.
    private func scheduleOverflowUpdate() {
        guard !overflowUpdateScheduled else { return }
        overflowUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.overflowUpdateScheduled = false
            self.allowOverflowThroughDivKitWrappers()
        }
    }
}

private final class NativeButtonBlockFactory {
    static let ctaCustomType = "pnlight.cta_button"
    static let iconCustomType = "pnlight.icon_button"

    var onTap: ((_ url: String?, _ logId: String?) -> Void)?
    weak var overflowBoundary: UIView?

    func makeBlock(
        kind: NativeButtonConfig.Kind,
        props: [String: Any],
        actionSequence: NativeButtonActionSequence?,
        data: DivCustomData,
        context: DivBlockModelingContext
    ) -> Block {
        let config = NativeButtonConfig.make(from: props, kind: kind)

        // Surface a bad SF Symbol name in the card's errors rather than
        // silently rendering an empty button.
        if let icon = config.icon, UIImage(systemName: icon) == nil {
            context.addError(message: "Unknown SF Symbol '\(icon)'")
        }

        let forwardTap: (UIView, String?, String?) -> Void = {
            [weak self] sender, url, logId in
            if let actionSequence {
                actionSequence.execute(sender: sender)
            } else {
                self?.onTap?(url, logId)
            }
        }
        let button: UIView
        if #available(iOS 26.0, *), config.glass.isEnabled {
            button = NativeGlassButtonView(config: config, onTap: forwardTap)
        } else {
            button = NativeButtonView(config: config, onTap: forwardTap)
        }
        let overflowContainer = NativeOverflowContainerView(
            contentView: button,
            overflowBoundary: overflowBoundary
        )
        let intrinsicSize = overflowContainer.intrinsicContentSize
        return GenericViewBlock(
            content: .view(overflowContainer),
            width: blockTrait(from: data.widthTrait, intrinsicSize: intrinsicSize.width),
            height: blockTrait(from: data.heightTrait, intrinsicSize: intrinsicSize.height)
        )
    }
}

/// Dispatches DivKit `custom` nodes to the matching PNLight native component.
/// Add new native components here by matching their `custom_type`.
private final class PNLightCustomBlockFactory: DivCustomBlockFactory {
    /// Forwarded taps from interactive native components (the CTA and icon
    /// buttons).
    var onAction: ((_ url: String?, _ logId: String?) -> Void)? {
        didSet { buttonFactory.onTap = onAction }
    }
    weak var overflowBoundary: UIView? {
        didSet { buttonFactory.overflowBoundary = overflowBoundary }
    }

    private let circularLoaderFactory = CircularLoaderBlockFactory()
    private let buttonFactory = NativeButtonBlockFactory()
    private let prependListFactory = NativePrependListBlockFactory()

    func makeBlock(data: DivCustomData, context: DivBlockModelingContext) -> Block {
        var rawProps = data.data
        let actionSequence = NativeButtonActionSequence.make(
            from: rawProps.removeValue(forKey: pnlightNativeButtonActionsKey),
            context: context
        )
        if data.name == NativePrependListBlockFactory.customType ||
            data.name == NativePrependListBlockFactory.legacyCustomType,
           let countVariable = CustomPropReader.string(rawProps["count_variable"]) {
            // Keep the cross-platform contract compatible with DivKit Web,
            // where expressions embedded directly in custom_props are not
            // reactive. Resolving the named variable here also registers the
            // dependency that makes native DivKit remodel on each increment.
            rawProps["count"] = "@{\(countVariable)}"
        }
        let props = CustomPropReader.resolvingExpressions(
            rawProps,
            with: context.expressionResolver
        )

        switch data.name {
        case CircularLoaderBlockFactory.customType:
            return circularLoaderFactory.makeBlock(props: props, data: data, context: context)
        case NativeButtonBlockFactory.ctaCustomType:
            return buttonFactory.makeBlock(
                kind: .cta,
                props: props,
                actionSequence: actionSequence,
                data: data,
                context: context
            )
        case NativeButtonBlockFactory.iconCustomType:
            return buttonFactory.makeBlock(
                kind: .icon,
                props: props,
                actionSequence: actionSequence,
                data: data,
                context: context
            )
        case NativePrependListBlockFactory.customType,
             NativePrependListBlockFactory.legacyCustomType:
            return prependListFactory.makeBlock(props: props, data: data, context: context)
        default:
            context.addError(message: "Unsupported PNLight custom type '\(data.name)'")
            return EmptyBlock.zeroSized
        }
    }
}

struct RemoteUiActionPayload {
    let url: String
    let scheme: String
    let path: String
    let params: [String: String]
    let logId: String
    let action: String?

    init(action: DivActionInfo) {
        let resolvedUrl = action.url
        let components = resolvedUrl.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        }

        var extractedParams: [String: String] = [:]
        components?.queryItems?.forEach { extractedParams[$0.name] = $0.value ?? "" }

        url = resolvedUrl?.absoluteString ?? ""
        scheme = components?.scheme ?? ""
        path = components?.path ?? ""
        params = extractedParams
        logId = action.logId
        self.action = nil
    }

    init(customAction: String) {
        url = ""
        scheme = ""
        path = ""
        params = [:]
        logId = customAction
        action = customAction
    }

    /// Builds a payload from a native component tap, mirroring how a DivKit
    /// `DivActionInfo` URL is decoded so consumers see a consistent shape.
    init(url: URL, logId: String) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        var extractedParams: [String: String] = [:]
        components?.queryItems?.forEach { extractedParams[$0.name] = $0.value ?? "" }

        self.url = url.absoluteString
        scheme = components?.scheme ?? ""
        path = components?.path ?? ""
        params = extractedParams
        self.logId = logId
        action = nil
    }

    func asDictionary() -> [String: Any] {
        var payload: [String: Any] = ["logId": logId]

        if let action = action {
            payload["action"] = action
        }

        if !url.isEmpty {
            payload["url"] = url
            payload["scheme"] = scheme
            payload["path"] = path
            if !params.isEmpty {
                payload["params"] = params
            }
        }

        return payload
    }
}

// MARK: - Server-driven flows

/// Versions PNLight's JSON envelope independently from the SDK package.
/// Documents without this field are legacy v1 documents and must retain the
/// rendering behavior they had before PNLight extensions were introduced.
fileprivate enum PNLightRemoteUiSchema {
    static let legacyVersion = 1
    static let currentVersion = 2

    static func parse(from root: [String: Any]?) throws -> Int {
        guard let rawValue = root?["schemaVersion"] else {
            return legacyVersion
        }
        guard !(rawValue is Bool),
              !(rawValue is String),
              let version = CustomPropReader.double(rawValue),
              version.isFinite,
              version.rounded() == version,
              version >= Double(Int.min),
              version <= Double(Int.max) else {
            throw PNLightRemoteUiSchemaError.invalidVersion
        }
        let integerVersion = Int(version)
        guard integerVersion >= legacyVersion,
              integerVersion <= currentVersion else {
            throw PNLightRemoteUiSchemaError.unsupportedVersion(integerVersion)
        }
        return integerVersion
    }
}

private enum PNLightRemoteUiSchemaError: LocalizedError {
    case invalidVersion
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .invalidVersion:
            return "Invalid PNLight schemaVersion: expected an integer"
        case let .unsupportedVersion(version):
            return "Unsupported PNLight schemaVersion \(version); this SDK supports versions 1...\(PNLightRemoteUiSchema.currentVersion)"
        }
    }
}

/// Native dialogs declared by a Remote UI document. Buttons intentionally
/// retain their action dictionaries so the renderer can send them through
/// DivKit's own action handler with the current card's variable/state context.
fileprivate struct PNLightDialogDefinition {
    struct Button {
        enum Style: String {
            case `default`
            case cancel
            case destructive
        }

        let title: String
        let style: Style
        let actions: [[String: Any]]
    }

    enum Style: String {
        case alert
        case actionSheet = "action_sheet"
    }

    let style: Style
    let title: String?
    let message: String?
    let buttons: [Button]

    static func parseDefinitions(_ value: Any?) throws -> [String: PNLightDialogDefinition] {
        guard let value else { return [:] }
        guard let objects = value as? [String: Any] else {
            throw PNLightDialogError.invalidConfiguration("'dialogs' must be an object")
        }
        guard objects.count <= 32 else {
            throw PNLightDialogError.invalidConfiguration(
                "'dialogs' cannot contain more than 32 definitions"
            )
        }

        var definitions: [String: PNLightDialogDefinition] = [:]
        for (id, rawDefinition) in objects {
            guard id.isEmpty == false,
                  let dictionary = rawDefinition as? [String: Any],
                  let styleName = CustomPropReader.string(dictionary["style"]),
                  let style = Style(rawValue: styleName) else {
                throw PNLightDialogError.invalidConfiguration(
                    "Dialog '\(id)' must have style 'alert' or 'action_sheet'"
                )
            }

            let title = CustomPropReader.string(dictionary["title"])
            let message = CustomPropReader.string(dictionary["message"])
            guard title != nil || message != nil else {
                throw PNLightDialogError.invalidConfiguration(
                    "Dialog '\(id)' must have a title or message"
                )
            }
            guard let rawButtons = dictionary["buttons"] as? [[String: Any]],
                  rawButtons.isEmpty == false,
                  rawButtons.count <= 20 else {
                throw PNLightDialogError.invalidConfiguration(
                    "Dialog '\(id)' must contain 1...20 buttons"
                )
            }

            var cancelButtonCount = 0
            let buttons = try rawButtons.enumerated().map { index, rawButton -> Button in
                guard let buttonTitle = CustomPropReader.string(rawButton["title"]) else {
                    throw PNLightDialogError.invalidConfiguration(
                        "Dialog '\(id)' button \(index) is missing a title"
                    )
                }
                let buttonStyle = CustomPropReader.string(rawButton["style"])
                    .flatMap(Button.Style.init(rawValue:)) ?? .default
                if buttonStyle == .cancel {
                    cancelButtonCount += 1
                }

                let actions: [[String: Any]]
                if let value = rawButton["actions"] {
                    guard let dictionaries = value as? [[String: Any]],
                          dictionaries.count <= 32,
                          dictionaries.allSatisfy(JSONSerialization.isValidJSONObject) else {
                        throw PNLightDialogError.invalidConfiguration(
                            "Dialog '\(id)' button \(index) has an invalid 'actions' array"
                        )
                    }
                    actions = dictionaries
                } else {
                    actions = []
                }
                return Button(title: buttonTitle, style: buttonStyle, actions: actions)
            }

            guard cancelButtonCount <= 1 else {
                throw PNLightDialogError.invalidConfiguration(
                    "Dialog '\(id)' cannot contain more than one cancel button"
                )
            }
            definitions[id] = PNLightDialogDefinition(
                style: style,
                title: title,
                message: message,
                buttons: buttons
            )
        }
        return definitions
    }
}

private enum PNLightDialogError: LocalizedError {
    case invalidConfiguration(String)

    var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message):
            return "Invalid PNLight dialogs: \(message)"
        }
    }
}

/// Reference viewport used to expose document-level linear scaling factors.
/// Values are logical UIKit points, never physical pixels.
fileprivate struct PNLightReferenceSizeConfiguration {
    let width: CGFloat
    let height: CGFloat

    static func parse(from root: [String: Any]) throws -> PNLightReferenceSizeConfiguration? {
        guard let value = root["referenceSize"] else { return nil }
        guard let dictionary = value as? [String: Any],
              let width = CustomPropReader.cgFloat(dictionary["width"]),
              let height = CustomPropReader.cgFloat(dictionary["height"]),
              width.isFinite,
              height.isFinite,
              width > 0,
              height > 0 else {
            throw PNLightReferenceSizeError.invalidConfiguration(
                "'referenceSize' must contain positive finite 'width' and 'height'"
            )
        }
        return PNLightReferenceSizeConfiguration(width: width, height: height)
    }
}

private enum PNLightReferenceSizeError: LocalizedError {
    case invalidConfiguration(String)

    var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message):
            return "Invalid PNLight reference size: \(message)"
        }
    }
}

/// Controls how a Remote UI document participates in the host view's safe area.
///
/// Schema v1 remains edge-to-edge for compatibility. Schema v2 defaults to
/// `inset`: arbitrary markup has no reliable way to distinguish decorative
/// backgrounds from interactive content, so keeping the complete document
/// inside the safe area prevents controls from sitting under system UI.
fileprivate struct PNLightSafeAreaConfiguration {
    enum Mode: String {
        case inset
        case content
        case edgeToEdge = "edge_to_edge"
    }

    let mode: Mode
    let edges: UIRectEdge

    static let defaultValue = PNLightSafeAreaConfiguration(
        mode: .inset,
        edges: .all
    )

    static let edgeToEdge = PNLightSafeAreaConfiguration(
        mode: .edgeToEdge,
        edges: .all
    )

    static func parse(
        from root: [String: Any],
        defaultValue: PNLightSafeAreaConfiguration = .defaultValue
    ) -> PNLightSafeAreaConfiguration {
        guard let dictionary = root["safe_area"] as? [String: Any] else {
            return defaultValue
        }

        let mode = CustomPropReader.string(dictionary["mode"])
            .flatMap(Mode.init(rawValue:)) ?? .inset
        let edgeNames = dictionary["edges"] as? [Any]
        let edges: UIRectEdge
        if let edgeNames {
            edges = edgeNames.reduce(into: UIRectEdge()) { result, value in
                switch CustomPropReader.string(value) {
                case "top": result.insert(.top)
                case "bottom": result.insert(.bottom)
                case "left": result.insert(.left)
                case "right": result.insert(.right)
                default: break
                }
            }
        } else {
            edges = .all
        }
        return PNLightSafeAreaConfiguration(mode: mode, edges: edges)
    }

    func selectedInsets(from insets: UIEdgeInsets) -> UIEdgeInsets {
        UIEdgeInsets(
            top: edges.contains(.top) ? insets.top : 0,
            left: edges.contains(.left) ? insets.left : 0,
            bottom: edges.contains(.bottom) ? insets.bottom : 0,
            right: edges.contains(.right) ? insets.right : 0
        )
    }
}

/// A PNLight flow is an envelope around multiple complete DivKit documents.
/// Legacy `{ "card": ... }` documents bypass this parser and continue through
/// the existing single-card renderer unchanged.
fileprivate struct PNLightFlowDefinition {
    struct HapticPattern {
        struct Event {
            enum Kind: String {
                case transient
                case continuous
            }

            let kind: Kind
            let relativeTime: TimeInterval
            let duration: TimeInterval
            let intensity: Float
            let sharpness: Float
        }

        let events: [Event]
        let loops: Bool
        let maximumDuration: TimeInterval
    }

    struct Route {
        let id: String
        let divKitJson: String
        let presentation: Presentation?
        let safeArea: PNLightSafeAreaConfiguration
        let referenceSize: PNLightReferenceSizeConfiguration?
    }

    struct Presentation {
        enum Style: String {
            case embedded
            case sheet
            case fullScreen = "full_screen"
        }

        enum Detent: String {
            case medium
            case large
        }

        var style: Style
        var detent: Detent
        var showsGrabber: Bool
        var isDismissible: Bool
        var cornerRadius: CGFloat?

        static let largeSheet = Presentation(
            style: .sheet,
            detent: .large,
            showsGrabber: true,
            isDismissible: true,
            cornerRadius: nil
        )

        init(dictionary: [String: Any]) {
            style = Style(rawValue: CustomPropReader.string(dictionary["style"]) ?? "") ?? .sheet
            detent = Detent(rawValue: CustomPropReader.string(dictionary["detent"]) ?? "") ?? .large
            showsGrabber = CustomPropReader.bool(dictionary["grabber"]) ?? true
            isDismissible = CustomPropReader.bool(dictionary["dismissible"]) ?? true
            cornerRadius = CustomPropReader.cgFloat(dictionary["corner_radius"])
        }

        private init(
            style: Style,
            detent: Detent,
            showsGrabber: Bool,
            isDismissible: Bool,
            cornerRadius: CGFloat?
        ) {
            self.style = style
            self.detent = detent
            self.showsGrabber = showsGrabber
            self.isDismissible = isDismissible
            self.cornerRadius = cornerRadius
        }

        func overriding(with params: [String: String]) -> Presentation {
            var result = self
            if let style = params["style"].flatMap(Style.init(rawValue:)) {
                result.style = style
            }
            if let detent = params["detent"].flatMap(Detent.init(rawValue:)) {
                result.detent = detent
            }
            if let value = params["grabber"].flatMap(CustomPropReader.bool) {
                result.showsGrabber = value
            }
            if let value = params["dismissible"].flatMap(CustomPropReader.bool) {
                result.isDismissible = value
            }
            if let value = params["corner_radius"].flatMap(CustomPropReader.cgFloat) {
                result.cornerRadius = value
            }
            return result
        }
    }

    let initialRoute: String
    let routes: [String: Route]
    let haptics: [String: HapticPattern]
    let dialogs: [String: PNLightDialogDefinition]
    let safeArea: PNLightSafeAreaConfiguration
    let schemaVersion: Int

    static func parse(data: Data, schemaVersion: Int) throws -> PNLightFlowDefinition? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              CustomPropReader.string(root["type"]) == "flow" else {
            return nil
        }
        guard schemaVersion >= PNLightRemoteUiSchema.currentVersion else {
            throw PNLightFlowError.invalidConfiguration(
                "'type: flow' requires schemaVersion \(PNLightRemoteUiSchema.currentVersion)"
            )
        }

        guard let initialRoute = CustomPropReader.string(root["initial_route"]) else {
            throw PNLightFlowError.invalidConfiguration("Missing non-empty 'initial_route'")
        }
        guard let routeObjects = root["routes"] as? [String: Any], routeObjects.isEmpty == false else {
            throw PNLightFlowError.invalidConfiguration("Missing non-empty 'routes' object")
        }
        let haptics = try parseHaptics(root["haptics"])
        let dialogs = try PNLightDialogDefinition.parseDefinitions(root["dialogs"])
        let safeArea = PNLightSafeAreaConfiguration.parse(from: root)
        let referenceSize = try PNLightReferenceSizeConfiguration.parse(from: root)

        var routes: [String: Route] = [:]
        for (routeId, rawRoute) in routeObjects {
            guard routeId.isEmpty == false,
                  let routeObject = rawRoute as? [String: Any],
                  let divKitObject = routeObject["divkit"],
                  JSONSerialization.isValidJSONObject(divKitObject) else {
                throw PNLightFlowError.invalidConfiguration(
                    "Route '\(routeId)' must contain a valid 'divkit' object"
                )
            }

            let divKitData = try JSONSerialization.data(withJSONObject: divKitObject)
            guard let divKitJson = String(data: divKitData, encoding: .utf8) else {
                throw PNLightFlowError.invalidConfiguration(
                    "Route '\(routeId)' contains invalid UTF-8"
                )
            }

            let presentation = (routeObject["presentation"] as? [String: Any])
                .map(Presentation.init(dictionary:))
            let routeSafeArea = routeObject["safe_area"] == nil
                ? safeArea
                : PNLightSafeAreaConfiguration.parse(from: routeObject)
            let divKitRoot = divKitObject as? [String: Any]
            let routeReferenceSize = if routeObject["referenceSize"] != nil {
                try PNLightReferenceSizeConfiguration.parse(from: routeObject)
            } else if let divKitRoot,
                      let value = try PNLightReferenceSizeConfiguration.parse(from: divKitRoot) {
                value
            } else {
                referenceSize
            }
            routes[routeId] = Route(
                id: routeId,
                divKitJson: divKitJson,
                presentation: presentation,
                safeArea: routeSafeArea,
                referenceSize: routeReferenceSize
            )
        }

        guard routes[initialRoute] != nil else {
            throw PNLightFlowError.invalidConfiguration(
                "Initial route '\(initialRoute)' is not declared in 'routes'"
            )
        }

        return PNLightFlowDefinition(
            initialRoute: initialRoute,
            routes: routes,
            haptics: haptics,
            dialogs: dialogs,
            safeArea: safeArea,
            schemaVersion: schemaVersion
        )
    }

    private static func parseHaptics(_ value: Any?) throws -> [String: HapticPattern] {
        guard let value else { return [:] }
        guard let patternObjects = value as? [String: Any] else {
            throw PNLightFlowError.invalidConfiguration("'haptics' must be an object")
        }
        guard patternObjects.count <= 32 else {
            throw PNLightFlowError.invalidConfiguration("'haptics' cannot contain more than 32 patterns")
        }

        var patterns: [String: HapticPattern] = [:]
        for (name, rawPattern) in patternObjects {
            guard name.isEmpty == false,
                  let patternObject = rawPattern as? [String: Any],
                  let eventObjects = patternObject["events"] as? [[String: Any]],
                  eventObjects.isEmpty == false,
                  eventObjects.count <= 128 else {
                throw PNLightFlowError.invalidConfiguration(
                    "Haptic pattern '\(name)' must contain 1...128 events"
                )
            }

            let events = try eventObjects.enumerated().map { index, eventObject in
                guard let kindName = CustomPropReader.string(eventObject["type"]),
                      let kind = HapticPattern.Event.Kind(rawValue: kindName) else {
                    throw PNLightFlowError.invalidConfiguration(
                        "Haptic pattern '\(name)' event \(index) has an invalid 'type'"
                    )
                }

                let relativeTime = seconds(
                    value: eventObject["time"],
                    milliseconds: eventObject["time_ms"],
                    fallback: 0
                )
                let duration = seconds(
                    value: eventObject["duration"],
                    milliseconds: eventObject["duration_ms"],
                    fallback: kind == .continuous ? 1 : 0
                )
                guard relativeTime >= 0, relativeTime <= 60,
                      duration >= 0, duration <= 30 else {
                    throw PNLightFlowError.invalidConfiguration(
                        "Haptic pattern '\(name)' event \(index) exceeds supported timing limits"
                    )
                }

                return HapticPattern.Event(
                    kind: kind,
                    relativeTime: relativeTime,
                    duration: kind == .continuous ? max(duration, 0.01) : 0,
                    intensity: Float(clamp(CustomPropReader.double(eventObject["intensity"]) ?? 1)),
                    sharpness: Float(clamp(CustomPropReader.double(eventObject["sharpness"]) ?? 0.5))
                )
            }

            let maximumDuration = seconds(
                value: patternObject["max_duration"],
                milliseconds: patternObject["max_duration_ms"],
                fallback: 300
            )
            guard maximumDuration >= 1, maximumDuration <= 600 else {
                throw PNLightFlowError.invalidConfiguration(
                    "Haptic pattern '\(name)' max duration must be between 1 and 600 seconds"
                )
            }
            patterns[name] = HapticPattern(
                events: events,
                loops: CustomPropReader.bool(patternObject["loop"]) ?? false,
                maximumDuration: maximumDuration
            )
        }
        return patterns
    }

    private static func seconds(
        value: Any?,
        milliseconds: Any?,
        fallback: TimeInterval
    ) -> TimeInterval {
        if let seconds = CustomPropReader.double(value) {
            return seconds
        }
        if let milliseconds = CustomPropReader.double(milliseconds) {
            return milliseconds / 1_000
        }
        return fallback
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

private enum PNLightFlowError: LocalizedError {
    case invalidConfiguration(String)

    var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message):
            return "Invalid PNLight flow: \(message)"
        }
    }
}

private struct PNLightFlowNavigationAction {
    enum Operation: String {
        case push
        case pop
        case replace
        case popToRoot = "pop_to_root"
        case present
        case dismiss
    }

    let operation: Operation
    let route: String?
    let params: [String: String]

    init?(url: URL) {
        guard url.scheme?.lowercased() == "pnlight",
              url.host?.lowercased() == "navigation" else {
            return nil
        }

        let operationName = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let operation = Operation(rawValue: operationName) else { return nil }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var params: [String: String] = [:]
        components?.queryItems?.forEach { params[$0.name] = $0.value ?? "" }

        self.operation = operation
        route = params["route"]
        self.params = params
    }
}

private struct PNLightHapticAction {
    enum Operation: String {
        case impact
        case selection
        case notification
        case start
        case stop
    }

    let operation: Operation
    let params: [String: String]

    init?(url: URL) {
        guard url.scheme?.lowercased() == "pnlight",
              url.host?.lowercased() == "haptic" else {
            return nil
        }
        let operationName = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let operation = Operation(rawValue: operationName) else { return nil }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var params: [String: String] = [:]
        components?.queryItems?.forEach { params[$0.name] = $0.value ?? "" }
        self.operation = operation
        self.params = params
    }
}

private final class PNLightHapticController {
    private var patterns: [String: PNLightFlowDefinition.HapticPattern] = [:]
    private var engine: CHHapticEngine?
    private var players: [String: CHHapticAdvancedPatternPlayer] = [:]
    private var stopTasks: [String: DispatchWorkItem] = [:]
    private var backgroundObserver: NSObjectProtocol?

    init() {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopAll()
        }
    }

    deinit {
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
        stopAll()
        engine?.stop()
    }

    func configure(patterns: [String: PNLightFlowDefinition.HapticPattern]) {
        stopAll()
        self.patterns = patterns
    }

    func handle(_ action: PNLightHapticAction) {
        switch action.operation {
        case .impact:
            playImpact(params: action.params)
        case .selection:
            let generator = UISelectionFeedbackGenerator()
            generator.prepare()
            generator.selectionChanged()
        case .notification:
            playNotification(params: action.params)
        case .start:
            guard let name = action.params["pattern"], name.isEmpty == false else {
                NSLog("[PNLight][Haptics] Ignoring start action without a pattern")
                return
            }
            startPattern(named: name)
        case .stop:
            if let name = action.params["pattern"], name.isEmpty == false {
                stopPattern(named: name)
            } else {
                stopAll()
            }
        }
    }

    func stopAll() {
        stopTasks.values.forEach { $0.cancel() }
        stopTasks.removeAll()
        players.values.forEach { try? $0.stop(atTime: CHHapticTimeImmediate) }
        players.removeAll()
    }

    private func playImpact(params: [String: String]) {
        let style: UIImpactFeedbackGenerator.FeedbackStyle
        switch params["style"]?.lowercased() {
        case "light": style = .light
        case "heavy": style = .heavy
        case "soft": style = .soft
        case "rigid": style = .rigid
        default: style = .medium
        }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        if let rawIntensity = params["intensity"], let intensity = Double(rawIntensity) {
            generator.impactOccurred(intensity: min(max(intensity, 0), 1))
        } else {
            generator.impactOccurred()
        }
    }

    private func playNotification(params: [String: String]) {
        let type: UINotificationFeedbackGenerator.FeedbackType
        switch params["type"]?.lowercased() {
        case "warning": type = .warning
        case "error": type = .error
        default: type = .success
        }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }

    private func startPattern(named name: String) {
        guard let definition = patterns[name] else {
            NSLog("[PNLight][Haptics] Ignoring unknown pattern '%@'", name)
            return
        }
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            NSLog("[PNLight][Haptics] Core Haptics is unavailable on this device")
            return
        }

        do {
            let engine = try runningEngine()
            stopPattern(named: name)
            let events = definition.events.map { event -> CHHapticEvent in
                let eventType: CHHapticEvent.EventType = event.kind == .continuous
                    ? .hapticContinuous
                    : .hapticTransient
                let parameters = [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: event.intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: event.sharpness),
                ]
                if event.kind == .continuous {
                    return CHHapticEvent(
                        eventType: eventType,
                        parameters: parameters,
                        relativeTime: event.relativeTime,
                        duration: event.duration
                    )
                }
                return CHHapticEvent(
                    eventType: eventType,
                    parameters: parameters,
                    relativeTime: event.relativeTime
                )
            }
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            player.loopEnabled = definition.loops
            player.completionHandler = { [weak self, weak player] _ in
                DispatchQueue.main.async {
                    guard let self, self.players[name] === player else { return }
                    self.stopTasks.removeValue(forKey: name)?.cancel()
                    self.players.removeValue(forKey: name)
                }
            }
            players[name] = player
            try player.start(atTime: CHHapticTimeImmediate)

            let stopTask = DispatchWorkItem { [weak self] in
                self?.stopPattern(named: name)
            }
            stopTasks[name] = stopTask
            DispatchQueue.main.asyncAfter(
                deadline: .now() + definition.maximumDuration,
                execute: stopTask
            )
        } catch {
            NSLog("[PNLight][Haptics] Failed to start pattern '%@': %@", name, "\(error)")
            stopPattern(named: name)
        }
    }

    private func stopPattern(named name: String) {
        stopTasks.removeValue(forKey: name)?.cancel()
        if let player = players.removeValue(forKey: name) {
            try? player.stop(atTime: CHHapticTimeImmediate)
        }
    }

    private func runningEngine() throws -> CHHapticEngine {
        if let engine {
            try engine.start()
            return engine
        }

        let engine = try CHHapticEngine()
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = true
        engine.stoppedHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.players.removeAll()
                self?.stopTasks.values.forEach { $0.cancel() }
                self?.stopTasks.removeAll()
            }
        }
        engine.resetHandler = { [weak engine] in
            try? engine?.start()
        }
        try engine.start()
        self.engine = engine
        return engine
    }
}

private final class PNLightFlowNavigationController: UINavigationController {
    let isModalFlowContext: Bool

    init(rootViewController: UIViewController, isModalFlowContext: Bool) {
        self.isModalFlowContext = isModalFlowContext
        super.init(rootViewController: rootViewController)
        setNavigationBarHidden(true, animated: false)
        interactivePopGestureRecognizer?.isEnabled = true
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class PNLightFlowRouteViewController: UIViewController {
    let renderer = PNLightRemoteUiRendererView()
    private var preloadedCardId: String?
    private var isPrepared = false
    private var isRouteAppearing = false
    private var isRouteVisible = false
    private var needsVisibilityActivation = false
    private var preparationCallbacks: [() -> Void] = []

    override func loadView() {
        view = renderer
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isRouteAppearing = true
        isRouteVisible = false
        displayPreloadedConfigIfReady(activateVisibility: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isRouteAppearing = false
        isRouteVisible = true
        let displayedNow = displayPreloadedConfigIfReady(activateVisibility: true)
        if displayedNow == false, needsVisibilityActivation {
            renderer.activatePreloadedConfigVisibility()
            needsVisibilityActivation = false
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isRouteAppearing = false
        isRouteVisible = false
    }

    func prepare(configJson: String, cardId: String) {
        preloadedCardId = cardId
        renderer.prepareForOffscreenPreload()
        Task { [weak self] in
            guard let self else { return }
            await renderer.preloadConfig(configJson: configJson, cardId: cardId)
            isPrepared = true
            if isRouteVisible {
                displayPreloadedConfigIfReady(activateVisibility: true)
            } else if isRouteAppearing {
                displayPreloadedConfigIfReady(activateVisibility: false)
            }
            let callbacks = preparationCallbacks
            preparationCallbacks.removeAll()
            callbacks.forEach { $0() }
        }
    }

    func whenPrepared(_ callback: @escaping () -> Void) {
        if isPrepared {
            callback()
        } else {
            preparationCallbacks.append(callback)
        }
    }

    @discardableResult
    private func displayPreloadedConfigIfReady(activateVisibility: Bool) -> Bool {
        guard isPrepared, (isRouteAppearing || isRouteVisible),
              let preloadedCardId else {
            return false
        }
        renderer.displayPreloadedConfig(
            cardId: preloadedCardId,
            activateVisibility: activateVisibility
        )
        needsVisibilityActivation = !activateVisibility
        self.preloadedCardId = nil
        return true
    }
}

/// Owns the native view-controller hierarchy for one server-delivered flow.
/// The root navigation controller is embedded in `PNLightRemoteUiRendererView`;
/// every `present` operation creates another native navigation context.
private final class PNLightFlowCoordinator: NSObject, UIAdaptivePresentationControllerDelegate {
    private final class BackdropAppearance {
        weak var view: UIView?
        weak var window: UIWindow?
        let transform: CGAffineTransform
        let cornerRadius: CGFloat
        let masksToBounds: Bool
        let cornerCurve: CALayerCornerCurve
        let windowBackgroundColor: UIColor?

        init(view: UIView) {
            self.view = view
            window = view.window
            transform = view.transform
            cornerRadius = view.layer.cornerRadius
            masksToBounds = view.layer.masksToBounds
            cornerCurve = view.layer.cornerCurve
            windowBackgroundColor = view.window?.backgroundColor
        }
    }

    private let definition: PNLightFlowDefinition
    private let baseCardId: String
    private weak var owner: PNLightRemoteUiRendererView?
    private(set) var navigationController: PNLightFlowNavigationController!
    private var presentedNavigationControllers: [PNLightFlowNavigationController] = []
    private var backdropAppearances: [ObjectIdentifier: BackdropAppearance] = [:]
    private var preparedRouteControllers: [String: PNLightFlowRouteViewController] = [:]

    init(
        definition: PNLightFlowDefinition,
        baseCardId: String,
        owner: PNLightRemoteUiRendererView
    ) {
        self.definition = definition
        self.baseCardId = baseCardId
        self.owner = owner
        super.init()

        let root = makeRouteViewController(routeId: definition.initialRoute, preloadOnly: true)
        navigationController = PNLightFlowNavigationController(
            rootViewController: root,
            isModalFlowContext: false
        )
        navigationController.view.backgroundColor = .clear
        prepareAllRoutes()
    }

    func installView(in container: UIView) {
        let navigationView = navigationController.view!
        navigationView.frame = container.bounds
        navigationView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if navigationView.superview !== container {
            navigationView.removeFromSuperview()
            container.insertSubview(navigationView, at: 0)
        }
    }

    func attach(to parent: UIViewController, in container: UIView) {
        guard navigationController.parent !== parent else {
            installView(in: container)
            return
        }

        if navigationController.parent != nil {
            navigationController.willMove(toParent: nil)
            navigationController.removeFromParent()
        }

        // Containment has to exist *before* the flow view enters the hierarchy,
        // otherwise UIKit never runs the child's appearance transition and the
        // routes stay unloaded. Hosts that apply the config before mounting the
        // renderer (React Native sets props on an unmounted view, so `applyFlow`
        // installs the view while there is no parent controller yet) land here
        // with the view already in place, so it is re-inserted deliberately.
        navigationController.viewIfLoaded?.removeFromSuperview()
        parent.addChild(navigationController)
        installView(in: container)
        navigationController.didMove(toParent: parent)
    }

    func detach() {
        presentedNavigationControllers.reversed().forEach {
            restoreBackdrop(for: $0, animated: false)
            $0.dismiss(animated: false)
        }
        presentedNavigationControllers.removeAll()
        navigationController.willMove(toParent: nil)
        navigationController.viewIfLoaded?.removeFromSuperview()
        navigationController.removeFromParent()
    }

    private func makeRouteViewController(
        routeId: String,
        preloadOnly: Bool
    ) -> PNLightFlowRouteViewController {
        guard let route = definition.routes[routeId] else {
            preconditionFailure("Validated flow route '\(routeId)' disappeared")
        }

        let controller = PNLightFlowRouteViewController()
        let renderer = controller.renderer
        renderer.secure = false
        renderer.setCaptureMonitoringEnabled(false)
        renderer.configureSchemaVersionOverride(definition.schemaVersion)
        renderer.configureSafeAreaOverride(route.safeArea)
        renderer.configureReferenceSizeOverride(route.referenceSize)
        renderer.navigationActionHandler = { [weak self, weak controller] action in
            guard let self, let controller else { return true }
            return self.handle(action, from: controller)
        }
        renderer.onCustomAction = { [weak owner = owner] payload in
            owner?.onCustomAction?(payload)
        }
        let cardId = routeCardId(routeId)
        if preloadOnly {
            renderer.setHapticPatterns(definition.haptics)
            controller.prepare(configJson: route.divKitJson, cardId: cardId)
        } else {
            renderer.applyConfig(configJson: route.divKitJson, cardId: cardId)
            renderer.setHapticPatterns(definition.haptics)
        }
        renderer.setDialogDefinitions(definition.dialogs)
        return controller
    }

    private func handle(
        _ action: PNLightFlowNavigationAction,
        from source: PNLightFlowRouteViewController
    ) -> Bool {
        switch action.operation {
        case .push:
            guard let route = validRoute(named: action.route) else { return true }
            guard let navigationController = source.navigationController else {
                NSLog(
                    "[PNLight][RemoteUiFlow] Ignoring push to '%@': the source route is not in a flow navigation stack",
                    route.id
                )
                return true
            }
            // The destination is captured strongly on purpose:
            // `takePreparedRouteViewController` hands over the only strong
            // reference, so a route whose preload is still in flight would
            // otherwise deallocate before the callback runs and the navigation
            // would be dropped without a trace. The callback list is cleared
            // once it fires, which releases the controller again.
            let controller = takePreparedRouteViewController(routeId: route.id)
            controller.whenPrepared { [weak navigationController] in
                navigationController?.pushViewController(controller, animated: true)
            }

        case .pop:
            source.navigationController?.popViewController(animated: true)

        case .replace:
            guard let route = validRoute(named: action.route) else { return true }
            guard let navigationController = source.navigationController else {
                NSLog(
                    "[PNLight][RemoteUiFlow] Ignoring replace with '%@': the source route is not in a flow navigation stack",
                    route.id
                )
                return true
            }
            let replacement = takePreparedRouteViewController(routeId: route.id)
            replacement.whenPrepared { [weak navigationController] in
                guard let navigationController else { return }
                var controllers = navigationController.viewControllers
                if controllers.isEmpty {
                    controllers = [replacement]
                } else {
                    controllers[controllers.count - 1] = replacement
                }
                navigationController.setViewControllers(controllers, animated: true)
            }

        case .popToRoot:
            source.navigationController?.popToRootViewController(animated: true)

        case .present:
            guard let route = validRoute(named: action.route) else { return true }
            let controller = takePreparedRouteViewController(routeId: route.id)
            controller.whenPrepared { [weak self, weak source] in
                guard let self, let source else { return }
                let modalNavigation = PNLightFlowNavigationController(
                    rootViewController: controller,
                    isModalFlowContext: true
                )
                self.configure(
                    modalNavigation,
                    with: (route.presentation ?? .largeSheet).overriding(with: action.params)
                )
                modalNavigation.presentationController?.delegate = self
                self.presentedNavigationControllers.removeAll {
                    $0.presentingViewController == nil && $0.viewIfLoaded?.window == nil
                }
                self.presentedNavigationControllers.append(modalNavigation)
                let presenter = self.presentationHost(from: source)
                self.registerBackdrop(for: modalNavigation, presenter: presenter)
                presenter.present(modalNavigation, animated: true)
                self.animateBackdropPresentation(for: modalNavigation)
            }

        case .dismiss:
            guard let navigationController =
                    source.navigationController as? PNLightFlowNavigationController,
                  navigationController.isModalFlowContext else {
                return true
            }
            restoreBackdrop(for: navigationController, animated: true)
            navigationController.dismiss(animated: true) { [weak self, weak navigationController] in
                guard let navigationController else { return }
                self?.presentedNavigationControllers.removeAll { $0 === navigationController }
            }
        }

        return true
    }

    /// Builds every route while its renderer is detached from a window. DivKit
    /// can parse and build the block tree here, but visibility-driven actions,
    /// transitions, and PNLight native component animations do not start until
    /// UIKit actually places the selected controller on screen.
    private func prepareAllRoutes() {
        for routeId in definition.routes.keys {
            preparedRouteControllers[routeId] = makeRouteViewController(
                routeId: routeId,
                preloadOnly: true
            )
        }
    }

    private func takePreparedRouteViewController(
        routeId: String
    ) -> PNLightFlowRouteViewController {
        let controller = preparedRouteControllers.removeValue(forKey: routeId)
            ?? makeRouteViewController(routeId: routeId, preloadOnly: true)

        // Keep one detached instance warm for a later visit to the same route.
        preparedRouteControllers[routeId] = makeRouteViewController(
            routeId: routeId,
            preloadOnly: true
        )
        return controller
    }

    func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {
        guard let navigationController =
                presentationController.presentedViewController as? PNLightFlowNavigationController else {
            return
        }
        restoreBackdropAlongsideInteractiveDismissal(for: navigationController)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        let dismissedController = presentationController.presentedViewController
        if let navigationController = dismissedController as? PNLightFlowNavigationController {
            restoreBackdrop(for: navigationController, animated: false)
        }
        presentedNavigationControllers.removeAll { $0 === dismissedController }
    }

    private func registerBackdrop(
        for navigationController: PNLightFlowNavigationController,
        presenter: UIViewController
    ) {
        let key = ObjectIdentifier(navigationController)
        guard backdropAppearances[key] == nil else { return }
        backdropAppearances[key] = BackdropAppearance(view: presenter.view)
    }

    private func animateBackdropPresentation(
        for navigationController: PNLightFlowNavigationController
    ) {
        let animations: () -> Void = { [weak self] in
            self?.applyScaledBackdrop(for: navigationController)
        }

        if let transitionCoordinator = navigationController.transitionCoordinator {
            transitionCoordinator.animate(alongsideTransition: { _ in
                animations()
            }, completion: { [weak self, weak navigationController] context in
                guard context.isCancelled, let navigationController else { return }
                self?.restoreBackdrop(for: navigationController, animated: false)
            })
        } else {
            UIView.animate(
                withDuration: 0.45,
                delay: 0,
                usingSpringWithDamping: 1,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: animations
            )
        }
    }

    private func applyScaledBackdrop(
        for navigationController: PNLightFlowNavigationController
    ) {
        guard let appearance = backdropAppearances[ObjectIdentifier(navigationController)],
              let view = appearance.view else {
            return
        }

        let width = max(view.bounds.width, 1)
        let scale = max((width - 16) / width, 0.94)
        let effect = CGAffineTransform(translationX: 0, y: -8)
            .scaledBy(x: scale, y: scale)

        appearance.window?.backgroundColor = .black
        view.transform = appearance.transform.concatenating(effect)
        view.layer.cornerCurve = .continuous
        view.layer.cornerRadius = max(appearance.cornerRadius, 16)
        view.layer.masksToBounds = true
    }

    private func restoreBackdrop(
        for navigationController: PNLightFlowNavigationController,
        animated: Bool
    ) {
        let key = ObjectIdentifier(navigationController)
        guard let appearance = backdropAppearances[key] else { return }

        let restore = {
            self.applyOriginalBackdrop(appearance)
        }
        let completion: (Bool) -> Void = { [weak self] _ in
            self?.backdropAppearances.removeValue(forKey: key)
        }

        if animated {
            UIView.animate(
                withDuration: 0.35,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: restore,
                completion: completion
            )
        } else {
            restore()
            completion(true)
        }
    }

    private func restoreBackdropAlongsideInteractiveDismissal(
        for navigationController: PNLightFlowNavigationController
    ) {
        let key = ObjectIdentifier(navigationController)
        guard let appearance = backdropAppearances[key] else { return }
        guard let transitionCoordinator = navigationController.transitionCoordinator else {
            restoreBackdrop(for: navigationController, animated: true)
            return
        }

        transitionCoordinator.animate(alongsideTransition: { [weak self] _ in
            self?.applyOriginalBackdrop(appearance)
        }, completion: { [weak self, weak navigationController] context in
            guard let self, let navigationController else { return }
            if context.isCancelled {
                self.applyScaledBackdrop(for: navigationController)
            } else {
                self.backdropAppearances.removeValue(forKey: key)
            }
        })
    }

    private func applyOriginalBackdrop(_ appearance: BackdropAppearance) {
        appearance.view?.transform = appearance.transform
        appearance.view?.layer.cornerRadius = appearance.cornerRadius
        appearance.view?.layer.cornerCurve = appearance.cornerCurve
        appearance.view?.layer.masksToBounds = appearance.masksToBounds
        appearance.window?.backgroundColor = appearance.windowBackgroundColor
    }

    private func validRoute(named routeId: String?) -> PNLightFlowDefinition.Route? {
        guard let routeId, let route = definition.routes[routeId] else {
            NSLog("[PNLight][RemoteUiFlow] Ignoring navigation to unknown route '%@'", routeId ?? "")
            return nil
        }
        return route
    }

    private func configure(
        _ navigationController: PNLightFlowNavigationController,
        with presentation: PNLightFlowDefinition.Presentation
    ) {
        switch presentation.style {
        case .fullScreen:
            navigationController.modalPresentationStyle = .fullScreen

        case .embedded, .sheet:
            navigationController.modalPresentationStyle = .pageSheet
            guard let sheet = navigationController.sheetPresentationController else { break }

            switch presentation.detent {
            case .large:
                sheet.detents = [.large()]
            case .medium:
                sheet.detents = [.medium(), .large()]
                sheet.selectedDetentIdentifier = .medium
            }

            sheet.prefersGrabberVisible = presentation.showsGrabber
            sheet.preferredCornerRadius = presentation.cornerRadius
        }

        navigationController.isModalInPresentation = presentation.isDismissible == false
    }

    private func presentationHost(from source: UIViewController) -> UIViewController {
        var presenter = source.view.window?.rootViewController ?? source
        while let presented = presenter.presentedViewController,
              presented.isBeingDismissed == false {
            presenter = presented
        }
        return presenter
    }

    private func routeCardId(_ routeId: String) -> String {
        let safeRoute = routeId.map { character -> Character in
            character.isLetter || character.isNumber || character == "_" || character == "-"
                ? character
                : "_"
        }
        return "\(baseCardId)_\(String(safeRoute))"
    }
}

public class PNLightRemoteUiRendererView: UIView {
    private final class UrlHandler: DivUrlHandler {
        weak var owner: PNLightRemoteUiRendererView?

        func handle(_ url: URL, info: DivActionInfo, sender: AnyObject?) {
            guard let owner else { return }

            if owner.handleNavigationAction(url) {
                return
            }

            if owner.handleDialogAction(url, sender: sender) {
                return
            }

            if owner.handleHapticAction(url) {
                return
            }

            if owner.isCustomAction(url) {
                owner.onCustomAction?(RemoteUiActionPayload(action: info))
                return
            }

            owner.open(url)
        }

        func handle(_ url: URL, sender: AnyObject?) {
            guard let owner else { return }
            if owner.handleNavigationAction(url) {
                return
            }
            if owner.handleDialogAction(url, sender: sender) {
                return
            }
            if owner.handleHapticAction(url) {
                return
            }
            owner.open(url)
        }
    }

    private let divView: DivView
    private let divViewPreloader: DivViewPreloader
    private let divKitComponents: DivKitComponents
    private let loadingIndicator: UIActivityIndicatorView
    private let errorLabel: UILabel
    private let contentContainer: UIView
    private let urlHandler: UrlHandler
    private let customBlockFactory: PNLightCustomBlockFactory
    private let hapticController: PNLightHapticController
    private var dialogDefinitions: [String: PNLightDialogDefinition] = [:]
    private weak var presentedDialog: UIAlertController?
    private var currentCardId = "divkit"
    private let dismissActionName = "view_dismissed"
    private var flowCoordinator: PNLightFlowCoordinator?
    private var captureObservers: [NSObjectProtocol] = []
    private var isCaptureMonitoringEnabled = true
    private var wasScreenCaptured = false
    private var didHandleCaptureAttempt = false
    private var pendingDismissAction = false
    var secure: Bool {
        didSet {
            guard secure != oldValue else { return }
            updateContainerView()
            // Capture blocking follows the backend `secure` flag: a non-secure
            // placement stays visible (and unreported) while the screen is
            // recorded or screenshotted.
            updateCaptureMonitoring()
            if isCaptureBlockingActive, window != nil {
                evaluateCaptureStateIfNeeded()
            }
        }
    }
    var preventRecording: Bool {
        didSet {
            // Deprecated. Capture reporting is backend-controlled.
        }
    }
    private var secureTextField: UITextField?
    private var containerView: UIView?
    private var schemaVersion = PNLightRemoteUiSchema.legacyVersion
    private var schemaVersionOverride: Int?
    private var safeAreaConfiguration = PNLightSafeAreaConfiguration.edgeToEdge
    private var safeAreaOverride: PNLightSafeAreaConfiguration?
    private var lastPublishedSafeAreaInsets: UIEdgeInsets?
    private var referenceSizeConfiguration: PNLightReferenceSizeConfiguration?
    private var referenceSizeOverride: PNLightReferenceSizeConfiguration?
    private var lastPublishedScale: CGSize?

    fileprivate var navigationActionHandler: ((PNLightFlowNavigationAction) -> Bool)?

    var onCustomAction: ((RemoteUiActionPayload) -> Void)? {
        didSet {
            flushPendingDismissActionIfNeeded()
            evaluateCaptureStateIfNeeded()
        }
    }

    var loadFailureMessage: String {
        "Failed to load DivKit content"
    }

    public override init(frame: CGRect) {
        secure = true
        preventRecording = true
        urlHandler = UrlHandler()
        hapticController = PNLightHapticController()
        let customBlockFactory = PNLightCustomBlockFactory()
        self.customBlockFactory = customBlockFactory
        let divKitComponents = DivKitComponents(
            divCustomBlockFactory: customBlockFactory,
            extensionHandlers: [makePNLightLottieExtensionHandler()],
            urlHandler: urlHandler
        )
        self.divKitComponents = divKitComponents
        let divViewPreloader = DivViewPreloader(divKitComponents: divKitComponents)
        self.divViewPreloader = divViewPreloader
        divView = DivView(
            divKitComponents: divKitComponents,
            divViewPreloader: divViewPreloader
        )
        loadingIndicator = UIActivityIndicatorView(style: .large)
        errorLabel = UILabel()
        contentContainer = UIView()

        super.init(frame: frame)

        urlHandler.owner = self
        customBlockFactory.overflowBoundary = divView
        customBlockFactory.onAction = { [weak self] url, logId in
            self?.handleCustomViewAction(urlString: url, logId: logId)
        }
        backgroundColor = .clear
        setupSubviews()
        updateCaptureMonitoring()
    }

    public init(frame: CGRect, secure: Bool, preventRecording: Bool = true) {
        self.secure = secure
        self.preventRecording = preventRecording
        urlHandler = UrlHandler()
        hapticController = PNLightHapticController()
        let customBlockFactory = PNLightCustomBlockFactory()
        self.customBlockFactory = customBlockFactory
        let divKitComponents = DivKitComponents(
            divCustomBlockFactory: customBlockFactory,
            extensionHandlers: [makePNLightLottieExtensionHandler()],
            urlHandler: urlHandler
        )
        self.divKitComponents = divKitComponents
        let divViewPreloader = DivViewPreloader(divKitComponents: divKitComponents)
        self.divViewPreloader = divViewPreloader
        divView = DivView(
            divKitComponents: divKitComponents,
            divViewPreloader: divViewPreloader
        )
        loadingIndicator = UIActivityIndicatorView(style: .large)
        errorLabel = UILabel()
        contentContainer = UIView()

        super.init(frame: frame)

        urlHandler.owner = self
        customBlockFactory.overflowBoundary = divView
        customBlockFactory.onAction = { [weak self] url, logId in
            self?.handleCustomViewAction(urlString: url, logId: logId)
        }
        backgroundColor = .clear
        setupSubviews()
        updateCaptureMonitoring()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        presentedDialog?.dismiss(animated: false)
        hapticController.stopAll()
        flowCoordinator?.detach()
        stopCaptureMonitoring()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        updateSafeAreaLayout()
        loadingIndicator.center = CGPoint(
            x: contentContainer.bounds.width / 2,
            y: contentContainer.bounds.height / 2
        )
    }

    public override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        updateSafeAreaLayout()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            hapticController.stopAll()
            flowCoordinator?.detach()
        } else {
            attachFlowCoordinatorIfPossible()
        }
        updateSafeAreaLayout()
        evaluateCaptureStateIfNeeded()
    }

    public func applyConfig(configJson: String?, cardId: String) {
        hapticController.configure(patterns: [:])
        currentCardId = cardId
        dialogDefinitions = [:]
        presentedDialog?.dismiss(animated: false)
        guard let configJson, !configJson.isEmpty,
              let data = configJson.data(using: .utf8) else {
            // No content for this placement: stop the loader and show nothing
            // (empty is not an error).
            configureSchemaVersion(schemaVersionOverride ?? PNLightRemoteUiSchema.legacyVersion)
            configureReferenceSize(referenceSizeOverride)
            showEmpty()
            return
        }

        errorLabel.alpha = 0
        errorLabel.text = loadFailureMessage
        loadingIndicator.startAnimating()
        loadingIndicator.alpha = 1
        divView.alpha = 0

        let preservedDocument = PNLightNativeButtonActionPreserver.preserve(in: data)
        do {
            let preservedData = preservedDocument.data
            let rootObject = preservedDocument.root
            let documentSchemaVersion = try PNLightRemoteUiSchema.parse(from: rootObject)
            let effectiveSchemaVersion = schemaVersionOverride ?? documentSchemaVersion
            configureSchemaVersion(effectiveSchemaVersion)

            let legacyDocument = effectiveSchemaVersion == PNLightRemoteUiSchema.legacyVersion
            let documentSafeArea = legacyDocument
                ? PNLightSafeAreaConfiguration.edgeToEdge
                : rootObject.map {
                    PNLightSafeAreaConfiguration.parse(from: $0)
                } ?? .defaultValue
            configureSafeArea(safeAreaOverride ?? documentSafeArea)

            let documentReferenceSize = try rootObject.flatMap { root -> PNLightReferenceSizeConfiguration? in
                guard effectiveSchemaVersion >= PNLightRemoteUiSchema.currentVersion else {
                    return nil
                }
                return try PNLightReferenceSizeConfiguration.parse(from: root)
            }
            configureReferenceSize(referenceSizeOverride ?? documentReferenceSize)
            if effectiveSchemaVersion >= PNLightRemoteUiSchema.currentVersion {
                dialogDefinitions = try PNLightDialogDefinition.parseDefinitions(
                    rootObject?["dialogs"]
                )
            }
            if let flow = try PNLightFlowDefinition.parse(
                data: preservedData,
                schemaVersion: effectiveSchemaVersion
            ) {
                hapticController.configure(patterns: flow.haptics)
                dialogDefinitions = flow.dialogs
                applyFlow(flow, cardId: cardId)
                return
            }
        } catch {
            resetFlow()
            showError(error)
            return
        }

        resetFlow()
        applyDivKitData(preservedDocument.data, cardId: cardId)
    }

    private func applyDivKitData(_ data: Data, cardId: String) {
        let source = DivViewSource(
            kind: .data(data),
            cardId: DivCardID(rawValue: cardId) ?? "divkit"
        )

        Task { @MainActor in
            do {
                try await self.divView.setSource(source)
                self.showContent()
            } catch {
                self.showError(error)
            }
        }
    }

    fileprivate func prepareForOffscreenPreload() {
        loadingIndicator.stopAnimating()
        loadingIndicator.alpha = 0
        divView.alpha = 0
        errorLabel.alpha = 0
    }

    fileprivate func preloadConfig(configJson: String, cardId: String) async {
        guard let data = configJson.data(using: .utf8) else { return }
        currentCardId = cardId
        let source = DivViewSource(
            kind: .data(data),
            cardId: DivCardID(rawValue: cardId)
        )
        await divViewPreloader.setSource(source)
    }

    fileprivate func displayPreloadedConfig(
        cardId: String,
        activateVisibility: Bool
    ) {
        currentCardId = cardId
        if activateVisibility == false {
            // DivView treats its current bounds as visible even while detached
            // from a window. Show the prepared card with zero bounds first so
            // UIKit can build and lay out the destination without consuming
            // one-shot visibility actions before the route is onscreen.
            let frame = divView.frame
            divView.frame = CGRect(origin: frame.origin, size: .zero)
            divView.showCardId(DivCardID(rawValue: cardId))
            divView.frame = frame
            divView.onVisibleBoundsChanged(to: .zero)
            divView.setNeedsLayout()
            divView.layoutIfNeeded()
            loadingIndicator.stopAnimating()
            loadingIndicator.alpha = 0
            errorLabel.alpha = 0
            divView.alpha = 1
            return
        }

        divView.showCardId(DivCardID(rawValue: cardId))
        showContent()
    }

    fileprivate func activatePreloadedConfigVisibility() {
        guard window != nil else { return }
        divView.onVisibleBoundsChanged(to: divView.bounds)
        divView.setNeedsLayout()
        divView.layoutIfNeeded()
    }

    fileprivate func setHapticPatterns(
        _ patterns: [String: PNLightFlowDefinition.HapticPattern]
    ) {
        hapticController.configure(patterns: patterns)
    }

    fileprivate func setDialogDefinitions(
        _ definitions: [String: PNLightDialogDefinition]
    ) {
        dialogDefinitions = definitions
    }

    fileprivate func configureSafeArea(_ configuration: PNLightSafeAreaConfiguration) {
        safeAreaConfiguration = configuration
        lastPublishedSafeAreaInsets = nil
        setNeedsLayout()
        updateSafeAreaLayout()
    }

    fileprivate func configureSchemaVersionOverride(_ version: Int) {
        schemaVersionOverride = version
        configureSchemaVersion(version)
    }

    private func configureSchemaVersion(_ version: Int) {
        schemaVersion = version
        lastPublishedScale = nil
    }

    fileprivate func configureSafeAreaOverride(
        _ configuration: PNLightSafeAreaConfiguration
    ) {
        safeAreaOverride = configuration
        configureSafeArea(configuration)
    }

    fileprivate func configureReferenceSizeOverride(
        _ configuration: PNLightReferenceSizeConfiguration?
    ) {
        referenceSizeOverride = configuration
        configureReferenceSize(configuration)
    }

    private func configureReferenceSize(
        _ configuration: PNLightReferenceSizeConfiguration?
    ) {
        referenceSizeConfiguration = configuration
        lastPublishedScale = nil
        setNeedsLayout()
        updateSafeAreaLayout()
    }

    private func applyFlow(_ flow: PNLightFlowDefinition, cardId: String) {
        resetFlow()
        // Each route owns its safe-area policy. The envelope renderer stays
        // edge-to-edge so a route is never inset twice.
        configureSafeArea(.edgeToEdge)
        let coordinator = PNLightFlowCoordinator(
            definition: flow,
            baseCardId: cardId,
            owner: self
        )
        flowCoordinator = coordinator
        coordinator.installView(in: contentContainer)
        attachFlowCoordinatorIfPossible()
        showContent()
    }

    /// Shows the loading indicator (e.g. while the config request is in flight).
    public func showLoading() {
        errorLabel.alpha = 0
        divView.alpha = 0
        flowCoordinator?.navigationController.view.alpha = 0
        loadingIndicator.startAnimating()
        loadingIndicator.alpha = 1
    }

    /// Stops the loader and surfaces a load failure in the view.
    public func showLoadFailure(message: String? = nil) {
        resetFlow()
        errorLabel.text = message ?? loadFailureMessage
        loadingIndicator.stopAnimating()
        UIView.animate(withDuration: 0.3) {
            self.loadingIndicator.alpha = 0
            self.divView.alpha = 0
            self.errorLabel.alpha = 1
        }
    }

    private func showEmpty() {
        resetFlow()
        loadingIndicator.stopAnimating()
        loadingIndicator.alpha = 0
        divView.alpha = 0
        errorLabel.alpha = 0
    }

    private func setupSubviews() {
        contentContainer.frame = bounds
        contentContainer.autoresizingMask = []
        contentContainer.backgroundColor = .clear

        divView.frame = bounds
        divView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        divView.alpha = 0
        divView.backgroundColor = .clear

        loadingIndicator.center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        loadingIndicator.autoresizingMask = [
            .flexibleLeftMargin,
            .flexibleRightMargin,
            .flexibleTopMargin,
            .flexibleBottomMargin,
        ]
        loadingIndicator.hidesWhenStopped = false
        loadingIndicator.startAnimating()

        errorLabel.text = loadFailureMessage
        errorLabel.textColor = .systemRed
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.frame = bounds
        errorLabel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        errorLabel.alpha = 0

        contentContainer.addSubview(divView)
        contentContainer.addSubview(loadingIndicator)
        contentContainer.addSubview(errorLabel)
        updateContainerView()
    }

    private func updateSafeAreaLayout() {
        let selectedInsets = safeAreaConfiguration.selectedInsets(from: safeAreaInsets)
        let layoutInsets = safeAreaConfiguration.mode == .inset
            ? selectedInsets
            : .zero
        let nextFrame = bounds.inset(by: layoutInsets)
        if contentContainer.frame != nextFrame {
            contentContainer.frame = nextFrame
            divView.frame = contentContainer.bounds
            errorLabel.frame = contentContainer.bounds
            flowCoordinator?.installView(in: contentContainer)
        }

        // These values represent safe area still left for the document to
        // consume. Physically inset and explicit edge-to-edge documents receive
        // zeroes; `content` exposes the selected system insets to expressions.
        let variableInsets = safeAreaConfiguration.mode == .content
            ? selectedInsets
            : .zero
        if lastPublishedSafeAreaInsets != variableInsets {
            lastPublishedSafeAreaInsets = variableInsets
            divKitComponents.safeAreaManager.setEdgeInsets(variableInsets)
        }

        if schemaVersion >= PNLightRemoteUiSchema.currentVersion {
            let scale: CGSize
            if let referenceSizeConfiguration,
               nextFrame.width > 0,
               nextFrame.height > 0 {
                scale = CGSize(
                    width: nextFrame.width / referenceSizeConfiguration.width,
                    height: nextFrame.height / referenceSizeConfiguration.height
                )
            } else {
                scale = CGSize(width: 1, height: 1)
            }
            if lastPublishedScale != scale {
                lastPublishedScale = scale
                divKitComponents.variablesStorage.append(
                    variables: [
                        DivVariableName(rawValue: "scaleX"): .number(Double(scale.width)),
                        DivVariableName(rawValue: "scaleY"): .number(Double(scale.height)),
                    ],
                    triggerUpdate: true
                )
            }
        }
    }

    private func updateContainerView() {
        let nextContainer = secure
            ? makeSecureContainer(frame: bounds)
            : makePlainContainer(frame: bounds)
        nextContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        contentContainer.removeFromSuperview()
        nextContainer.addSubview(contentContainer)

        containerView?.removeFromSuperview()
        addSubview(nextContainer)
        containerView = nextContainer
        updateSafeAreaLayout()
    }

    /// Capture attempts are only acted on for secure placements, and only when
    /// the host hasn't opted out (flow routes disable it explicitly).
    private var isCaptureBlockingActive: Bool {
        isCaptureMonitoringEnabled && secure
    }

    private func updateCaptureMonitoring() {
        stopCaptureMonitoring()
        guard isCaptureBlockingActive else { return }

        let notificationCenter = NotificationCenter.default

        captureObservers.append(
            notificationCenter.addObserver(
                forName: UIApplication.userDidTakeScreenshotNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleCaptureAttempt()
            }
        )

        captureObservers.append(
            notificationCenter.addObserver(
                forName: UIScreen.capturedDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.evaluateCaptureStateIfNeeded()
            }
        )

        captureObservers.append(
            notificationCenter.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.evaluateCaptureStateIfNeeded()
            }
        )
    }

    private func stopCaptureMonitoring() {
        captureObservers.forEach(NotificationCenter.default.removeObserver)
        captureObservers.removeAll()
    }

    private func evaluateCaptureStateIfNeeded() {
        let isCaptured = isAnyScreenCaptured
        defer { wasScreenCaptured = isCaptured }

        guard isCaptured, wasScreenCaptured == false else { return }
        handleCaptureAttempt()
    }

    private var isAnyScreenCaptured: Bool {
        UIScreen.screens.contains { $0.isCaptured }
    }

    private func handleCaptureAttempt() {
        // `evaluateCaptureStateIfNeeded()` also runs outside the notification
        // observers (e.g. when `onCustomAction` is assigned), so the check has
        // to live here too, not only in `updateCaptureMonitoring()`.
        guard isCaptureBlockingActive, didHandleCaptureAttempt == false else { return }

        didHandleCaptureAttempt = true
        hideAfterCaptureAttempt()
        pendingDismissAction = true
        PNLightSDK.shared.reportRemoteUiCapture()
        flushPendingDismissActionIfNeeded()
    }

    private func hideAfterCaptureAttempt() {
        layer.removeAllAnimations()
        containerView?.layer.removeAllAnimations()
        contentContainer.layer.removeAllAnimations()

        loadingIndicator.stopAnimating()
        alpha = 0
        isHidden = true
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
    }

    private func flushPendingDismissActionIfNeeded() {
        guard pendingDismissAction, let onCustomAction = onCustomAction else { return }

        pendingDismissAction = false
        onCustomAction(RemoteUiActionPayload(customAction: dismissActionName))
    }

    private func makeSecureContainer(frame: CGRect) -> UIView {
        let textField = UITextField(frame: frame)
        textField.isSecureTextEntry = true
        textField.isUserInteractionEnabled = false
        textField.backgroundColor = .clear
        secureTextField = textField

        guard let secureLayer = textField.layer.sublayers?.first,
              let secureView = secureLayer.delegate as? UIView else {
            NSLog("[PNLight][RemoteUiView] Secure container unavailable, using fallback")
            let fallback = UIView(frame: frame)
            fallback.backgroundColor = .clear
            return fallback
        }

        secureView.subviews.forEach { $0.removeFromSuperview() }
        secureView.frame = frame
        secureView.isUserInteractionEnabled = true
        secureView.backgroundColor = .clear
        secureView.clipsToBounds = true
        return secureView
    }

    private func makePlainContainer(frame: CGRect) -> UIView {
        secureTextField = nil
        let container = UIView(frame: frame)
        container.backgroundColor = .clear
        container.clipsToBounds = true
        return container
    }

    private func showContent() {
        loadingIndicator.stopAnimating()
        UIView.animate(withDuration: 0.3) {
            self.loadingIndicator.alpha = 0
            self.divView.alpha = self.flowCoordinator == nil ? 1 : 0
            self.flowCoordinator?.navigationController.view.alpha = 1
        }
    }

    private func showError(_ error: Error) {
        errorLabel.text = "\(loadFailureMessage):\n\(error.localizedDescription)"
        loadingIndicator.stopAnimating()
        UIView.animate(withDuration: 0.3) {
            self.loadingIndicator.alpha = 0
            self.errorLabel.alpha = 1
        }
    }

    /// Routes a tap from a native custom component (e.g. the CTA button) through
    /// the same pipeline as DivKit action URLs: custom-scheme URLs surface via
    /// `onCustomAction`, http(s) URLs open externally.
    private func handleCustomViewAction(urlString: String?, logId: String?) {
        if let urlString, let url = URL(string: urlString) {
            if handleNavigationAction(url) {
                return
            }

            if handleDialogAction(url, sender: self) {
                return
            }

            if handleHapticAction(url) {
                return
            }

            if isCustomAction(url) {
                onCustomAction?(RemoteUiActionPayload(url: url, logId: logId ?? ""))
            } else {
                open(url)
            }
            return
        }

        if let logId, !logId.isEmpty {
            onCustomAction?(RemoteUiActionPayload(customAction: logId))
        }
    }

    fileprivate func setCaptureMonitoringEnabled(_ isEnabled: Bool) {
        guard isCaptureMonitoringEnabled != isEnabled else { return }
        isCaptureMonitoringEnabled = isEnabled
        updateCaptureMonitoring()
    }

    fileprivate func handleNavigationAction(_ url: URL) -> Bool {
        guard let action = PNLightFlowNavigationAction(url: url) else { return false }
        return navigationActionHandler?(action) ?? false
    }

    fileprivate func handleDialogAction(_ url: URL, sender: AnyObject?) -> Bool {
        guard schemaVersion >= PNLightRemoteUiSchema.currentVersion,
              url.scheme?.lowercased() == "pnlight",
              url.host?.lowercased() == "dialog",
              url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "show" else {
            return false
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let dialogId = components?.queryItems?.first(where: { $0.name == "id" })?.value
        guard let dialogId, let definition = dialogDefinitions[dialogId] else {
            NSLog("[PNLight][Dialogs] Ignoring unknown dialog '%@'", dialogId ?? "")
            return true
        }
        presentDialog(definition, sourceView: sender as? UIView)
        return true
    }

    fileprivate func handleHapticAction(_ url: URL) -> Bool {
        guard schemaVersion >= PNLightRemoteUiSchema.currentVersion,
              let action = PNLightHapticAction(url: url) else {
            return false
        }
        hapticController.handle(action)
        return true
    }

    private func presentDialog(
        _ definition: PNLightDialogDefinition,
        sourceView: UIView?
    ) {
        guard presentedDialog == nil, let nearestViewController else { return }
        let preferredStyle: UIAlertController.Style = definition.style == .alert
            ? .alert
            : .actionSheet
        let alert = UIAlertController(
            title: definition.title,
            message: definition.message,
            preferredStyle: preferredStyle
        )

        for button in definition.buttons {
            let style: UIAlertAction.Style
            switch button.style {
            case .default: style = .default
            case .cancel: style = .cancel
            case .destructive: style = .destructive
            }
            alert.addAction(UIAlertAction(title: button.title, style: style) { [weak self] _ in
                guard let self else { return }
                self.presentedDialog = nil
                self.performDivKitActions(button.actions, sender: alert)
            })
        }

        if let popover = alert.popoverPresentationController {
            let anchor = sourceView ?? self
            popover.sourceView = anchor
            popover.sourceRect = anchor.bounds
        }

        var presenter = nearestViewController
        while let presented = presenter.presentedViewController,
              presented.isBeingDismissed == false {
            presenter = presented
        }
        presentedDialog = alert
        presenter.present(alert, animated: true)
    }

    private func performDivKitActions(
        _ actions: [[String: Any]],
        sender: AnyObject
    ) {
        let path = UIElementPath(currentCardId)
        for action in actions {
            divKitComponents.actionHandler.handle(
                params: UserInterfaceAction.DivActionParams(
                    action: .object(action.typedJSON()),
                    path: path,
                    source: .tap,
                    url: nil
                ),
                sender: sender
            )
        }
    }

    private func attachFlowCoordinatorIfPossible() {
        guard let flowCoordinator, let parent = nearestViewController else { return }
        flowCoordinator.attach(to: parent, in: contentContainer)
    }

    private var nearestViewController: UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let viewController = current as? UIViewController {
                return viewController
            }
            responder = current.next
        }
        return nil
    }

    private func resetFlow() {
        flowCoordinator?.detach()
        flowCoordinator = nil
    }

    private func isCustomAction(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme != "http" && scheme != "https"
    }

    private func open(_ url: URL) {
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
}
