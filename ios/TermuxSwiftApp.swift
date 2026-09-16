import SwiftUI
import UIKit

// termux-swift / iOS port
// Swift rewrite of the `app` Gradle module (TermuxActivity.java and friends).
// The Android app's Activity + TerminalView stack becomes a SwiftUI App
// wrapping a UIKit TerminalView via UIViewControllerRepresentable.

@main
struct TermuxSwiftApp: App {
    var body: some Scene {
        WindowGroup {
            TerminalScreen()
                .ignoresSafeArea(.container, edges: .bottom)
                .preferredColorScheme(.dark)
        }
    }
}

struct TerminalScreen: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> TerminalViewController {
        TerminalViewController()
    }

    func updateUIViewController(_ viewController: TerminalViewController, context: Context) {}
}

final class TerminalViewController: UIViewController, TerminalSessionDelegate {

    private let terminalView = TerminalView(frame: .zero)
    private let session: TerminalSession = DemoShellSession()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        terminalView.frame = view.bounds
        terminalView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(terminalView)

        terminalView.session = session
        session.delegate = self
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        session.start()
        terminalView.becomeFirstResponder()
    }

    // MARK: TerminalSessionDelegate

    func session(_ session: TerminalSession, didOutput data: Data) {
        // The demo session is synchronous, so we're already on the main thread.
        terminalView.feed(data)
    }

    func sessionDidExit(_ session: TerminalSession) {
        terminalView.feed(Data("\r\n[process exited]\r\n".utf8))
    }
}
