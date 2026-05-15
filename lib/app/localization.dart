import 'package:flutter/foundation.dart';

import '../connectors/connector_factory.dart';
import 'localization_data.dart';

/// Supported app languages
enum AppLanguage { zh, ja, en }

/// Global language controller
class AppLanguageController {
  static final ValueNotifier<AppLanguage> notifier =
      ValueNotifier<AppLanguage>(AppLanguage.zh);

  static AppLanguage get current => notifier.value;

  static void setLanguage(AppLanguage language) {
    if (language == notifier.value) return;
    notifier.value = language;
  }
}

/// Centralised copy management. Data lives in [LocalizationData.strings].
class S {
  static AppLanguage get _lang => AppLanguageController.current;

  static String _t(String key) =>
      LocalizationData.strings[key]?[_lang.name] ?? key;

  static String _tp(String key, Map<String, Object> args) {
    var s = _t(key);
    args.forEach((k, v) => s = s.replaceAll('{$k}', v.toString()));
    return s;
  }

  // ── Static constant ────────────────────────────────────────────────────────
  static const String appName = 'Matrix';

  // ── Simple getters ─────────────────────────────────────────────────────────

  static String get configMenuTitle => _t('configMenuTitle');
  static String get loading => _t('loading');
  static String get snackCopied => _t('snackCopied');
  static String get noOutput => _t('noOutput');
  static String get logErrorTag => _t('logErrorTag');
  static String get languageChinese => _t('languageChinese');
  static String get languageJapanese => _t('languageJapanese');
  static String get languageEnglish => _t('languageEnglish');
  static String get menuProject => _t('menuProject');
  static String get menuWebshell => _t('menuWebshell');
  static String get menuExp => _t('menuExp');
  static String get menuPayload => _t('menuPayload');
  static String get menuTerminal => _t('menuTerminal');
  static String get menuFrp => _t('menuFrp');
  static String get menuSuo5 => _t('menuSuo5');
  static String get sidebarCollapse => _t('sidebarCollapse');
  static String get sidebarExpandTooltip => _t('sidebarExpandTooltip');
  static String get workspaceWelcomeTitle => _t('workspaceWelcomeTitle');
  static String get workspaceQuickActions => _t('workspaceQuickActions');
  static String get quickActionNew => _t('quickActionNew');
  static String get workspaceRecentActivities => _t('workspaceRecentActivities');
  static String get actionNewProject => _t('actionNewProject');
  static String get actionAddWebshell => _t('actionAddWebshell');
  static String get actionGoCreateProject => _t('actionGoCreateProject');
  static String get actionRefresh => _t('actionRefresh');
  static String get actionListenConfig => _t('actionListenConfig');
  static String get actionCopy => _t('actionCopy');
  static String get actionCopyBase64 => _t('actionCopyBase64');
  static String get actionDownload => _t('actionDownload');
  static String get quickActionUpload => _t('quickActionUpload');
  static String get quickActionOpen => _t('quickActionOpen');
  static String get tabFileManager => _t('tabFileManager');
  static String get tabTerminal => _t('tabTerminal');
  static String get tabSysInfo => _t('tabSysInfo');
  static String get sectionPrivEsc => _t('sectionPrivEsc');
  static String get btnCancel => _t('btnCancel');
  static String get btnConfirm => _t('btnConfirm');
  static String get btnSave => _t('btnSave');
  static String get btnDelete => _t('btnDelete');
  static String get btnCreate => _t('btnCreate');
  static String get btnClose => _t('btnClose');
  static String get btnAdd => _t('btnAdd');
  static String get btnRetry => _t('btnRetry');
  static String get btnClear => _t('btnClear');
  static String get btnExecute => _t('btnExecute');
  static String get btnAutoDetect => _t('btnAutoDetect');
  static String get btnSwitchProject => _t('btnSwitchProject');
  static String get btnStartListen => _t('btnStartListen');
  static String get btnStopListen => _t('btnStopListen');
  static String get btnPortOccupied => _t('btnPortOccupied');
  static String get btnCheckAll => _t('btnCheckAll');
  static String get tooltipEdit => _t('tooltipEdit');
  static String get tooltipDelete => _t('tooltipDelete');
  static String get tooltipBack => _t('tooltipBack');
  static String get tooltipView => _t('tooltipView');
  static String get tooltipCopyContent => _t('tooltipCopyContent');
  static String get tooltipClearTerminal => _t('tooltipClearTerminal');
  static String get tooltipFullTerminal => _t('tooltipFullTerminal');
  static String get tooltipParentDir => _t('tooltipParentDir');
  static String get tooltipUploadFile => _t('tooltipUploadFile');
  static String get tooltipDownload => _t('tooltipDownload');
  static String get tooltipClose => _t('tooltipClose');
  static String get selectDownloadDir => _t('selectDownloadDir');
  static String get snackWriteNotSupported => _t('snackWriteNotSupported');
  static String get tooltipSwitchToSeparate => _t('tooltipSwitchToSeparate');
  static String get tooltipSwitchToIntegrated => _t('tooltipSwitchToIntegrated');
  static String get titleDeletePayload => _t('titleDeletePayload');
  static String get payloadNoneFound => _t('payloadNoneFound');
  static String get payloadImportHint => _t('payloadImportHint');
  static String get payloadBuiltinTooltip => _t('payloadBuiltinTooltip');
  static String get payloadBuiltin => _t('payloadBuiltin');
  static String get binaryPreviewDisabled => _t('binaryPreviewDisabled');
  static String get snackBinaryCopyUnsupported => _t('snackBinaryCopyUnsupported');
  static String get snackCopiedBase64 => _t('snackCopiedBase64');
  static String get fieldProjectName => _t('fieldProjectName');
  static String get fieldDomainOrId => _t('fieldDomainOrId');
  static String get hintDomainOrId => _t('hintDomainOrId');
  static String get fieldDescription => _t('fieldDescription');
  static String get webModeWarning => _t('webModeWarning');
  static String get menuEnterWebshell => _t('menuEnterWebshell');
  static String get menuEnterExp => _t('menuEnterExp');
  static String get dialogChooseProjectEntryTitle => _t('dialogChooseProjectEntryTitle');
  static String get noProjects => _t('noProjects');
  static String get noProjectsHint => _t('noProjectsHint');
  static String get selectProject => _t('selectProject');
  static String get titleSelectProject => _t('titleSelectProject');
  static String get terminalTitle => _t('terminalTitle');
  static String get noActiveSessions => _t('noActiveSessions');
  static String get fieldLhost => _t('fieldLhost');
  static String get fieldLport => _t('fieldLport');
  static String get snackPortOccupied => _t('snackPortOccupied');
  static String get noSessionsHint => _t('noSessionsHint');
  static String get snackSessionDisconnected => _t('snackSessionDisconnected');
  static String get sessionDisconnected => _t('sessionDisconnected');
  static String get pingFailHint => _t('pingFailHint');
  static String get connectionFailed => _t('connectionFailed');
  static String get statusChecking => _t('statusChecking');
  static String get statusConnected => _t('statusConnected');
  static String get statusReconnect => _t('statusReconnect');
  static String get titleSelectTerminalMode => _t('titleSelectTerminalMode');
  static String get terminalModeScript => _t('terminalModeScript');
  static String get terminalModeScriptDesc => _t('terminalModeScriptDesc');
  static String get terminalModeBash => _t('terminalModeBash');
  static String get terminalModeBashDesc => _t('terminalModeBashDesc');
  static String get terminalModeSocat => _t('terminalModeSocat');
  static String get terminalModeSocatDesc => _t('terminalModeSocatDesc');
  static String get snackReverseShellSent => _t('snackReverseShellSent');
  static String get titleSocatCommand => _t('titleSocatCommand');
  static String get socatInstructions => _t('socatInstructions');
  static String get terminalEmptyHint => _t('terminalEmptyHint');
  static String get terminalKeyHint => _t('terminalKeyHint');
  static String get modeIntegrated => _t('modeIntegrated');
  static String get modeSeparate => _t('modeSeparate');
  static String get noCompletions => _t('noCompletions');
  static String get executing => _t('executing');
  static String get fieldWebshellUrl => _t('fieldWebshellUrl');
  static String get hintWebshellUrl => _t('hintWebshellUrl');
  static String get fieldWebshellName => _t('fieldWebshellName');
  static String get hintWebshellName => _t('hintWebshellName');
  static String get labelRequestMethod => _t('labelRequestMethod');
  static String get snackFillUrlAndPassword => _t('snackFillUrlAndPassword');
  static String get titleEditWebshell => _t('titleEditWebshell');
  static String get webshellPasswordLabel => _t('webshellPasswordLabel');
  static String get connectorMethodFixed => _t('connectorMethodFixed');
  static String get fieldConnectorType => _t('fieldConnectorType');
  static String get fieldPasswordKey => _t('fieldPasswordKey');
  static String get fieldParamName => _t('fieldParamName');
  static String get hintPasswordKey => _t('hintPasswordKey');
  static String get helperPasswordKey => _t('helperPasswordKey');
  static String get detectSuccess => _t('detectSuccess');
  static String get detectFailed => _t('detectFailed');
  static String get snackWriteUnsupported => _t('snackWriteUnsupported');
  static String get allFiles => _t('allFiles');
  static String get snackNoPayloads => _t('snackNoPayloads');
  static String get dirEmptyOrDenied => _t('dirEmptyOrDenied');
  static String get dirEmpty => _t('dirEmpty');
  static String get colName => _t('colName');
  static String get colSize => _t('colSize');
  static String get colPermissions => _t('colPermissions');
  static String get colModified => _t('colModified');
  static String get titleConfirmDelete => _t('titleConfirmDelete');
  static String get snackDeleteFailed => _t('snackDeleteFailed');
  static String get snackUploadCancelled => _t('snackUploadCancelled');
  static String get snackUploadFail => _t('snackUploadFail');
  static String get titleSelectPayload => _t('titleSelectPayload');
  static String get tooltipPayloadUploadToWebshellTmp => _t('tooltipPayloadUploadToWebshellTmp');
  static String get titleSelectWebshellForPayload => _t('titleSelectWebshellForPayload');
  static String get snackNoWebshellsAnyProject => _t('snackNoWebshellsAnyProject');
  static String get dialogUploadSuccessTitle => _t('dialogUploadSuccessTitle');
  static String get dialogUploadFailureTitle => _t('dialogUploadFailureTitle');
  static String get uploading => _t('uploading');
  static String get downloading => _t('downloading');
  static String get uploadingProgress => _t('uploadingProgress');
  static String get downloadingProgress => _t('downloadingProgress');
  static String get snackSaveSuccess => _t('snackSaveSuccess');
  static String get snackSaveFailure => _t('snackSaveFailure');
  static String get serverInfo => _t('serverInfo');
  static String get sysInfoFailed => _t('sysInfoFailed');
  static String get sysInfoFailedHint => _t('sysInfoFailedHint');
  static String get sysInfoFieldOs => _t('sysInfoFieldOs');
  static String get sysInfoFieldPhpVersion => _t('sysInfoFieldPhpVersion');
  static String get sysInfoFieldRunUser => _t('sysInfoFieldRunUser');
  static String get sysInfoFieldServerIp => _t('sysInfoFieldServerIp');
  static String get sysInfoFieldServerSoftware => _t('sysInfoFieldServerSoftware');
  static String get sysInfoFieldDocRoot => _t('sysInfoFieldDocRoot');
  static String get sysInfoFieldCurrentDir => _t('sysInfoFieldCurrentDir');
  static String get sysInfoFieldMemoryLimit => _t('sysInfoFieldMemoryLimit');
  static String get sysInfoFieldMaxExecutionTime => _t('sysInfoFieldMaxExecutionTime');
  static String get sysInfoFieldSafeMode => _t('sysInfoFieldSafeMode');
  static String get sysInfoFieldHost => _t('sysInfoFieldHost');
  static String get sysInfoFieldUserId => _t('sysInfoFieldUserId');
  static String get sysInfoFieldKernelVersion => _t('sysInfoFieldKernelVersion');
  static String get sysInfoFieldDotnetClr => _t('sysInfoFieldDotnetClr');
  static String get privEscTitle => _t('privEscTitle');
  static String get checkingAll => _t('checkingAll');
  static String get privEscSuggestions => _t('privEscSuggestions');
  static String get privEscGroupCurrentPriv => _t('privEscGroupCurrentPriv');
  static String get privEscGroupSysInfo => _t('privEscGroupSysInfo');
  static String get privEscGroupEscVectors => _t('privEscGroupEscVectors');
  static String get privEscGroupSensitiveInfo => _t('privEscGroupSensitiveInfo');
  static String get privEscItemUserGroup => _t('privEscItemUserGroup');
  static String get privEscItemUserGroupDesc => _t('privEscItemUserGroupDesc');
  static String get privEscItemSudo => _t('privEscItemSudo');
  static String get privEscItemSudoDesc => _t('privEscItemSudoDesc');
  static String get privEscItemEnv => _t('privEscItemEnv');
  static String get privEscItemEnvDesc => _t('privEscItemEnvDesc');
  static String get privEscItemKernel => _t('privEscItemKernel');
  static String get privEscItemKernelDesc => _t('privEscItemKernelDesc');
  static String get privEscItemDistro => _t('privEscItemDistro');
  static String get privEscItemDistroDesc => _t('privEscItemDistroDesc');
  static String get privEscItemLoggedUsers => _t('privEscItemLoggedUsers');
  static String get privEscItemLoggedUsersDesc => _t('privEscItemLoggedUsersDesc');
  static String get privEscItemRootProcs => _t('privEscItemRootProcs');
  static String get privEscItemRootProcsDesc => _t('privEscItemRootProcsDesc');
  static String get privEscItemSuid => _t('privEscItemSuid');
  static String get privEscItemSuidDesc => _t('privEscItemSuidDesc');
  static String get privEscItemSgid => _t('privEscItemSgid');
  static String get privEscItemSgidDesc => _t('privEscItemSgidDesc');
  static String get privEscItemCap => _t('privEscItemCap');
  static String get privEscItemCapDesc => _t('privEscItemCapDesc');
  static String get privEscItemCron => _t('privEscItemCron');
  static String get privEscItemCronDesc => _t('privEscItemCronDesc');
  static String get privEscItemCronWritable => _t('privEscItemCronWritable');
  static String get privEscItemCronWritableDesc => _t('privEscItemCronWritableDesc');
  static String get privEscItemWritableDirs => _t('privEscItemWritableDirs');
  static String get privEscItemWritableDirsDesc => _t('privEscItemWritableDirsDesc');
  static String get privEscItemPathHijack => _t('privEscItemPathHijack');
  static String get privEscItemPathHijackDesc => _t('privEscItemPathHijackDesc');
  static String get privEscItemLoginableAccounts => _t('privEscItemLoginableAccounts');
  static String get privEscItemLoginableAccountsDesc => _t('privEscItemLoginableAccountsDesc');
  static String get privEscItemShadow => _t('privEscItemShadow');
  static String get privEscItemShadowDesc => _t('privEscItemShadowDesc');
  static String get privEscItemHistory => _t('privEscItemHistory');
  static String get privEscItemHistoryDesc => _t('privEscItemHistoryDesc');
  static String get privEscItemSshKeys => _t('privEscItemSshKeys');
  static String get privEscItemSshKeysDesc => _t('privEscItemSshKeysDesc');
  static String get privEscItemConfigPasswords => _t('privEscItemConfigPasswords');
  static String get privEscItemConfigPasswordsDesc => _t('privEscItemConfigPasswordsDesc');
  static String get privEscSudoAllTitle => _t('privEscSudoAllTitle');
  static String get privEscSudoAllReason => _t('privEscSudoAllReason');
  static String get privEscSudoLimitedTitle => _t('privEscSudoLimitedTitle');
  static String get privEscSuidTitle => _t('privEscSuidTitle');
  static String get privEscSuidReason => _t('privEscSuidReason');
  static String get privEscKernelTitle => _t('privEscKernelTitle');
  static String get privEscShadowTitle => _t('privEscShadowTitle');
  static String get privEscCronTitle => _t('privEscCronTitle');
  static String get privEscCapTitle => _t('privEscCapTitle');
  static String get privEscCapReason => _t('privEscCapReason');
  static String get expWaiting => _t('expWaiting');
  static String get statusRunning => _t('statusRunning');
  static String get statusIdle => _t('statusIdle');
  static String get expManagementTitle => _t('expManagementTitle');
  static String get expManagementHint => _t('expManagementHint');
  static String get sectionTargetConfig => _t('sectionTargetConfig');
  static String get fieldTargetUrl => _t('fieldTargetUrl');
  static String get fieldTimeout => _t('fieldTimeout');
  static String get fieldCommand => _t('fieldCommand');
  static String get btnDetect => _t('btnDetect');
  static String get btnDetectVuln => _t('btnDetectVuln');
  static String get btnDetectAll => _t('btnDetectAll');
  static String get btnExecCmd => _t('btnExecCmd');
  static String get btnSubmitCmd => _t('btnSubmitCmd');
  static String get sectionCmdExec => _t('sectionCmdExec');
  static String get sectionGetShell => _t('sectionGetShell');
  static String get fieldAttackerIp => _t('fieldAttackerIp');
  static String get fieldAttackerPort => _t('fieldAttackerPort');
  static String get btnStartReverseShell => _t('btnStartReverseShell');
  static String get fieldShellPassword => _t('fieldShellPassword');
  static String get btnWriteWebShell => _t('btnWriteWebShell');
  static String get sectionVulnSelect => _t('sectionVulnSelect');
  static String get titleWebshellManager => _t('titleWebshellManager');
  static String get expLogEnterTargetUrl => _t('expLogEnterTargetUrl');
  static String get expLogInvalidLhostLport => _t('expLogInvalidLhostLport');
  static String get expLogNoVulnGeneric => _t('expLogNoVulnGeneric');
  static String get expLogReverseSentWaiting => _t('expLogReverseSentWaiting');
  static String get expLogSendFailed => _t('expLogSendFailed');
  static String get expLogSocatRunOnTarget => _t('expLogSocatRunOnTarget');
  static String get terminalConnectionClosed => _t('terminalConnectionClosed');
  static String get frpLogCopiedSnack => _t('frpLogCopiedSnack');
  static String get frpAuthMd5Label => _t('frpAuthMd5Label');
  static String get frpAuthHmacSha1Label => _t('frpAuthHmacSha1Label');
  static String get frpAuthHmacSha256Label => _t('frpAuthHmacSha256Label');
  static String get frpAuthRawTokenLabel => _t('frpAuthRawTokenLabel');
  static String get sectionVulnType => _t('sectionVulnType');
  static String get nacosStep2 => _t('nacosStep2');
  static String get sectionSshModuleCmdInject => _t('sectionSshModuleCmdInject');
  static String get btnGetShell => _t('btnGetShell');
  static String get detectPingOk => _t('detectPingOk');
  static String get detectPingNo => _t('detectPingNo');
  static String get detectPingTimeout => _t('detectPingTimeout');
  static String get detectPingConnectFailed => _t('detectPingConnectFailed');
  static String get btnDisconnect => _t('btnDisconnect');
  static String get actionPaste => _t('actionPaste');
  static String get frpTunnelTitle => _t('frpTunnelTitle');
  static String get frpStatusRunning => _t('frpStatusRunning');
  static String get frpStatusConnecting => _t('frpStatusConnecting');
  static String get frpStatusError => _t('frpStatusError');
  static String get frpStatusIdle => _t('frpStatusIdle');
  static String get frpSavedConfigs => _t('frpSavedConfigs');
  static String get frpNoConfigs => _t('frpNoConfigs');
  static String get frpNewConfig => _t('frpNewConfig');
  static String get frpRunLog => _t('frpRunLog');
  static String get frpNoLogs => _t('frpNoLogs');
  static String get frpMissingServerOrProxy => _t('frpMissingServerOrProxy');
  static String get frpDeleteTitle => _t('frpDeleteTitle');
  static String get btnStart => _t('btnStart');
  static String get btnStop => _t('btnStop');
  static String get btnEdit => _t('btnEdit');
  static String get btnDuplicate => _t('btnDuplicate');
  static String get frpNewConfigTitle => _t('frpNewConfigTitle');
  static String get frpEditConfigTitle => _t('frpEditConfigTitle');
  static String get frpRunningNoEdit => _t('frpRunningNoEdit');
  static String get frpAutoSave => _t('frpAutoSave');
  static String get frpConfigName => _t('frpConfigName');
  static String get frpConfigNameHint => _t('frpConfigNameHint');
  static String get frpServerSection => _t('frpServerSection');
  static String get frpServerAddr => _t('frpServerAddr');
  static String get frpServerAddrHint => _t('frpServerAddrHint');
  static String get frpPort => _t('frpPort');
  static String get frpProxySection => _t('frpProxySection');
  static String get frpProxyName => _t('frpProxyName');
  static String get frpRemotePort => _t('frpRemotePort');
  static String get frpLocalAddr => _t('frpLocalAddr');
  static String get frpLocalPort => _t('frpLocalPort');
  static String get frpAdvanced => _t('frpAdvanced');
  static String get frpVersionLabel => _t('frpVersionLabel');
  static String get frpVersionHint => _t('frpVersionHint');
  static String get frpTcpMux => _t('frpTcpMux');
  static String get frpAutoReconnect => _t('frpAutoReconnect');
  static String get frpAuthAlgorithm => _t('frpAuthAlgorithm');
  static String get frpToken => _t('frpToken');
  static String get frpUnnamedConfig => _t('frpUnnamedConfig');
  static String get frpActiveNotMatched => _t('frpActiveNotMatched');
  static String get frpStopConnection => _t('frpStopConnection');
  static String get shiroPageTitle => _t('shiroPageTitle');
  static String get shiroCardTitle => _t('shiroCardTitle');
  static String get shiroCardSubtitle => _t('shiroCardSubtitle');
  static String get shiroInnerTitle => _t('shiroInnerTitle');
  static String get shiroSectionKeyPayload => _t('shiroSectionKeyPayload');
  static String get shiroSectionMemShell => _t('shiroSectionMemShell');
  static String get shiroFieldMethod => _t('shiroFieldMethod');
  static String get shiroFieldMode => _t('shiroFieldMode');
  static String get shiroModeHint => _t('shiroModeHint');
  static String get shiroFieldCookieName => _t('shiroFieldCookieName');
  static String get shiroVerboseLog => _t('shiroVerboseLog');
  static String get shiroCurrentKey => _t('shiroCurrentKey');
  static String get shiroKeyAutoFilled => _t('shiroKeyAutoFilled');
  static String get shiroPayloadBase64 => _t('shiroPayloadBase64');
  static String get shiroPayloadHint => _t('shiroPayloadHint');
  static String get shiroCheckBtn => _t('shiroCheckBtn');
  static String get shiroBruteforceBtn => _t('shiroBruteforceBtn');
  static String get shiroVerifyBtn => _t('shiroVerifyBtn');
  static String get shiroSendPayloadBtn => _t('shiroSendPayloadBtn');
  static String get shiroShellType => _t('shiroShellType');
  static String get shiroShellPassword => _t('shiroShellPassword');
  static String get shiroShellPath => _t('shiroShellPath');
  static String get shiroMemShellDesc => _t('shiroMemShellDesc');
  static String get noProjectTitle => _t('noProjectTitle');
  static String get hintCreateProjectForWebshell => _t('hintCreateProjectForWebshell');
  static String get fieldProjectNameHint => _t('fieldProjectNameHint');
  static String get fieldDomainOrIdHint => _t('fieldDomainOrIdHint');
  static String get btnSkip => _t('btnSkip');
  static String get thinkphpTitle => _t('thinkphpTitle');
  static String get thinkphpSubtitle => _t('thinkphpSubtitle');
  static String get thinkphpInnerTitle => _t('thinkphpInnerTitle');
  static String get thinkphpSectionDetect => _t('thinkphpSectionDetect');
  static String get thinkphpSectionRce => _t('thinkphpSectionRce');
  static String get thinkphpSingleVuln => _t('thinkphpSingleVuln');
  static String get thinkphpExploitVuln => _t('thinkphpExploitVuln');
  static String get thinkphpGetShellPassword => _t('thinkphpGetShellPassword');
  static String get thinkphpCheckAllRce => _t('thinkphpCheckAllRce');
  static String get zentaoTitle => _t('zentaoTitle');
  static String get zentaoSubtitle => _t('zentaoSubtitle');
  static String get zentaoRootPath => _t('zentaoRootPath');
  static String get zentaoSectionExploit => _t('zentaoSectionExploit');
  static String get zentaoDetectBtn => _t('zentaoDetectBtn');
  static String get vulhubDrupalTitle => _t('vulhubDrupalTitle');
  static String get vulhubDrupalCardTitle => _t('vulhubDrupalCardTitle');
  static String get vulhubDrupalCardSubtitle => _t('vulhubDrupalCardSubtitle');
  static String get vulhubFlaskSstiTitle => _t('vulhubFlaskSstiTitle');
  static String get vulhubFlaskSstiCardTitle => _t('vulhubFlaskSstiCardTitle');
  static String get vulhubFlaskSstiCardSubtitle => _t('vulhubFlaskSstiCardSubtitle');
  static String get vulhubHttpdTitle => _t('vulhubHttpdTitle');
  static String get vulhubHttpdCardTitle => _t('vulhubHttpdCardTitle');
  static String get vulhubHttpdCardSubtitle => _t('vulhubHttpdCardSubtitle');
  static String get vulhubNacosTitle => _t('vulhubNacosTitle');
  static String get vulhubNacosCardTitle => _t('vulhubNacosCardTitle');
  static String get vulhubNacosCardSubtitle => _t('vulhubNacosCardSubtitle');
  static String get vulhubPhpTitle => _t('vulhubPhpTitle');
  static String get vulhubPhpCardTitle => _t('vulhubPhpCardTitle');
  static String get vulhubPhpCardSubtitle => _t('vulhubPhpCardSubtitle');
  static String get vulhubSpringTitle => _t('vulhubSpringTitle');
  static String get vulhubSpringCardTitle => _t('vulhubSpringCardTitle');
  static String get vulhubSpringCardSubtitle => _t('vulhubSpringCardSubtitle');
  static String get vulhubStruts2Title => _t('vulhubStruts2Title');
  static String get vulhubStruts2CardTitle => _t('vulhubStruts2CardTitle');
  static String get vulhubStruts2CardSubtitle => _t('vulhubStruts2CardSubtitle');
  static String get vulhubTomcatTitle => _t('vulhubTomcatTitle');
  static String get vulhubTomcatCardTitle => _t('vulhubTomcatCardTitle');
  static String get vulhubTomcatCardSubtitle => _t('vulhubTomcatCardSubtitle');
  static String get vulhubWeblogicTitle => _t('vulhubWeblogicTitle');
  static String get vulhubWeblogicCardTitle => _t('vulhubWeblogicCardTitle');
  static String get vulhubWeblogicCardSubtitle => _t('vulhubWeblogicCardSubtitle');
  static String get vulhubXxljobTitle => _t('vulhubXxljobTitle');
  static String get vulhubXxljobCardTitle => _t('vulhubXxljobCardTitle');
  static String get vulhubXxljobCardSubtitle => _t('vulhubXxljobCardSubtitle');
  static String get vulhubAria2BtnListTasks => _t('vulhubAria2BtnListTasks');
  static String get vulhubAria2SectionCron => _t('vulhubAria2SectionCron');
  static String get vulhubAria2FieldCronUrl => _t('vulhubAria2FieldCronUrl');
  static String get sectionFullTerminal => _t('sectionFullTerminal');
  static String get fieldBasicAuth => _t('fieldBasicAuth');
  static String get sectionVulnDetect => _t('sectionVulnDetect');
  static String get sectionGroovyRce => _t('sectionGroovyRce');
  static String get sectionPathTraversal => _t('sectionPathTraversal');
  static String get fieldFilePath => _t('fieldFilePath');
  static String get sectionCgiRce => _t('sectionCgiRce');
  static String get btnReadFile => _t('btnReadFile');
  static String get fieldCoreName => _t('fieldCoreName');
  static String get sectionCmdExecOob => _t('sectionCmdExecOob');
  static String get sectionCmdExecAutoUpload => _t('sectionCmdExecAutoUpload');
  static String get sectionCmdExecOobNeeded => _t('sectionCmdExecOobNeeded');
  static String get sectionCmdExecUserAgentInject => _t('sectionCmdExecUserAgentInject');
  static String get btnInjectAndTrigger => _t('btnInjectAndTrigger');
  static String get sectionCveSelect => _t('sectionCveSelect');
  static String get fieldUsername => _t('fieldUsername');
  static String get fieldPassword => _t('fieldPassword');
  static String get nacosStep1 => _t('nacosStep1');
  static String get nacosStep3 => _t('nacosStep3');
  static String get nacosListUsers => _t('nacosListUsers');
  static String get nacosCreateUser => _t('nacosCreateUser');
  static String get nacosLoginForToken => _t('nacosLoginForToken');
  static String get nacosTokenHint => _t('nacosTokenHint');
  static String get nacosDerbySql => _t('nacosDerbySql');
  static String get nacosExecSql => _t('nacosExecSql');
  static String get flaskSstiInjectParam => _t('flaskSstiInjectParam');
  static String get sectionRequestHeaders => _t('sectionRequestHeaders');
  static String get fieldCustomHeaders => _t('fieldCustomHeaders');
  static String get sectionRequestBody => _t('sectionRequestBody');
  static String get flaskSstiBodyInject => _t('flaskSstiBodyInject');
  static String get flaskSstiBodyPostOnly => _t('flaskSstiBodyPostOnly');
  static String get flaskSstiBtnDetect => _t('flaskSstiBtnDetect');
  static String get phpFieldFilePath => _t('phpFieldFilePath');
  static String get struts2FieldPath => _t('struts2FieldPath');
  static String get supervisorBtnDetect => _t('supervisorBtnDetect');
  static String get xxljobBtnDetect => _t('xxljobBtnDetect');
  static String get ofbizBtnDetect51467 => _t('ofbizBtnDetect51467');
  static String get ofbizBtnDetect38856 => _t('ofbizBtnDetect38856');
  static String get tomcatFieldPath => _t('tomcatFieldPath');
  static String get expTagGeneric => _t('expTagGeneric');
  static String get expTagZentao => _t('expTagZentao');
  static String get expSubtitleShiro => _t('expSubtitleShiro');
  static String get expVersionShiro => _t('expVersionShiro');
  static String get expSubtitleThinkphp => _t('expSubtitleThinkphp');
  static String get expVersionThinkphp => _t('expVersionThinkphp');
  static String get expSubtitleZentao => _t('expSubtitleZentao');
  static String get expVersionZentao => _t('expVersionZentao');
  static String get expSubtitleStruts2 => _t('expSubtitleStruts2');
  static String get expVersionStruts2 => _t('expVersionStruts2');
  static String get expSubtitleSpring => _t('expSubtitleSpring');
  static String get expVersionSpring => _t('expVersionSpring');
  static String get expSubtitleHttpd => _t('expSubtitleHttpd');
  static String get expVersionHttpd => _t('expVersionHttpd');
  static String get expSubtitleDruid => _t('expSubtitleDruid');
  static String get expVersionDruid => _t('expVersionDruid');
  static String get expSubtitleOfbiz => _t('expSubtitleOfbiz');
  static String get expVersionOfbiz => _t('expVersionOfbiz');
  static String get expSubtitleSolr => _t('expSubtitleSolr');
  static String get expVersionSolr => _t('expVersionSolr');
  static String get expSubtitleDrupal => _t('expSubtitleDrupal');
  static String get expVersionDrupal => _t('expVersionDrupal');
  static String get expSubtitleElastic => _t('expSubtitleElastic');
  static String get expVersionElastic => _t('expVersionElastic');
  static String get expSubtitleFlaskSsti => _t('expSubtitleFlaskSsti');
  static String get expVersionFlaskSsti => _t('expVersionFlaskSsti');
  static String get expTitlePhp => _t('expTitlePhp');
  static String get expSubtitlePhp => _t('expSubtitlePhp');
  static String get expVersionPhp => _t('expVersionPhp');
  static String get expSubtitleTomcat => _t('expSubtitleTomcat');
  static String get expVersionTomcat => _t('expVersionTomcat');
  static String get expSubtitleWeblogic => _t('expSubtitleWeblogic');
  static String get expVersionWeblogic => _t('expVersionWeblogic');
  static String get expTitleXxljob => _t('expTitleXxljob');
  static String get expSubtitleXxljob => _t('expSubtitleXxljob');
  static String get expVersionXxljob => _t('expVersionXxljob');
  static String get expSubtitleNacos => _t('expSubtitleNacos');
  static String get expVersionNacos => _t('expVersionNacos');
  static String get menuEnterSuo5 => _t('menuEnterSuo5');
  static String get menuEnterSuoTunnel => _t('menuEnterSuoTunnel');
  static String get titleSuo5Manager => _t('titleSuo5Manager');
  static String get actionAddSuo5 => _t('actionAddSuo5');
  static String get suo5NewConfigTitle => _t('suo5NewConfigTitle');
  static String get suo5EditConfigTitle => _t('suo5EditConfigTitle');
  static String get suo5ConfigName => _t('suo5ConfigName');
  static String get suo5ConfigNameHint => _t('suo5ConfigNameHint');
  static String get suo5TargetUrl => _t('suo5TargetUrl');
  static String get suo5TargetUrlHint => _t('suo5TargetUrlHint');
  static String get suo5ListenHost => _t('suo5ListenHost');
  static String get suo5ListenPort => _t('suo5ListenPort');
  static String get suo5StatusRunning => _t('suo5StatusRunning');
  static String get suo5StatusConnecting => _t('suo5StatusConnecting');
  static String get suo5StatusError => _t('suo5StatusError');
  static String get suo5StatusIdle => _t('suo5StatusIdle');
  static String get suo5InvalidUrl => _t('suo5InvalidUrl');
  static String get suo5InvalidPort => _t('suo5InvalidPort');
  static String get suo5MissingUrl => _t('suo5MissingUrl');
  static String get suo5RunningNoEdit => _t('suo5RunningNoEdit');
  static String get suo5StatActiveConn => _t('suo5StatActiveConn');
  static String get suo5StatUpload => _t('suo5StatUpload');
  static String get suo5StatDownload => _t('suo5StatDownload');
  static String get suo5RunLog => _t('suo5RunLog');
  static String get suo5NoLogs => _t('suo5NoLogs');
  static String get suo5LogCopiedSnack => _t('suo5LogCopiedSnack');
  static String get suo5HandshakeOk => _t('suo5HandshakeOk');
  static String get suo5BtnProbe => _t('suo5BtnProbe');
  static String get suoProbeHandshakeLoading => _t('suoProbeHandshakeLoading');
  static String get suoHandshakeResultTitle => _t('suoHandshakeResultTitle');
  static String get suo5MappingLabel => _t('suo5MappingLabel');
  static String get menuSuoTunnel => _t('menuSuoTunnel');
  static String get titleSuoTunnelManager => _t('titleSuoTunnelManager');
  static String get actionAddSuoTunnel => _t('actionAddSuoTunnel');
  static String get tooltipWebshellOneClickTunnel => _t('tooltipWebshellOneClickTunnel');
  static String get webshellJspSuoTunnelPickTitle => _t('webshellJspSuoTunnelPickTitle');
  static String get webshellJspSuoTunnelPickBody => _t('webshellJspSuoTunnelPickBody');
  static String get webshellOneClickTunnelUnavailable => _t('webshellOneClickTunnelUnavailable');
  static String get webshellOneClickTunnelNeedConn => _t('webshellOneClickTunnelNeedConn');
  static String get webshellOneClickTunnelPayloadMissing => _t('webshellOneClickTunnelPayloadMissing');
  static String get webshellOneClickTunnelUploadFailed => _t('webshellOneClickTunnelUploadFailed');
  static String get suoTunnelNewConfigTitle => _t('suoTunnelNewConfigTitle');
  static String get suoTunnelEditConfigTitle => _t('suoTunnelEditConfigTitle');
  static String get suoTunnelProtocol => _t('suoTunnelProtocol');
  static String get suoTunnelProtocolSuo5 => _t('suoTunnelProtocolSuo5');
  static String get suoTunnelProtocolSuo6 => _t('suoTunnelProtocolSuo6');
  static String get suoTunnelRunLog => _t('suoTunnelRunLog');
  static String get suoTunnelProfileCreatedSnack => _t('suoTunnelProfileCreatedSnack');
  static String get suoTunnelProtocolSwitchTitle => _t('suoTunnelProtocolSwitchTitle');
  static String get suoTunnelProtocolSwitchBody => _t('suoTunnelProtocolSwitchBody');
  static String get suo6MissingUrl => _t('suo6MissingUrl');
  static String get obfuscateUploadLabel => _t('obfuscateUploadLabel');
  static String get obfuscateUploadTooltip => _t('obfuscateUploadTooltip');
  static String get obfuscateModeOn => _t('obfuscateModeOn');
  static String get obfuscateModeOff => _t('obfuscateModeOff');
  static String get tooltipDeobfuscate => _t('tooltipDeobfuscate');
  static String get tooltipShowObfuscated => _t('tooltipShowObfuscated');
  static String get obfuscatedFileDialogTitle => _t('obfuscatedFileDialogTitle');
  static String get obfuscatedFileDialogMsg => _t('obfuscatedFileDialogMsg');
  static String get btnSaveDeobfuscated => _t('btnSaveDeobfuscated');
  static String get btnSaveAsIs => _t('btnSaveAsIs');
  static String get tooltipDetectWritableDirs => _t('tooltipDetectWritableDirs');
  static String get writableDirsDialogTitle => _t('writableDirsDialogTitle');
  static String get writableDirsNoneFound => _t('writableDirsNoneFound');

  // ── Parameterized methods ─────────────────────────────────────────────────

  static String errorResult(Object e) => _tp('errorResult', {'e': e});

  static String workspaceWelcomeSubtitle(String pageTitle) => _tp('workspaceWelcomeSubtitle', {'pageTitle': pageTitle});

  static String recentFileTitle(int index) => _tp('recentFileTitle', {'index': index});

  static String recentHoursAgo(int hours) => _tp('recentHoursAgo', {'hours': hours});

  static String payloadCount(int n) => _tp('payloadCount', {'n': n});

  static String confirmDeletePayload(String name) => _tp('confirmDeletePayload', {'name': name});

  static String snackImported(String name) => _tp('snackImported', {'name': name});

  static String snackImportFailed(Object e) => _tp('snackImportFailed', {'e': e});

  static String snackSavedTo(String path) => _tp('snackSavedTo', {'path': path});

  static String snackSaveFailed(Object e) => _tp('snackSaveFailed', {'e': e});

  static String titleEditProject(int id) => _tp('titleEditProject', {'id': id});

  static String projectEmptyHint(String newProjectLabel) => _tp('projectEmptyHint', {'newProjectLabel': newProjectLabel});

  static String projectCreatedUpdated(String created, String updated) => _tp('projectCreatedUpdated', {'created': created, 'updated': updated});

  static String confirmDeleteProject(String name) => _tp('confirmDeleteProject', {'name': name});

  static String activeSessionCount(int n) => _tp('activeSessionCount', {'n': n});

  static String listeningOn(String addr, int port) => _tp('listeningOn', {'addr': addr, 'port': port});

  static String portOccupiedOn(String addr, int port) => _tp('portOccupiedOn', {'addr': addr, 'port': port});

  static String notListening(String host, int port) => _tp('notListening', {'host': host, 'port': port});

  static String snackListenStarted(int lport, String lhost) => _tp('snackListenStarted', {'lport': lport, 'lhost': lhost});

  static String snackListenFailed(Object e) => _tp('snackListenFailed', {'e': e});

  static String snackStartFailed(Object e) => _tp('snackStartFailed', {'e': e});

  static String socatTips(int lport) => _tp('socatTips', {'lport': lport});

  static String tabCompletionTitle(int total) => _tp('tabCompletionTitle', {'total': total});

  static String confirmDeleteWebshell(String name) => _tp('confirmDeleteWebshell', {'name': name});

  static String webshellManagementTitle(String projectName) => _tp('webshellManagementTitle', {'projectName': projectName});

  static String expManagementScopedTitle(String projectName) => _tp('expManagementScopedTitle', {'projectName': projectName});

  static String webshellCount(int n) => _tp('webshellCount', {'n': n});

  static String webshellEmptyHint(String addLabel) => _tp('webshellEmptyHint', {'addLabel': addLabel});

  static String unknownConnector(String value) => _tp('unknownConnector', {'value': value});

  static String helperParamName(String param) => _tp('helperParamName', {'param': param});

  static String hintParamName(String param) => _tp('hintParamName', {'param': param});

  static String snackPayloadDecodeFailed(String name) => _tp('snackPayloadDecodeFailed', {'name': name});

  static String confirmDeleteFile(String name) => _tp('confirmDeleteFile', {'name': name});

  static String snackDeleted(String name) => _tp('snackDeleted', {'name': name});

  static String snackUploadFailed(Object e) => _tp('snackUploadFailed', {'e': e});

  static String snackUploaded(String fileName) => _tp('snackUploaded', {'fileName': fileName});

  static String snackDownloadedTo(String path) => _tp('snackDownloadedTo', {'path': path});

  static String snackDownloadFailed(Object e) => _tp('snackDownloadFailed', {'e': e});

  static String snackPayloadUploadedToRemote(String remotePath) => _tp('snackPayloadUploadedToRemote', {'remotePath': remotePath});

  static String disabledFunctions(int n) => _tp('disabledFunctions', {'n': n});

  static String loadedExtensions(int n) => _tp('loadedExtensions', {'n': n});

  static String privEscSudoLimitedReason(String paths) => _tp('privEscSudoLimitedReason', {'paths': paths});

  static String privEscKernelReason(String ver, String arch) => _tp('privEscKernelReason', {'ver': ver, 'arch': arch});

  static String privEscShadowReason(String hashMode) => _tp('privEscShadowReason', {'hashMode': hashMode});

  static String privEscCronReason(String paths) => _tp('privEscCronReason', {'paths': paths});

  static String expVersionRequirement(String ver) => _tp('expVersionRequirement', {'ver': ver});

  static String expLogException(Object e) => _tp('expLogException', {'e': e});

  static String expLogStartFailed(Object e) => _tp('expLogStartFailed', {'e': e});

  static String expLogStartFullTerminalListen(String lhost, int lport, String mode) => _tp('expLogStartFullTerminalListen', {'lhost': lhost, 'lport': lport, 'mode': mode});

  static String frpDupDisplayName(String base) => _tp('frpDupDisplayName', {'base': base});

  static String frpDupDisplayNameIndexed(String base, int i) => _tp('frpDupDisplayNameIndexed', {'base': base, 'i': i});

  static String frpDupProxyFirst(String proxyName) => _tp('frpDupProxyFirst', {'proxyName': proxyName});

  static String frpDupProxyIndexed(String proxyName, int i) => _tp('frpDupProxyIndexed', {'proxyName': proxyName, 'i': i});

  /// 下拉框等处的连接器展示名（与 [ConnectorFactory] 一致）。
  ///
  /// 历史上 `connectorUiLabel` 文案无 `{connectorType}` 占位符，导致所有类型
  /// 都显示成「PHP 冰蝎」；现改为按类型组合 stack + short 标签。
  static String connectorUiLabel(String connectorType) => _tp(
        'connectorUiLabelDetail',
        {
          'stack': ConnectorFactory.typeLabel(connectorType).toUpperCase(),
          'short': ConnectorFactory.shortLabel(connectorType),
        },
      );

  static String terminalFullTitle(String label) => _tp('terminalFullTitle', {'label': label});

  static String frpDuplicatedSnack(String name, String proxyName, int port) => _tp('frpDuplicatedSnack', {'name': name, 'proxyName': proxyName, 'port': port});

  static String frpDuplicateFailed(Object e) => _tp('frpDuplicateFailed', {'e': e});

  static String frpConfirmDelete(String name) => _tp('frpConfirmDelete', {'name': name});

  static String frpDeletedSnack(String name) => _tp('frpDeletedSnack', {'name': name});

  static String frpMappingLabel(int remotePort, String localAddr, int localPort) => _tp('frpMappingLabel', {'remotePort': remotePort, 'localAddr': localAddr, 'localPort': localPort});

  static String frpServerLabel(String serverAddr, int serverPort) => _tp('frpServerLabel', {'serverAddr': serverAddr, 'serverPort': serverPort});

  static String frpSaveFailed(Object e) => _tp('frpSaveFailed', {'e': e});

  static String thinkphpCurrentVuln(String label) => _tp('thinkphpCurrentVuln', {'label': label});

  static String suo5ManagementTitle(String projectName) => _tp('suo5ManagementTitle', {'projectName': projectName});

  static String suo5Count(int n) => _tp('suo5Count', {'n': n});

  static String suo5EmptyHint(String addLabel) => _tp('suo5EmptyHint', {'addLabel': addLabel});

  static String confirmDeleteSuo5(String name) => _tp('confirmDeleteSuo5', {'name': name});

  static String suo5HandshakeFailed(Object e) => _tp('suo5HandshakeFailed', {'e': e});

  static String suo5ActiveBanner(String name, String statusLabel) => _tp('suo5ActiveBanner', {'name': name, 'statusLabel': statusLabel});

  static String suo5HeaderRunningSummary(int running, int total) => _tp('suo5HeaderRunningSummary', {'running': running, 'total': total});

  static String suoTunnelManagementTitle(String projectName) => _tp('suoTunnelManagementTitle', {'projectName': projectName});

  static String suoTunnelEmptyHint(String addLabel) => _tp('suoTunnelEmptyHint', {'addLabel': addLabel});

  static String suoTunnelCount(int n) => _tp('suoTunnelCount', {'n': n});

  static String confirmDeleteSuo6(String name) => _tp('confirmDeleteSuo6', {'name': name});

  static String writableDirsFoundHint(int n) => _tp('writableDirsFoundHint', {'n': n});

  // ── Aliases ────────────────────────────────────────────────────────────────
  static String get suo6InvalidUrl => suo5InvalidUrl;
  static String get suo6InvalidPort => suo5InvalidPort;
  static String get suo6StatActiveConn => suo5StatActiveConn;
  static String get suo6StatUpload => suo5StatUpload;
  static String get suo6StatDownload => suo5StatDownload;
  static String get suo6StatusRunning => suo5StatusRunning;
  static String get suo6StatusConnecting => suo5StatusConnecting;
  static String get suo6StatusError => suo5StatusError;
  static String get suo6StatusIdle => suo5StatusIdle;
}
