import 'package:flutter/foundation.dart';

/// 支持的应用语言
enum AppLanguage { zh, ja, en }

/// 全局语言控制器（简单的 ValueNotifier，避免引入额外状态管理框架）
class AppLanguageController {
  static final ValueNotifier<AppLanguage> notifier = ValueNotifier<AppLanguage>(
    AppLanguage.zh,
  );

  static AppLanguage get current => notifier.value;

  static void setLanguage(AppLanguage language) {
    if (language == notifier.value) return;
    notifier.value = language;
  }
}

/// 简单的文案集中管理
class S {
  static AppLanguage get _lang => AppLanguageController.current;

  // ── 通用 ─────────────────────────────────────────────────────────────────

  static String get appName => 'Matrix';

  static String get configMenuTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return '配置';
      case AppLanguage.ja:
        return '設定';
      case AppLanguage.en:
        return 'Settings';
    }
  }

  static String get loading {
    switch (_lang) {
      case AppLanguage.zh:
        return '加载中...';
      case AppLanguage.ja:
        return '読み込み中...';
      case AppLanguage.en:
        return 'Loading...';
    }
  }

  static String get snackCopied {
    switch (_lang) {
      case AppLanguage.zh:
        return '已复制到剪贴板';
      case AppLanguage.ja:
        return 'クリップボードにコピーしました';
      case AppLanguage.en:
        return 'Copied to clipboard';
    }
  }

  static String get noOutput {
    switch (_lang) {
      case AppLanguage.zh:
        return '(无输出)';
      case AppLanguage.ja:
        return '(出力なし)';
      case AppLanguage.en:
        return '(no output)';
    }
  }

  static String errorResult(Object e) {
    switch (_lang) {
      case AppLanguage.zh:
        return '[错误] $e';
      case AppLanguage.ja:
        return '[エラー] $e';
      case AppLanguage.en:
        return '[Error] $e';
    }
  }

  /// 与 [errorResult] 输出前缀一致，用于判断日志行是否为错误。
  static String get logErrorTag {
    switch (_lang) {
      case AppLanguage.zh:
        return '[错误]';
      case AppLanguage.ja:
        return '[エラー]';
      case AppLanguage.en:
        return '[Error]';
    }
  }

  // ── 语言名称 ──────────────────────────────────────────────────────────────

  static String get languageChinese {
    switch (_lang) {
      case AppLanguage.zh:
        return '中文';
      case AppLanguage.ja:
        return '中国語';
      case AppLanguage.en:
        return 'Chinese';
    }
  }

  static String get languageJapanese {
    switch (_lang) {
      case AppLanguage.zh:
        return '日文';
      case AppLanguage.ja:
        return '日本語';
      case AppLanguage.en:
        return 'Japanese';
    }
  }

  static String get languageEnglish {
    switch (_lang) {
      case AppLanguage.zh:
        return '英文';
      case AppLanguage.ja:
        return '英語';
      case AppLanguage.en:
        return 'English';
    }
  }

  // ── 侧边菜单 ──────────────────────────────────────────────────────────────

  static String get menuProject {
    switch (_lang) {
      case AppLanguage.zh:
        return '项目';
      case AppLanguage.ja:
        return 'プロジェクト';
      case AppLanguage.en:
        return 'Projects';
    }
  }

  static String get menuWebshell {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Webshell';
      case AppLanguage.ja:
        return 'Webshell';
      case AppLanguage.en:
        return 'Webshell';
    }
  }

  static String get menuExp {
    switch (_lang) {
      case AppLanguage.zh:
        return 'EXP';
      case AppLanguage.ja:
        return 'EXP';
      case AppLanguage.en:
        return 'Exploits';
    }
  }

  static String get menuPayload {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Payload';
      case AppLanguage.ja:
        return 'Payload';
      case AppLanguage.en:
        return 'Payloads';
    }
  }

  static String get menuTerminal {
    switch (_lang) {
      case AppLanguage.zh:
        return '完整终端';
      case AppLanguage.ja:
        return 'フルターミナル';
      case AppLanguage.en:
        return 'Terminal';
    }
  }

  static String get menuFrp {
    switch (_lang) {
      case AppLanguage.zh:
        return 'FRP隧道';
      case AppLanguage.ja:
        return 'FRP トンネル';
      case AppLanguage.en:
        return 'FRP Tunnel';
    }
  }

  static String get menuSuo5 {
    switch (_lang) {
      case AppLanguage.zh:
        return 'suo5代理';
      case AppLanguage.ja:
        return 'suo5 プロキシ';
      case AppLanguage.en:
        return 'suo5 Proxy';
    }
  }

  static String get sidebarCollapse {
    switch (_lang) {
      case AppLanguage.zh:
        return '收起';
      case AppLanguage.ja:
        return '折りたたむ';
      case AppLanguage.en:
        return 'Collapse';
    }
  }

  static String get sidebarExpandTooltip {
    switch (_lang) {
      case AppLanguage.zh:
        return '展开菜单';
      case AppLanguage.ja:
        return 'メニューを展開';
      case AppLanguage.en:
        return 'Expand menu';
    }
  }

  // ── 欢迎区 & Dashboard ────────────────────────────────────────────────────

  static String get workspaceWelcomeTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return '> 欢迎使用 Matrix';
      case AppLanguage.ja:
        return '> Matrix へようこそ';
      case AppLanguage.en:
        return '> Welcome to Matrix';
    }
  }

  static String workspaceWelcomeSubtitle(String pageTitle) {
    switch (_lang) {
      case AppLanguage.zh:
        return '当前页面：$pageTitle · 开始您的工作吧';
      case AppLanguage.ja:
        return '現在のページ：$pageTitle · 作業を始めましょう';
      case AppLanguage.en:
        return 'Current page: $pageTitle · Let\'s get started';
    }
  }

  static String get workspaceQuickActions {
    switch (_lang) {
      case AppLanguage.zh:
        return '快捷入口';
      case AppLanguage.ja:
        return 'クイック操作';
      case AppLanguage.en:
        return 'Quick actions';
    }
  }

  static String get quickActionNew {
    switch (_lang) {
      case AppLanguage.zh:
        return '新建';
      case AppLanguage.ja:
        return '新規作成';
      case AppLanguage.en:
        return 'New';
    }
  }

  static String get workspaceRecentActivities {
    switch (_lang) {
      case AppLanguage.zh:
        return '最近活动';
      case AppLanguage.ja:
        return '最近のアクティビティ';
      case AppLanguage.en:
        return 'Recent activity';
    }
  }

  static String recentFileTitle(int index) {
    switch (_lang) {
      case AppLanguage.zh:
        return '项目文件 $index';
      case AppLanguage.ja:
        return 'プロジェクトファイル $index';
      case AppLanguage.en:
        return 'Project file $index';
    }
  }

  static String recentHoursAgo(int hours) {
    switch (_lang) {
      case AppLanguage.zh:
        return '$hours 小时前';
      case AppLanguage.ja:
        return '$hours 時間前';
      case AppLanguage.en:
        return '$hours hours ago';
    }
  }

  // ── 通用操作按钮 ──────────────────────────────────────────────────────────

  static String get actionNewProject {
    switch (_lang) {
      case AppLanguage.zh:
        return '新建项目';
      case AppLanguage.ja:
        return '新規プロジェクト';
      case AppLanguage.en:
        return 'New project';
    }
  }

  static String get actionAddWebshell {
    switch (_lang) {
      case AppLanguage.zh:
        return '添加 Webshell';
      case AppLanguage.ja:
        return 'Webshell を追加';
      case AppLanguage.en:
        return 'Add Webshell';
    }
  }

  static String get actionGoCreateProject {
    switch (_lang) {
      case AppLanguage.zh:
        return '去创建项目';
      case AppLanguage.ja:
        return 'プロジェクトを作成';
      case AppLanguage.en:
        return 'Create project';
    }
  }

  static String get actionRefresh {
    switch (_lang) {
      case AppLanguage.zh:
        return '刷新';
      case AppLanguage.ja:
        return '更新';
      case AppLanguage.en:
        return 'Refresh';
    }
  }

  static String get actionListenConfig {
    switch (_lang) {
      case AppLanguage.zh:
        return '监听配置';
      case AppLanguage.ja:
        return 'リッスン設定';
      case AppLanguage.en:
        return 'Listener config';
    }
  }

  static String get actionCopy {
    switch (_lang) {
      case AppLanguage.zh:
        return '复制';
      case AppLanguage.ja:
        return 'コピー';
      case AppLanguage.en:
        return 'Copy';
    }
  }

  static String get actionCopyBase64 {
    switch (_lang) {
      case AppLanguage.zh:
        return '复制为Base64';
      case AppLanguage.ja:
        return 'Base64でコピー';
      case AppLanguage.en:
        return 'Copy as Base64';
    }
  }

  static String get actionDownload {
    switch (_lang) {
      case AppLanguage.zh:
        return '下载';
      case AppLanguage.ja:
        return 'ダウンロード';
      case AppLanguage.en:
        return 'Download';
    }
  }

  static String get quickActionUpload {
    switch (_lang) {
      case AppLanguage.zh:
        return '上传';
      case AppLanguage.ja:
        return 'アップロード';
      case AppLanguage.en:
        return 'Upload';
    }
  }

  static String get quickActionOpen {
    switch (_lang) {
      case AppLanguage.zh:
        return '打开';
      case AppLanguage.ja:
        return '開く';
      case AppLanguage.en:
        return 'Open';
    }
  }

  // ── Tab / 标签 ────────────────────────────────────────────────────────────

  static String get tabFileManager {
    switch (_lang) {
      case AppLanguage.zh:
        return '文件管理';
      case AppLanguage.ja:
        return 'ファイル管理';
      case AppLanguage.en:
        return 'File manager';
    }
  }

  static String get tabTerminal {
    switch (_lang) {
      case AppLanguage.zh:
        return '终  端';
      case AppLanguage.ja:
        return 'ターミナル';
      case AppLanguage.en:
        return 'Terminal';
    }
  }

  static String get tabSysInfo {
    switch (_lang) {
      case AppLanguage.zh:
        return '系统信息';
      case AppLanguage.ja:
        return 'システム情報';
      case AppLanguage.en:
        return 'System info';
    }
  }

  static String get sectionPrivEsc {
    switch (_lang) {
      case AppLanguage.zh:
        return '提权检查';
      case AppLanguage.ja:
        return '権限昇格チェック';
      case AppLanguage.en:
        return 'Privilege check';
    }
  }

  // ── 通用按钮 ──────────────────────────────────────────────────────────────

  static String get btnCancel {
    switch (_lang) {
      case AppLanguage.zh:
        return '取消';
      case AppLanguage.ja:
        return 'キャンセル';
      case AppLanguage.en:
        return 'Cancel';
    }
  }

  static String get btnConfirm {
    switch (_lang) {
      case AppLanguage.zh:
        return '确定';
      case AppLanguage.ja:
        return '確認';
      case AppLanguage.en:
        return 'OK';
    }
  }

  static String get btnSave {
    switch (_lang) {
      case AppLanguage.zh:
        return '保存';
      case AppLanguage.ja:
        return '保存';
      case AppLanguage.en:
        return 'Save';
    }
  }

  static String get btnDelete {
    switch (_lang) {
      case AppLanguage.zh:
        return '删除';
      case AppLanguage.ja:
        return '削除';
      case AppLanguage.en:
        return 'Delete';
    }
  }

  static String get btnCreate {
    switch (_lang) {
      case AppLanguage.zh:
        return '创建';
      case AppLanguage.ja:
        return '作成';
      case AppLanguage.en:
        return 'Create';
    }
  }

  static String get btnClose {
    switch (_lang) {
      case AppLanguage.zh:
        return '关闭';
      case AppLanguage.ja:
        return '閉じる';
      case AppLanguage.en:
        return 'Close';
    }
  }

  static String get btnAdd {
    switch (_lang) {
      case AppLanguage.zh:
        return '添加';
      case AppLanguage.ja:
        return '追加';
      case AppLanguage.en:
        return 'Add';
    }
  }

  static String get btnRetry {
    switch (_lang) {
      case AppLanguage.zh:
        return '重试';
      case AppLanguage.ja:
        return '再試行';
      case AppLanguage.en:
        return 'Retry';
    }
  }

  static String get btnClear {
    switch (_lang) {
      case AppLanguage.zh:
        return '清空';
      case AppLanguage.ja:
        return 'クリア';
      case AppLanguage.en:
        return 'Clear';
    }
  }

  static String get btnExecute {
    switch (_lang) {
      case AppLanguage.zh:
        return '执行';
      case AppLanguage.ja:
        return '実行';
      case AppLanguage.en:
        return 'Run';
    }
  }

  static String get btnAutoDetect {
    switch (_lang) {
      case AppLanguage.zh:
        return '自动检测';
      case AppLanguage.ja:
        return '自動検出';
      case AppLanguage.en:
        return 'Auto detect';
    }
  }

  static String get btnSwitchProject {
    switch (_lang) {
      case AppLanguage.zh:
        return '切换项目';
      case AppLanguage.ja:
        return 'プロジェクト切替';
      case AppLanguage.en:
        return 'Switch project';
    }
  }

  static String get btnStartListen {
    switch (_lang) {
      case AppLanguage.zh:
        return '启动监听';
      case AppLanguage.ja:
        return '監視開始';
      case AppLanguage.en:
        return 'Start listen';
    }
  }

  static String get btnStopListen {
    switch (_lang) {
      case AppLanguage.zh:
        return '关闭监听';
      case AppLanguage.ja:
        return '監視停止';
      case AppLanguage.en:
        return 'Stop listen';
    }
  }

  static String get btnPortOccupied {
    switch (_lang) {
      case AppLanguage.zh:
        return '端口占用';
      case AppLanguage.ja:
        return 'ポート使用中';
      case AppLanguage.en:
        return 'Port in use';
    }
  }

  static String get btnCheckAll {
    switch (_lang) {
      case AppLanguage.zh:
        return '一键检查';
      case AppLanguage.ja:
        return '一括チェック';
      case AppLanguage.en:
        return 'Check all';
    }
  }

  // ── Tooltip ───────────────────────────────────────────────────────────────

  static String get tooltipEdit {
    switch (_lang) {
      case AppLanguage.zh:
        return '编辑';
      case AppLanguage.ja:
        return '編集';
      case AppLanguage.en:
        return 'Edit';
    }
  }

  static String get tooltipDelete {
    switch (_lang) {
      case AppLanguage.zh:
        return '删除';
      case AppLanguage.ja:
        return '削除';
      case AppLanguage.en:
        return 'Delete';
    }
  }

  static String get tooltipBack {
    switch (_lang) {
      case AppLanguage.zh:
        return '返回';
      case AppLanguage.ja:
        return '戻る';
      case AppLanguage.en:
        return 'Back';
    }
  }

  static String get tooltipView {
    switch (_lang) {
      case AppLanguage.zh:
        return '查看';
      case AppLanguage.ja:
        return '表示';
      case AppLanguage.en:
        return 'View';
    }
  }

  static String get tooltipCopyContent {
    switch (_lang) {
      case AppLanguage.zh:
        return '复制内容';
      case AppLanguage.ja:
        return '内容をコピー';
      case AppLanguage.en:
        return 'Copy content';
    }
  }

  static String get tooltipClearTerminal {
    switch (_lang) {
      case AppLanguage.zh:
        return '清空终端';
      case AppLanguage.ja:
        return 'ターミナルをクリア';
      case AppLanguage.en:
        return 'Clear terminal';
    }
  }

  static String get tooltipFullTerminal {
    switch (_lang) {
      case AppLanguage.zh:
        return '完整终端（反弹 Shell）';
      case AppLanguage.ja:
        return 'フルターミナル（リバースシェル）';
      case AppLanguage.en:
        return 'Full terminal (reverse shell)';
    }
  }

  static String get tooltipParentDir {
    switch (_lang) {
      case AppLanguage.zh:
        return '上级目录';
      case AppLanguage.ja:
        return '上位ディレクトリ';
      case AppLanguage.en:
        return 'Parent directory';
    }
  }

  static String get tooltipUploadFile {
    switch (_lang) {
      case AppLanguage.zh:
        return '上传文件';
      case AppLanguage.ja:
        return 'ファイルをアップロード';
      case AppLanguage.en:
        return 'Upload file';
    }
  }

  static String get tooltipDownload {
    switch (_lang) {
      case AppLanguage.zh:
        return '下载';
      case AppLanguage.ja:
        return 'ダウンロード';
      case AppLanguage.en:
        return 'Download';
    }
  }

  static String get tooltipClose {
    switch (_lang) {
      case AppLanguage.zh:
        return '关闭';
      case AppLanguage.ja:
        return '閉じる';
      case AppLanguage.en:
        return 'Close';
    }
  }

  static String get selectDownloadDir {
    switch (_lang) {
      case AppLanguage.zh:
        return '选择下载目录';
      case AppLanguage.ja:
        return 'ダウンロード先を選択';
      case AppLanguage.en:
        return 'Select download folder';
    }
  }

  static String get snackWriteNotSupported {
    switch (_lang) {
      case AppLanguage.zh:
        return '当前连接器不支持文件写入';
      case AppLanguage.ja:
        return '現在のコネクターはファイル書き込みをサポートしていません';
      case AppLanguage.en:
        return 'Current connector does not support file write';
    }
  }

  static String get tooltipSwitchToSeparate {
    switch (_lang) {
      case AppLanguage.zh:
        return '切换到分离式（底部输入栏）';
      case AppLanguage.ja:
        return '分離モードへ切替（下部入力バー）';
      case AppLanguage.en:
        return 'Switch to split mode (bottom input bar)';
    }
  }

  static String get tooltipSwitchToIntegrated {
    switch (_lang) {
      case AppLanguage.zh:
        return '切换到一体式（模拟真实终端）';
      case AppLanguage.ja:
        return '統合モードへ切替（ターミナル風）';
      case AppLanguage.en:
        return 'Switch to integrated mode (terminal-like)';
    }
  }

  // ── Payload 页面 ──────────────────────────────────────────────────────────

  static String payloadCount(int n) {
    switch (_lang) {
      case AppLanguage.zh:
        return '$n 个文件';
      case AppLanguage.ja:
        return '$n ファイル';
      case AppLanguage.en:
        return '$n files';
    }
  }

  static String get titleDeletePayload {
    switch (_lang) {
      case AppLanguage.zh:
        return '删除 Payload';
      case AppLanguage.ja:
        return 'Payload 削除';
      case AppLanguage.en:
        return 'Delete payload';
    }
  }

  static String confirmDeletePayload(String name) {
    switch (_lang) {
      case AppLanguage.zh:
        return '确定要删除 "$name" 吗？\n此操作不可撤销。';
      case AppLanguage.ja:
        return '"$name" を削除してもよろしいですか？\nこの操作は元に戻せません。';
      case AppLanguage.en:
        return 'Delete "$name"?\nThis action cannot be undone.';
    }
  }

  static String get payloadNoneFound {
    switch (_lang) {
      case AppLanguage.zh:
        return '暂无 Payload';
      case AppLanguage.ja:
        return 'Payload が見つかりません';
      case AppLanguage.en:
        return 'No payloads found';
    }
  }

  static String get payloadImportHint {
    switch (_lang) {
      case AppLanguage.zh:
        return '导入文件以开始';
      case AppLanguage.ja:
        return 'ファイルをインポートして開始';
      case AppLanguage.en:
        return 'Import a file to get started';
    }
  }

  static String get payloadBuiltinTooltip {
    switch (_lang) {
      case AppLanguage.zh:
        return '内置默认，不可删除';
      case AppLanguage.ja:
        return '組み込みデフォルト、削除不可';
      case AppLanguage.en:
        return 'Built-in default, cannot delete';
    }
  }

  static String get payloadBuiltin {
    switch (_lang) {
      case AppLanguage.zh:
        return '内置';
      case AppLanguage.ja:
        return '組み込み';
      case AppLanguage.en:
        return 'Built-in';
    }
  }

  static String get binaryPreviewDisabled {
    switch (_lang) {
      case AppLanguage.zh:
        return '二进制 Payload，无法预览。';
      case AppLanguage.ja:
        return 'バイナリ Payload のためプレビュー不可。';
      case AppLanguage.en:
        return 'Binary payload detected.\nPreview disabled.';
    }
  }

  static String snackImported(String name) {
    switch (_lang) {
      case AppLanguage.zh:
        return '已导入 $name';
      case AppLanguage.ja:
        return '$name をインポートしました';
      case AppLanguage.en:
        return 'Imported $name';
    }
  }

  static String snackImportFailed(Object e) {
    switch (_lang) {
      case AppLanguage.zh:
        return '导入失败: $e';
      case AppLanguage.ja:
        return 'インポート失敗: $e';
      case AppLanguage.en:
        return 'Import failed: $e';
    }
  }

  static String snackSavedTo(String path) {
    switch (_lang) {
      case AppLanguage.zh:
        return '已保存到 $path';
      case AppLanguage.ja:
        return '$path に保存しました';
      case AppLanguage.en:
        return 'Saved to $path';
    }
  }

  static String snackSaveFailed(Object e) {
    switch (_lang) {
      case AppLanguage.zh:
        return '保存失败: $e';
      case AppLanguage.ja:
        return '保存失敗: $e';
      case AppLanguage.en:
        return 'Save failed: $e';
    }
  }

  static String get snackBinaryCopyUnsupported {
    switch (_lang) {
      case AppLanguage.zh:
        return '二进制 Payload 不支持直接复制文本';
      case AppLanguage.ja:
        return 'バイナリ Payload はテキストとしてコピーできません';
      case AppLanguage.en:
        return 'Binary payload cannot be copied as text';
    }
  }

  static String get snackCopiedBase64 {
    switch (_lang) {
      case AppLanguage.zh:
        return '已复制为 Base64';
      case AppLanguage.ja:
        return 'Base64 でコピーしました';
      case AppLanguage.en:
        return 'Copied as Base64';
    }
  }

  // ── 项目管理 ──────────────────────────────────────────────────────────────

  static String get fieldProjectName {
    switch (_lang) {
      case AppLanguage.zh:
        return '项目名称';
      case AppLanguage.ja:
        return 'プロジェクト名';
      case AppLanguage.en:
        return 'Project name';
    }
  }

  static String get fieldDomainOrId {
    switch (_lang) {
      case AppLanguage.zh:
        return '目标 URL *';
      case AppLanguage.ja:
        return 'ターゲット URL *';
      case AppLanguage.en:
        return 'Target URL *';
    }
  }

  static String get hintDomainOrId {
    switch (_lang) {
      case AppLanguage.zh:
        return '例如：https://target.example 或 http://192.168.1.1:8080';
      case AppLanguage.ja:
        return '例：https://target.example または http://192.168.1.1:8080';
      case AppLanguage.en:
        return 'e.g. https://target.example or http://192.168.1.1:8080';
    }
  }

  static String get fieldDescription {
    switch (_lang) {
      case AppLanguage.zh:
        return '描述（可选）';
      case AppLanguage.ja:
        return '説明（任意）';
      case AppLanguage.en:
        return 'Description (optional)';
    }
  }

  static String titleEditProject(int id) {
    switch (_lang) {
      case AppLanguage.zh:
        return '编辑项目 #$id';
      case AppLanguage.ja:
        return 'プロジェクト #$id を編集';
      case AppLanguage.en:
        return 'Edit project #$id';
    }
  }

  static String get webModeWarning {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Web 模式：数据仅保存在内存中，刷新页面将丢失。请使用桌面版以持久化存储。';
      case AppLanguage.ja:
        return 'Web モード：データはメモリのみに保存されます。ページを更新すると失われます。永続保存にはデスクトップ版をご利用ください。';
      case AppLanguage.en:
        return 'Web mode: data is stored in memory only and will be lost on refresh. Use the desktop app for persistent storage.';
    }
  }

  static String projectEmptyHint(String newProjectLabel) {
    switch (_lang) {
      case AppLanguage.zh:
        return '暂无项目，点击「$newProjectLabel」开始';
      case AppLanguage.ja:
        return 'プロジェクトがありません。「$newProjectLabel」をクリックして開始';
      case AppLanguage.en:
        return 'No projects yet. Click "$newProjectLabel" to get started';
    }
  }

  static String projectCreatedUpdated(String created, String updated) {
    switch (_lang) {
      case AppLanguage.zh:
        return '创建于 $created · 更新于 $updated';
      case AppLanguage.ja:
        return '作成：$created · 更新：$updated';
      case AppLanguage.en:
        return 'Created $created · Updated $updated';
    }
  }

  static String get menuEnterWebshell {
    switch (_lang) {
      case AppLanguage.zh:
        return '进入 Webshell';
      case AppLanguage.ja:
        return 'Webshell へ';
      case AppLanguage.en:
        return 'Open Webshell';
    }
  }

  static String get menuEnterExp {
    switch (_lang) {
      case AppLanguage.zh:
        return '进入 EXP';
      case AppLanguage.ja:
        return 'EXP へ';
      case AppLanguage.en:
        return 'Open Exploits';
    }
  }

  static String get dialogChooseProjectEntryTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return '选择进入方式';
      case AppLanguage.ja:
        return '開く方法を選択';
      case AppLanguage.en:
        return 'Choose where to open';
    }
  }

  static String confirmDeleteProject(String name) {
    switch (_lang) {
      case AppLanguage.zh:
        return '确定要删除项目「$name」吗？将同时删除该项目的 Webshell 及信息收集数据，此操作不可恢复。';
      case AppLanguage.ja:
        return 'プロジェクト「$name」を削除してもよろしいですか？Webshell と収集データも削除されます。この操作は元に戻せません。';
      case AppLanguage.en:
        return 'Delete project "$name"? This will also delete its Webshell and collected data. This action cannot be undone.';
    }
  }

  // ── 项目选择 ──────────────────────────────────────────────────────────────

  static String get noProjects {
    switch (_lang) {
      case AppLanguage.zh:
        return '暂无项目';
      case AppLanguage.ja:
        return 'プロジェクトなし';
      case AppLanguage.en:
        return 'No projects';
    }
  }

  static String get noProjectsHint {
    switch (_lang) {
      case AppLanguage.zh:
        return '请先创建项目后再使用此功能';
      case AppLanguage.ja:
        return 'この機能を使用するには先にプロジェクトを作成してください';
      case AppLanguage.en:
        return 'Please create a project before using this feature';
    }
  }

  static String get selectProject {
    switch (_lang) {
      case AppLanguage.zh:
        return '请选择项目';
      case AppLanguage.ja:
        return 'プロジェクトを選択してください';
      case AppLanguage.en:
        return 'Select a project';
    }
  }

  static String get titleSelectProject {
    switch (_lang) {
      case AppLanguage.zh:
        return '选择项目';
      case AppLanguage.ja:
        return 'プロジェクトを選択';
      case AppLanguage.en:
        return 'Select project';
    }
  }

  // ── 反弹 Shell Dashboard ──────────────────────────────────────────────────

  static String get terminalTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return '完整终端 · 反弹 Shell 会话';
      case AppLanguage.ja:
        return 'フルターミナル · リバースシェルセッション';
      case AppLanguage.en:
        return 'Full terminal · Reverse shell sessions';
    }
  }

  static String get noActiveSessions {
    switch (_lang) {
      case AppLanguage.zh:
        return '当前没有活跃的反弹 Shell 会话';
      case AppLanguage.ja:
        return 'アクティブなリバースシェルセッションはありません';
      case AppLanguage.en:
        return 'No active reverse shell sessions';
    }
  }

  static String activeSessionCount(int n) {
    switch (_lang) {
      case AppLanguage.zh:
        return '活跃会话数：$n';
      case AppLanguage.ja:
        return 'アクティブセッション数：$n';
      case AppLanguage.en:
        return 'Active sessions: $n';
    }
  }

  static String listeningOn(String addr, int port) {
    switch (_lang) {
      case AppLanguage.zh:
        return '监听中：$addr:$port';
      case AppLanguage.ja:
        return '監視中：$addr:$port';
      case AppLanguage.en:
        return 'Listening: $addr:$port';
    }
  }

  static String portOccupiedOn(String addr, int port) {
    switch (_lang) {
      case AppLanguage.zh:
        return '端口占用：$addr:$port（可能已有监听）';
      case AppLanguage.ja:
        return 'ポート使用中：$addr:$port（既に監視中の可能性）';
      case AppLanguage.en:
        return 'Port in use: $addr:$port (may already be listening)';
    }
  }

  static String notListening(String host, int port) {
    switch (_lang) {
      case AppLanguage.zh:
        return '未监听（配置：$host:$port）';
      case AppLanguage.ja:
        return '未監視（設定：$host:$port）';
      case AppLanguage.en:
        return 'Not listening (config: $host:$port)';
    }
  }

  static String get fieldLhost {
    switch (_lang) {
      case AppLanguage.zh:
        return '监听 IP（LHOST）';
      case AppLanguage.ja:
        return '待受 IP（LHOST）';
      case AppLanguage.en:
        return 'Listen IP (LHOST)';
    }
  }

  static String get fieldLport {
    switch (_lang) {
      case AppLanguage.zh:
        return '监听端口（LPORT）';
      case AppLanguage.ja:
        return '待受ポート（LPORT）';
      case AppLanguage.en:
        return 'Listen port (LPORT)';
    }
  }

  static String get snackPortOccupied {
    switch (_lang) {
      case AppLanguage.zh:
        return '端口处于占用状态，请先释放后再启动监听';
      case AppLanguage.ja:
        return 'ポートが使用中です。解放してから監視を開始してください';
      case AppLanguage.en:
        return 'Port is in use. Release it before starting to listen';
    }
  }

  static String snackListenStarted(int lport, String lhost) {
    switch (_lang) {
      case AppLanguage.zh:
        return '已在 :$lport 启动监听（LHOST=$lhost）';
      case AppLanguage.ja:
        return ':$lport で監視開始（LHOST=$lhost）';
      case AppLanguage.en:
        return 'Listening on :$lport (LHOST=$lhost)';
    }
  }

  static String snackListenFailed(Object e) {
    switch (_lang) {
      case AppLanguage.zh:
        return '启动监听失败：$e';
      case AppLanguage.ja:
        return '監視開始失敗：$e';
      case AppLanguage.en:
        return 'Failed to start listener: $e';
    }
  }

  static String get noSessionsHint {
    switch (_lang) {
      case AppLanguage.zh:
        return '> 暂无会话，可在 Webshell 终端中点击「完整终端」发起反弹 Shell。';
      case AppLanguage.ja:
        return '> セッションなし。Webshell ターミナルで「フルターミナル」をクリックしてリバースシェルを開始。';
      case AppLanguage.en:
        return '> No sessions. Click "Full terminal" in the Webshell terminal to start a reverse shell.';
    }
  }

  static String get snackSessionDisconnected {
    switch (_lang) {
      case AppLanguage.zh:
        return '该会话已断开，无法打开终端';
      case AppLanguage.ja:
        return 'セッションが切断されました。ターミナルを開けません';
      case AppLanguage.en:
        return 'Session disconnected, cannot open terminal';
    }
  }

  static String get sessionDisconnected {
    switch (_lang) {
      case AppLanguage.zh:
        return '已断开';
      case AppLanguage.ja:
        return '切断済み';
      case AppLanguage.en:
        return 'Disconnected';
    }
  }

  // ── Webshell 交互 Terminal ────────────────────────────────────────────────

  static String get pingFailHint {
    switch (_lang) {
      case AppLanguage.zh:
        return '请核对：① 连接器类型与目标脚本是否一致；② 地址能否在浏览器打开。';
      case AppLanguage.ja:
        return '確認：① コネクタタイプとターゲットスクリプトが一致しているか；② URLにブラウザからアクセスできるか。';
      case AppLanguage.en:
        return 'Check: ① Connector type matches the target script; ② URL is accessible in a browser.';
    }
  }

  static String get connectionFailed {
    switch (_lang) {
      case AppLanguage.zh:
        return '连接失败，命令执行可能异常';
      case AppLanguage.ja:
        return '接続失敗。コマンド実行が正常でない可能性があります';
      case AppLanguage.en:
        return 'Connection failed, command execution may be unreliable';
    }
  }

  static String get statusChecking {
    switch (_lang) {
      case AppLanguage.zh:
        return '检测中';
      case AppLanguage.ja:
        return '確認中';
      case AppLanguage.en:
        return 'Checking';
    }
  }

  static String get statusConnected {
    switch (_lang) {
      case AppLanguage.zh:
        return '已连接';
      case AppLanguage.ja:
        return '接続済み';
      case AppLanguage.en:
        return 'Connected';
    }
  }

  static String get statusReconnect {
    switch (_lang) {
      case AppLanguage.zh:
        return '重连';
      case AppLanguage.ja:
        return '再接続';
      case AppLanguage.en:
        return 'Reconnect';
    }
  }

  static String get titleSelectTerminalMode {
    switch (_lang) {
      case AppLanguage.zh:
        return '选择完整终端方案';
      case AppLanguage.ja:
        return 'フルターミナルの方式を選択';
      case AppLanguage.en:
        return 'Select terminal mode';
    }
  }

  static String get terminalModeScript {
    switch (_lang) {
      case AppLanguage.zh:
        return '内置反弹 · script 模式';
      case AppLanguage.ja:
        return '内蔵リバース · script モード';
      case AppLanguage.en:
        return 'Built-in reverse · script mode';
    }
  }

  static String get terminalModeScriptDesc {
    switch (_lang) {
      case AppLanguage.zh:
        return '优先使用 script 分配伪终端，推荐在类 Unix 目标上使用';
      case AppLanguage.ja:
        return 'script で疑似ターミナルを割り当て。Unix 系ターゲットに推奨';
      case AppLanguage.en:
        return 'Uses script to allocate a pseudo-terminal. Recommended for Unix-like targets';
    }
  }

  static String get terminalModeBash {
    switch (_lang) {
      case AppLanguage.zh:
        return '内置反弹 · bash 模式';
      case AppLanguage.ja:
        return '内蔵リバース · bash モード';
      case AppLanguage.en:
        return 'Built-in reverse · bash mode';
    }
  }

  static String get terminalModeBashDesc {
    switch (_lang) {
      case AppLanguage.zh:
        return '不依赖 script，仅使用 bash -i 或 /bin/sh -i 反弹';
      case AppLanguage.ja:
        return 'script 不要。bash -i または /bin/sh -i のみ使用';
      case AppLanguage.en:
        return 'No script dependency. Uses bash -i or /bin/sh -i only';
    }
  }

  static String get terminalModeSocat {
    switch (_lang) {
      case AppLanguage.zh:
        return 'socat 反弹（在目标上手动执行命令）';
      case AppLanguage.ja:
        return 'socat リバース（ターゲットで手動実行）';
      case AppLanguage.en:
        return 'socat reverse (manually run command on target)';
    }
  }

  static String get terminalModeSocatDesc {
    switch (_lang) {
      case AppLanguage.zh:
        return '适合目标已安装 socat，获得更完整的 TTY 体验';
      case AppLanguage.ja:
        return 'socat がインストール済みのターゲットに適合。より完全な TTY 体験';
      case AppLanguage.en:
        return 'For targets with socat installed. Provides a more complete TTY experience';
    }
  }

  static String get snackReverseShellSent {
    switch (_lang) {
      case AppLanguage.zh:
        return '已发送反弹 Shell 命令，等待连接 ...';
      case AppLanguage.ja:
        return 'リバースシェルコマンドを送信しました。接続を待機中 ...';
      case AppLanguage.en:
        return 'Reverse shell command sent, waiting for connection ...';
    }
  }

  static String snackStartFailed(Object e) {
    switch (_lang) {
      case AppLanguage.zh:
        return '启动失败：$e';
      case AppLanguage.ja:
        return '起動失敗：$e';
      case AppLanguage.en:
        return 'Failed to start: $e';
    }
  }

  static String get titleSocatCommand {
    switch (_lang) {
      case AppLanguage.zh:
        return 'socat 反弹命令';
      case AppLanguage.ja:
        return 'socat リバースシェルコマンド';
      case AppLanguage.en:
        return 'socat reverse shell command';
    }
  }

  static String get socatInstructions {
    switch (_lang) {
      case AppLanguage.zh:
        return '在目标机器上执行以下命令以建立完整 TTY 反弹 Shell：';
      case AppLanguage.ja:
        return 'ターゲットマシンで以下のコマンドを実行してフル TTY リバースシェルを確立：';
      case AppLanguage.en:
        return 'Run the following command on the target to establish a full TTY reverse shell:';
    }
  }

  static String socatTips(int lport) {
    switch (_lang) {
      case AppLanguage.zh:
        return '提示：\n1. 本机已在 :$lport 端口监听。\n2. 目标执行成功后，这里会自动弹出完整终端窗口。';
      case AppLanguage.ja:
        return 'ヒント：\n1. ローカルは :$lport で待受中。\n2. ターゲット実行成功後、ターミナルウィンドウが自動で開きます。';
      case AppLanguage.en:
        return 'Tips:\n1. Local machine is listening on :$lport.\n2. After the target connects, the terminal window will open automatically.';
    }
  }

  static String get terminalEmptyHint {
    switch (_lang) {
      case AppLanguage.zh:
        return '> 输入命令开始执行';
      case AppLanguage.ja:
        return '> コマンドを入力して実行開始';
      case AppLanguage.en:
        return '> Type a command to get started';
    }
  }

  static String get terminalKeyHint {
    switch (_lang) {
      case AppLanguage.zh:
        return '使用 ↑↓ 键切换历史命令，输入 clear 清空终端';
      case AppLanguage.ja:
        return '↑↓ キーで履歴切替、clear でターミナルをクリア';
      case AppLanguage.en:
        return 'Use ↑↓ to navigate history, type clear to reset';
    }
  }

  static String get modeIntegrated {
    switch (_lang) {
      case AppLanguage.zh:
        return '一体式';
      case AppLanguage.ja:
        return '統合';
      case AppLanguage.en:
        return 'Integrated';
    }
  }

  static String get modeSeparate {
    switch (_lang) {
      case AppLanguage.zh:
        return '分离式';
      case AppLanguage.ja:
        return '分離';
      case AppLanguage.en:
        return 'Split';
    }
  }

  static String tabCompletionTitle(int total) {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Tab 候选（$total）';
      case AppLanguage.ja:
        return 'Tab 補完（$total）';
      case AppLanguage.en:
        return 'Tab candidates ($total)';
    }
  }

  static String get noCompletions {
    switch (_lang) {
      case AppLanguage.zh:
        return '当前无候选';
      case AppLanguage.ja:
        return '候補なし';
      case AppLanguage.en:
        return 'No candidates';
    }
  }

  static String get executing {
    switch (_lang) {
      case AppLanguage.zh:
        return '执行中...';
      case AppLanguage.ja:
        return '実行中...';
      case AppLanguage.en:
        return 'Running...';
    }
  }

  // ── Webshell ─────────────────────────────────────────────────────────────

  static String get fieldWebshellUrl {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Webshell 地址 *';
      case AppLanguage.ja:
        return 'Webshell URL *';
      case AppLanguage.en:
        return 'Webshell URL *';
    }
  }

  static String get hintWebshellUrl {
    switch (_lang) {
      case AppLanguage.zh:
        return 'http://example.com/shell.php';
      case AppLanguage.ja:
        return 'http://example.com/shell.php';
      case AppLanguage.en:
        return 'http://example.com/shell.php';
    }
  }

  static String get fieldWebshellName {
    switch (_lang) {
      case AppLanguage.zh:
        return '备注名称（可选）';
      case AppLanguage.ja:
        return 'メモ名（任意）';
      case AppLanguage.en:
        return 'Alias (optional)';
    }
  }

  static String get hintWebshellName {
    switch (_lang) {
      case AppLanguage.zh:
        return '例如：后台管理 Shell';
      case AppLanguage.ja:
        return '例：管理画面 Shell';
      case AppLanguage.en:
        return 'e.g. Admin panel shell';
    }
  }

  static String get labelRequestMethod {
    switch (_lang) {
      case AppLanguage.zh:
        return '请求方法：';
      case AppLanguage.ja:
        return 'リクエストメソッド：';
      case AppLanguage.en:
        return 'Request method:';
    }
  }

  static String get snackFillUrlAndPassword {
    switch (_lang) {
      case AppLanguage.zh:
        return '请先填写地址和密码';
      case AppLanguage.ja:
        return 'URLとパスワードを入力してください';
      case AppLanguage.en:
        return 'Please enter the URL and password first';
    }
  }

  static String get titleEditWebshell {
    switch (_lang) {
      case AppLanguage.zh:
        return '编辑 Webshell';
      case AppLanguage.ja:
        return 'Webshell を編集';
      case AppLanguage.en:
        return 'Edit Webshell';
    }
  }

  static String confirmDeleteWebshell(String name) {
    switch (_lang) {
      case AppLanguage.zh:
        return '确定要删除「$name」吗？此操作不可恢复。';
      case AppLanguage.ja:
        return '「$name」を削除してもよろしいですか？この操作は元に戻せません。';
      case AppLanguage.en:
        return 'Delete "$name"? This action cannot be undone.';
    }
  }

  static String webshellManagementTitle(String projectName) {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Webshell · $projectName';
      case AppLanguage.ja:
        return 'Webshell · $projectName';
      case AppLanguage.en:
        return 'Webshell · $projectName';
    }
  }

  static String expManagementScopedTitle(String projectName) {
    switch (_lang) {
      case AppLanguage.zh:
        return 'EXP · $projectName';
      case AppLanguage.ja:
        return 'EXP · $projectName';
      case AppLanguage.en:
        return 'Exploits · $projectName';
    }
  }

  static String webshellCount(int n) {
    switch (_lang) {
      case AppLanguage.zh:
        return '共 $n 条';
      case AppLanguage.ja:
        return '計 $n 件';
      case AppLanguage.en:
        return '$n total';
    }
  }

  static String webshellEmptyHint(String addLabel) {
    switch (_lang) {
      case AppLanguage.zh:
        return '暂无 Webshell，点击「$addLabel」开始';
      case AppLanguage.ja:
        return 'Webshell がありません。「$addLabel」をクリックして開始';
      case AppLanguage.en:
        return 'No Webshell yet. Click "$addLabel" to get started';
    }
  }

  static String get webshellPasswordLabel {
    switch (_lang) {
      case AppLanguage.zh:
        return '密码';
      case AppLanguage.ja:
        return 'パスワード';
      case AppLanguage.en:
        return 'Password';
    }
  }

  static String get connectorMethodFixed {
    switch (_lang) {
      case AppLanguage.zh:
        return '由连接器固定';
      case AppLanguage.ja:
        return 'コネクタで固定';
      case AppLanguage.en:
        return 'Fixed by connector';
    }
  }

  static String get fieldConnectorType {
    switch (_lang) {
      case AppLanguage.zh:
        return '连接器类型';
      case AppLanguage.ja:
        return 'コネクタタイプ';
      case AppLanguage.en:
        return 'Connector type';
    }
  }

  static String unknownConnector(String value) {
    switch (_lang) {
      case AppLanguage.zh:
        return '未知: $value';
      case AppLanguage.ja:
        return '不明: $value';
      case AppLanguage.en:
        return 'Unknown: $value';
    }
  }

  static String get fieldPasswordKey {
    switch (_lang) {
      case AppLanguage.zh:
        return '连接密码/密钥 *';
      case AppLanguage.ja:
        return '接続パスワード/キー *';
      case AppLanguage.en:
        return 'Password / key *';
    }
  }

  static String get fieldParamName {
    switch (_lang) {
      case AppLanguage.zh:
        return '参数名 *';
      case AppLanguage.ja:
        return 'パラメータ名 *';
      case AppLanguage.en:
        return 'Parameter name *';
    }
  }

  static String get hintPasswordKey {
    switch (_lang) {
      case AppLanguage.zh:
        return '默认 mAtrix_911，或 payload 中 k 的 16 位 hex';
      case AppLanguage.ja:
        return 'デフォルト mAtrix_911、または payload の k の 16 進数 16 桁';
      case AppLanguage.en:
        return 'Default mAtrix_911, or the 16-char hex of k in the payload';
    }
  }

  static String get helperPasswordKey {
    switch (_lang) {
      case AppLanguage.zh:
        return '连接密码（MD5 前 16 位为密钥）；或直接填 payload 中 String k="xxx" 的 hex 值';
      case AppLanguage.ja:
        return '接続パスワード（MD5 前半 16 桁をキーとして使用）；または payload の String k="xxx" の hex 値を直接入力';
      case AppLanguage.en:
        return 'Connection password (first 16 chars of MD5 as key); or enter the hex value of String k="xxx" from the payload directly';
    }
  }

  static String helperParamName(String param) {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Payload 中接收命令的 HTTP 参数名（如 \$_POST["$param"]）';
      case AppLanguage.ja:
        return 'Payload でコマンドを受け取る HTTP パラメータ名（例：\$_POST["$param"]）';
      case AppLanguage.en:
        return 'HTTP parameter name for receiving commands in the payload (e.g. \$_POST["$param"])';
    }
  }

  static String hintParamName(String param) {
    switch (_lang) {
      case AppLanguage.zh:
        return '参数名，默认: $param';
      case AppLanguage.ja:
        return 'パラメータ名、デフォルト: $param';
      case AppLanguage.en:
        return 'Parameter name, default: $param';
    }
  }

  static String get detectSuccess {
    switch (_lang) {
      case AppLanguage.zh:
        return '检测完成，已自动选择第一个有响应的类型';
      case AppLanguage.ja:
        return '検出完了。最初に応答したタイプを自動選択しました';
      case AppLanguage.en:
        return 'Detection complete. Auto-selected the first responsive connector type';
    }
  }

  static String get detectFailed {
    switch (_lang) {
      case AppLanguage.zh:
        return '未检测到有响应的连接器，请检查地址与密码';
      case AppLanguage.ja:
        return '応答するコネクタが見つかりません。URLとパスワードを確認してください';
      case AppLanguage.en:
        return 'No responsive connector found. Check the URL and password';
    }
  }

  // ── 文件管理 ──────────────────────────────────────────────────────────────

  static String get snackWriteUnsupported {
    switch (_lang) {
      case AppLanguage.zh:
        return '当前连接器不支持文件写入';
      case AppLanguage.ja:
        return '現在のコネクタはファイル書き込みをサポートしていません';
      case AppLanguage.en:
        return 'Current connector does not support file writing';
    }
  }

  static String get allFiles {
    switch (_lang) {
      case AppLanguage.zh:
        return '所有文件';
      case AppLanguage.ja:
        return '全てのファイル';
      case AppLanguage.en:
        return 'All files';
    }
  }

  static String get snackNoPayloads {
    switch (_lang) {
      case AppLanguage.zh:
        return '暂无可上传的 Payload';
      case AppLanguage.ja:
        return 'アップロード可能な Payload がありません';
      case AppLanguage.en:
        return 'No payloads available to upload';
    }
  }

  static String snackPayloadDecodeFailed(String name) {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Payload 解码失败: $name';
      case AppLanguage.ja:
        return 'Payload デコード失敗: $name';
      case AppLanguage.en:
        return 'Payload decode failed: $name';
    }
  }

  static String get dirEmptyOrDenied {
    switch (_lang) {
      case AppLanguage.zh:
        return '目录为空或无权访问';
      case AppLanguage.ja:
        return 'ディレクトリが空またはアクセス権限がありません';
      case AppLanguage.en:
        return 'Directory is empty or access denied';
    }
  }

  static String get dirEmpty {
    switch (_lang) {
      case AppLanguage.zh:
        return '目录为空';
      case AppLanguage.ja:
        return 'ディレクトリが空です';
      case AppLanguage.en:
        return 'Directory is empty';
    }
  }

  static String get colName {
    switch (_lang) {
      case AppLanguage.zh:
        return '名称';
      case AppLanguage.ja:
        return '名前';
      case AppLanguage.en:
        return 'Name';
    }
  }

  static String get colSize {
    switch (_lang) {
      case AppLanguage.zh:
        return '大小';
      case AppLanguage.ja:
        return 'サイズ';
      case AppLanguage.en:
        return 'Size';
    }
  }

  static String get colPermissions {
    switch (_lang) {
      case AppLanguage.zh:
        return '权限';
      case AppLanguage.ja:
        return '権限';
      case AppLanguage.en:
        return 'Perms';
    }
  }

  static String get colModified {
    switch (_lang) {
      case AppLanguage.zh:
        return '修改时间';
      case AppLanguage.ja:
        return '更新日時';
      case AppLanguage.en:
        return 'Modified';
    }
  }

  static String get titleConfirmDelete {
    switch (_lang) {
      case AppLanguage.zh:
        return '确认删除';
      case AppLanguage.ja:
        return '削除確認';
      case AppLanguage.en:
        return 'Confirm delete';
    }
  }

  static String confirmDeleteFile(String name) {
    switch (_lang) {
      case AppLanguage.zh:
        return '确定删除「$name」吗？此操作不可恢复。';
      case AppLanguage.ja:
        return '「$name」を削除してもよろしいですか？この操作は元に戻せません。';
      case AppLanguage.en:
        return 'Delete "$name"? This action cannot be undone.';
    }
  }

  static String snackDeleted(String name) {
    switch (_lang) {
      case AppLanguage.zh:
        return '已删除 $name';
      case AppLanguage.ja:
        return '$name を削除しました';
      case AppLanguage.en:
        return 'Deleted $name';
    }
  }

  static String get snackDeleteFailed {
    switch (_lang) {
      case AppLanguage.zh:
        return '删除失败';
      case AppLanguage.ja:
        return '削除失敗';
      case AppLanguage.en:
        return 'Delete failed';
    }
  }

  static String get snackUploadCancelled {
    switch (_lang) {
      case AppLanguage.zh:
        return '上传已取消';
      case AppLanguage.ja:
        return 'アップロードをキャンセルしました';
      case AppLanguage.en:
        return 'Upload cancelled';
    }
  }

  static String snackUploadFailed(Object e) {
    switch (_lang) {
      case AppLanguage.zh:
        return '上传失败: $e';
      case AppLanguage.ja:
        return 'アップロード失敗: $e';
      case AppLanguage.en:
        return 'Upload failed: $e';
    }
  }

  static String snackUploaded(String fileName) {
    switch (_lang) {
      case AppLanguage.zh:
        return '已上传 $fileName';
      case AppLanguage.ja:
        return '$fileName をアップロードしました';
      case AppLanguage.en:
        return 'Uploaded $fileName';
    }
  }

  static String get snackUploadFail {
    switch (_lang) {
      case AppLanguage.zh:
        return '上传失败';
      case AppLanguage.ja:
        return 'アップロード失敗';
      case AppLanguage.en:
        return 'Upload failed';
    }
  }

  static String snackDownloadedTo(String path) {
    switch (_lang) {
      case AppLanguage.zh:
        return '已保存至 $path';
      case AppLanguage.ja:
        return '$path に保存しました';
      case AppLanguage.en:
        return 'Saved to $path';
    }
  }

  static String snackDownloadFailed(Object e) {
    switch (_lang) {
      case AppLanguage.zh:
        return '下载失败: $e';
      case AppLanguage.ja:
        return 'ダウンロード失敗: $e';
      case AppLanguage.en:
        return 'Download failed: $e';
    }
  }

  static String get titleSelectPayload {
    switch (_lang) {
      case AppLanguage.zh:
        return '选择 Payload 上传';
      case AppLanguage.ja:
        return 'アップロードする Payload を選択';
      case AppLanguage.en:
        return 'Select payload to upload';
    }
  }

  /// Payload 管理卡片：上传到所选 Webshell 的 /tmp
  static String get tooltipPayloadUploadToWebshellTmp {
    switch (_lang) {
      case AppLanguage.zh:
        return '上传到 Webshell 的 /tmp';
      case AppLanguage.ja:
        return 'Webshell の /tmp にアップロード';
      case AppLanguage.en:
        return 'Upload to Webshell /tmp';
    }
  }

  static String get titleSelectWebshellForPayload {
    switch (_lang) {
      case AppLanguage.zh:
        return '选择 Webshell（上传到 /tmp）';
      case AppLanguage.ja:
        return 'Webshell を選択（/tmp にアップロード）';
      case AppLanguage.en:
        return 'Select Webshell (upload to /tmp)';
    }
  }

  static String get snackNoWebshellsAnyProject {
    switch (_lang) {
      case AppLanguage.zh:
        return '没有任何项目下保存 Webshell，请先在 Webshell 中添加';
      case AppLanguage.ja:
        return 'Webshell がありません。先に Webshell で追加してください';
      case AppLanguage.en:
        return 'No Webshell found. Add one under Webshell first';
    }
  }

  static String snackPayloadUploadedToRemote(String remotePath) {
    switch (_lang) {
      case AppLanguage.zh:
        return '已上传至 $remotePath';
      case AppLanguage.ja:
        return '$remotePath にアップロードしました';
      case AppLanguage.en:
        return 'Uploaded to $remotePath';
    }
  }

  static String get dialogUploadSuccessTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return '上传成功';
      case AppLanguage.ja:
        return 'アップロード完了';
      case AppLanguage.en:
        return 'Upload successful';
    }
  }

  static String get dialogUploadFailureTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return '上传失败';
      case AppLanguage.ja:
        return 'アップロード失敗';
      case AppLanguage.en:
        return 'Upload failed';
    }
  }

  static String get uploading {
    switch (_lang) {
      case AppLanguage.zh:
        return '上传中';
      case AppLanguage.ja:
        return 'アップロード中';
      case AppLanguage.en:
        return 'Uploading';
    }
  }

  static String get downloading {
    switch (_lang) {
      case AppLanguage.zh:
        return '下载中';
      case AppLanguage.ja:
        return 'ダウンロード中';
      case AppLanguage.en:
        return 'Downloading';
    }
  }

  static String get uploadingProgress {
    switch (_lang) {
      case AppLanguage.zh:
        return '正在上传...';
      case AppLanguage.ja:
        return 'アップロード中...';
      case AppLanguage.en:
        return 'Uploading...';
    }
  }

  static String get downloadingProgress {
    switch (_lang) {
      case AppLanguage.zh:
        return '正在接收数据，请稍候...';
      case AppLanguage.ja:
        return 'データを受信中、しばらくお待ちください...';
      case AppLanguage.en:
        return 'Receiving data, please wait...';
    }
  }

  static String get snackSaveSuccess {
    switch (_lang) {
      case AppLanguage.zh:
        return '保存成功';
      case AppLanguage.ja:
        return '保存しました';
      case AppLanguage.en:
        return 'Saved successfully';
    }
  }

  static String get snackSaveFailure {
    switch (_lang) {
      case AppLanguage.zh:
        return '保存失败';
      case AppLanguage.ja:
        return '保存失敗';
      case AppLanguage.en:
        return 'Save failed';
    }
  }

  // ── 系统信息 / 提权 ───────────────────────────────────────────────────────

  static String get serverInfo {
    switch (_lang) {
      case AppLanguage.zh:
        return '服务器基本信息';
      case AppLanguage.ja:
        return 'サーバー基本情報';
      case AppLanguage.en:
        return 'Server information';
    }
  }

  static String get sysInfoFailed {
    switch (_lang) {
      case AppLanguage.zh:
        return '无法获取系统信息';
      case AppLanguage.ja:
        return 'システム情報を取得できません';
      case AppLanguage.en:
        return 'Failed to retrieve system info';
    }
  }

  static String get sysInfoFailedHint {
    switch (_lang) {
      case AppLanguage.zh:
        return '请检查 Webshell 是否可正常执行远程代码/命令';
      case AppLanguage.ja:
        return 'Webshell がリモートコード/コマンドを正常に実行できるか確認してください';
      case AppLanguage.en:
        return 'Check whether the Webshell can execute remote code/commands normally';
    }
  }

  static String disabledFunctions(int n) {
    switch (_lang) {
      case AppLanguage.zh:
        return '禁用函数 ($n)';
      case AppLanguage.ja:
        return '無効化関数 ($n)';
      case AppLanguage.en:
        return 'Disabled functions ($n)';
    }
  }

  static String loadedExtensions(int n) {
    switch (_lang) {
      case AppLanguage.zh:
        return '已加载扩展 ($n)';
      case AppLanguage.ja:
        return '読み込み済み拡張 ($n)';
      case AppLanguage.en:
        return 'Loaded extensions ($n)';
    }
  }

  static String get sysInfoFieldOs {
    switch (_lang) {
      case AppLanguage.zh:
        return '操作系统';
      case AppLanguage.ja:
        return 'OS';
      case AppLanguage.en:
        return 'OS';
    }
  }

  static String get sysInfoFieldPhpVersion {
    switch (_lang) {
      case AppLanguage.zh:
        return 'PHP版本';
      case AppLanguage.ja:
        return 'PHP バージョン';
      case AppLanguage.en:
        return 'PHP version';
    }
  }

  static String get sysInfoFieldRunUser {
    switch (_lang) {
      case AppLanguage.zh:
        return '运行用户';
      case AppLanguage.ja:
        return '実行ユーザー';
      case AppLanguage.en:
        return 'Runtime user';
    }
  }

  static String get sysInfoFieldServerIp {
    switch (_lang) {
      case AppLanguage.zh:
        return '服务器IP';
      case AppLanguage.ja:
        return 'サーバーIP';
      case AppLanguage.en:
        return 'Server IP';
    }
  }

  static String get sysInfoFieldServerSoftware {
    switch (_lang) {
      case AppLanguage.zh:
        return '服务器软件';
      case AppLanguage.ja:
        return 'サーバーソフト';
      case AppLanguage.en:
        return 'Server software';
    }
  }

  static String get sysInfoFieldDocRoot {
    switch (_lang) {
      case AppLanguage.zh:
        return '文档根目录';
      case AppLanguage.ja:
        return 'ドキュメントルート';
      case AppLanguage.en:
        return 'Document root';
    }
  }

  static String get sysInfoFieldCurrentDir {
    switch (_lang) {
      case AppLanguage.zh:
        return '当前目录';
      case AppLanguage.ja:
        return '現在ディレクトリ';
      case AppLanguage.en:
        return 'Current directory';
    }
  }

  static String get sysInfoFieldMemoryLimit {
    switch (_lang) {
      case AppLanguage.zh:
        return '内存限制';
      case AppLanguage.ja:
        return 'メモリ制限';
      case AppLanguage.en:
        return 'Memory limit';
    }
  }

  static String get sysInfoFieldMaxExecutionTime {
    switch (_lang) {
      case AppLanguage.zh:
        return '最大执行时间';
      case AppLanguage.ja:
        return '最大実行時間';
      case AppLanguage.en:
        return 'Max execution time';
    }
  }

  static String get sysInfoFieldSafeMode {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Safe Mode';
      case AppLanguage.ja:
        return 'セーフモード';
      case AppLanguage.en:
        return 'Safe Mode';
    }
  }

  static String get sysInfoFieldHost {
    switch (_lang) {
      case AppLanguage.zh:
        return '主机名';
      case AppLanguage.ja:
        return 'ホスト名';
      case AppLanguage.en:
        return 'Hostname';
    }
  }

  static String get sysInfoFieldUserId {
    switch (_lang) {
      case AppLanguage.zh:
        return '用户ID';
      case AppLanguage.ja:
        return 'ユーザーID';
      case AppLanguage.en:
        return 'User ID';
    }
  }

  static String get sysInfoFieldKernelVersion {
    switch (_lang) {
      case AppLanguage.zh:
        return '内核版本';
      case AppLanguage.ja:
        return 'カーネルバージョン';
      case AppLanguage.en:
        return 'Kernel version';
    }
  }

  static String get sysInfoFieldDotnetClr {
    switch (_lang) {
      case AppLanguage.zh:
        return '.NET CLR 版本';
      case AppLanguage.ja:
        return '.NET CLR バージョン';
      case AppLanguage.en:
        return '.NET CLR version';
    }
  }

  static String get privEscTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return '本地提权检查';
      case AppLanguage.ja:
        return 'ローカル権限昇格チェック';
      case AppLanguage.en:
        return 'Privilege escalation checks';
    }
  }

  static String get checkingAll {
    switch (_lang) {
      case AppLanguage.zh:
        return '检查中…';
      case AppLanguage.ja:
        return 'チェック中…';
      case AppLanguage.en:
        return 'Checking…';
    }
  }

  static String get privEscSuggestions {
    switch (_lang) {
      case AppLanguage.zh:
        return '提权建议（根据检查结果）';
      case AppLanguage.ja:
        return '権限昇格の提案（チェック結果に基づく）';
      case AppLanguage.en:
        return 'Privilege escalation suggestions (based on results)';
    }
  }

  // ── 提权分组标题 ──────────────────────────────────────────────────────────

  static String get privEscGroupCurrentPriv {
    switch (_lang) {
      case AppLanguage.zh:
        return '当前权限';
      case AppLanguage.ja:
        return '現在の権限';
      case AppLanguage.en:
        return 'Current privileges';
    }
  }

  static String get privEscGroupSysInfo {
    switch (_lang) {
      case AppLanguage.zh:
        return '系统信息';
      case AppLanguage.ja:
        return 'システム情報';
      case AppLanguage.en:
        return 'System info';
    }
  }

  static String get privEscGroupEscVectors {
    switch (_lang) {
      case AppLanguage.zh:
        return '提权向量';
      case AppLanguage.ja:
        return '昇格ベクター';
      case AppLanguage.en:
        return 'Escalation vectors';
    }
  }

  static String get privEscGroupSensitiveInfo {
    switch (_lang) {
      case AppLanguage.zh:
        return '敏感信息';
      case AppLanguage.ja:
        return '機密情報';
      case AppLanguage.en:
        return 'Sensitive information';
    }
  }

  // ── 提权检查项 ────────────────────────────────────────────────────────────

  static String get privEscItemUserGroup {
    switch (_lang) {
      case AppLanguage.zh:
        return '用户 & 组';
      case AppLanguage.ja:
        return 'ユーザー & グループ';
      case AppLanguage.en:
        return 'User & group';
    }
  }

  static String get privEscItemUserGroupDesc {
    switch (_lang) {
      case AppLanguage.zh:
        return '当前用户 UID/GID 及所属组';
      case AppLanguage.ja:
        return '現在のユーザー UID/GID と所属グループ';
      case AppLanguage.en:
        return 'Current user UID/GID and groups';
    }
  }

  static String get privEscItemSudo {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Sudo 权限';
      case AppLanguage.ja:
        return 'Sudo 権限';
      case AppLanguage.en:
        return 'Sudo privileges';
    }
  }

  static String get privEscItemSudoDesc {
    switch (_lang) {
      case AppLanguage.zh:
        return '可 sudo 免密执行的命令';
      case AppLanguage.ja:
        return 'パスワードなしで sudo 実行できるコマンド';
      case AppLanguage.en:
        return 'Commands executable via sudo without password';
    }
  }

  static String get privEscItemEnv {
    switch (_lang) {
      case AppLanguage.zh:
        return '环境变量';
      case AppLanguage.ja:
        return '環境変数';
      case AppLanguage.en:
        return 'Environment variables';
    }
  }

  static String get privEscItemEnvDesc {
    switch (_lang) {
      case AppLanguage.zh:
        return '环境变量中可能含凭证';
      case AppLanguage.ja:
        return '環境変数に認証情報が含まれる可能性';
      case AppLanguage.en:
        return 'Environment variables may contain credentials';
    }
  }

  static String get privEscItemKernel {
    switch (_lang) {
      case AppLanguage.zh:
        return '内核版本';
      case AppLanguage.ja:
        return 'カーネルバージョン';
      case AppLanguage.en:
        return 'Kernel version';
    }
  }

  static String get privEscItemKernelDesc {
    switch (_lang) {
      case AppLanguage.zh:
        return '检查内核版本以匹配本地提权 EXP';
      case AppLanguage.ja:
        return 'カーネルバージョンを確認してローカル昇格 EXP に照合';
      case AppLanguage.en:
        return 'Check kernel version to match local privilege escalation exploits';
    }
  }

  static String get privEscItemDistro {
    switch (_lang) {
      case AppLanguage.zh:
        return '发行版';
      case AppLanguage.ja:
        return 'ディストリビューション';
      case AppLanguage.en:
        return 'Distribution';
    }
  }

  static String get privEscItemDistroDesc {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Linux 发行版及版本号';
      case AppLanguage.ja:
        return 'Linux ディストリビューションとバージョン';
      case AppLanguage.en:
        return 'Linux distribution and version';
    }
  }

  static String get privEscItemLoggedUsers {
    switch (_lang) {
      case AppLanguage.zh:
        return '登录用户';
      case AppLanguage.ja:
        return 'ログインユーザー';
      case AppLanguage.en:
        return 'Logged-in users';
    }
  }

  static String get privEscItemLoggedUsersDesc {
    switch (_lang) {
      case AppLanguage.zh:
        return '当前在线会话';
      case AppLanguage.ja:
        return '現在のオンラインセッション';
      case AppLanguage.en:
        return 'Current active sessions';
    }
  }

  static String get privEscItemRootProcs {
    switch (_lang) {
      case AppLanguage.zh:
        return '以 root 运行的进程';
      case AppLanguage.ja:
        return 'root で実行中のプロセス';
      case AppLanguage.en:
        return 'Processes running as root';
    }
  }

  static String get privEscItemRootProcsDesc {
    switch (_lang) {
      case AppLanguage.zh:
        return '以 root 身份运行的服务进程';
      case AppLanguage.ja:
        return 'root として動作しているサービスプロセス';
      case AppLanguage.en:
        return 'Service processes running as root';
    }
  }

  static String get privEscItemSuid {
    switch (_lang) {
      case AppLanguage.zh:
        return 'SUID 文件';
      case AppLanguage.ja:
        return 'SUID ファイル';
      case AppLanguage.en:
        return 'SUID files';
    }
  }

  static String get privEscItemSuidDesc {
    switch (_lang) {
      case AppLanguage.zh:
        return '具有 SUID 位的可执行文件（可用于提权）';
      case AppLanguage.ja:
        return 'SUID ビットを持つ実行ファイル（昇格に利用可能）';
      case AppLanguage.en:
        return 'Executables with SUID bit set (may be used for escalation)';
    }
  }

  static String get privEscItemSgid {
    switch (_lang) {
      case AppLanguage.zh:
        return 'SGID 文件';
      case AppLanguage.ja:
        return 'SGID ファイル';
      case AppLanguage.en:
        return 'SGID files';
    }
  }

  static String get privEscItemSgidDesc {
    switch (_lang) {
      case AppLanguage.zh:
        return '具有 SGID 位的可执行文件';
      case AppLanguage.ja:
        return 'SGID ビットを持つ実行ファイル';
      case AppLanguage.en:
        return 'Executables with SGID bit set';
    }
  }

  static String get privEscItemCap {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Capabilities';
      case AppLanguage.ja:
        return 'Capabilities';
      case AppLanguage.en:
        return 'Capabilities';
    }
  }

  static String get privEscItemCapDesc {
    switch (_lang) {
      case AppLanguage.zh:
        return '具有 Linux Capabilities 的文件';
      case AppLanguage.ja:
        return 'Linux Capabilities を持つファイル';
      case AppLanguage.en:
        return 'Files with Linux capabilities';
    }
  }

  static String get privEscItemCron {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Cron 任务';
      case AppLanguage.ja:
        return 'Cron タスク';
      case AppLanguage.en:
        return 'Cron jobs';
    }
  }

  static String get privEscItemCronDesc {
    switch (_lang) {
      case AppLanguage.zh:
        return '定时任务配置及脚本';
      case AppLanguage.ja:
        return 'スケジュールタスクの設定とスクリプト';
      case AppLanguage.en:
        return 'Scheduled task configuration and scripts';
    }
  }

  static String get privEscItemCronWritable {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Cron 可写脚本';
      case AppLanguage.ja:
        return 'Cron 書き込み可能スクリプト';
      case AppLanguage.en:
        return 'Writable cron scripts';
    }
  }

  static String get privEscItemCronWritableDesc {
    switch (_lang) {
      case AppLanguage.zh:
        return '根据权限位+当前用户/组判断可写（无写入、无副作用）';
      case AppLanguage.ja:
        return '権限ビットと現在のユーザー/グループに基づき書き込み可能と判断（書き込みなし、副作用なし）';
      case AppLanguage.en:
        return 'Writable by current user/group based on permission bits (read-only check, no side effects)';
    }
  }

  static String get privEscItemWritableDirs {
    switch (_lang) {
      case AppLanguage.zh:
        return '可写目录';
      case AppLanguage.ja:
        return '書き込み可能ディレクトリ';
      case AppLanguage.en:
        return 'Writable directories';
    }
  }

  static String get privEscItemWritableDirsDesc {
    switch (_lang) {
      case AppLanguage.zh:
        return '当前用户可写的目录';
      case AppLanguage.ja:
        return '現在のユーザーが書き込み可能なディレクトリ';
      case AppLanguage.en:
        return 'Directories writable by the current user';
    }
  }

  static String get privEscItemPathHijack {
    switch (_lang) {
      case AppLanguage.zh:
        return 'PATH 劫持';
      case AppLanguage.ja:
        return 'PATH ハイジャック';
      case AppLanguage.en:
        return 'PATH hijacking';
    }
  }

  static String get privEscItemPathHijackDesc {
    switch (_lang) {
      case AppLanguage.zh:
        return '检查 PATH 中是否有可写目录';
      case AppLanguage.ja:
        return 'PATH 内に書き込み可能なディレクトリがあるか確認';
      case AppLanguage.en:
        return 'Check for writable directories in PATH';
    }
  }

  static String get privEscItemLoginableAccounts {
    switch (_lang) {
      case AppLanguage.zh:
        return '可登录账户';
      case AppLanguage.ja:
        return 'ログイン可能アカウント';
      case AppLanguage.en:
        return 'Loginable accounts';
    }
  }

  static String get privEscItemLoginableAccountsDesc {
    switch (_lang) {
      case AppLanguage.zh:
        return '可正常登录的用户账户';
      case AppLanguage.ja:
        return '正常にログインできるユーザーアカウント';
      case AppLanguage.en:
        return 'User accounts that can log in normally';
    }
  }

  static String get privEscItemShadow {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Shadow 文件';
      case AppLanguage.ja:
        return 'Shadow ファイル';
      case AppLanguage.en:
        return 'Shadow file';
    }
  }

  static String get privEscItemShadowDesc {
    switch (_lang) {
      case AppLanguage.zh:
        return '尝试读取密码哈希（需 root）';
      case AppLanguage.ja:
        return 'パスワードハッシュの読み取りを試みる（root 必要）';
      case AppLanguage.en:
        return 'Attempt to read password hashes (requires root)';
    }
  }

  static String get privEscItemHistory {
    switch (_lang) {
      case AppLanguage.zh:
        return '历史命令';
      case AppLanguage.ja:
        return 'コマンド履歴';
      case AppLanguage.en:
        return 'Command history';
    }
  }

  static String get privEscItemHistoryDesc {
    switch (_lang) {
      case AppLanguage.zh:
        return '历史命令中可能含明文凭证';
      case AppLanguage.ja:
        return 'コマンド履歴に平文の認証情報が含まれる可能性';
      case AppLanguage.en:
        return 'Command history may contain plaintext credentials';
    }
  }

  static String get privEscItemSshKeys {
    switch (_lang) {
      case AppLanguage.zh:
        return 'SSH 密钥';
      case AppLanguage.ja:
        return 'SSH 鍵';
      case AppLanguage.en:
        return 'SSH keys';
    }
  }

  static String get privEscItemSshKeysDesc {
    switch (_lang) {
      case AppLanguage.zh:
        return '私钥文件是否可读';
      case AppLanguage.ja:
        return '秘密鍵ファイルが読み取り可能かどうか';
      case AppLanguage.en:
        return 'Whether private key files are readable';
    }
  }

  static String get privEscItemConfigPasswords {
    switch (_lang) {
      case AppLanguage.zh:
        return '配置文件密码';
      case AppLanguage.ja:
        return '設定ファイルのパスワード';
      case AppLanguage.en:
        return 'Config file passwords';
    }
  }

  static String get privEscItemConfigPasswordsDesc {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Web/系统配置文件中的明文密码';
      case AppLanguage.ja:
        return 'Web/システム設定ファイル内の平文パスワード';
      case AppLanguage.en:
        return 'Plaintext passwords in web/system config files';
    }
  }

  // ── 提权建议标题 & 原因 ────────────────────────────────────────────────────

  static String get privEscSudoAllTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Sudo 免密提权';
      case AppLanguage.ja:
        return 'Sudo パスワードなし昇格';
      case AppLanguage.en:
        return 'Sudo passwordless escalation';
    }
  }

  static String get privEscSudoAllReason {
    switch (_lang) {
      case AppLanguage.zh:
        return '检测到 sudo 可免密执行 ALL，直接提权：';
      case AppLanguage.ja:
        return 'sudo が NOPASSWD で ALL を実行可能と検出。直接昇格：';
      case AppLanguage.en:
        return 'Detected sudo can run ALL without password. Direct escalation:';
    }
  }

  static String get privEscSudoLimitedTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Sudo 受限命令提权';
      case AppLanguage.ja:
        return 'Sudo 制限コマンド昇格';
      case AppLanguage.en:
        return 'Sudo limited command escalation';
    }
  }

  static String privEscSudoLimitedReason(String paths) {
    switch (_lang) {
      case AppLanguage.zh:
        return '检测到免密 sudo：$paths';
      case AppLanguage.ja:
        return 'パスワードなし sudo を検出：$paths';
      case AppLanguage.en:
        return 'Detected passwordless sudo: $paths';
    }
  }

  static String get privEscSuidTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'SUID 提权';
      case AppLanguage.ja:
        return 'SUID 権限昇格';
      case AppLanguage.en:
        return 'SUID escalation';
    }
  }

  static String get privEscSuidReason {
    switch (_lang) {
      case AppLanguage.zh:
        return '发现可滥用 SUID 文件，在终端执行（需在可写目录）：';
      case AppLanguage.ja:
        return '悪用可能な SUID ファイルを発見。ターミナルで実行（書き込み可能ディレクトリ必要）：';
      case AppLanguage.en:
        return 'Found exploitable SUID files. Execute in terminal (requires writable directory):';
    }
  }

  static String get privEscKernelTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return '内核提权（需本地查找 exploit）';
      case AppLanguage.ja:
        return 'カーネル昇格（ローカルで exploit を検索が必要）';
      case AppLanguage.en:
        return 'Kernel escalation (find exploit locally)';
    }
  }

  static String privEscKernelReason(String ver, String arch) {
    switch (_lang) {
      case AppLanguage.zh:
        return '内核 $ver ($arch)，需在本地搜索对应 CVE';
      case AppLanguage.ja:
        return 'カーネル $ver ($arch)。対応する CVE をローカルで検索';
      case AppLanguage.en:
        return 'Kernel $ver ($arch). Search for matching CVE locally';
    }
  }

  static String get privEscShadowTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return '密码哈希破解（需本地破解）';
      case AppLanguage.ja:
        return 'パスワードハッシュ解析（ローカル解析が必要）';
      case AppLanguage.en:
        return 'Password hash cracking (crack locally)';
    }
  }

  static String privEscShadowReason(String hashMode) {
    switch (_lang) {
      case AppLanguage.zh:
        return '已获取 shadow，本地破解（$hashMode），成功率取决于密码强度';
      case AppLanguage.ja:
        return 'shadow を取得。ローカル解析（$hashMode）。成功率はパスワード強度に依存';
      case AppLanguage.en:
        return 'Obtained shadow. Crack locally ($hashMode). Success rate depends on password strength';
    }
  }

  static String get privEscCronTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Cron 劫持（已验证可写）';
      case AppLanguage.ja:
        return 'Cron ハイジャック（書き込み確認済み）';
      case AppLanguage.en:
        return 'Cron hijacking (write access confirmed)';
    }
  }

  static String privEscCronReason(String paths) {
    switch (_lang) {
      case AppLanguage.zh:
        return '已自动检测到可写 cron 文件：$paths';
      case AppLanguage.ja:
        return '書き込み可能な cron ファイルを自動検出：$paths';
      case AppLanguage.en:
        return 'Auto-detected writable cron files: $paths';
    }
  }

  static String get privEscCapTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Capabilities 提权';
      case AppLanguage.ja:
        return 'Capabilities 権限昇格';
      case AppLanguage.en:
        return 'Capabilities escalation';
    }
  }

  static String get privEscCapReason {
    switch (_lang) {
      case AppLanguage.zh:
        return '发现 cap_setuid，直接执行上述路径：';
      case AppLanguage.ja:
        return 'cap_setuid を発見。上記のパスを直接実行：';
      case AppLanguage.en:
        return 'Found cap_setuid. Execute the path above directly:';
    }
  }

  // --- Status / log panel ---
  static String get expWaiting {
    switch (_lang) {
      case AppLanguage.zh:
        return '> 等待操作';
      case AppLanguage.ja:
        return '> 操作を待機中';
      case AppLanguage.en:
        return '> Awaiting action';
    }
  }

  static String get statusRunning {
    switch (_lang) {
      case AppLanguage.zh:
        return '运行中';
      case AppLanguage.ja:
        return '実行中';
      case AppLanguage.en:
        return 'Running';
    }
  }

  static String get statusIdle {
    switch (_lang) {
      case AppLanguage.zh:
        return '空闲';
      case AppLanguage.ja:
        return 'アイドル';
      case AppLanguage.en:
        return 'Idle';
    }
  }

  // --- EXP management ---
  static String get expManagementTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'EXP 管理';
      case AppLanguage.ja:
        return 'EXP 管理';
      case AppLanguage.en:
        return 'EXP Management';
    }
  }

  static String get expManagementHint {
    switch (_lang) {
      case AppLanguage.zh:
        return '在这里集中管理各类漏洞利用模块，点击条目进入对应利用界面';
      case AppLanguage.ja:
        return '各種エクスプロイトモジュールをここで一元管理。エントリをクリックして利用画面へ';
      case AppLanguage.en:
        return 'Manage all exploit modules here. Tap an entry to open its exploit interface';
    }
  }

  static String expVersionRequirement(String ver) {
    switch (_lang) {
      case AppLanguage.zh:
        return '版本要求：$ver';
      case AppLanguage.ja:
        return 'バージョン要件：$ver';
      case AppLanguage.en:
        return 'Version requirement: $ver';
    }
  }

  // --- Common EXP UI ---
  static String get sectionTargetConfig {
    switch (_lang) {
      case AppLanguage.zh:
        return '目标配置';
      case AppLanguage.ja:
        return 'ターゲット設定';
      case AppLanguage.en:
        return 'Target config';
    }
  }

  static String get fieldTargetUrl {
    switch (_lang) {
      case AppLanguage.zh:
        return '目标 URL';
      case AppLanguage.ja:
        return 'ターゲット URL';
      case AppLanguage.en:
        return 'Target URL';
    }
  }

  static String get fieldTimeout {
    switch (_lang) {
      case AppLanguage.zh:
        return '超时(s)';
      case AppLanguage.ja:
        return 'タイムアウト(s)';
      case AppLanguage.en:
        return 'Timeout (s)';
    }
  }

  static String get fieldCommand {
    switch (_lang) {
      case AppLanguage.zh:
        return '命令';
      case AppLanguage.ja:
        return 'コマンド';
      case AppLanguage.en:
        return 'Command';
    }
  }

  static String get btnDetect {
    switch (_lang) {
      case AppLanguage.zh:
        return '检测';
      case AppLanguage.ja:
        return '検出';
      case AppLanguage.en:
        return 'Detect';
    }
  }

  static String get btnDetectVuln {
    switch (_lang) {
      case AppLanguage.zh:
        return '检测漏洞';
      case AppLanguage.ja:
        return '脆弱性を検出';
      case AppLanguage.en:
        return 'Detect vuln';
    }
  }

  static String get btnDetectAll {
    switch (_lang) {
      case AppLanguage.zh:
        return '检测全部';
      case AppLanguage.ja:
        return '全て検出';
      case AppLanguage.en:
        return 'Detect all';
    }
  }

  static String get btnExecCmd {
    switch (_lang) {
      case AppLanguage.zh:
        return '执行命令';
      case AppLanguage.ja:
        return 'コマンド実行';
      case AppLanguage.en:
        return 'Execute command';
    }
  }

  static String get btnSubmitCmd {
    switch (_lang) {
      case AppLanguage.zh:
        return '提交命令';
      case AppLanguage.ja:
        return 'コマンドを送信';
      case AppLanguage.en:
        return 'Submit command';
    }
  }

  static String get sectionCmdExec {
    switch (_lang) {
      case AppLanguage.zh:
        return '命令执行';
      case AppLanguage.ja:
        return 'コマンド実行';
      case AppLanguage.en:
        return 'Command execution';
    }
  }

  static String get sectionGetShell {
    switch (_lang) {
      case AppLanguage.zh:
        return 'GetShell（反弹 Shell）';
      case AppLanguage.ja:
        return 'GetShell（リバースシェル）';
      case AppLanguage.en:
        return 'GetShell (reverse shell)';
    }
  }

  static String get fieldAttackerIp {
    switch (_lang) {
      case AppLanguage.zh:
        return '攻击机 IP';
      case AppLanguage.ja:
        return '攻撃者 IP';
      case AppLanguage.en:
        return 'Attacker IP';
    }
  }

  static String get fieldAttackerPort {
    switch (_lang) {
      case AppLanguage.zh:
        return '攻击机端口';
      case AppLanguage.ja:
        return '攻撃者ポート';
      case AppLanguage.en:
        return 'Attacker port';
    }
  }

  static String get btnStartReverseShell {
    switch (_lang) {
      case AppLanguage.zh:
        return '启动反弹终端';
      case AppLanguage.ja:
        return 'リバースシェル起動';
      case AppLanguage.en:
        return 'Start reverse shell';
    }
  }

  static String get fieldShellPassword {
    switch (_lang) {
      case AppLanguage.zh:
        return '冰蝎密码';
      case AppLanguage.ja:
        return 'Behinder パスワード';
      case AppLanguage.en:
        return 'Shell password';
    }
  }

  static String get btnWriteWebShell {
    switch (_lang) {
      case AppLanguage.zh:
        return '写入 WebShell';
      case AppLanguage.ja:
        return 'WebShell を書き込む';
      case AppLanguage.en:
        return 'Write WebShell';
    }
  }

  static String get sectionVulnSelect {
    switch (_lang) {
      case AppLanguage.zh:
        return '漏洞选择';
      case AppLanguage.ja:
        return '脆弱性を選択';
      case AppLanguage.en:
        return 'Vuln selection';
    }
  }

  /// 未选中项目时 [ProjectScopedPage] 的标题占位（与菜单一致）
  static String get titleWebshellManager {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Webshell';
      case AppLanguage.ja:
        return 'Webshell';
      case AppLanguage.en:
        return 'Webshell';
    }
  }

  // --- Common exploit operation logs (tags kept for vulhubRichLog coloring) ---
  static String get expLogEnterTargetUrl {
    switch (_lang) {
      case AppLanguage.zh:
        return '[!] 请输入目标 URL';
      case AppLanguage.ja:
        return '[!] ターゲット URL を入力してください';
      case AppLanguage.en:
        return '[!] Please enter the target URL';
    }
  }

  static String expLogException(Object e) {
    switch (_lang) {
      case AppLanguage.zh:
        return '[!] 异常: $e';
      case AppLanguage.ja:
        return '[!] 例外: $e';
      case AppLanguage.en:
        return '[!] Error: $e';
    }
  }

  static String get expLogInvalidLhostLport {
    switch (_lang) {
      case AppLanguage.zh:
        return '[!] LHOST/LPORT 无效';
      case AppLanguage.ja:
        return '[!] LHOST/LPORT が無効です';
      case AppLanguage.en:
        return '[!] Invalid LHOST/LPORT';
    }
  }

  static String get expLogNoVulnGeneric {
    switch (_lang) {
      case AppLanguage.zh:
        return '[-] 未检测到漏洞';
      case AppLanguage.ja:
        return '[-] 脆弱性は検出されませんでした';
      case AppLanguage.en:
        return '[-] No vulnerability detected';
    }
  }

  static String get expLogReverseSentWaiting {
    switch (_lang) {
      case AppLanguage.zh:
        return '[+] 已发送反弹 shell，等待连接...';
      case AppLanguage.ja:
        return '[+] リバースシェルを送信しました。接続待ち...';
      case AppLanguage.en:
        return '[+] Reverse shell payload sent, waiting for connection...';
    }
  }

  static String get expLogSendFailed {
    switch (_lang) {
      case AppLanguage.zh:
        return '[-] 发送失败';
      case AppLanguage.ja:
        return '[-] 送信に失敗しました';
      case AppLanguage.en:
        return '[-] Send failed';
    }
  }

  static String expLogStartFailed(Object e) {
    switch (_lang) {
      case AppLanguage.zh:
        return '[!] 启动失败: $e';
      case AppLanguage.ja:
        return '[!] 起動失敗: $e';
      case AppLanguage.en:
        return '[!] Failed to start: $e';
    }
  }

  static String expLogStartFullTerminalListen(
    String lhost,
    int lport,
    String mode,
  ) {
    switch (_lang) {
      case AppLanguage.zh:
        return '[*] 启动完整终端监听: $lhost:$lport ($mode)';
      case AppLanguage.ja:
        return '[*] フルターミナル待受を開始: $lhost:$lport ($mode)';
      case AppLanguage.en:
        return '[*] Starting full-terminal listener: $lhost:$lport ($mode)';
    }
  }

  static String get expLogSocatRunOnTarget {
    switch (_lang) {
      case AppLanguage.zh:
        return '[i] 在目标执行 socat 命令建立连接:';
      case AppLanguage.ja:
        return '[i] ターゲットで socat コマンドを実行して接続:';
      case AppLanguage.en:
        return '[i] Run the following socat command on the target:';
    }
  }

  static String get terminalConnectionClosed {
    switch (_lang) {
      case AppLanguage.zh:
        return '连接已断开';
      case AppLanguage.ja:
        return '接続が切断されました';
      case AppLanguage.en:
        return 'Connection closed';
    }
  }

  static String get frpLogCopiedSnack {
    switch (_lang) {
      case AppLanguage.zh:
        return '日志已复制到剪贴板';
      case AppLanguage.ja:
        return 'ログをクリップボードにコピーしました';
      case AppLanguage.en:
        return 'Log copied to clipboard';
    }
  }

  static String frpDupDisplayName(String base) {
    switch (_lang) {
      case AppLanguage.zh:
        return '$base 副本';
      case AppLanguage.ja:
        return '$base のコピー';
      case AppLanguage.en:
        return '$base copy';
    }
  }

  static String frpDupDisplayNameIndexed(String base, int i) {
    switch (_lang) {
      case AppLanguage.zh:
        return '$base 副本 ($i)';
      case AppLanguage.ja:
        return '$base のコピー ($i)';
      case AppLanguage.en:
        return '$base copy ($i)';
    }
  }

  static String frpDupProxyFirst(String proxyName) {
    switch (_lang) {
      case AppLanguage.zh:
        return '${proxyName}_副本';
      case AppLanguage.ja:
        return '${proxyName}_copy';
      case AppLanguage.en:
        return '${proxyName}_copy';
    }
  }

  static String frpDupProxyIndexed(String proxyName, int i) {
    switch (_lang) {
      case AppLanguage.zh:
        return '${proxyName}_副本$i';
      case AppLanguage.ja:
        return '${proxyName}_copy$i';
      case AppLanguage.en:
        return '${proxyName}_copy$i';
    }
  }

  static String get frpAuthMd5Label {
    switch (_lang) {
      case AppLanguage.zh:
        return 'MD5 (官方默认)';
      case AppLanguage.ja:
        return 'MD5（公式デフォルト）';
      case AppLanguage.en:
        return 'MD5 (official default)';
    }
  }

  static String get frpAuthHmacSha1Label {
    switch (_lang) {
      case AppLanguage.zh:
        return 'HMAC-SHA1';
      case AppLanguage.ja:
        return 'HMAC-SHA1';
      case AppLanguage.en:
        return 'HMAC-SHA1';
    }
  }

  static String get frpAuthHmacSha256Label {
    switch (_lang) {
      case AppLanguage.zh:
        return 'HMAC-SHA256';
      case AppLanguage.ja:
        return 'HMAC-SHA256';
      case AppLanguage.en:
        return 'HMAC-SHA256';
    }
  }

  static String get frpAuthRawTokenLabel {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Raw Token';
      case AppLanguage.ja:
        return 'Raw Token';
      case AppLanguage.en:
        return 'Raw Token';
    }
  }

  static String get sectionVulnType {
    switch (_lang) {
      case AppLanguage.zh:
        return '漏洞类型';
      case AppLanguage.ja:
        return '脆弱性タイプ';
      case AppLanguage.en:
        return 'Vulnerability type';
    }
  }

  static String get nacosStep2 {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Step 2 — Derby SQL RCE';
      case AppLanguage.ja:
        return 'Step 2 — Derby SQL RCE';
      case AppLanguage.en:
        return 'Step 2 — Derby SQL RCE';
    }
  }

  static String get sectionSshModuleCmdInject {
    switch (_lang) {
      case AppLanguage.zh:
        return 'SSH 模块命令注入';
      case AppLanguage.ja:
        return 'SSH モジュール コマンドインジェクション';
      case AppLanguage.en:
        return 'SSH module command injection';
    }
  }

  static String get btnGetShell {
    switch (_lang) {
      case AppLanguage.zh:
        return 'GetShell';
      case AppLanguage.ja:
        return 'GetShell';
      case AppLanguage.en:
        return 'GetShell';
    }
  }

  static String connectorUiLabel(String connectorType) {
    switch (connectorType) {
      case 'php_eval':
        return 'PHP Eval';
      case 'php_b64rot13':
        return 'PHP B64+ROT13';
      case 'php_behinder':
        switch (_lang) {
          case AppLanguage.zh:
            return 'PHP 冰蝎 (Behinder)';
          case AppLanguage.ja:
            return 'PHP Behinder';
          case AppLanguage.en:
            return 'PHP Behinder';
        }
      case 'php_passthru':
        return 'PHP Passthru';
      case 'jsp_classloader':
        return 'JSP ClassLoader';
      case 'jsp_behinder':
        switch (_lang) {
          case AppLanguage.zh:
            return 'JSP 冰蝎 (Behinder)';
          case AppLanguage.ja:
            return 'JSP Behinder';
          case AppLanguage.en:
            return 'JSP Behinder';
        }
      case 'jsp_runtime':
        return 'JSP Runtime';
      case 'asp_wscript':
        return 'ASP WScript';
      case 'aspx_cmd':
        return 'ASPX .NET';
      default:
        switch (_lang) {
          case AppLanguage.zh:
            return connectorType;
          case AppLanguage.ja:
            return connectorType;
          case AppLanguage.en:
            return connectorType;
        }
    }
  }

  static String get detectPingOk {
    switch (_lang) {
      case AppLanguage.zh:
        return '有响应';
      case AppLanguage.ja:
        return '応答あり';
      case AppLanguage.en:
        return 'Responded';
    }
  }

  static String get detectPingNo {
    switch (_lang) {
      case AppLanguage.zh:
        return '无响应';
      case AppLanguage.ja:
        return '応答なし';
      case AppLanguage.en:
        return 'No response';
    }
  }

  static String get detectPingTimeout {
    switch (_lang) {
      case AppLanguage.zh:
        return '超时';
      case AppLanguage.ja:
        return 'タイムアウト';
      case AppLanguage.en:
        return 'Timeout';
    }
  }

  static String get detectPingConnectFailed {
    switch (_lang) {
      case AppLanguage.zh:
        return '连接失败';
      case AppLanguage.ja:
        return '接続失敗';
      case AppLanguage.en:
        return 'Connection failed';
    }
  }

  // --- Reverse shell terminal page ---
  static String terminalFullTitle(String label) {
    switch (_lang) {
      case AppLanguage.zh:
        return '完整终端 · $label';
      case AppLanguage.ja:
        return 'フルターミナル · $label';
      case AppLanguage.en:
        return 'Full terminal · $label';
    }
  }

  static String get btnDisconnect {
    switch (_lang) {
      case AppLanguage.zh:
        return '主动断开';
      case AppLanguage.ja:
        return '切断する';
      case AppLanguage.en:
        return 'Disconnect';
    }
  }

  static String get actionPaste {
    switch (_lang) {
      case AppLanguage.zh:
        return '粘贴';
      case AppLanguage.ja:
        return '貼り付け';
      case AppLanguage.en:
        return 'Paste';
    }
  }

  // --- FRP tunnel ---
  static String get frpTunnelTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'FRP 隧道客户端';
      case AppLanguage.ja:
        return 'FRP トンネルクライアント';
      case AppLanguage.en:
        return 'FRP Tunnel Client';
    }
  }

  static String get frpStatusRunning {
    switch (_lang) {
      case AppLanguage.zh:
        return '隧道运行中 · 远端流量将转发到本地';
      case AppLanguage.ja:
        return 'トンネル実行中 · リモートトラフィックをローカルに転送';
      case AppLanguage.en:
        return 'Tunnel running · Remote traffic is being forwarded locally';
    }
  }

  static String get frpStatusConnecting {
    switch (_lang) {
      case AppLanguage.zh:
        return '正在连接...';
      case AppLanguage.ja:
        return '接続中...';
      case AppLanguage.en:
        return 'Connecting...';
    }
  }

  static String get frpStatusError {
    switch (_lang) {
      case AppLanguage.zh:
        return '连接出错，请检查参数或日志';
      case AppLanguage.ja:
        return '接続エラー。パラメーターまたはログを確認してください';
      case AppLanguage.en:
        return 'Connection error. Check parameters or logs';
    }
  }

  static String get frpStatusIdle {
    switch (_lang) {
      case AppLanguage.zh:
        return '就绪 · 在列表中点击「启动」连接隧道';
      case AppLanguage.ja:
        return '待機中 · リストで「起動」をクリックしてトンネルに接続';
      case AppLanguage.en:
        return 'Ready · Click "Start" in the list to connect the tunnel';
    }
  }

  static String get frpSavedConfigs {
    switch (_lang) {
      case AppLanguage.zh:
        return '已保存配置';
      case AppLanguage.ja:
        return '保存済み設定';
      case AppLanguage.en:
        return 'Saved profiles';
    }
  }

  static String get frpNoConfigs {
    switch (_lang) {
      case AppLanguage.zh:
        return '暂无配置，点击底部「新建配置」添加。';
      case AppLanguage.ja:
        return '設定なし。下の「新規設定」をクリックして追加してください。';
      case AppLanguage.en:
        return 'No profiles yet. Click "New profile" below to add one.';
    }
  }

  static String get frpNewConfig {
    switch (_lang) {
      case AppLanguage.zh:
        return '新建配置';
      case AppLanguage.ja:
        return '新規設定';
      case AppLanguage.en:
        return 'New profile';
    }
  }

  static String get frpRunLog {
    switch (_lang) {
      case AppLanguage.zh:
        return '运行日志';
      case AppLanguage.ja:
        return '実行ログ';
      case AppLanguage.en:
        return 'Run log';
    }
  }

  static String get frpNoLogs {
    switch (_lang) {
      case AppLanguage.zh:
        return '> 尚无日志';
      case AppLanguage.ja:
        return '> ログなし';
      case AppLanguage.en:
        return '> No logs yet';
    }
  }

  static String frpDuplicatedSnack(String name, String proxyName, int port) {
    switch (_lang) {
      case AppLanguage.zh:
        return '已复制「$name」\n代理名 $proxyName · 远端端口 $port（已与原版区分，可按需再改）';
      case AppLanguage.ja:
        return '「$name」を複製しました\nプロキシ名 $proxyName · リモートポート $port（元と区別済み、必要に応じて変更可）';
      case AppLanguage.en:
        return 'Duplicated "$name"\nProxy $proxyName · Remote port $port (distinct from original, edit as needed)';
    }
  }

  static String frpDuplicateFailed(Object e) {
    switch (_lang) {
      case AppLanguage.zh:
        return '复制失败：$e';
      case AppLanguage.ja:
        return '複製失敗：$e';
      case AppLanguage.en:
        return 'Duplicate failed: $e';
    }
  }

  static String get frpMissingServerOrProxy {
    switch (_lang) {
      case AppLanguage.zh:
        return '该配置缺少服务器地址或代理名称，请先编辑保存';
      case AppLanguage.ja:
        return 'サーバーアドレスまたはプロキシ名が不足しています。先に編集して保存してください';
      case AppLanguage.en:
        return 'This profile is missing a server address or proxy name. Edit and save first';
    }
  }

  static String get frpDeleteTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return '删除配置';
      case AppLanguage.ja:
        return '設定を削除';
      case AppLanguage.en:
        return 'Delete profile';
    }
  }

  static String frpConfirmDelete(String name) {
    switch (_lang) {
      case AppLanguage.zh:
        return '确定删除「$name」？此操作不可恢复。';
      case AppLanguage.ja:
        return '「$name」を削除しますか？この操作は元に戻せません。';
      case AppLanguage.en:
        return 'Delete "$name"? This action cannot be undone.';
    }
  }

  static String frpDeletedSnack(String name) {
    switch (_lang) {
      case AppLanguage.zh:
        return '已删除「$name」';
      case AppLanguage.ja:
        return '「$name」を削除しました';
      case AppLanguage.en:
        return 'Deleted "$name"';
    }
  }

  static String frpMappingLabel(
    int remotePort,
    String localAddr,
    int localPort,
  ) {
    switch (_lang) {
      case AppLanguage.zh:
        return '映射 远端端口 $remotePort → 本地 $localAddr:$localPort';
      case AppLanguage.ja:
        return 'リモートポート $remotePort → ローカル $localAddr:$localPort';
      case AppLanguage.en:
        return 'Remote port $remotePort → Local $localAddr:$localPort';
    }
  }

  static String frpServerLabel(String serverAddr, int serverPort) {
    switch (_lang) {
      case AppLanguage.zh:
        return 'frp 服务器 $serverAddr:$serverPort';
      case AppLanguage.ja:
        return 'frp サーバー $serverAddr:$serverPort';
      case AppLanguage.en:
        return 'frp server $serverAddr:$serverPort';
    }
  }

  static String get btnStart {
    switch (_lang) {
      case AppLanguage.zh:
        return '启动';
      case AppLanguage.ja:
        return '起動';
      case AppLanguage.en:
        return 'Start';
    }
  }

  static String get btnStop {
    switch (_lang) {
      case AppLanguage.zh:
        return '停止';
      case AppLanguage.ja:
        return '停止';
      case AppLanguage.en:
        return 'Stop';
    }
  }

  static String get btnEdit {
    switch (_lang) {
      case AppLanguage.zh:
        return '编辑';
      case AppLanguage.ja:
        return '編集';
      case AppLanguage.en:
        return 'Edit';
    }
  }

  static String get btnDuplicate {
    switch (_lang) {
      case AppLanguage.zh:
        return '复制';
      case AppLanguage.ja:
        return '複製';
      case AppLanguage.en:
        return 'Duplicate';
    }
  }

  static String get frpNewConfigTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return '新建配置';
      case AppLanguage.ja:
        return '新規設定';
      case AppLanguage.en:
        return 'New profile';
    }
  }

  static String get frpEditConfigTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return '编辑配置';
      case AppLanguage.ja:
        return '設定を編集';
      case AppLanguage.en:
        return 'Edit profile';
    }
  }

  static String get frpRunningNoEdit {
    switch (_lang) {
      case AppLanguage.zh:
        return '运行中不可改';
      case AppLanguage.ja:
        return '実行中は変更不可';
      case AppLanguage.en:
        return 'Cannot edit while running';
    }
  }

  static String get frpAutoSave {
    switch (_lang) {
      case AppLanguage.zh:
        return '修改将自动保存';
      case AppLanguage.ja:
        return '変更は自動保存されます';
      case AppLanguage.en:
        return 'Changes auto-save';
    }
  }

  static String get frpConfigName {
    switch (_lang) {
      case AppLanguage.zh:
        return '配置名称';
      case AppLanguage.ja:
        return '設定名';
      case AppLanguage.en:
        return 'Profile name';
    }
  }

  static String get frpConfigNameHint {
    switch (_lang) {
      case AppLanguage.zh:
        return '例如 办公网 / 测试机';
      case AppLanguage.ja:
        return '例：オフィスネット / テストサーバー';
      case AppLanguage.en:
        return 'e.g. Office network / Test server';
    }
  }

  static String get frpServerSection {
    switch (_lang) {
      case AppLanguage.zh:
        return '服务端配置';
      case AppLanguage.ja:
        return 'サーバー設定';
      case AppLanguage.en:
        return 'Server config';
    }
  }

  static String get frpServerAddr {
    switch (_lang) {
      case AppLanguage.zh:
        return 'frp 服务器地址';
      case AppLanguage.ja:
        return 'frp サーバーアドレス';
      case AppLanguage.en:
        return 'frp server address';
    }
  }

  static String get frpServerAddrHint {
    switch (_lang) {
      case AppLanguage.zh:
        return '例如 1.2.3.4';
      case AppLanguage.ja:
        return '例：1.2.3.4';
      case AppLanguage.en:
        return 'e.g. 1.2.3.4';
    }
  }

  static String get frpPort {
    switch (_lang) {
      case AppLanguage.zh:
        return '端口';
      case AppLanguage.ja:
        return 'ポート';
      case AppLanguage.en:
        return 'Port';
    }
  }

  static String get frpProxySection {
    switch (_lang) {
      case AppLanguage.zh:
        return '代理配置';
      case AppLanguage.ja:
        return 'プロキシ設定';
      case AppLanguage.en:
        return 'Proxy config';
    }
  }

  static String get frpProxyName {
    switch (_lang) {
      case AppLanguage.zh:
        return '代理名称';
      case AppLanguage.ja:
        return 'プロキシ名';
      case AppLanguage.en:
        return 'Proxy name';
    }
  }

  static String get frpRemotePort {
    switch (_lang) {
      case AppLanguage.zh:
        return '远端端口';
      case AppLanguage.ja:
        return 'リモートポート';
      case AppLanguage.en:
        return 'Remote port';
    }
  }

  static String get frpLocalAddr {
    switch (_lang) {
      case AppLanguage.zh:
        return '本地地址';
      case AppLanguage.ja:
        return 'ローカルアドレス';
      case AppLanguage.en:
        return 'Local address';
    }
  }

  static String get frpLocalPort {
    switch (_lang) {
      case AppLanguage.zh:
        return '本地端口';
      case AppLanguage.ja:
        return 'ローカルポート';
      case AppLanguage.en:
        return 'Local port';
    }
  }

  static String get frpAdvanced {
    switch (_lang) {
      case AppLanguage.zh:
        return '高级选项';
      case AppLanguage.ja:
        return '詳細オプション';
      case AppLanguage.en:
        return 'Advanced options';
    }
  }

  static String get frpVersionLabel {
    switch (_lang) {
      case AppLanguage.zh:
        return '客户端版本号（留空则不携带）';
      case AppLanguage.ja:
        return 'クライアントバージョン（空欄は省略）';
      case AppLanguage.en:
        return 'Client version (leave blank to omit)';
    }
  }

  static String get frpVersionHint {
    switch (_lang) {
      case AppLanguage.zh:
        return '例如 0.51.3 / 0.61.1';
      case AppLanguage.ja:
        return '例：0.51.3 / 0.61.1';
      case AppLanguage.en:
        return 'e.g. 0.51.3 / 0.61.1';
    }
  }

  static String get frpTcpMux {
    switch (_lang) {
      case AppLanguage.zh:
        return 'TCPMux（yamux 多路复用）';
      case AppLanguage.ja:
        return 'TCPMux（yamux 多重化）';
      case AppLanguage.en:
        return 'TCPMux (yamux multiplexing)';
    }
  }

  static String get frpAutoReconnect {
    switch (_lang) {
      case AppLanguage.zh:
        return '断开后自动重连（5 秒后重试）';
      case AppLanguage.ja:
        return '切断後に自動再接続（5 秒後に再試行）';
      case AppLanguage.en:
        return 'Auto-reconnect on disconnect (retry after 5 s)';
    }
  }

  static String get frpAuthAlgorithm {
    switch (_lang) {
      case AppLanguage.zh:
        return '认证算法：';
      case AppLanguage.ja:
        return '認証アルゴリズム：';
      case AppLanguage.en:
        return 'Auth algorithm:';
    }
  }

  static String get frpToken {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Token（可留空）';
      case AppLanguage.ja:
        return 'Token（空欄可）';
      case AppLanguage.en:
        return 'Token (optional)';
    }
  }

  static String get frpUnnamedConfig {
    switch (_lang) {
      case AppLanguage.zh:
        return '未命名配置';
      case AppLanguage.ja:
        return '無名設定';
      case AppLanguage.en:
        return 'Unnamed profile';
    }
  }

  static String frpSaveFailed(Object e) {
    switch (_lang) {
      case AppLanguage.zh:
        return '保存失败：$e';
      case AppLanguage.ja:
        return '保存失敗：$e';
      case AppLanguage.en:
        return 'Save failed: $e';
    }
  }

  static String get frpActiveNotMatched {
    switch (_lang) {
      case AppLanguage.zh:
        return '连接仍在，但与已保存配置不一致（例如切页后未恢复对应项）。可点右侧「停止连接」';
      case AppLanguage.ja:
        return '接続中ですが、保存済み設定と一致しません（ページ切替後など）。右の「接続停止」をクリック';
      case AppLanguage.en:
        return 'Tunnel active but does not match any saved profile (e.g. after navigation). Click "Stop" on the right';
    }
  }

  static String get frpStopConnection {
    switch (_lang) {
      case AppLanguage.zh:
        return '停止连接';
      case AppLanguage.ja:
        return '接続を停止';
      case AppLanguage.en:
        return 'Stop connection';
    }
  }

  // --- Shiro exploit ---
  static String get shiroPageTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Apache Shiro 反序列化利用';
      case AppLanguage.ja:
        return 'Apache Shiro デシリアライゼーション攻撃';
      case AppLanguage.en:
        return 'Apache Shiro Deserialization Exploit';
    }
  }

  static String get shiroCardTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'rememberMe Key 爆破与利用';
      case AppLanguage.ja:
        return 'rememberMe Key ブルートフォースと利用';
      case AppLanguage.en:
        return 'rememberMe Key bruteforce & exploit';
    }
  }

  static String get shiroCardSubtitle {
    switch (_lang) {
      case AppLanguage.zh:
        return '支持 AES-CBC / AES-GCM，字典爆破 Key 后加载自定义 Payload';
      case AppLanguage.ja:
        return 'AES-CBC / AES-GCM 対応。辞書でKey爆破後にカスタム Payload をロード';
      case AppLanguage.en:
        return 'Supports AES-CBC / AES-GCM. Bruteforce Key then load custom Payload';
    }
  }

  static String get shiroInnerTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Shiro 反序列化';
      case AppLanguage.ja:
        return 'Shiro デシリアライゼーション';
      case AppLanguage.en:
        return 'Shiro deserialization';
    }
  }

  static String get shiroSectionKeyPayload {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Key 与 Payload';
      case AppLanguage.ja:
        return 'Key と Payload';
      case AppLanguage.en:
        return 'Key & Payload';
    }
  }

  static String get shiroSectionMemShell {
    switch (_lang) {
      case AppLanguage.zh:
        return '内存冰蝎马注入';
      case AppLanguage.ja:
        return 'メモリ Behinder シェル注入';
      case AppLanguage.en:
        return 'In-memory Behinder shell injection';
    }
  }

  static String get shiroFieldMethod {
    switch (_lang) {
      case AppLanguage.zh:
        return '方法';
      case AppLanguage.ja:
        return 'メソッド';
      case AppLanguage.en:
        return 'Method';
    }
  }

  static String get shiroFieldMode {
    switch (_lang) {
      case AppLanguage.zh:
        return '模式';
      case AppLanguage.ja:
        return 'モード';
      case AppLanguage.en:
        return 'Mode';
    }
  }

  static String get shiroModeHint {
    switch (_lang) {
      case AppLanguage.zh:
        return '模式: 自定义 Payload（仅发送下方 Base64）';
      case AppLanguage.ja:
        return 'モード: カスタム Payload（下の Base64 のみ送信）';
      case AppLanguage.en:
        return 'Mode: custom Payload (only sends the Base64 below)';
    }
  }

  static String get shiroFieldCookieName {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Cookie 名';
      case AppLanguage.ja:
        return 'Cookie 名';
      case AppLanguage.en:
        return 'Cookie name';
    }
  }

  static String get shiroVerboseLog {
    switch (_lang) {
      case AppLanguage.zh:
        return '详细日志';
      case AppLanguage.ja:
        return '詳細ログ';
      case AppLanguage.en:
        return 'Verbose log';
    }
  }

  static String get shiroCurrentKey {
    switch (_lang) {
      case AppLanguage.zh:
        return '当前 Key';
      case AppLanguage.ja:
        return '現在の Key';
      case AppLanguage.en:
        return 'Current Key';
    }
  }

  static String get shiroKeyAutoFilled {
    switch (_lang) {
      case AppLanguage.zh:
        return '爆破后自动填充';
      case AppLanguage.ja:
        return 'ブルートフォース後に自動入力';
      case AppLanguage.en:
        return 'Auto-filled after bruteforce';
    }
  }

  static String get shiroPayloadBase64 {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Payload Base64';
      case AppLanguage.ja:
        return 'Payload Base64';
      case AppLanguage.en:
        return 'Payload Base64';
    }
  }

  static String get shiroPayloadHint {
    switch (_lang) {
      case AppLanguage.zh:
        return '粘贴 Base64 编码的序列化 Payload';
      case AppLanguage.ja:
        return 'Base64 エンコードされたシリアライズ Payload を貼り付け';
      case AppLanguage.en:
        return 'Paste Base64-encoded serialized Payload';
    }
  }

  static String get shiroCheckBtn {
    switch (_lang) {
      case AppLanguage.zh:
        return '检测 Shiro';
      case AppLanguage.ja:
        return 'Shiro を検出';
      case AppLanguage.en:
        return 'Detect Shiro';
    }
  }

  static String get shiroBruteforceBtn {
    switch (_lang) {
      case AppLanguage.zh:
        return '爆破 Key';
      case AppLanguage.ja:
        return 'Key をブルートフォース';
      case AppLanguage.en:
        return 'Bruteforce Key';
    }
  }

  static String get shiroVerifyBtn {
    switch (_lang) {
      case AppLanguage.zh:
        return '验证 Key';
      case AppLanguage.ja:
        return 'Key を検証';
      case AppLanguage.en:
        return 'Verify Key';
    }
  }

  static String get shiroSendPayloadBtn {
    switch (_lang) {
      case AppLanguage.zh:
        return '发送 Payload';
      case AppLanguage.ja:
        return 'Payload を送信';
      case AppLanguage.en:
        return 'Send Payload';
    }
  }

  static String get shiroShellType {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Shell 类型';
      case AppLanguage.ja:
        return 'Shell タイプ';
      case AppLanguage.en:
        return 'Shell type';
    }
  }

  static String get shiroShellPassword {
    switch (_lang) {
      case AppLanguage.zh:
        return '冰蝎密码（16位HEX）';
      case AppLanguage.ja:
        return 'Behinder パスワード（16桁 HEX）';
      case AppLanguage.en:
        return 'Behinder password (16-char HEX)';
    }
  }

  static String get shiroShellPath {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Shell 路径';
      case AppLanguage.ja:
        return 'Shell パス';
      case AppLanguage.en:
        return 'Shell path';
    }
  }

  static String get shiroMemShellDesc {
    switch (_lang) {
      case AppLanguage.zh:
        return '内置 CB1-InjectMemTool 链，无需手动填写 Payload。服务端反序列化后读取 user 参数注入冰蝎内存马。';
      case AppLanguage.ja:
        return '内蔵 CB1-InjectMemTool チェーン。Payload 手動入力不要。サーバーデシリアライズ後、user パラメーターで Behinder メモリシェルを注入。';
      case AppLanguage.en:
        return 'Built-in CB1-InjectMemTool chain. No manual Payload required. After server deserialization, injects a Behinder memory shell via the user parameter.';
    }
  }

  // --- Shared project picker ---
  static String get noProjectTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return '暂无项目';
      case AppLanguage.ja:
        return 'プロジェクトなし';
      case AppLanguage.en:
        return 'No projects';
    }
  }

  static String get hintCreateProjectForWebshell {
    switch (_lang) {
      case AppLanguage.zh:
        return '请先创建一个项目以保存 Webshell';
      case AppLanguage.ja:
        return 'Webshell を保存するプロジェクトを先に作成してください';
      case AppLanguage.en:
        return 'Create a project first to save the Webshell';
    }
  }

  static String get fieldProjectNameHint {
    switch (_lang) {
      case AppLanguage.zh:
        return '例如：目标站点';
      case AppLanguage.ja:
        return '例：ターゲットサイト';
      case AppLanguage.en:
        return 'e.g. Target site';
    }
  }

  static String get fieldDomainOrIdHint {
    switch (_lang) {
      case AppLanguage.zh:
        return '例如：example.com';
      case AppLanguage.ja:
        return '例：example.com';
      case AppLanguage.en:
        return 'e.g. example.com';
    }
  }

  static String get btnSkip {
    switch (_lang) {
      case AppLanguage.zh:
        return '跳过';
      case AppLanguage.ja:
        return 'スキップ';
      case AppLanguage.en:
        return 'Skip';
    }
  }

  // --- ThinkPHP exploit ---
  static String get thinkphpTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'ThinkPHP CVE-2018-20062/CVE-2019-9082/CNVD-2022-86535';
      case AppLanguage.ja:
        return 'ThinkPHP CVE-2018-20062/CVE-2019-9082/CNVD-2022-86535';
      case AppLanguage.en:
        return 'ThinkPHP CVE-2018-20062/CVE-2019-9082/CNVD-2022-86535';
    }
  }

  static String get thinkphpSubtitle {
    switch (_lang) {
      case AppLanguage.zh:
        return '支持漏洞检测、命令执行、GetShell，100% 复现 ThinkphpGUI';
      case AppLanguage.ja:
        return '脆弱性検出・コマンド実行・GetShell 対応。ThinkphpGUI を 100% 再現';
      case AppLanguage.en:
        return 'Vuln detection, command execution, GetShell. 100% ThinkphpGUI replication';
    }
  }

  static String get thinkphpInnerTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'ThinkPHP 漏洞利用';
      case AppLanguage.ja:
        return 'ThinkPHP エクスプロイト';
      case AppLanguage.en:
        return 'ThinkPHP exploit';
    }
  }

  static String thinkphpCurrentVuln(String label) {
    switch (_lang) {
      case AppLanguage.zh:
        return '当前: $label';
      case AppLanguage.ja:
        return '選択中: $label';
      case AppLanguage.en:
        return 'Current: $label';
    }
  }

  static String get thinkphpSectionDetect {
    switch (_lang) {
      case AppLanguage.zh:
        return '漏洞检测';
      case AppLanguage.ja:
        return '脆弱性検出';
      case AppLanguage.en:
        return 'Vuln detection';
    }
  }

  static String get thinkphpSectionRce {
    switch (_lang) {
      case AppLanguage.zh:
        return 'RCE 利用';
      case AppLanguage.ja:
        return 'RCE 利用';
      case AppLanguage.en:
        return 'RCE exploit';
    }
  }

  static String get thinkphpSingleVuln {
    switch (_lang) {
      case AppLanguage.zh:
        return '单漏洞:';
      case AppLanguage.ja:
        return '単一 CVE:';
      case AppLanguage.en:
        return 'Single CVE:';
    }
  }

  static String get thinkphpExploitVuln {
    switch (_lang) {
      case AppLanguage.zh:
        return '利用漏洞:';
      case AppLanguage.ja:
        return '利用する CVE:';
      case AppLanguage.en:
        return 'Exploit CVE:';
    }
  }

  static String get thinkphpGetShellPassword {
    switch (_lang) {
      case AppLanguage.zh:
        return 'GetShell 密码';
      case AppLanguage.ja:
        return 'GetShell パスワード';
      case AppLanguage.en:
        return 'GetShell password';
    }
  }

  static String get thinkphpCheckAllRce {
    switch (_lang) {
      case AppLanguage.zh:
        return '检测全部RCE';
      case AppLanguage.ja:
        return '全RCEを検出';
      case AppLanguage.en:
        return 'Detect all RCE';
    }
  }

  // --- Zentao exploit ---
  static String get zentaoTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Zentao CVE-2024-24216 · GetShell';
      case AppLanguage.ja:
        return 'Zentao CVE-2024-24216 · GetShell';
      case AppLanguage.en:
        return 'Zentao CVE-2024-24216 · GetShell';
    }
  }

  static String get zentaoSubtitle {
    switch (_lang) {
      case AppLanguage.zh:
        return '利用禅道 Repo 配置写入冰蝎 WebShell，一键 GetShell';
      case AppLanguage.ja:
        return '禅道 Repo 設定を悪用して Behinder WebShell を書き込み。ワンクリック GetShell';
      case AppLanguage.en:
        return 'Exploit Zentao Repo config to write a Behinder WebShell. One-click GetShell';
    }
  }

  static String get zentaoRootPath {
    switch (_lang) {
      case AppLanguage.zh:
        return '禅道根路径';
      case AppLanguage.ja:
        return 'Zentao ルートパス';
      case AppLanguage.en:
        return 'Zentao root path';
    }
  }

  static String get zentaoSectionExploit {
    switch (_lang) {
      case AppLanguage.zh:
        return '利用动作';
      case AppLanguage.ja:
        return '攻撃アクション';
      case AppLanguage.en:
        return 'Exploit actions';
    }
  }

  static String get zentaoDetectBtn {
    switch (_lang) {
      case AppLanguage.zh:
        return '探测/验证绕过';
      case AppLanguage.ja:
        return '検出/バイパス確認';
      case AppLanguage.en:
        return 'Probe / verify bypass';
    }
  }

  // --- Vulhub page titles ---

  // (Druid EXP removed)

  static String get vulhubDrupalTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Drupal CVE-2018-7600 (Drupalgeddon2) Form API RCE';
      case AppLanguage.ja:
        return 'Drupal CVE-2018-7600 (Drupalgeddon2) Form API RCE';
      case AppLanguage.en:
        return 'Drupal CVE-2018-7600 (Drupalgeddon2) Form API RCE';
    }
  }

  static String get vulhubDrupalCardTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Drupal CVE-2018-7600';
      case AppLanguage.ja:
        return 'Drupal CVE-2018-7600';
      case AppLanguage.en:
        return 'Drupal CVE-2018-7600';
    }
  }

  static String get vulhubDrupalCardSubtitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Drupalgeddon2 — Form API #post_render 回调 PHP 代码执行';
      case AppLanguage.ja:
        return 'Drupalgeddon2 — Form API #post_render コールバック PHP コード実行';
      case AppLanguage.en:
        return 'Drupalgeddon2 — Form API #post_render callback PHP code execution';
    }
  }

  static String get vulhubFlaskSstiTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Flask / Jinja2 SSTI 服务端模板注入 RCE';
      case AppLanguage.ja:
        return 'Flask / Jinja2 SSTI サーバーサイドテンプレートインジェクション RCE';
      case AppLanguage.en:
        return 'Flask / Jinja2 SSTI Server-Side Template Injection RCE';
    }
  }

  static String get vulhubFlaskSstiCardTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Flask / Jinja2 SSTI';
      case AppLanguage.ja:
        return 'Flask / Jinja2 SSTI';
      case AppLanguage.en:
        return 'Flask / Jinja2 SSTI';
    }
  }

  static String get vulhubFlaskSstiCardSubtitle {
    switch (_lang) {
      case AppLanguage.zh:
        return '服务端 Jinja2 模板注入，通过 URL 参数执行任意 Python 代码';
      case AppLanguage.ja:
        return 'サーバーサイド Jinja2 テンプレートインジェクション。URL パラメーターで任意 Python コードを実行';
      case AppLanguage.en:
        return 'Server-side Jinja2 template injection. Execute arbitrary Python code via URL parameter';
    }
  }

  static String get vulhubHttpdTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Apache HTTP Server CVE-2021-41773 路径穿越 + CGI RCE';
      case AppLanguage.ja:
        return 'Apache HTTP Server CVE-2021-41773 パストラバーサル + CGI RCE';
      case AppLanguage.en:
        return 'Apache HTTP Server CVE-2021-41773 Path Traversal + CGI RCE';
    }
  }

  static String get vulhubHttpdCardTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Apache HTTPd CVE-2021-41773';
      case AppLanguage.ja:
        return 'Apache HTTPd CVE-2021-41773';
      case AppLanguage.en:
        return 'Apache HTTPd CVE-2021-41773';
    }
  }

  static String get vulhubHttpdCardSubtitle {
    switch (_lang) {
      case AppLanguage.zh:
        return '路径规范化缺陷 — 文件读取 + CGI 命令执行 (Apache 2.4.49)';
      case AppLanguage.ja:
        return 'パス正規化の欠陥 — ファイル読み取り + CGI コマンド実行 (Apache 2.4.49)';
      case AppLanguage.en:
        return 'Path normalization flaw — file read + CGI command execution (Apache 2.4.49)';
    }
  }

  static String get vulhubNacosTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Nacos CVE-2021-29441 User-Agent 认证绕过';
      case AppLanguage.ja:
        return 'Nacos CVE-2021-29441 User-Agent 認証バイパス';
      case AppLanguage.en:
        return 'Nacos CVE-2021-29441 User-Agent Auth Bypass';
    }
  }

  static String get vulhubNacosCardTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Nacos CVE-2021-29441';
      case AppLanguage.ja:
        return 'Nacos CVE-2021-29441';
      case AppLanguage.en:
        return 'Nacos CVE-2021-29441';
    }
  }

  static String get vulhubNacosCardSubtitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'User-Agent: Nacos-Server 绕过认证，枚举/创建用户（< 1.4.1）';
      case AppLanguage.ja:
        return 'User-Agent: Nacos-Server で認証バイパス。ユーザーの列挙/作成（< 1.4.1）';
      case AppLanguage.en:
        return 'User-Agent: Nacos-Server bypasses auth. Enumerate/create users (< 1.4.1)';
    }
  }

  // (OFBiz EXP removed)

  static String get vulhubPhpTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'PHP 8.1.0-dev 后门 / CVE-2012-1823 PHP-CGI RCE';
      case AppLanguage.ja:
        return 'PHP 8.1.0-dev バックドア / CVE-2012-1823 PHP-CGI RCE';
      case AppLanguage.en:
        return 'PHP 8.1.0-dev Backdoor / CVE-2012-1823 PHP-CGI RCE';
    }
  }

  static String get vulhubPhpCardTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'PHP RCE 系列';
      case AppLanguage.ja:
        return 'PHP RCE シリーズ';
      case AppLanguage.en:
        return 'PHP RCE Series';
    }
  }

  static String get vulhubPhpCardSubtitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'PHP 8.1.0-dev User-Agentt 后门 + CVE-2012-1823 PHP-CGI 参数注入';
      case AppLanguage.ja:
        return 'PHP 8.1.0-dev User-Agentt バックドア + CVE-2012-1823 PHP-CGI パラメーターインジェクション';
      case AppLanguage.en:
        return 'PHP 8.1.0-dev User-Agentt backdoor + CVE-2012-1823 PHP-CGI parameter injection';
    }
  }

  // (SaltStack/Shellshock/Solr EXP removed)

  static String get vulhubSpringTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Spring Framework CVE-2022-22965/22963/CVE-2018-1273/CVE-2017-8046 RCE';
      case AppLanguage.ja:
        return 'Spring Framework CVE-2022-22965/22963/CVE-2018-1273/CVE-2017-8046 RCE';
      case AppLanguage.en:
        return 'Spring Framework CVE-2022-22965/22963/CVE-2018-1273/CVE-2017-8046 RCE';
    }
  }

  static String get vulhubSpringCardTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Spring Framework RCE';
      case AppLanguage.ja:
        return 'Spring Framework RCE';
      case AppLanguage.en:
        return 'Spring Framework RCE';
    }
  }

  static String get vulhubSpringCardSubtitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Spring4Shell / Spring Cloud Function / Spring Data SpEL 注入系列';
      case AppLanguage.ja:
        return 'Spring4Shell / Spring Cloud Function / Spring Data SpEL インジェクションシリーズ';
      case AppLanguage.en:
        return 'Spring4Shell / Spring Cloud Function / Spring Data SpEL injection series';
    }
  }

  static String get vulhubStruts2Title {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Apache Struts2 S2-032/045/053/057/059 RCE';
      case AppLanguage.ja:
        return 'Apache Struts2 S2-032/045/053/057/059 RCE';
      case AppLanguage.en:
        return 'Apache Struts2 S2-032/045/053/057/059 RCE';
    }
  }

  static String get vulhubStruts2CardTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Apache Struts2 RCE';
      case AppLanguage.ja:
        return 'Apache Struts2 RCE';
      case AppLanguage.en:
        return 'Apache Struts2 RCE';
    }
  }

  static String get vulhubStruts2CardSubtitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'S2-032 / S2-045 / S2-053 / S2-057 / S2-059 — OGNL 表达式注入';
      case AppLanguage.ja:
        return 'S2-032 / S2-045 / S2-053 / S2-057 / S2-059 — OGNL 式インジェクション';
      case AppLanguage.en:
        return 'S2-032 / S2-045 / S2-053 / S2-057 / S2-059 — OGNL expression injection';
    }
  }

  // (Supervisor EXP removed)

  static String get vulhubTomcatTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Apache Tomcat CVE-2017-12615 PUT 方法任意文件上传 RCE';
      case AppLanguage.ja:
        return 'Apache Tomcat CVE-2017-12615 PUT メソッド任意ファイルアップロード RCE';
      case AppLanguage.en:
        return 'Apache Tomcat CVE-2017-12615 PUT Method Arbitrary File Upload RCE';
    }
  }

  static String get vulhubTomcatCardTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Apache Tomcat CVE-2017-12615';
      case AppLanguage.ja:
        return 'Apache Tomcat CVE-2017-12615';
      case AppLanguage.en:
        return 'Apache Tomcat CVE-2017-12615';
    }
  }

  static String get vulhubTomcatCardSubtitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'PUT 方法开启时上传 JSP Webshell 执行命令 (Tomcat 8.5.19)';
      case AppLanguage.ja:
        return 'PUT メソッド有効時に JSP Webshell をアップロードしてコマンド実行 (Tomcat 8.5.19)';
      case AppLanguage.en:
        return 'Upload JSP Webshell when PUT method is enabled (Tomcat 8.5.19)';
    }
  }

  static String get vulhubWeblogicTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Oracle WebLogic CVE-2019-2725/CVE-2020-14882/CVE-2020-14883 RCE';
      case AppLanguage.ja:
        return 'Oracle WebLogic CVE-2019-2725/CVE-2020-14882/CVE-2020-14883 RCE';
      case AppLanguage.en:
        return 'Oracle WebLogic CVE-2019-2725/CVE-2020-14882/CVE-2020-14883 RCE';
    }
  }

  static String get vulhubWeblogicCardTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Oracle WebLogic RCE';
      case AppLanguage.ja:
        return 'Oracle WebLogic RCE';
      case AppLanguage.en:
        return 'Oracle WebLogic RCE';
    }
  }

  static String get vulhubWeblogicCardSubtitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'XMLDecoder 反序列化 + 控制台未授权 RCE';
      case AppLanguage.ja:
        return 'XMLDecoder デシリアライゼーション + コンソール未認証 RCE';
      case AppLanguage.en:
        return 'XMLDecoder deserialization + console unauthenticated RCE';
    }
  }

  static String get vulhubXxljobTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'XXL-JOB 未授权访问执行器 RCE';
      case AppLanguage.ja:
        return 'XXL-JOB 未認証アクセス Executor RCE';
      case AppLanguage.en:
        return 'XXL-JOB Unauthenticated Executor RCE';
    }
  }

  static String get vulhubXxljobCardTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return 'XXL-JOB 未授权 RCE';
      case AppLanguage.ja:
        return 'XXL-JOB 未認証 RCE';
      case AppLanguage.en:
        return 'XXL-JOB Unauthenticated RCE';
    }
  }

  static String get vulhubXxljobCardSubtitle {
    switch (_lang) {
      case AppLanguage.zh:
        return '执行器接口未授权，通过 GLUE_SHELL 类型提交任意 Shell 命令 (2.2.0)';
      case AppLanguage.ja:
        return 'Executor インターフェース未認証。GLUE_SHELL タイプで任意 Shell コマンドを送信 (2.2.0)';
      case AppLanguage.en:
        return 'Unauthenticated Executor interface. Submit arbitrary shell commands via GLUE_SHELL type (2.2.0)';
    }
  }

  // --- Vulhub page-specific UI strings ---
  static String get vulhubAria2BtnListTasks {
    switch (_lang) {
      case AppLanguage.zh:
        return '列出活跃任务';
      case AppLanguage.ja:
        return 'アクティブタスクを一覧';
      case AppLanguage.en:
        return 'List active tasks';
    }
  }

  static String get vulhubAria2SectionCron {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Cron 写入 RCE';
      case AppLanguage.ja:
        return 'Cron 書き込み RCE';
      case AppLanguage.en:
        return 'Cron write RCE';
    }
  }

  static String get vulhubAria2FieldCronUrl {
    switch (_lang) {
      case AppLanguage.zh:
        return '攻击者 cron 文件 URL';
      case AppLanguage.ja:
        return '攻撃者 cron ファイル URL';
      case AppLanguage.en:
        return 'Attacker cron file URL';
    }
  }

  static String get sectionFullTerminal {
    switch (_lang) {
      case AppLanguage.zh:
        return '完整终端';
      case AppLanguage.ja:
        return 'フルターミナル';
      case AppLanguage.en:
        return 'Full terminal';
    }
  }

  static String get fieldBasicAuth {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Basic Auth 凭据';
      case AppLanguage.ja:
        return 'Basic Auth 認証情報';
      case AppLanguage.en:
        return 'Basic Auth credentials';
    }
  }

  static String get sectionVulnDetect {
    switch (_lang) {
      case AppLanguage.zh:
        return '漏洞检测';
      case AppLanguage.ja:
        return '脆弱性検出';
      case AppLanguage.en:
        return 'Vuln detection';
    }
  }

  static String get sectionGroovyRce {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Groovy RCE 执行';
      case AppLanguage.ja:
        return 'Groovy RCE 実行';
      case AppLanguage.en:
        return 'Groovy RCE execution';
    }
  }

  static String get sectionPathTraversal {
    switch (_lang) {
      case AppLanguage.zh:
        return '路径穿越文件读取';
      case AppLanguage.ja:
        return 'パストラバーサル ファイル読み取り';
      case AppLanguage.en:
        return 'Path traversal file read';
    }
  }

  static String get fieldFilePath {
    switch (_lang) {
      case AppLanguage.zh:
        return '文件路径';
      case AppLanguage.ja:
        return 'ファイルパス';
      case AppLanguage.en:
        return 'File path';
    }
  }

  static String get sectionCgiRce {
    switch (_lang) {
      case AppLanguage.zh:
        return 'CGI RCE（需 mod_cgi 启用）';
      case AppLanguage.ja:
        return 'CGI RCE（mod_cgi 有効化が必要）';
      case AppLanguage.en:
        return 'CGI RCE (requires mod_cgi enabled)';
    }
  }

  static String get btnReadFile {
    switch (_lang) {
      case AppLanguage.zh:
        return '读取文件';
      case AppLanguage.ja:
        return 'ファイルを読み取る';
      case AppLanguage.en:
        return 'Read file';
    }
  }

  static String get fieldCoreName {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Core 名称';
      case AppLanguage.ja:
        return 'Core 名';
      case AppLanguage.en:
        return 'Core name';
    }
  }

  static String get sectionCmdExecOob {
    switch (_lang) {
      case AppLanguage.zh:
        return '命令执行（无回显，结合 OOB 验证）';
      case AppLanguage.ja:
        return 'コマンド実行（応答なし、OOB で検証）';
      case AppLanguage.en:
        return 'Command execution (blind, verify via OOB)';
    }
  }

  static String get sectionCmdExecAutoUpload {
    switch (_lang) {
      case AppLanguage.zh:
        return '命令执行（自动上传 + 执行）';
      case AppLanguage.ja:
        return 'コマンド実行（自動アップロード + 実行）';
      case AppLanguage.en:
        return 'Command execution (auto-upload + execute)';
    }
  }

  static String get sectionCmdExecOobNeeded {
    switch (_lang) {
      case AppLanguage.zh:
        return '命令执行（无回显，需 OOB）';
      case AppLanguage.ja:
        return 'コマンド実行（応答なし、OOB 必要）';
      case AppLanguage.en:
        return 'Command execution (no output, OOB required)';
    }
  }

  static String get sectionCmdExecUserAgentInject {
    switch (_lang) {
      case AppLanguage.zh:
        return '命令执行（通过 User-Agent 注入）';
      case AppLanguage.ja:
        return 'コマンド実行（User-Agent インジェクション経由）';
      case AppLanguage.en:
        return 'Command execution (via User-Agent injection)';
    }
  }

  static String get btnInjectAndTrigger {
    switch (_lang) {
      case AppLanguage.zh:
        return '注入并触发';
      case AppLanguage.ja:
        return '注入して起動';
      case AppLanguage.en:
        return 'Inject and trigger';
    }
  }

  static String get sectionCveSelect {
    switch (_lang) {
      case AppLanguage.zh:
        return 'CVE 选择';
      case AppLanguage.ja:
        return 'CVE 選択';
      case AppLanguage.en:
        return 'CVE selection';
    }
  }

  static String get fieldUsername {
    switch (_lang) {
      case AppLanguage.zh:
        return '用户名';
      case AppLanguage.ja:
        return 'ユーザー名';
      case AppLanguage.en:
        return 'Username';
    }
  }

  static String get fieldPassword {
    switch (_lang) {
      case AppLanguage.zh:
        return '密码';
      case AppLanguage.ja:
        return 'パスワード';
      case AppLanguage.en:
        return 'Password';
    }
  }

  static String get nacosStep1 {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Step 1 — 创建/使用管理员账号';
      case AppLanguage.ja:
        return 'Step 1 — 管理者アカウントを作成/使用';
      case AppLanguage.en:
        return 'Step 1 — Create / use admin account';
    }
  }

  static String get nacosStep3 {
    switch (_lang) {
      case AppLanguage.zh:
        return 'Step 3 — Cron 反弹 Shell';
      case AppLanguage.ja:
        return 'Step 3 — Cron リバースシェル';
      case AppLanguage.en:
        return 'Step 3 — Cron reverse shell';
    }
  }

  static String get nacosListUsers {
    switch (_lang) {
      case AppLanguage.zh:
        return '枚举用户';
      case AppLanguage.ja:
        return 'ユーザーを列挙';
      case AppLanguage.en:
        return 'Enumerate users';
    }
  }

  static String get nacosCreateUser {
    switch (_lang) {
      case AppLanguage.zh:
        return '创建用户';
      case AppLanguage.ja:
        return 'ユーザーを作成';
      case AppLanguage.en:
        return 'Create user';
    }
  }

  static String get nacosLoginForToken {
    switch (_lang) {
      case AppLanguage.zh:
        return '登录获取 Token';
      case AppLanguage.ja:
        return 'ログインして Token を取得';
      case AppLanguage.en:
        return 'Login to get Token';
    }
  }

  static String get nacosTokenHint {
    switch (_lang) {
      case AppLanguage.zh:
        return '登录后自动填入';
      case AppLanguage.ja:
        return 'ログイン後に自動入力';
      case AppLanguage.en:
        return 'Auto-filled after login';
    }
  }

  static String get nacosDerbySql {
    switch (_lang) {
      case AppLanguage.zh:
        return '任意 Derby SQL';
      case AppLanguage.ja:
        return '任意 Derby SQL';
      case AppLanguage.en:
        return 'Arbitrary Derby SQL';
    }
  }

  static String get nacosExecSql {
    switch (_lang) {
      case AppLanguage.zh:
        return '执行 SQL';
      case AppLanguage.ja:
        return 'SQL を実行';
      case AppLanguage.en:
        return 'Execute SQL';
    }
  }

  static String get flaskSstiInjectParam {
    switch (_lang) {
      case AppLanguage.zh:
        return '注入参数名 (GET)';
      case AppLanguage.ja:
        return '注入パラメーター名 (GET)';
      case AppLanguage.en:
        return 'Injection parameter (GET)';
    }
  }

  static String get sectionRequestHeaders {
    switch (_lang) {
      case AppLanguage.zh:
        return '请求头';
      case AppLanguage.ja:
        return 'リクエストヘッダー';
      case AppLanguage.en:
        return 'Request headers';
    }
  }

  static String get fieldCustomHeaders {
    switch (_lang) {
      case AppLanguage.zh:
        return '自定义 Headers';
      case AppLanguage.ja:
        return 'カスタム Headers';
      case AppLanguage.en:
        return 'Custom headers';
    }
  }

  static String get sectionRequestBody {
    switch (_lang) {
      case AppLanguage.zh:
        return '请求体';
      case AppLanguage.ja:
        return 'リクエストボディ';
      case AppLanguage.en:
        return 'Request body';
    }
  }

  static String get flaskSstiBodyInject {
    switch (_lang) {
      case AppLanguage.zh:
        return '请求体（{{INJECT}} 为注入点）';
      case AppLanguage.ja:
        return 'リクエストボディ（{{INJECT}} が注入点）';
      case AppLanguage.en:
        return 'Request body ({{INJECT}} is the injection point)';
    }
  }

  static String get flaskSstiBodyPostOnly {
    switch (_lang) {
      case AppLanguage.zh:
        return '请求体（POST 模式生效）';
      case AppLanguage.ja:
        return 'リクエストボディ（POST モードのみ有効）';
      case AppLanguage.en:
        return 'Request body (POST mode only)';
    }
  }

  static String get flaskSstiBtnDetect {
    switch (_lang) {
      case AppLanguage.zh:
        return '检测 SSTI';
      case AppLanguage.ja:
        return 'SSTI を検出';
      case AppLanguage.en:
        return 'Detect SSTI';
    }
  }

  static String get phpFieldFilePath {
    switch (_lang) {
      case AppLanguage.zh:
        return 'PHP 文件路径';
      case AppLanguage.ja:
        return 'PHP ファイルパス';
      case AppLanguage.en:
        return 'PHP file path';
    }
  }

  static String get struts2FieldPath {
    switch (_lang) {
      case AppLanguage.zh:
        return '路径 (005/007/052/053/057)';
      case AppLanguage.ja:
        return 'パス (005/007/052/053/057)';
      case AppLanguage.en:
        return 'Path (005/007/052/053/057)';
    }
  }

  static String get supervisorBtnDetect {
    switch (_lang) {
      case AppLanguage.zh:
        return '检测 XML-RPC';
      case AppLanguage.ja:
        return 'XML-RPC を検出';
      case AppLanguage.en:
        return 'Detect XML-RPC';
    }
  }

  static String get xxljobBtnDetect {
    switch (_lang) {
      case AppLanguage.zh:
        return '检测未授权';
      case AppLanguage.ja:
        return '未認証アクセスを検出';
      case AppLanguage.en:
        return 'Detect unauthorized access';
    }
  }

  static String get ofbizBtnDetect51467 {
    switch (_lang) {
      case AppLanguage.zh:
        return '检测 CVE-2023-51467 (OFBiz 18.12.10)';
      case AppLanguage.ja:
        return 'CVE-2023-51467 を検出 (OFBiz 18.12.10)';
      case AppLanguage.en:
        return 'Detect CVE-2023-51467 (OFBiz 18.12.10)';
    }
  }

  static String get ofbizBtnDetect38856 {
    switch (_lang) {
      case AppLanguage.zh:
        return '检测 CVE-2024-38856 (OFBiz 18.12.11)';
      case AppLanguage.ja:
        return 'CVE-2024-38856 を検出 (OFBiz 18.12.11)';
      case AppLanguage.en:
        return 'Detect CVE-2024-38856 (OFBiz 18.12.11)';
    }
  }

  static String get tomcatFieldPath {
    switch (_lang) {
      case AppLanguage.zh:
        return '上传路径';
      case AppLanguage.ja:
        return 'アップロードパス';
      case AppLanguage.en:
        return 'Upload path';
    }
  }

  // ── EXP 入口卡片（exp_registry / exp_content）───────────────────────────────
  // 标题保持 CVE 编号原文不翻译。Subtitle/version/tag 走 i18n。

  static String get expTagGeneric {
    switch (_lang) {
      case AppLanguage.zh: return '通用';
      case AppLanguage.ja: return '汎用';
      case AppLanguage.en: return 'Generic';
    }
  }

  static String get expTagZentao {
    switch (_lang) {
      case AppLanguage.zh: return '禅道';
      case AppLanguage.ja: return 'Zentao';
      case AppLanguage.en: return 'Zentao';
    }
  }

  // Shiro
  static String get expSubtitleShiro {
    switch (_lang) {
      case AppLanguage.zh: return 'rememberMe Key 爆破 / Payload 注入';
      case AppLanguage.ja: return 'rememberMe Key 爆破 / Payload 注入';
      case AppLanguage.en: return 'rememberMe key bruteforce / Payload injection';
    }
  }

  static String get expVersionShiro {
    switch (_lang) {
      case AppLanguage.zh: return 'Shiro: <=1.2.4 | 条件: rememberMe 默认密钥场景';
      case AppLanguage.ja: return 'Shiro: <=1.2.4 | 条件: rememberMe デフォルトキーのケース';
      case AppLanguage.en: return 'Shiro: <=1.2.4 | Condition: default rememberMe key';
    }
  }

  // ThinkPHP
  static String get expSubtitleThinkphp {
    switch (_lang) {
      case AppLanguage.zh: return '3.x/5.x/6.x 漏洞检测、RCE、GetShell';
      case AppLanguage.ja: return '3.x/5.x/6.x の脆弱性検出・RCE・GetShell';
      case AppLanguage.en: return '3.x/5.x/6.x vuln detection, RCE, GetShell';
    }
  }

  static String get expVersionThinkphp {
    switch (_lang) {
      case AppLanguage.zh: return 'ThinkPHP: 2.x / <=5.0.23 / 5.0.22/5.1.29 | 条件: 路由/调用链可达';
      case AppLanguage.ja: return 'ThinkPHP: 2.x / <=5.0.23 / 5.0.22/5.1.29 | 条件: ルート/呼び出し連鎖到達可能';
      case AppLanguage.en: return 'ThinkPHP: 2.x / <=5.0.23 / 5.0.22/5.1.29 | Condition: route/gadget chain reachable';
    }
  }

  // Zentao
  static String get expSubtitleZentao {
    switch (_lang) {
      case AppLanguage.zh: return '绕过登录 · Repo 配置写入冰蝎 WebShell';
      case AppLanguage.ja: return 'ログインバイパス · Repo 設定で Behinder WebShell を書き込み';
      case AppLanguage.en: return 'Login bypass · Write Behinder WebShell via Repo config';
    }
  }

  static String get expVersionZentao {
    switch (_lang) {
      case AppLanguage.zh: return 'Zentao: 请按官方公告版本区间核对 | 条件: 漏洞链路可达';
      case AppLanguage.ja: return 'Zentao: 公式アドバイザリのバージョンを参照 | 条件: 攻撃連鎖到達可能';
      case AppLanguage.en: return 'Zentao: see official advisory range | Condition: exploit path reachable';
    }
  }

  // Struts2
  static String get expSubtitleStruts2 {
    switch (_lang) {
      case AppLanguage.zh: return 'OGNL 表达式注入 RCE 系列';
      case AppLanguage.ja: return 'OGNL 式インジェクション RCE シリーズ';
      case AppLanguage.en: return 'OGNL expression injection RCE series';
    }
  }

  static String get expVersionStruts2 {
    switch (_lang) {
      case AppLanguage.zh: return 'Struts2: S2-032=2.3.20-2.3.28(除2.3.20.3/2.3.24.3); S2-045/053/057/059=2.0.0-2.5.20 | 条件: 对应 OGNL 触发面存在';
      case AppLanguage.ja: return 'Struts2: S2-032=2.3.20-2.3.28(2.3.20.3/2.3.24.3 除く); S2-045/053/057/059=2.0.0-2.5.20 | 条件: 対応する OGNL トリガー面が存在';
      case AppLanguage.en: return 'Struts2: S2-032=2.3.20-2.3.28(except 2.3.20.3/2.3.24.3); S2-045/053/057/059=2.0.0-2.5.20 | Condition: matching OGNL trigger surface present';
    }
  }

  // Spring
  static String get expSubtitleSpring {
    switch (_lang) {
      case AppLanguage.zh: return 'Spring4Shell / Cloud Function / Data SpEL 注入系列';
      case AppLanguage.ja: return 'Spring4Shell / Cloud Function / Data SpEL インジェクションシリーズ';
      case AppLanguage.en: return 'Spring4Shell / Cloud Function / Data SpEL injection series';
    }
  }

  static String get expVersionSpring {
    switch (_lang) {
      case AppLanguage.zh: return 'Spring: 22965=5.3.17; 22963=SCF 3.2.2; 1273=Data Commons<=2.0.5; 8046=Data REST 2.6.6 | 条件: 各 CVE 对应部署方式满足';
      case AppLanguage.ja: return 'Spring: 22965=5.3.17; 22963=SCF 3.2.2; 1273=Data Commons<=2.0.5; 8046=Data REST 2.6.6 | 条件: 各 CVE のデプロイ条件を満たす';
      case AppLanguage.en: return 'Spring: 22965=5.3.17; 22963=SCF 3.2.2; 1273=Data Commons<=2.0.5; 8046=Data REST 2.6.6 | Condition: deployment matches each CVE';
    }
  }

  // HTTPd
  static String get expSubtitleHttpd {
    switch (_lang) {
      case AppLanguage.zh: return '路径规范化缺陷 — 路径穿越文件读取 + CGI RCE';
      case AppLanguage.ja: return 'パス正規化の不具合 — パストラバーサル + CGI RCE';
      case AppLanguage.en: return 'Path normalization flaw — path traversal + CGI RCE';
    }
  }

  static String get expVersionHttpd {
    switch (_lang) {
      case AppLanguage.zh: return 'HTTPd: =2.4.49 | 条件: 目录访问配置允许穿越';
      case AppLanguage.ja: return 'HTTPd: =2.4.49 | 条件: ディレクトリ設定がトラバーサルを許可';
      case AppLanguage.en: return 'HTTPd: =2.4.49 | Condition: directory config allows traversal';
    }
  }

  // Druid
  static String get expSubtitleDruid {
    switch (_lang) {
      case AppLanguage.zh: return '嵌入式 JavaScript 代码注入 RCE (≤ 0.20.0)';
      case AppLanguage.ja: return '組み込み JavaScript コード注入 RCE (≤ 0.20.0)';
      case AppLanguage.en: return 'Embedded JavaScript code injection RCE (≤ 0.20.0)';
    }
  }

  static String get expVersionDruid {
    switch (_lang) {
      case AppLanguage.zh: return 'Druid: <=0.20.0 | 条件: sampler/indexer 接口可访问';
      case AppLanguage.ja: return 'Druid: <=0.20.0 | 条件: sampler/indexer エンドポイントへアクセス可能';
      case AppLanguage.en: return 'Druid: <=0.20.0 | Condition: sampler/indexer endpoints reachable';
    }
  }

  // OFBiz
  static String get expSubtitleOfbiz {
    switch (_lang) {
      case AppLanguage.zh: return 'Groovy 代码注入无需认证 RCE';
      case AppLanguage.ja: return '認証不要の Groovy コード注入 RCE';
      case AppLanguage.en: return 'Unauthenticated Groovy code injection RCE';
    }
  }

  static String get expVersionOfbiz {
    switch (_lang) {
      case AppLanguage.zh: return 'OFBiz: 18.12.10 / 18.12.11 | 条件: ProgramExport 路径可达';
      case AppLanguage.ja: return 'OFBiz: 18.12.10 / 18.12.11 | 条件: ProgramExport パスが到達可能';
      case AppLanguage.en: return 'OFBiz: 18.12.10 / 18.12.11 | Condition: ProgramExport path reachable';
    }
  }

  // Solr
  static String get expSubtitleSolr {
    switch (_lang) {
      case AppLanguage.zh: return 'RunExecutableListener 任意命令执行 (< 7.1.0)';
      case AppLanguage.ja: return 'RunExecutableListener 任意コマンド実行 (< 7.1.0)';
      case AppLanguage.en: return 'RunExecutableListener arbitrary command execution (< 7.1.0)';
    }
  }

  static String get expVersionSolr {
    switch (_lang) {
      case AppLanguage.zh: return 'Solr: <7.1.0 | 条件: config API 可写 listener';
      case AppLanguage.ja: return 'Solr: <7.1.0 | 条件: config API でリスナー書き込み可能';
      case AppLanguage.en: return 'Solr: <7.1.0 | Condition: config API can write listener';
    }
  }

  // Drupal
  static String get expSubtitleDrupal {
    switch (_lang) {
      case AppLanguage.zh: return 'Form API #post_render 回调 PHP 代码执行';
      case AppLanguage.ja: return 'Form API #post_render コールバックによる PHP 実行';
      case AppLanguage.en: return 'Form API #post_render callback PHP execution';
    }
  }

  static String get expVersionDrupal {
    switch (_lang) {
      case AppLanguage.zh: return 'Drupal: <7.58; 8.x<8.3.9/<8.4.6/<8.5.1 | 条件: Form API 路径可达';
      case AppLanguage.ja: return 'Drupal: <7.58; 8.x<8.3.9/<8.4.6/<8.5.1 | 条件: Form API パス到達可能';
      case AppLanguage.en: return 'Drupal: <7.58; 8.x<8.3.9/<8.4.6/<8.5.1 | Condition: Form API path reachable';
    }
  }

  // Elasticsearch
  static String get expSubtitleElastic {
    switch (_lang) {
      case AppLanguage.zh: return 'Groovy 脚本沙箱逃逸 RCE (< 1.3.8 / < 1.4.3)';
      case AppLanguage.ja: return 'Groovy スクリプトサンドボックス回避 RCE (< 1.3.8 / < 1.4.3)';
      case AppLanguage.en: return 'Groovy script sandbox escape RCE (< 1.3.8 / < 1.4.3)';
    }
  }

  static String get expVersionElastic {
    switch (_lang) {
      case AppLanguage.zh: return 'Elasticsearch: <1.3.8 或 <1.4.3 | 条件: 动态脚本执行可用';
      case AppLanguage.ja: return 'Elasticsearch: <1.3.8 または <1.4.3 | 条件: 動的スクリプト実行が有効';
      case AppLanguage.en: return 'Elasticsearch: <1.3.8 or <1.4.3 | Condition: dynamic scripting enabled';
    }
  }

  // Flask SSTI
  static String get expSubtitleFlaskSsti {
    switch (_lang) {
      case AppLanguage.zh: return '服务端模板注入执行任意 Python 代码';
      case AppLanguage.ja: return 'サーバーサイドテンプレートインジェクションで任意 Python 実行';
      case AppLanguage.en: return 'Server-side template injection executes arbitrary Python code';
    }
  }

  static String get expVersionFlaskSsti {
    switch (_lang) {
      case AppLanguage.zh: return 'Flask/Jinja2: 取决于组件版本 | 条件: 存在 SSTI 模板注入点';
      case AppLanguage.ja: return 'Flask/Jinja2: コンポーネント次第 | 条件: SSTI 注入点が存在';
      case AppLanguage.en: return 'Flask/Jinja2: depends on components | Condition: SSTI injection point exists';
    }
  }

  // PHP backdoor / CGI
  static String get expTitlePhp {
    switch (_lang) {
      case AppLanguage.zh: return 'PHP 8.1.0-dev 后门 / CVE-2012-1823 PHP-CGI';
      case AppLanguage.ja: return 'PHP 8.1.0-dev バックドア / CVE-2012-1823 PHP-CGI';
      case AppLanguage.en: return 'PHP 8.1.0-dev backdoor / CVE-2012-1823 PHP-CGI';
    }
  }

  static String get expSubtitlePhp {
    switch (_lang) {
      case AppLanguage.zh: return 'User-Agentt 后门 + CGI 参数注入 RCE';
      case AppLanguage.ja: return 'User-Agentt バックドア + CGI 引数インジェクション RCE';
      case AppLanguage.en: return 'User-Agentt backdoor + CGI argument injection RCE';
    }
  }

  static String get expVersionPhp {
    switch (_lang) {
      case AppLanguage.zh: return 'PHP: 8.1.0-dev 或 CGI<5.3.12/<5.4.2 | 条件: 后门头/CGI 参数可达';
      case AppLanguage.ja: return 'PHP: 8.1.0-dev または CGI<5.3.12/<5.4.2 | 条件: バックドアヘッダ/CGI 引数到達可能';
      case AppLanguage.en: return 'PHP: 8.1.0-dev or CGI<5.3.12/<5.4.2 | Condition: backdoor header / CGI args reachable';
    }
  }

  // Tomcat
  static String get expSubtitleTomcat {
    switch (_lang) {
      case AppLanguage.zh: return 'PUT 方法开启时上传 JSP Webshell RCE';
      case AppLanguage.ja: return 'PUT メソッド有効時に JSP Webshell をアップロードして RCE';
      case AppLanguage.en: return 'Upload JSP Webshell when PUT method is enabled';
    }
  }

  static String get expVersionTomcat {
    switch (_lang) {
      case AppLanguage.zh: return 'Tomcat: 8.5.19 | 条件: DefaultServlet readonly=false';
      case AppLanguage.ja: return 'Tomcat: 8.5.19 | 条件: DefaultServlet readonly=false';
      case AppLanguage.en: return 'Tomcat: 8.5.19 | Condition: DefaultServlet readonly=false';
    }
  }

  // WebLogic
  static String get expSubtitleWeblogic {
    switch (_lang) {
      case AppLanguage.zh: return 'XMLDecoder 反序列化 + 控制台未授权 + WS 测试页文件上传 RCE';
      case AppLanguage.ja: return 'XMLDecoder デシリアライゼーション + コンソール未認証 + WS テストページファイルアップロード RCE';
      case AppLanguage.en: return 'XMLDecoder deserialization + console unauth + WS test page upload RCE';
    }
  }

  static String get expVersionWeblogic {
    switch (_lang) {
      case AppLanguage.zh: return 'WebLogic: 10271<10.3.6; 14882/14883=12.2.1.3(12.2.1+) | 条件: 控制台/组件路径可达';
      case AppLanguage.ja: return 'WebLogic: 10271<10.3.6; 14882/14883=12.2.1.3(12.2.1+) | 条件: コンソール/コンポーネント到達可能';
      case AppLanguage.en: return 'WebLogic: 10271<10.3.6; 14882/14883=12.2.1.3(12.2.1+) | Condition: console/component reachable';
    }
  }

  // XXL-JOB
  static String get expTitleXxljob {
    switch (_lang) {
      case AppLanguage.zh: return 'XXL-JOB 未授权访问执行器 RCE';
      case AppLanguage.ja: return 'XXL-JOB 未認証 Executor アクセス RCE';
      case AppLanguage.en: return 'XXL-JOB unauthenticated executor RCE';
    }
  }

  static String get expSubtitleXxljob {
    switch (_lang) {
      case AppLanguage.zh: return 'GLUE_SHELL 类型提交任意 Shell 命令 (2.2.0)';
      case AppLanguage.ja: return 'GLUE_SHELL タイプで任意 Shell コマンド送信 (2.2.0)';
      case AppLanguage.en: return 'Submit arbitrary shell commands via GLUE_SHELL type (2.2.0)';
    }
  }

  static String get expVersionXxljob {
    switch (_lang) {
      case AppLanguage.zh: return 'XXL-JOB: 按官方公告核对 | 条件: 未授权访问执行器接口';
      case AppLanguage.ja: return 'XXL-JOB: 公式アドバイザリで確認 | 条件: Executor 未認証アクセス';
      case AppLanguage.en: return 'XXL-JOB: cross-check official advisory | Condition: unauthenticated executor';
    }
  }

  // Nacos
  static String get expSubtitleNacos {
    switch (_lang) {
      case AppLanguage.zh: return 'User-Agent 认证绕过，枚举/创建用户 (< 1.4.1)';
      case AppLanguage.ja: return 'User-Agent 認証バイパスでユーザー列挙/作成 (< 1.4.1)';
      case AppLanguage.en: return 'User-Agent auth bypass, enumerate/create users (< 1.4.1)';
    }
  }

  static String get expVersionNacos {
    switch (_lang) {
      case AppLanguage.zh: return 'Nacos: <1.4.1 | 条件: User-Agent 绕过链可达';
      case AppLanguage.ja: return 'Nacos: <1.4.1 | 条件: User-Agent バイパス連鎖到達可能';
      case AppLanguage.en: return 'Nacos: <1.4.1 | Condition: User-Agent bypass chain reachable';
    }
  }

  // (Supervisor/Shellshock/SaltStack EXP removed)

  // --- suo5 proxy management ---

  static String get menuEnterSuo5 {
    switch (_lang) {
      case AppLanguage.zh:
        return '进入 suo5 代理';
      case AppLanguage.ja:
        return 'suo5 プロキシへ';
      case AppLanguage.en:
        return 'Open suo5 Proxy';
    }
  }

  static String get titleSuo5Manager {
    switch (_lang) {
      case AppLanguage.zh:
        return 'suo5 代理';
      case AppLanguage.ja:
        return 'suo5 プロキシ';
      case AppLanguage.en:
        return 'suo5 Proxy';
    }
  }

  static String suo5ManagementTitle(String projectName) {
    switch (_lang) {
      case AppLanguage.zh:
        return 'suo5 · $projectName';
      case AppLanguage.ja:
        return 'suo5 · $projectName';
      case AppLanguage.en:
        return 'suo5 · $projectName';
    }
  }

  static String get actionAddSuo5 {
    switch (_lang) {
      case AppLanguage.zh:
        return '添加 suo5 代理';
      case AppLanguage.ja:
        return 'suo5 プロキシを追加';
      case AppLanguage.en:
        return 'Add suo5 Proxy';
    }
  }

  static String get suo5NewConfigTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return '新建 suo5 代理';
      case AppLanguage.ja:
        return '新規 suo5 プロキシ';
      case AppLanguage.en:
        return 'New suo5 Proxy';
    }
  }

  static String get suo5EditConfigTitle {
    switch (_lang) {
      case AppLanguage.zh:
        return '编辑 suo5 代理';
      case AppLanguage.ja:
        return 'suo5 プロキシを編集';
      case AppLanguage.en:
        return 'Edit suo5 Proxy';
    }
  }

  static String get suo5ConfigName {
    switch (_lang) {
      case AppLanguage.zh:
        return '配置名称';
      case AppLanguage.ja:
        return '設定名';
      case AppLanguage.en:
        return 'Profile name';
    }
  }

  static String get suo5ConfigNameHint {
    switch (_lang) {
      case AppLanguage.zh:
        return '便于识别的名称';
      case AppLanguage.ja:
        return '識別しやすい名前';
      case AppLanguage.en:
        return 'A friendly name';
    }
  }

  static String get suo5TargetUrl {
    switch (_lang) {
      case AppLanguage.zh:
        return 'suo5 URL';
      case AppLanguage.ja:
        return 'suo5 URL';
      case AppLanguage.en:
        return 'suo5 URL';
    }
  }

  static String get suo5TargetUrlHint {
    switch (_lang) {
      case AppLanguage.zh:
        return 'https://target/path/suo5.php';
      case AppLanguage.ja:
        return 'https://target/path/suo5.php';
      case AppLanguage.en:
        return 'https://target/path/suo5.php';
    }
  }

  static String get suo5ListenHost {
    switch (_lang) {
      case AppLanguage.zh:
        return '监听地址';
      case AppLanguage.ja:
        return 'リッスンアドレス';
      case AppLanguage.en:
        return 'Listen host';
    }
  }

  static String get suo5ListenPort {
    switch (_lang) {
      case AppLanguage.zh:
        return '监听端口';
      case AppLanguage.ja:
        return 'リッスンポート';
      case AppLanguage.en:
        return 'Listen port';
    }
  }

  static String suo5Count(int n) {
    switch (_lang) {
      case AppLanguage.zh:
        return '共 $n 条';
      case AppLanguage.ja:
        return '計 $n 件';
      case AppLanguage.en:
        return '$n total';
    }
  }

  static String suo5EmptyHint(String addLabel) {
    switch (_lang) {
      case AppLanguage.zh:
        return '暂无 suo5 代理，点击「$addLabel」开始';
      case AppLanguage.ja:
        return 'suo5 プロキシがありません。「$addLabel」をクリックして開始';
      case AppLanguage.en:
        return 'No suo5 proxy yet. Click "$addLabel" to get started';
    }
  }

  static String confirmDeleteSuo5(String name) {
    switch (_lang) {
      case AppLanguage.zh:
        return '确定要删除「$name」吗？此操作不可恢复。';
      case AppLanguage.ja:
        return '「$name」を削除してもよろしいですか？この操作は元に戻せません。';
      case AppLanguage.en:
        return 'Delete "$name"? This action cannot be undone.';
    }
  }

  static String get suo5StatusRunning {
    switch (_lang) {
      case AppLanguage.zh:
        return '运行中';
      case AppLanguage.ja:
        return '実行中';
      case AppLanguage.en:
        return 'Running';
    }
  }

  static String get suo5StatusConnecting {
    switch (_lang) {
      case AppLanguage.zh:
        return '连接中';
      case AppLanguage.ja:
        return '接続中';
      case AppLanguage.en:
        return 'Connecting';
    }
  }

  static String get suo5StatusError {
    switch (_lang) {
      case AppLanguage.zh:
        return '错误';
      case AppLanguage.ja:
        return 'エラー';
      case AppLanguage.en:
        return 'Error';
    }
  }

  static String get suo5StatusIdle {
    switch (_lang) {
      case AppLanguage.zh:
        return '空闲';
      case AppLanguage.ja:
        return '待機中';
      case AppLanguage.en:
        return 'Idle';
    }
  }

  static String get suo5InvalidUrl {
    switch (_lang) {
      case AppLanguage.zh:
        return 'URL 必须是 http/https';
      case AppLanguage.ja:
        return 'URL は http/https である必要があります';
      case AppLanguage.en:
        return 'URL must be http/https';
    }
  }

  static String get suo5InvalidPort {
    switch (_lang) {
      case AppLanguage.zh:
        return '监听端口不合法';
      case AppLanguage.ja:
        return 'リッスンポートが無効です';
      case AppLanguage.en:
        return 'Listen port is invalid';
    }
  }

  static String get suo5MissingUrl {
    switch (_lang) {
      case AppLanguage.zh:
        return '请填写 suo5 URL';
      case AppLanguage.ja:
        return 'suo5 URL を入力してください';
      case AppLanguage.en:
        return 'Please enter the suo5 URL';
    }
  }

  static String get suo5RunningNoEdit {
    switch (_lang) {
      case AppLanguage.zh:
        return '运行中不可编辑';
      case AppLanguage.ja:
        return '実行中は編集できません';
      case AppLanguage.en:
        return 'Cannot edit while running';
    }
  }

  static String get suo5StatActiveConn {
    switch (_lang) {
      case AppLanguage.zh:
        return '连接数';
      case AppLanguage.ja:
        return '接続数';
      case AppLanguage.en:
        return 'Conns';
    }
  }

  static String get suo5StatUpload {
    switch (_lang) {
      case AppLanguage.zh:
        return '上传';
      case AppLanguage.ja:
        return 'アップロード';
      case AppLanguage.en:
        return 'Upload';
    }
  }

  static String get suo5StatDownload {
    switch (_lang) {
      case AppLanguage.zh:
        return '下载';
      case AppLanguage.ja:
        return 'ダウンロード';
      case AppLanguage.en:
        return 'Download';
    }
  }

  static String get suo5RunLog {
    switch (_lang) {
      case AppLanguage.zh:
        return '运行日志';
      case AppLanguage.ja:
        return '実行ログ';
      case AppLanguage.en:
        return 'Run log';
    }
  }

  static String get suo5NoLogs {
    switch (_lang) {
      case AppLanguage.zh:
        return '> 尚无日志';
      case AppLanguage.ja:
        return '> ログなし';
      case AppLanguage.en:
        return '> No logs yet';
    }
  }

  static String get suo5LogCopiedSnack {
    switch (_lang) {
      case AppLanguage.zh:
        return '日志已复制';
      case AppLanguage.ja:
        return 'ログをコピーしました';
      case AppLanguage.en:
        return 'Logs copied';
    }
  }

  static String get suo5HandshakeOk {
    switch (_lang) {
      case AppLanguage.zh:
        return '握手成功';
      case AppLanguage.ja:
        return 'ハンドシェイク成功';
      case AppLanguage.en:
        return 'Handshake OK';
    }
  }

  static String suo5HandshakeFailed(Object e) {
    switch (_lang) {
      case AppLanguage.zh:
        return '握手失败: $e';
      case AppLanguage.ja:
        return 'ハンドシェイク失敗: $e';
      case AppLanguage.en:
        return 'Handshake failed: $e';
    }
  }

  static String get suo5BtnProbe {
    switch (_lang) {
      case AppLanguage.zh:
        return '测试握手';
      case AppLanguage.ja:
        return 'ハンドシェイク確認';
      case AppLanguage.en:
        return 'Probe';
    }
  }

  static String get suo5MappingLabel {
    switch (_lang) {
      case AppLanguage.zh:
        return '本地监听';
      case AppLanguage.ja:
        return 'ローカルリッスン';
      case AppLanguage.en:
        return 'Local listen';
    }
  }

  static String suo5ActiveBanner(String name, String statusLabel) {
    switch (_lang) {
      case AppLanguage.zh:
        return '$statusLabel · $name';
      case AppLanguage.ja:
        return '$statusLabel · $name';
      case AppLanguage.en:
        return '$statusLabel · $name';
    }
  }

  /// 顶部头条："运行中 X / Y" 形式的汇总
  static String suo5HeaderRunningSummary(int running, int total) {
    switch (_lang) {
      case AppLanguage.zh:
        return '运行中 $running / $total';
      case AppLanguage.ja:
        return '実行中 $running / $total';
      case AppLanguage.en:
        return 'Running $running / $total';
    }
  }

}
