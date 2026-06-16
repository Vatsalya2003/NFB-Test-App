// DisableInteractivePopGesture.swift
// Blocks system swipe-back (edge and full-screen) on pushed navigation screens.
// Back navigation uses the nav bar button or in-app gestures we define (3-finger swipe, etc.).

import SwiftUI
import UIKit

// MARK: - Public modifier

extension View {
    /// Disables UIKit swipe-to-pop on the enclosing `UINavigationController`.
    func disableInteractivePopGesture() -> some View {
        overlay(NavigationPopGestureDisablerView().frame(width: 0, height: 0))
    }
}

// MARK: - Gesture blocker

/// Shared delegate that refuses every interactive pop gesture.
final class NavigationPopGestureBlocker: NSObject, UIGestureRecognizerDelegate {
    static let shared = NavigationPopGestureBlocker()

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    /// Installs the blocker on all known navigation-controller back-swipe recognizers.
    static func install(on navigationController: UINavigationController) {
        for recognizer in popGestureRecognizers(on: navigationController) {
            recognizer.isEnabled = true
            recognizer.delegate = shared
        }
    }

    private static func popGestureRecognizers(on navigationController: UINavigationController) -> [UIGestureRecognizer] {
        var result: [UIGestureRecognizer] = []
        if let edgePop = navigationController.interactivePopGestureRecognizer {
            result.append(edgePop)
        }

        // iOS 18+ full-screen swipe-back (works anywhere on screen, not just the edge).
        if #available(iOS 18.0, *) {
            let selector = NSSelectorFromString("interactiveContentPopGestureRecognizer")
            if navigationController.responds(to: selector),
               let contentPop = navigationController.perform(selector)?.takeUnretainedValue() as? UIGestureRecognizer {
                result.append(contentPop)
            }
        }

        return result
    }
}

// MARK: - SwiftUI bridge

private struct NavigationPopGestureDisablerView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> PopGestureDisablerHostController {
        PopGestureDisablerHostController()
    }

    func updateUIViewController(_ uiViewController: PopGestureDisablerHostController, context: Context) {
        uiViewController.applyBlocker()
    }
}

private final class PopGestureDisablerHostController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyBlocker()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyBlocker()
        // SwiftUI attaches the navigation controller slightly after appear — re-apply once more.
        DispatchQueue.main.async { [weak self] in
            self?.applyBlocker()
        }
    }

    func applyBlocker() {
        if let navigationController = resolveNavigationController() {
            NavigationPopGestureBlocker.install(on: navigationController)
        }
    }

    private func resolveNavigationController() -> UINavigationController? {
        if let navigationController {
            return navigationController
        }

        var ancestor: UIViewController? = parent
        while let current = ancestor {
            if let navigationController = current as? UINavigationController {
                return navigationController
            }
            if let navigationController = current.navigationController {
                return navigationController
            }
            ancestor = current.parent
        }

        return findNavigationController(in: view.window?.rootViewController)
    }

    private func findNavigationController(in viewController: UIViewController?) -> UINavigationController? {
        guard let viewController else { return nil }
        if let navigationController = viewController as? UINavigationController {
            return navigationController
        }
        if let navigationController = viewController.navigationController {
            return navigationController
        }
        for child in viewController.children {
            if let navigationController = findNavigationController(in: child) {
                return navigationController
            }
        }
        if let presented = viewController.presentedViewController {
            return findNavigationController(in: presented)
        }
        return nil
    }
}
