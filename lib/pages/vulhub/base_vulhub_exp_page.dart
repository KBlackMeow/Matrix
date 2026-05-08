import 'package:flutter/material.dart';

import '../../app/constants.dart';
import '../../core/log/log_buffer.dart';
import '../../theme/app_theme.dart';
import '_vulhub_page_helpers.dart';

abstract class BaseVulhubExpPage extends StatefulWidget {
  const BaseVulhubExpPage({super.key});
}

abstract class BaseVulhubExpPageState<T extends BaseVulhubExpPage>
    extends State<T> {
  final ScrollController logScroll = ScrollController();
  final LogBuffer _logBuffer = LogBuffer(maxLines: AppConstants.logBufferSize);
  bool running = false;

  IconData get pageIcon;
  String get appBarTitle;
  String get cardTitle;
  String get cardSubtitle;
  Widget buildLeftPanel(BuildContext context);

  String get logText => _logBuffer.joined;

  int timeoutFrom(TextEditingController controller) {
    return int.tryParse(controller.text.trim()) ??
        AppConstants.defaultHttpTimeoutSeconds;
  }

  void appendLog(String line) {
    setState(() {
      _logBuffer.append(line);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (logScroll.hasClients) {
        logScroll.animateTo(
          logScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void clearLog() {
    setState(() {
      _logBuffer.clear();
    });
  }

  @override
  void dispose() {
    logScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgElevated,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Icon(pageIcon, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                appBarTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.heading(
                  size: 14,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            vulhubInfoCard(pageIcon, cardTitle, cardSubtitle),
            const SizedBox(height: 16),
            Expanded(
              child: VulhubExpCardShell(
                running: running,
                log: logText,
                logScroll: logScroll,
                onClearLog: clearLog,
                leftPanel: buildLeftPanel(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
