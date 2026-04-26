import 'package:flutter/material.dart';
import 'package:y300/features/startup/presentation/startup_page.dart';

/// 应用根组件，仅负责主题与路由入口。
class Y300App extends StatelessWidget {
  const Y300App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Y300',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F7A8C)),
        useMaterial3: true,
      ),
      home: const StartupPage(),
    );
  }
}
