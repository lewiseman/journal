import Flutter
import UIKit
import Network

/// Storage and resource facts survive removal of any inference engine.
final class LocalAiStorage {
  private static let monitor = NWPathMonitor()
  private static let queue = DispatchQueue(label: "journal.ai.network")
  private static var wifi = false
  static func register(with registrar: FlutterPluginRegistrar) {
    monitor.pathUpdateHandler = { path in
      wifi = path.status == .satisfied && path.usesInterfaceType(.wifi) && !path.isExpensive
    }
    monitor.start(queue: queue)
    let channel = FlutterMethodChannel(name: "journal/local_ai_storage", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      do {
        var directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
          appropriateFor: nil, create: true).appendingPathComponent("ai_models", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        switch call.method {
        case "directory": result(directory.path)
        case "resources":
          let attributes = try FileManager.default.attributesOfFileSystem(forPath: directory.path)
          result(["freeBytes": attributes[.systemFreeSize] as? UInt64 ?? 0,
            "ramBytes": ProcessInfo.processInfo.physicalMemory, "wifi": queue.sync { wifi }])
        default: result(FlutterMethodNotImplemented)
        }
      } catch { result(FlutterError(code: "RESOURCE", message: "Model storage is unavailable.", details: nil)) }
    }
  }
}
