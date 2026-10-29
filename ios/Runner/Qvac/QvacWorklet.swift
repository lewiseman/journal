// Adapted from qvac_flutter, Apache-2.0. See native/qvac/THIRD_PARTY_NOTICES.md.
#if canImport(BareKit)
import BareKit
import Flutter
import UIKit

/// Runs the QVAC worker in a BareKit worklet and passes its IPC bytes to Dart.
/// Dart speaks bare-rpc over these bytes; this side never looks inside them.
@objc(QvacWorklet) public class QvacWorklet: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var worklet: BareWorklet?
  private var ipc: BareIPC?
  private var sink: FlutterEventSink?
  // Bytes that arrived before Dart started listening.
  private var early: [Data] = []
  private var outbox: [Data] = []
  private var writing = false
  private var suspended = false
  @objc private func background() {
    suspended = true
    sink?(["state": "interrupted"])
    worklet?.suspend(withLinger: 0)
  }
  @objc private func foreground() {
    suspended = false
    worklet?.resume()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = QvacWorklet()
    NotificationCenter.default.addObserver(instance, selector: #selector(instance.background), name: UIApplication.didEnterBackgroundNotification, object: nil)
    NotificationCenter.default.addObserver(instance, selector: #selector(instance.foreground), name: UIApplication.willEnterForegroundNotification, object: nil)
    let methods = FlutterMethodChannel(name: "journal/qvac", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: methods)
    let events = FlutterEventChannel(name: "journal/qvac_ipc", binaryMessenger: registrar.messenger())
    events.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      let args = call.arguments as? [String: Any] ?? [:]
      result(start(homeDir: args["homeDir"] as? String))
    case "write":
      guard let bytes = call.arguments as? FlutterStandardTypedData else {
        return result(FlutterError(code: "bad_args", message: "write needs bytes", details: nil))
      }
      if suspended { worklet?.resume() } // Dart is sending cancellation/shutdown.
      write(bytes.data)
      result(nil)
    case "stop":
      stop()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func start(homeDir: String?) -> Any {
    guard !suspended else { return FlutterError(code: "NOT_READY", message: "Keep Journal in the foreground.", details: nil) }
    // Left over from before a hot restart. Dart shuts it down and starts again.
    if worklet != nil {
      early.removeAll()
      return "running"
    }
    guard let url = Bundle.main.url(forResource: "worker", withExtension: "bundle"),
      let source = try? Data(contentsOf: url)
    else {
      return FlutterError(code: "no_bundle", message: "worker.bundle is missing. Run npm run build in tool/worker.", details: nil)
    }
    guard let home = homeDir ?? defaultHome() else {
      return FlutterError(code: "start_failed", message: "Could not create the model folder", details: nil)
    }
    guard let config = try? JSONSerialization.data(withJSONObject: ["HOME_DIR": home]),
      let worklet = BareWorklet(configuration: nil)
    else {
      return FlutterError(code: "start_failed", message: "Could not create the BareKit worklet", details: nil)
    }
    // Same argument shape as QVAC's Expo client: the JSON config must be third.
    worklet.start("/worker.bundle", source: source, arguments: ["journal/qvac", "worker.bundle", String(decoding: config, as: UTF8.self)])
    self.worklet = worklet
    ipc = BareIPC(worklet: worklet)
    read()
    return "started"
  }

  // Models are big and can be downloaded again, so they stay out of iCloud backups.
  private func defaultHome() -> String? {
    guard var url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
      .appendingPathComponent("qvac", isDirectory: true),
      (try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)) != nil
    else { return nil }
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? url.setResourceValues(values)
    return url.path
  }

  private func read() {
    guard let current = ipc else { return }
    current.read { [weak self] data, error in
      DispatchQueue.main.async {
        guard let self = self, self.ipc === current else { return }
        if let error = error {
          self.emit(FlutterError(code: "ipc_error", message: error.localizedDescription, details: nil))
        } else if let data = data {
          self.emit(FlutterStandardTypedData(bytes: data))
          self.read()
        } else {
          self.emit(FlutterEndOfEventStream)
        }
      }
    }
  }

  private func emit(_ event: Any) {
    if let sink = sink {
      sink(event)
    } else if let typed = event as? FlutterStandardTypedData {
      early.append(typed.data)
    }
  }

  // One write at a time, so frames reach the worker in order.
  private func write(_ data: Data) {
    outbox.append(data)
    flush()
  }

  private func flush() {
    guard !writing, let ipc = ipc, !outbox.isEmpty else { return }
    writing = true
    ipc.write(outbox.removeFirst()) { [weak self] error in
      DispatchQueue.main.async {
        guard let self = self, self.ipc === ipc else { return }
        self.writing = false
        if let error = error {
          self.emit(FlutterError(code: "ipc_error", message: error.localizedDescription, details: nil))
        }
        self.flush()
      }
    }
  }

  // Dart sends __shutdown__ first; terminating without it crashes the next start.
  private func stop() {
    worklet?.resume()
    ipc?.close()
    ipc = nil
    worklet?.terminate()
    worklet = nil
    outbox.removeAll()
    early.removeAll()
    writing = false
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    NotificationCenter.default.removeObserver(self)
    stop()
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    for data in early {
      events(FlutterStandardTypedData(bytes: data))
    }
    early.removeAll()
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }
}

#endif
