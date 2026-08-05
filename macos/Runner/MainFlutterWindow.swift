import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Own the Sparkle coordinator on the AppDelegate so it outlives the window.
    if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
      appDelegate.macosUpdater = MacOSUpdater.register(with: flutterViewController)
    }

    super.awakeFromNib()
  }
}
