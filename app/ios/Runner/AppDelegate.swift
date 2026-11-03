import Core
import Flutter
import NetworkExtension
import UIKit

/// The Go core (Core.xcframework, gomobile bind -target=ios) and the VPN.
///
/// While the VPN is off, the core runs in this process with the proxy off,
/// so the settings and the accounts work, as on Android. Turned on, the
/// packet tunnel provider (PacketTunnel/PacketTunnelProvider.swift) runs its
/// own core in the system's extension process: the VPN's tunnel needs one,
/// and only the system may keep it alive when the UI is gone. The app then
/// talks to that core through the same HTTP API on loopback; both cores use
/// the same data folder (the App Group's), so the accounts, the settings
/// and the API token carry over.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
    /// The folder both processes share (PacketTunnel reads the same constant).
    static let appGroupId = "group.com.arman.firefoxvpn"
    static let tunnelBundleId = "com.arman.firefoxvpn.PacketTunnel"

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    }
}

/// The channel's work, kept apart from the app delegate so the scene
/// delegate can attach it when the Flutter view controller is there.
@objc class IosChannel: NSObject {
    static let name = "app/ios"

    private static let worker = DispatchQueue(label: "app.ios.core", qos: .userInitiated)
    /// The VPN is going away: isRunning says no at once, so the app starts
    /// its own core (off) without waiting for the system's status.
    private static var stoppingTunnel = false
    private static var stoppingAt = Date.distantPast

    /// Attaches the channel to the view controller's messenger.
    static func attach(_ messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
        channel.setMethodCallHandler { call, result in
            handle(call, result)
        }
    }

    /// The app group's data folder, the extension's too.
    static func dataDir() -> String {
        let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppDelegate.appGroupId)?
            .path ?? NSTemporaryDirectory()
        return base + "/data"
    }

    /// Whether the VPN's tunnel is up (or coming up) and its extension,
    /// then, owns the core the app talks to.
    static func tunnelActive() -> Bool {
        if stoppingTunnel && Date().timeIntervalSince(stoppingAt) < 10 {
            return false
        }
        guard let manager = current else { return false }
        return Self.tunnelActive(manager: manager)
    }

    /// The manager this process saved or started last, so tunnelActive
    /// answers without a loadAll round trip.
    private static var current: NETunnelProviderManager?

    private static func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        switch call.method {
        case "dataDir":
            result(dataDir())
        case "isRunning":
            if MobileRunning() {
                result(true)
                return
            }
            loadManagers { managers in
                let on = !(stoppingTunnel && Date().timeIntervalSince(stoppingAt) < 10)
                    && (managers ?? []).contains { m in
                        m.isEnabled && Self.tunnelActive(manager: m)
                    }
                result(on)
            }
        case "startCore":
            // The tunnel's core owns the API while the VPN is on; ask the
            // system, since this process may have started since the tunnel
            // did, and `current` knows nothing of it.
            loadManagers { managers in
                let tunnelOwnsIt = (managers).contains { m in
                    m.isEnabled && Self.tunnelActive(manager: m)
                }
                if tunnelOwnsIt {
                    result(nil)
                    return
                }
                self.worker.async {
                    var err: NSError?
                    let ok = MobileStart(self.dataDir(), false, &err)
                    DispatchQueue.main.async {
                        if ok {
                            result(nil)
                        } else {
                            result(FlutterError(
                                code: "start_failed",
                                message: err?.localizedDescription ?? MobileLastError(),
                                details: nil))
                        }
                    }
                }
            }
        case "setOn":
            let on = (call.arguments as? [String: Any])?["on"] as? Bool ?? false
            if on {
                turnOn(result)
            } else {
                turnOff(result)
            }
        case "connectionMode":
            result("vpn")
        case "setConnectionMode":
            result(nil)
        case "showSpeed":
            result(false)
        case "setShowSpeed":
            result(nil)
        case "abi":
            // The device's processor (app_info), such as ios-arm64.
            result("ios-" + Machine.arch)
        case "isTv":
            result(false)
        case "openUrl":
            let url = (call.arguments as? [String: Any])?["url"] as? String ?? ""
            guard let u = URL(string: url) else {
                result(false)
                return
            }
            UIApplication.shared.open(u, options: [:]) { opened in
                result(opened)
            }
        default:
            // installedApps, appIcon, appRouting, setAppRouting: per-app
            // routing is Android's; iOS has no such VPN control.
            result(FlutterMethodNotImplemented)
        }
    }

    private static func tunnelActive(manager: NETunnelProviderManager) -> Bool {
        switch manager.connection.status {
        case .connected, .connecting, .reasserting:
            return true
        default:
            return false
        }
    }

    /// The tunnel managers, answered on the main thread (the call talks to
    /// the system); empty when there are none or it refused.
    private static func loadManagers(_ done: @escaping ([NETunnelProviderManager]) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { managers, _ in
            DispatchQueue.main.async {
                done(managers ?? [])
            }
        }
    }

    /// Ours among the managers, by the provider's bundle id.
    private static func ours(_ managers: [NETunnelProviderManager]) -> NETunnelProviderManager? {
        managers.first { m in
            (m.protocolConfiguration as? NETunnelProviderProtocol)?
                .providerBundleIdentifier == AppDelegate.tunnelBundleId
        }
    }

    /// Turns the VPN on: the app's core stops (it holds the API's port),
    /// then the tunnel profile is saved and started, which runs the
    /// extension and its core.
    private static func turnOn(_ result: @escaping FlutterResult) {
        worker.async {
            MobileStop()
            DispatchQueue.main.async {
                loadManagers { managers in
                    let manager = ours(managers) ?? NETunnelProviderManager()
                    let protocol_ = (manager.protocolConfiguration as? NETunnelProviderProtocol)
                        ?? NETunnelProviderProtocol()
                    protocol_.providerBundleIdentifier = AppDelegate.tunnelBundleId
                    protocol_.serverAddress = "Firefox VPN"
                    manager.protocolConfiguration = protocol_
                    manager.localizedDescription = "Firefox VPN"
                    manager.isEnabled = true
                    manager.saveToPreferences { error in
                        if let error {
                            result(FlutterError(
                                code: "vpn_denied", message: error.localizedDescription, details: nil))
                            return
                        }
                        manager.loadFromPreferences { _, _ in
                            // The system asks to allow the VPN the first
                            // time; a refusal comes as configurationDisabled.
                            manager.connection.startVPNTunnel { error in
                                if let error {
                                    let code = (error as? NEVPNError) == .configurationDisabled
                                        ? "vpn_denied" : "start_failed"
                                    result(FlutterError(
                                        code: code, message: error.localizedDescription, details: nil))
                                    return
                                }
                                current = manager
                                result(nil)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Turns the VPN off; the extension's core stops with it, and the app
    /// runs its own (off) again as soon as isRunning says no.
    private static func turnOff(_ result: @escaping FlutterResult) {
        loadManagers { managers in
            if let manager = ours(managers) {
                stoppingTunnel = true
                stoppingAt = Date()
                manager.connection.stopVPNTunnel()
            }
            result(nil)
        }
    }
}

/// The device's processor, for the abi the app reports.
enum Machine {
    static var arch: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
