import SwiftUI

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Everything starts here rather than in a view: on a background relaunch
        // (significant location change) no scene is created.
        let reason = launchOptions?[.location] != nil ? "relaunched by iOS for a location event" : "normal launch"
        let state = application.applicationState == .background ? "in background" : "in foreground"
        DiagnosticsLog.shared.processStarted("\(reason), \(state)")
        AppModel.registerBackgroundTasks()
        AppModel.shared.launch()
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        DiagnosticsLog.shared.processTerminating()
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        DiagnosticsLog.shared.log("Memory warning – iOS may kill background apps soon")
    }
}

@main
struct IntfyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(AppModel.shared)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: AppModel.shared.becameActive()
            case .background: AppModel.shared.enteredBackground()
            default: break
            }
        }
    }
}
