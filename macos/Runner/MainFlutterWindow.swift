import Cocoa
import Darwin
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let workspaceBookmarkKey = "matrix_workspace_bookmark"
  private var workspaceURL: URL?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let workspaceChannel = FlutterMethodChannel(
      name: "matrix/local_workspace",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    workspaceChannel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "getWorkspacePath":
        self?.restoreWorkspace(result: result)
      case "selectWorkspace":
        self?.selectWorkspace(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }

  private func restoreWorkspace(result: @escaping FlutterResult) {
    guard let bookmark = UserDefaults.standard.data(forKey: workspaceBookmarkKey) else {
      result(nil)
      return
    }

    do {
      var isStale = false
      let url = try URL(
        resolvingBookmarkData: bookmark,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale)
      guard url.startAccessingSecurityScopedResource() else {
        result(FlutterError(code: "workspace_access_denied", message: "无法访问已授权的 Matrix 工作区", details: nil))
        return
      }
      workspaceURL = url
      if isStale {
        try saveBookmark(for: url)
      }
      result(url.path)
    } catch {
      UserDefaults.standard.removeObject(forKey: workspaceBookmarkKey)
      result(nil)
    }
  }

  private func selectWorkspace(result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.title = "选择 Matrix 本地工作区"
    panel.message = "请选择或新建一个目录；MCP 只会访问其中的 uploads 和 downloads。"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.directoryURL = realHomeURL

    panel.beginSheetModal(for: self) { [weak self] response in
      guard response == .OK, let url = panel.url else {
        result(nil)
        return
      }

      do {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        guard url.startAccessingSecurityScopedResource() else {
          result(FlutterError(code: "workspace_access_denied", message: "无法获取所选目录的访问授权", details: nil))
          return
        }
        self?.workspaceURL = url
        try self?.saveBookmark(for: url)
        result(url.path)
      } catch {
        result(FlutterError(code: "workspace_bookmark_failed", message: error.localizedDescription, details: nil))
      }
    }
  }

  private func saveBookmark(for url: URL) throws {
    let bookmark = try url.bookmarkData(
      options: [.withSecurityScope],
      includingResourceValuesForKeys: nil,
      relativeTo: nil)
    UserDefaults.standard.set(bookmark, forKey: workspaceBookmarkKey)
  }

  /// NSHomeDirectory() resolves to the Container in a sandboxed app. The POSIX
  /// account entry preserves the real user home used as the picker default.
  private var realHomeURL: URL {
    if let account = getpwuid(getuid()) {
      return URL(fileURLWithPath: String(cString: account.pointee.pw_dir), isDirectory: true)
    }
    return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
  }
}
