import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // До первого кадра Flutter по умолчанию чёрное полотно — совпадаем с AppColors.backgroundLight (#FAFAF8).
    flutterViewController.backgroundColor = NSColor(
      calibratedRed: 250.0 / 255.0,
      green: 250.0 / 255.0,
      blue: 248.0 / 255.0,
      alpha: 1.0
    )
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
