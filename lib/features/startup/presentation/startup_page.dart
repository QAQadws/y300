import 'package:flutter/material.dart';
import 'package:y300/features/startup/presentation/main_shell_page.dart';

/// MVP 启动页：承担品牌展示和冷启动过渡
class StartupPage extends StatefulWidget {
  const StartupPage({super.key, this.onCompleted});

  /// 测试注入点：用于替代真实跳转动作。
  final VoidCallback? onCompleted;

  @override
  State<StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends State<StartupPage> {
  @override
  void initState() {
    super.initState();
    _startBootstrap();
  }

  Future<void> _startBootstrap() async {
    // 保证启动页至少可见一小段时间，避免闪屏。
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) {
      return;
    }

    if (widget.onCompleted != null) {
      widget.onCompleted!.call();
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const MainShellPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Y300',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '正在初始化论坛数据...',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
