import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/webshell_service.dart';
import '../theme/app_theme.dart';

/// 进程信息
class _ProcessInfo {
  final String pid;
  final String name;
  final String user;
  final String cpu;
  final String mem;
  final String path;
  const _ProcessInfo({
    required this.pid,
    required this.name,
    required this.user,
    required this.cpu,
    required this.mem,
    required this.path,
  });
}

class ProcessListTab extends StatefulWidget {
  final WebshellService service;
  const ProcessListTab({super.key, required this.service});

  @override
  State<ProcessListTab> createState() => _ProcessListTabState();
}

class _ProcessListTabState extends State<ProcessListTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<_ProcessInfo> _processes = [];
  bool _loading = false;
  String? _error;
  Timer? _autoRefreshTimer;
  bool _autoRefresh = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String? _sortColumn;
  bool _sortAsc = true;

  bool get _isWindows =>
      widget.service.webshell.connectorType.startsWith('asp');

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _toggleAutoRefresh(bool on) {
    setState(() => _autoRefresh = on);
    _autoRefreshTimer?.cancel();
    if (on) {
      _autoRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        refresh();
      });
    }
  }

  Future<void> refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cmd = _isWindows ? 'tasklist /FO CSV /NH' : 'ps aux --sort=-%mem';
      final output = await widget.service.executeCommand(cmd);
      if (!mounted) return;
      setState(() {
        _processes = _parseOutput(output);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<_ProcessInfo> _parseOutput(String raw) {
    if (raw.isEmpty || raw.startsWith('[')) return [];
    if (_isWindows) return _parseWindows(raw);
    return _parsePsAux(raw);
  }

  List<_ProcessInfo> _parsePsAux(String raw) {
    final result = <_ProcessInfo>[];
    for (final line in raw.trim().split('\n')) {
      if (line.isEmpty || line.startsWith('USER')) continue;
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 11) continue;
      try {
        result.add(_ProcessInfo(
          pid: parts[1],
          name: parts[10].split('/').last.split('\\').last,
          user: parts[0],
          cpu: parts[2],
          mem: parts[3],
          path: parts.length > 10 ? parts.sublist(10).join(' ') : '',
        ));
      } catch (_) {}
    }
    return result;
  }

  List<_ProcessInfo> _parseWindows(String raw) {
    return _parseTasklist(raw);
  }

  List<_ProcessInfo> _parseTasklist(String raw) {
    final result = <_ProcessInfo>[];
    for (final line in raw.trim().split('\n')) {
      if (line.isEmpty || line.startsWith('"Image Name"')) continue;
      final parts = line.split('","');
      if (parts.length < 2) continue;
      try {
        result.add(_ProcessInfo(
          pid: parts[1].replaceAll('"', ''),
          name: parts[0].replaceAll('"', ''),
          user: parts.length > 6 ? parts[6].replaceAll('"', '') : '',
          cpu: '',
          mem: parts.length > 4
              ? parts[4].replaceAll('"', '').replaceAll(' K', '')
              : '',
          path: '',
        ));
      } catch (_) {}
    }
    return result;
  }

  Future<void> _killProcess(_ProcessInfo proc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        title: Text('Terminate process', style: AppTextStyles.heading()),
        content: Text(
          'Kill ${proc.name} (PID: ${proc.pid})?',
          style: AppTextStyles.body(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Kill'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final killCmd = _isWindows
          ? 'taskkill /F /PID ${proc.pid}'
          : 'kill -9 ${proc.pid}';
      final r = await widget.service.executeCommand(killCmd);
      if (!mounted) return;
      final success = !r.contains('not found') &&
          !r.contains('No such') &&
          !r.contains('Error');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(success ? 'Killed ${proc.name}' : 'Failed: ${r.trim()}'),
        backgroundColor: success ? AppColors.primaryDim : AppColors.red,
        behavior: SnackBarBehavior.floating,
      ));
      if (success) refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Kill failed: $e'),
        backgroundColor: AppColors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  List<_ProcessInfo> get _filtered {
    if (_searchQuery.isEmpty) return _processes;
    final q = _searchQuery.toLowerCase();
    return _processes.where((p) {
      return p.pid.contains(q) ||
          p.name.toLowerCase().contains(q) ||
          p.user.toLowerCase().contains(q) ||
          p.path.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final filtered = _filtered;

    return Column(
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color: AppColors.bgElevated,
          child: Row(
            children: [
              Icon(Icons.memory, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                '${filtered.length} processes',
                style: AppTextStyles.caption(color: AppColors.primary),
              ),
              const Spacer(),
              SizedBox(
                width: 200,
                height: 32,
                child: TextField(
                  controller: _searchController,
                  style:
                      AppTextStyles.caption(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search PID/name/user...',
                    hintStyle:
                        AppTextStyles.caption(color: AppColors.textMuted),
                    prefixIcon: const Icon(Icons.search, size: 16),
                    filled: true,
                    fillColor: AppColors.bgDark,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide:
                          const BorderSide(color: AppColors.border),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              const SizedBox(width: 8),
              Text('Auto', style: AppTextStyles.caption()),
              Switch(
                value: _autoRefresh,
                onChanged: _toggleAutoRefresh,
                activeColor: AppColors.primary,
              ),
              IconButton(
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.primary),
                      )
                    : const Icon(Icons.refresh, size: 18),
                onPressed: _loading ? null : refresh,
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),
        Expanded(
          child: _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: AppColors.red),
                      const SizedBox(height: 12),
                      Flexible(
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(_error!,
                              style: AppTextStyles.caption(),
                              textAlign: TextAlign.center),
                        ),
                      ),
                    ],
                  ),
                )
              : _loading && _processes.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primary))
                  : _buildTable(filtered),
        ),
      ],
    );
  }

  Widget _buildTable(List<_ProcessInfo> procs) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          dataRowMinHeight: 32,
          dataRowMaxHeight: 36,
          headingRowHeight: 36,
          headingTextStyle: AppTextStyles.caption(
              color: AppColors.primary, size: 11),
          dataTextStyle:
              AppTextStyles.caption(color: AppColors.textPrimary),
          sortColumnIndex: _sortColumn == 'PID'
              ? 0
              : _sortColumn == 'Name'
                  ? 1
                  : _sortColumn == 'User'
                      ? 2
                      : null,
          sortAscending: _sortAsc,
          columns: [
            _col('PID', 56),
            _col('Name', 150),
            _col('User', 90),
            _col('CPU%', 52),
            _col('MEM%', 52),
            _col('Path', 320),
            _col('', 40),
          ],
          rows: procs.map((p) {
            return DataRow(
              color: WidgetStateProperty.resolveWith<Color?>((states) {
                if (states.contains(WidgetState.hovered)) {
                  return AppColors.bgElevated;
                }
                return null;
              }),
              cells: [
                DataCell(Text(p.pid)),
                DataCell(Text(p.name)),
                DataCell(Text(p.user)),
                DataCell(Text(p.cpu)),
                DataCell(Text(p.mem)),
                DataCell(Text(p.path, overflow: TextOverflow.ellipsis),
                    onTap: p.path.isNotEmpty
                        ? () {
                            Clipboard.setData(
                                ClipboardData(text: p.path));
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Path copied'),
                                    behavior: SnackBarBehavior.floating,
                                    duration: Duration(seconds: 1)));
                          }
                        : null),
                DataCell(
                  IconButton(
                    icon: const Icon(Icons.close,
                        size: 16, color: AppColors.red),
                    onPressed: () => _killProcess(p),
                    tooltip: 'Kill Process',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 24, minHeight: 24),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  DataColumn _col(String label, double width) {
    return DataColumn(
      label: SizedBox(width: width, child: Text(label)),
      onSort: (columnIndex, ascending) {
        setState(() {
          _sortColumn = label;
          _sortAsc = ascending;
        });
      },
    );
  }
}
