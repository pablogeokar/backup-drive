import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
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
        result(url.path)
      } else {
        result(nil)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
