import 'package:flutter/material.dart';

import '../app/localization.dart';
import '../theme/app_theme.dart';

/// 上传成功后的居中提示（替代底部 SnackBar）
Future<void> showUploadSuccessDialog(BuildContext context, String message) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_outline,
            color: AppColors.primary,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              S.dialogUploadSuccessTitle,
              style: AppTextStyles.heading(
                size: 15,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
      content: SelectableText(
        message,
        style: AppTextStyles.body(size: 13, color: AppColors.textSecondary),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.bgDark,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            S.btnConfirm,
            style: AppTextStyles.body(color: AppColors.bgDark),
          ),
        ),
      ],
    ),
  );
}

/// 上传失败或前置校验失败（居中提示）
Future<void> showUploadFailureDialog(BuildContext context, String message) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: MatrixDialogStyle.outlineDanger(0.42),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            color: AppColors.red.withValues(alpha: 0.9),
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              S.dialogUploadFailureTitle,
              style: AppTextStyles.heading(
                size: 15,
                color: AppColors.red.withValues(alpha: 0.95),
              ),
            ),
          ),
        ],
      ),
      content: SelectableText(
        message,
        style: AppTextStyles.body(size: 13, color: AppColors.textSecondary),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.red.withValues(alpha: 0.85),
            foregroundColor: AppColors.bgDark,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            S.btnConfirm,
            style: AppTextStyles.body(color: AppColors.bgDark),
          ),
        ),
      ],
    ),
  );
}

/// 用户取消上传进度后的居中提示
Future<void> showUploadCancelledDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: MatrixDialogStyle.outlineMuted(),
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.cancel_outlined,
            color: AppColors.textSecondary,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              S.snackUploadCancelled,
              style: AppTextStyles.body(
                size: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.bgDark,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            S.btnConfirm,
            style: AppTextStyles.body(color: AppColors.bgDark),
          ),
        ),
      ],
    ),
  );
}
