import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    PrivateClipboard.register(with: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

/// Copies values so that they stay private (lib/src/app/platform_services.dart):
/// - marked "concealed": clipboard managers that follow nspasteboard.org don't show or keep them;
/// - only on this Mac: Universal Clipboard does not hand them to the iPhone or to other Macs.
enum PrivateClipboard {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "thevault/clipboard", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "copy", let text = call.arguments as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      let pasteboard = NSPasteboard.general
      _ = pasteboard.prepareForNewContents(with: .currentHostOnly)
      let item = NSPasteboardItem()
      _ = item.setString(text, forType: .string)
      _ = item.setString("", forType: NSPasteboard.PasteboardType(rawValue: "org.nspasteboard.ConcealedType"))
      result(pasteboard.writeObjects([item]))
    }
  }
}
