import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/auth/presentation/login_page.dart';
import 'package:y300/features/forum/presentation/forum_home_controller.dart';
import 'package:y300/features/more/presentation/data_storage_page.dart';

class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('更多')),
      body: ListView(
        children: [
          ListTile(
            key: const Key('more-login-entry'),
            leading: const Icon(Icons.login),
            title: const Text('登录'),
            subtitle: const Text('登录论坛账号并同步登录状态'),
            onTap: () async {
              final result = await Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(builder: (_) => const LoginPage()),
              );
              if (result == true) {
                ref.invalidate(forumHomeControllerProvider);
              }
            },
          ),
          ListTile(
            key: const Key('more-data-storage-entry'),
            leading: const Icon(Icons.storage_outlined),
            title: const Text('数据与存储'),
            subtitle: const Text('管理图片缓存与下载位置'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const DataStoragePage()),
              );
            },
          ),
          const ListTile(
            key: Key('more-reader-settings-placeholder'),
            leading: Icon(Icons.menu_book_outlined),
            title: Text('阅读设置（预留）'),
            subtitle: Text('后续阶段接入阅读器细项配置'),
          ),
          const ListTile(
            key: Key('more-about-placeholder'),
            leading: Icon(Icons.info_outline),
            title: Text('关于（预留）'),
            subtitle: Text('后续阶段补充版本与帮助信息'),
          ),
        ],
      ),
    );
  }
}
