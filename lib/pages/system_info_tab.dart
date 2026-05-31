import 'package:flutter/material.dart';

import '../services/webshell_service.dart';
import '../theme/app_theme.dart';
import '../app/localization.dart';

class SystemInfoTab extends StatefulWidget {
  final WebshellService service;

  const SystemInfoTab({super.key, required this.service});

  @override
  State<SystemInfoTab> createState() => _SystemInfoTabState();
}

class _SystemInfoTabState extends State<SystemInfoTab>
    with AutomaticKeepAliveClientMixin {
  Map<String, String> _info = {};
  bool _loading = true;
  bool _failed = false;

  static const Map<String, List<String>> _fieldAliases = {
    'os': ['OS'],
    'phpVersion': ['PHP版本', 'PHP Version'],
    'runUser': ['运行用户', 'Runtime user', 'USER'],
    'serverIp': ['服务器IP', 'Server IP'],
    'serverSoftware': ['服务器软件', 'Server software'],
    'docRoot': ['文档根目录', 'Document root'],
    'currentDir': ['当前目录', 'Current directory', 'PWD'],
    'memoryLimit': ['内存限制', 'Memory limit'],
    'maxExecutionTime': ['最大执行时间', 'Max execution time'],
    'safeMode': ['Safe Mode'],
    'host': ['主机名', 'Hostname', 'HOST'],
    'userId': ['用户ID', 'User ID', 'ID'],
    'kernelVersion': ['内核版本', 'Kernel version', 'KERNEL'],
    'dotnetClr': ['.NET CLR 版本', '.NET CLR version', 'CLR'],
    'disabledFunctions': ['禁用函数', 'Disabled functions'],
    'loadedExtensions': ['已加载扩展', 'Loaded extensions'],
  };

  String? _valueOf(String field) {
    final aliases = _fieldAliases[field] ?? const [];
    for (final key in aliases) {
      final val = _info[key];
      if (val != null && val.isNotEmpty) return val;
    }
    return null;
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final info = await widget.service.getSystemInfo();
    if (mounted) {
      setState(() {
        _info = info;
        _loading = false;
        _failed = info.isEmpty;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        // 工具栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          color: AppColors.bgElevated,
          child: Row(
            children: [
              const Icon(
                Icons.dns_outlined,
                color: AppColors.primary,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                S.serverInfo,
                style: AppTextStyles.heading(
                  size: 14,
                  color: AppColors.primary,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, size: 15),
                label: Text(S.actionRefresh),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                )
              : _failed
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: AppColors.red,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        S.sysInfoFailed,
                        style: AppTextStyles.body(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        S.sysInfoFailedHint,
                        style: AppTextStyles.caption(
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: Text(S.btnRetry),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.bgDark,
                        ),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // 主要信息卡
                      _InfoGrid(info: _info),
                      const SizedBox(height: 20),
                      // 禁用函数
                      if (_valueOf('disabledFunctions') != null &&
                          _valueOf('disabledFunctions') != '无' &&
                          _valueOf('disabledFunctions') != 'N/A')
                        _DisabledFunctionsCard(
                          functions: _valueOf('disabledFunctions')!,
                        ),
                      // 扩展列表
                      if (_valueOf('loadedExtensions') != null)
                        _ExtensionsCard(extensions: _valueOf('loadedExtensions')!),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _InfoGrid extends StatelessWidget {
  final Map<String, String> info;

  const _InfoGrid({required this.info});

  static const _mainFields = [
    'os',
    'phpVersion',
    'runUser',
    'serverIp',
    'serverSoftware',
    'docRoot',
    'currentDir',
    'memoryLimit',
    'maxExecutionTime',
    'safeMode',
    'host',
    'userId',
    'kernelVersion',
    'dotnetClr',
  ];

  static const Map<String, List<String>> _fieldAliases = {
    'os': ['OS'],
    'phpVersion': ['PHP版本', 'PHP Version'],
    'runUser': ['运行用户', 'Runtime user', 'USER'],
    'serverIp': ['服务器IP', 'Server IP'],
    'serverSoftware': ['服务器软件', 'Server software'],
    'docRoot': ['文档根目录', 'Document root'],
    'currentDir': ['当前目录', 'Current directory', 'PWD'],
    'memoryLimit': ['内存限制', 'Memory limit'],
    'maxExecutionTime': ['最大执行时间', 'Max execution time'],
    'safeMode': ['Safe Mode'],
    'host': ['主机名', 'Hostname', 'HOST'],
    'userId': ['用户ID', 'User ID', 'ID'],
    'kernelVersion': ['内核版本', 'Kernel version', 'KERNEL'],
    'dotnetClr': ['.NET CLR 版本', '.NET CLR version', 'CLR'],
  };

  String? _valueOf(String field) {
    final aliases = _fieldAliases[field] ?? const [];
    for (final key in aliases) {
      final val = info[key];
      if (val != null && val.isNotEmpty) return val;
    }
    return null;
  }

  String _fieldLabel(String field) {
    switch (field) {
      case 'os':
        return S.sysInfoFieldOs;
      case 'phpVersion':
        return S.sysInfoFieldPhpVersion;
      case 'runUser':
        return S.sysInfoFieldRunUser;
      case 'serverIp':
        return S.sysInfoFieldServerIp;
      case 'serverSoftware':
        return S.sysInfoFieldServerSoftware;
      case 'docRoot':
        return S.sysInfoFieldDocRoot;
      case 'currentDir':
        return S.sysInfoFieldCurrentDir;
      case 'memoryLimit':
        return S.sysInfoFieldMemoryLimit;
      case 'maxExecutionTime':
        return S.sysInfoFieldMaxExecutionTime;
      case 'safeMode':
        return S.sysInfoFieldSafeMode;
      case 'host':
        return S.sysInfoFieldHost;
      case 'userId':
        return S.sysInfoFieldUserId;
      case 'kernelVersion':
        return S.sysInfoFieldKernelVersion;
      case 'dotnetClr':
        return S.sysInfoFieldDotnetClr;
      default:
        return field;
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _mainFields
        .map((f) => MapEntry(_fieldLabel(f), _valueOf(f)))
        .where((e) => e.value != null)
        .map((e) => MapEntry(e.key, e.value!))
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: items.map((e) {
          final isLast = e == items.last;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              border: isLast
                  ? null
                  : const Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    e.key,
                    style: AppTextStyles.caption(
                      size: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    e.value,
                    style: AppTextStyles.body(
                      size: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _DisabledFunctionsCard extends StatelessWidget {
  final String functions;

  const _DisabledFunctionsCard({required this.functions});

  @override
  Widget build(BuildContext context) {
    final funcs = functions
        .split(',')
        .map((f) => f.trim())
        .where((f) => f.isNotEmpty)
        .toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.block, color: AppColors.red, size: 16),
              const SizedBox(width: 8),
              Text(
                S.disabledFunctions(funcs.length),
                style: AppTextStyles.body(size: 13, color: AppColors.red),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: funcs
                .map(
                  (f) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: AppColors.red.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      f,
                      style: AppTextStyles.caption(
                        size: 11,
                        color: AppColors.red,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _ExtensionsCard extends StatelessWidget {
  final String extensions;

  const _ExtensionsCard({required this.extensions});

  @override
  Widget build(BuildContext context) {
    final exts =
        extensions
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList()
          ..sort();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.extension_outlined,
                color: AppColors.primary,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                S.loadedExtensions(exts.length),
                style: AppTextStyles.body(size: 13, color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: exts
                .map(
                  (e) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      e,
                      style: AppTextStyles.caption(
                        size: 11,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
