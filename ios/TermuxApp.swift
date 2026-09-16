import SwiftUI

/// New app entry point for the full Termux-style GUI.
///
/// IMPORTANT: delete the old `TermuxSwiftApp.swift` from the first version
/// (it had the @main attribute) or the project won't compile — a target can
/// only have one @main. `DemoShellSession.swift` can be deleted too; the
/// environment is now `TermuxShellSession`.

@main
struct TermuxApp: App {
    var body: some Scene {
        WindowGroup {
            TermuxRoot()
                .ignoresSafeArea(.container, edges: .bottom)
                .preferredColorScheme(.dark)
        }
    }
}

struct TermuxRoot: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> TermuxScreenController {
        TermuxScreenController()
    }

    func updateUIViewController(_ viewController: TermuxScreenController, context: Context) {}
}
