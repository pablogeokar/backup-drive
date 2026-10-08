import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private static var scopedEnvURL: URL?
  private static var scopedURLs: [String: URL] = [:]

  private static func scopedResult(for url: URL) throws -> [String: String] {
    if url.startAccessingSecurityScopedResource() {
      scopedURLs[url.path] = url
    }
    let bookmark = try url.bookmarkData(
      options: .withSecurityScope,
      includingResourceValuesForKeys: nil,
      relativeTo: nil)
    return ["path": url.path, "bookmark": bookmark.base64EncodedString()]
  }
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // NSOpenPanel hides dotfiles by default. The database connection file is
    // conventionally named `.env`, so expose hidden files in this dedicated
    // picker instead of requiring users to know the Cmd+Shift+ period shortcut.
    let envPicker = FlutterMethodChannel(
      name: "backup_drive/env_picker",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    envPicker.setMethodCallHandler { call, result in
      guard call.method == "pickEnv" else { result(FlutterMethodNotImplemented); return }
      let panel = NSOpenPanel()
      panel.canChooseFiles = true
      panel.canChooseDirectories = false
      panel.allowsMultipleSelection = false
      panel.showsHiddenFiles = true
      panel.title = "Selecione o arquivo .env"
      if panel.runModal() == .OK, let url = panel.url {
        MainFlutterWindow.scopedEnvURL?.stopAccessingSecurityScopedResource()
        if url.startAccessingSecurityScopedResource() {
          MainFlutterWindow.scopedEnvURL = url
        }
        result(url.path)
      } else {
        result(nil)
      }
    }

    // Persist access to user-selected backup folders/files across launches.
    // Saving only the POSIX path is insufficient inside the macOS sandbox.
    let bookmarkChannel = FlutterMethodChannel(
      name: "backup_drive/security_scoped_bookmarks",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    bookmarkChannel.setMethodCallHandler { call, result in
      do {
        switch call.method {
        case "pickDirectory":
          let panel = NSOpenPanel()
          panel.canChooseFiles = false
          panel.canChooseDirectories = true
          panel.allowsMultipleSelection = false
          panel.canCreateDirectories = true
          panel.title = "Selecione a pasta dos backups PostgreSQL"
          if panel.runModal() == .OK, let url = panel.url {
            result(try MainFlutterWindow.scopedResult(for: url))
          } else {
            result(nil)
          }
        case "pickBackupFile":
          let panel = NSOpenPanel()
          panel.canChooseFiles = true
          panel.canChooseDirectories = false
          panel.allowsMultipleSelection = false
          panel.title = "Selecione um backup PostgreSQL"
          if panel.runModal() == .OK, let url = panel.url {
            result(try MainFlutterWindow.scopedResult(for: url))
          } else {
            result(nil)
          }
        case "restore":
          guard
            let arguments = call.arguments as? [String: Any],
            let encoded = arguments["bookmark"] as? String,
            let data = Data(base64Encoded: encoded)
          else {
            result(FlutterError(code: "invalid_bookmark", message: "Bookmark inválido.", details: nil))
            return
          }
          var isStale = false
          let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale)
          var response = try MainFlutterWindow.scopedResult(for: url)
          response["stale"] = isStale ? "true" : "false"
          result(response)
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(
          code: "bookmark_error",
          message: error.localizedDescription,
          details: nil))
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
