import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // App de bandeja: fechar a janela nunca encerra o processo. Quem encerra é
  // o item "Sair" do menu da bandeja (TrayService._quit).
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
