import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/settings/app_appearance_controller.dart';
import 'package:y300/app/settings/app_appearance_settings.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/features/startup/presentation/main_shell_page.dart';

/// 应用根组件，仅负责主题与路由入口。
class Y300App extends ConsumerWidget {
  const Y300App({
    super.key,
    this.home = const MainShellPage(),
  });

  final Widget home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appAppearanceControllerProvider).maybeWhen(
          data: (settings) => settings,
          orElse: AppAppearanceSettings.defaults,
        );
    return MaterialApp(
      title: 'Y300',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,
      home: home,
    );
  }
}
