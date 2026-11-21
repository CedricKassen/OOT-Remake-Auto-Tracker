import Cocoa
import FlutterMacOS
import macos_window_utils

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // macos_window_utils hosts the Flutter view so the app can have a
    // translucent sidebar and a unified toolbar like a native Mac app.
    let windowFrame = self.frame
    let macOSWindowUtilsViewController = MacOSWindowUtilsViewController()
    let flutterViewController = macOSWindowUtilsViewController.flutterViewController
    self.contentViewController = macOSWindowUtilsViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 860, height: 560)

    MainFlutterWindowManipulator.start(mainFlutterWindow: self)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
