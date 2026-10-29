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
    if let plugin = NSClassFromString("QvacWorklet") as? FlutterPlugin.Type, let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "QvacWorklet") { plugin.register(with: registrar) }
    LocalAiStorage.register(with: engineBridge.pluginRegistry.registrar(forPlugin: "LocalAiStorage")!)
  }
}
