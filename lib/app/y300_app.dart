import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/features/startup/presentation/startup_page.dart';

/// 应用根组件，仅负责主题与路由入口。
class Y300App extends StatelessWidget {
  const Y300App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Y300',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const StartupPage(),
    );
  }
}
