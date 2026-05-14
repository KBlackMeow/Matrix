import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'router.dart';
import 'localization.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: AppLanguageController.notifier,
      builder: (context, language, _) {
        return MaterialApp(
          title: S.appName,
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.dark(
              primary: AppColors.primary,
              surface: AppColors.bgDark,
              onSurface: AppColors.textPrimary,
              scrim: MatrixDialogStyle.barrier,
            ),
            brightness: Brightness.dark,
            useMaterial3: true,
            dialogTheme: DialogThemeData(
              backgroundColor: AppColors.bgElevated,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              shadowColor: Colors.transparent,
              shape: MatrixDialogStyle.outlinePrimary(0.26),
              alignment: Alignment.center,
              titleTextStyle: AppTextStyles.heading(
                size: 16,
                color: AppColors.textPrimary,
              ),
              contentTextStyle: AppTextStyles.body(size: 13),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 28,
                vertical: 40,
              ),
              iconColor: AppColors.primary,
            ),
            radioTheme: RadioThemeData(
              fillColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return AppColors.primary;
                }
                return AppColors.textMuted;
              }),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                textStyle: const TextStyle(fontSize: 14, inherit: false),
              ),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                textStyle: const TextStyle(fontSize: 14, inherit: false),
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                textStyle: const TextStyle(fontSize: 14, inherit: false),
              ),
            ),
          ),
          home: AppRouter.home,
        );
      },
    );
  }
}


