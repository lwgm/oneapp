import SwiftUI
import UIKit

/// 点击任意非输入区域收起键盘。
///
/// 为什么不用 SwiftUI 手势：大标题「书库」属于 UIKit 的导航栏视图，
/// 挂在上面的手势永远收不到那里的点击。所以改在 window 上装手势，覆盖整屏。
///
/// 三个关键点：
/// - `cancelsTouchesInView = false`：不抢走原本的点击，按钮和列表行照常响应
/// - 只放行「点在输入控件里」：视图祖先链里有输入控件，或者落点落在
///   正在编辑的输入框矩形里（后者是为了让内嵌的清空按钮不被抢走焦点）。
///   早期版本把这个矩形用 SwiftUI 的 `.global` 记下来，再和 UIKit 的
///   `touch.location(in:)` 相比——两套坐标系一旦错开就会把标题附近整条空白带
///   当成「点在搜索框内」放行，点击没反应、键盘也不收。现在一律用 UIKit 换算。
/// - 收起键盘只有一条通道：`onTapOutside` 返回 true 表示 SwiftUI 侧已经把焦点
///   清掉了，这时不再补 `resignFirstResponder`。两条通道同时收同一个键盘会让
///   键盘动画被中途打断，安全区/内边距跟着重算，列表就会窜一下。
struct DismissKeyboardOnTapOutside: UIViewRepresentable {
    /// 点击非输入区域时调用。返回 true 表示焦点已由 SwiftUI 处理，无需再 resign。
    /// 设置页这类没有绑定 `@FocusState` 的页面返回 false，由这里兜底。
    var onTapOutside: () -> Bool = { false }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onWindowChanged = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        context.coordinator.onTapOutside = onTapOutside
        context.coordinator.attach(to: uiView.window)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTapOutside: onTapOutside)
    }

    final class ProbeView: UIView {
        var onWindowChanged: ((UIWindow?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // 视图刚创建时 window 还是 nil，真正挂上去之后才拿得到。
            onWindowChanged?(window)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTapOutside: () -> Bool

        private weak var installedWindow: UIWindow?
        private var recognizer: UITapGestureRecognizer?

        init(onTapOutside: @escaping () -> Bool) {
            self.onTapOutside = onTapOutside
        }

        func attach(to window: UIWindow?) {
            guard let window else { return }
            guard window !== installedWindow else { return }

            detach()

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            window.addGestureRecognizer(tap)

            recognizer = tap
            installedWindow = window
        }

        private func detach() {
            if let recognizer {
                installedWindow?.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            installedWindow = nil
        }

        @objc private func handleTap() {
            // 一条通道：SwiftUI 接住了就不再强制 resign。
            if onTapOutside() { return }

            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            // 输入控件本身放行，否则点不到光标位置。
            var node = touch.view
            while let current = node {
                if current is UITextField || current is UITextView {
                    return false
                }
                node = current.superview
            }

            // 正在输入的输入框整体放行（含内嵌的清空按钮）。
            // 这里用 UIKit 自己的坐标换算，矩形就是控件此刻真实的位置，
            // 不会出现「按 SwiftUI 的 .global 记下来、再和 window 坐标比」那种错位。
            // 放大 40pt 是为了盖住输入框两侧的图标和内边距。
            if let window = touch.window,
               let field = firstResponder(in: window) {
                let rect = field.convert(field.bounds, to: window)
                    .insetBy(dx: -40, dy: -8)
                if rect.contains(touch.location(in: window)) {
                    return false
                }
            }
            return true
        }

        /// 找到窗口里当前正在编辑的输入框（没有就是 nil）。
        private func firstResponder(in window: UIWindow) -> UITextField? {
            func find(_ view: UIView) -> UITextField? {
                if let field = view as? UITextField, field.isFirstResponder {
                    return field
                }
                for subview in view.subviews {
                    if let found = find(subview) {
                        return found
                    }
                }
                return nil
            }
            return find(window)
        }
    }
}
