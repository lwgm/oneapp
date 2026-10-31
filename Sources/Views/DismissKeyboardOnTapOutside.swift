import SwiftUI
import UIKit

/// 存放「不拦截」的区域，用引用类型是为了不触发 SwiftUI 重新求值。
///
/// 搜索框是 List 的一行，滚动时它的位置一直在变。如果把这个矩形放进
/// `@State`，每帧滚动都会触发一次视图更新，正好就是掉帧的来源。
/// 这里让手势在点击发生时按需读取最新值，界面本身不需要知道它变了。
final class TapExclusionBox {
    var rect: CGRect = .null
}

/// 点击任意非输入区域收起键盘。
///
/// 为什么不用 SwiftUI 手势：大标题「书库」属于 UIKit 的导航栏视图，
/// 挂在上面的手势永远收不到那里的点击。所以改在 window 上装手势，覆盖整屏。
///
/// 两个关键设置：
/// - `cancelsTouchesInView = false`：不抢走原本的点击，按钮和列表行照常响应
/// - 命中排除区（搜索框所在区域）直接放行：SwiftUI 的 Button 不是 UIControl，
///   靠类型判断拦不住「清空按钮」，所以改用坐标排除
struct DismissKeyboardOnTapOutside: UIViewRepresentable {
    /// 点击空白处时调用，用于把外部的焦点状态一并置为 false。
    var onTapOutside: () -> Void = {}
    /// 不拦截的区域。搜索框内部需要放行，否则点清空按钮会先收键盘。
    let exclusion: TapExclusionBox

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
        Coordinator(onTapOutside: onTapOutside, exclusion: exclusion)
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
        var onTapOutside: () -> Void
        private let exclusion: TapExclusionBox

        private weak var installedWindow: UIWindow?
        private var recognizer: UITapGestureRecognizer?

        init(onTapOutside: @escaping () -> Void, exclusion: TapExclusionBox) {
            self.onTapOutside = onTapOutside
            self.exclusion = exclusion
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
            // 先让 SwiftUI 更新焦点（顺带驱动按钮动画），
            // 再无条件 resign 一次，覆盖没有绑定焦点的页面（例如设置页）。
            onTapOutside()
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
            // 输入控件内部放行，否则点不到光标位置。
            var node = touch.view
            while let current = node {
                if current is UITextField || current is UITextView {
                    return false
                }
                node = current.superview
            }

            // 搜索框整体放行（含内嵌的清空按钮），留一点余量吸收边界误差。
            let rect = exclusion.rect
            if !rect.isNull, let window = touch.window {
                let point = touch.location(in: window)
                if rect.insetBy(dx: -8, dy: -8).contains(point) {
                    return false
                }
            }
            return true
        }
    }
}
