import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var menuChannel: FlutterMethodChannel?

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationWillFinishLaunching(_ notification: Notification) {
    // The Flutter delegate first puts the app name in the application menu.
    super.applicationWillFinishLaunching(notification)
    if let mainMenu = NSApp.mainMenu {
      AppMenu.configure(mainMenu, delegate: self)
    }
  }

  // MARK: Menu commands, handled by the app (lib/src/app/platform_services.dart)

  @objc func newEntry(_ sender: Any?) { sendMenuCommand("newItem") }
  @objc func lockVault(_ sender: Any?) { sendMenuCommand("lock") }
  @objc func openSettings(_ sender: Any?) { sendMenuCommand("settings") }

  private func sendMenuCommand(_ command: String) {
    if menuChannel == nil, let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      menuChannel = FlutterMethodChannel(name: "thevault/menu", binaryMessenger: controller.engine.binaryMessenger)
    }
    menuChannel?.invokeMethod(command, arguments: nil)
  }
}

/// The menu bar: the standard menus of MainMenu.xib trimmed to what the app uses, the app's own commands
/// (New Entry ⌘N, Lock ⌘L, Settings… ⌘,) and Italian titles on a Mac in Italian.
enum AppMenu {
  /// Text-editor submenus that the app's fields don't use; they would also take ⌘F and ⌘E from the app.
  private static let unusedEditItems: Set<String> = ["Find", "Spelling and Grammar", "Substitutions", "Transformations", "Speech"]

  private static let italianTitles: [String: String] = [
    "File": "Archivio",
    "New Entry": "Nuova voce",
    "Lock": "Blocca",
    "Settings…": "Impostazioni…",
    "Services": "Servizi",
    "Hide Others": "Nascondi altre",
    "Show All": "Mostra tutte",
    "Edit": "Composizione",
    "Undo": "Annulla",
    "Redo": "Ripristina",
    "Cut": "Taglia",
    "Copy": "Copia",
    "Paste": "Incolla",
    "Paste and Match Style": "Incolla e adatta stile",
    "Delete": "Elimina",
    "Select All": "Seleziona tutto",
    "View": "Vista",
    "Enter Full Screen": "Entra in modalità a tutto schermo",
    "Window": "Finestra",
    "Minimize": "Contrai",
    "Zoom": "Ridimensiona",
    "Bring All to Front": "Porta tutto in primo piano",
  ]

  /// Titles that end with the app name ("About The Vault"…).
  private static let italianPrefixes: [(String, String)] = [("About ", "Informazioni su "), ("Hide ", "Nascondi "), ("Quit ", "Esci da ")]

  static func configure(_ mainMenu: NSMenu, delegate: AppDelegate) {
    // No help book: no Help menu.
    for item in mainMenu.items where item.title == "Help" {
      mainMenu.removeItem(item)
    }

    if let edit = mainMenu.items.first(where: { $0.title == "Edit" })?.submenu {
      for item in edit.items where unusedEditItems.contains(item.title) {
        edit.removeItem(item)
      }
      while let last = edit.items.last, last.isSeparatorItem {
        edit.removeItem(last)
      }
    }

    if let appMenu = mainMenu.items.first?.submenu {
      for item in appMenu.items where item.title == "Preferences…" {
        item.title = "Settings…"
        item.action = #selector(AppDelegate.openSettings(_:))
        item.target = delegate
      }
    }

    let file = NSMenu(title: "File")
    let newEntryItem = NSMenuItem(title: "New Entry", action: #selector(AppDelegate.newEntry(_:)), keyEquivalent: "n")
    newEntryItem.target = delegate
    file.addItem(newEntryItem)
    file.addItem(NSMenuItem.separator())
    let lockItem = NSMenuItem(title: "Lock", action: #selector(AppDelegate.lockVault(_:)), keyEquivalent: "l")
    lockItem.target = delegate
    file.addItem(lockItem)
    let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
    fileItem.submenu = file
    mainMenu.insertItem(fileItem, at: min(1, mainMenu.items.count))

    if Locale.preferredLanguages.first?.hasPrefix("it") ?? false {
      translate(mainMenu)
    }
  }

  private static func translate(_ menu: NSMenu) {
    menu.title = italian(menu.title)
    for item in menu.items where !item.isSeparatorItem {
      item.title = italian(item.title)
      if let submenu = item.submenu {
        translate(submenu)
      }
    }
  }

  private static func italian(_ title: String) -> String {
    if let exact = italianTitles[title] {
      return exact
    }
    for (prefix, replacement) in italianPrefixes where title.hasPrefix(prefix) {
      return replacement + title.dropFirst(prefix.count)
    }
    return title
  }
}
