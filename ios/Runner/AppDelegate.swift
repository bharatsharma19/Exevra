import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerSecureWindowChannel(messenger: engineBridge.applicationRegistrar.messenger())
  }

  /// Answers the "exevra/secure_window" channel that Android uses to set
  /// FLAG_SECURE. iOS has no equivalent window flag, so `setSecure` succeeds
  /// without doing anything rather than failing with MissingPluginException.
  /// Hiding content in the app switcher is not done natively here: the
  /// privacy cover is drawn by the Flutter app on both platforms.
  private func registerSecureWindowChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "exevra/secure_window", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "setSecure":
        guard let arguments = call.arguments as? [String: Any],
          arguments["enabled"] is Bool
        else {
          result(
            FlutterError(
              code: "invalid_argument",
              message: "setSecure expects a boolean 'enabled' argument.",
              details: nil))
          return
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
