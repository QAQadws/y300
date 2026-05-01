import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/auth/presentation/login_controller.dart';
import 'package:y300/features/auth/presentation/login_state.dart';
import 'package:y300/features/forum/presentation/forum_home_controller.dart';

class LoginPage extends ConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(loginControllerProvider);
    final controller = ref.read(loginControllerProvider.notifier);
    final state = asyncState.value ?? LoginPageState.initial();

    return Scaffold(
      appBar: AppBar(title: const Text('登录')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const Key('login-username-field'),
            decoration: const InputDecoration(
              labelText: '用户名',
              hintText: '请输入论坛账号',
              border: OutlineInputBorder(),
            ),
            onChanged: controller.updateUsername,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('login-password-field'),
            decoration: const InputDecoration(
              labelText: '密码',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
            onChanged: controller.updatePassword,
          ),
          const SizedBox(height: 14),
          FilledButton(
            key: const Key('login-submit-button'),
            onPressed: state.isSubmitting
                ? null
                : () async {
                    final success = await controller.submit();
                    if (success && context.mounted) {
                      // 登录成功后主动刷新论坛首页，确保首页登录态立即生效。
                      ref.invalidate(forumHomeControllerProvider);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('登录成功')),
                      );
                      Navigator.of(context).pop(true);
                    }
                  },
            child: state.isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('登录'),
          ),
          if (state.errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              state.errorMessage!,
              key: const Key('login-error-text'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (state.successMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              state.successMessage!,
              key: const Key('login-success-text'),
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ],
        ],
      ),
    );
  }
}
