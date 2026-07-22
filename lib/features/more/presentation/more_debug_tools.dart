import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_quill_prototype_page.dart';
import 'package:y300/features/library_shared/presentation/controllers/sync_diagnostic_mode_controller.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_renderer_prototype_page.dart';
import 'package:y300/features/thread/presentation/thread_detail_diagnostic_controller.dart';

class MoreDebugTools {
  MoreDebugTools();

  static const int _diagnosticTapThreshold = 5;
  static const Duration _diagnosticTapWindow = Duration(seconds: 2);

  final List<DateTime> _aboutTapTimes = <DateTime>[];

  bool watchDiagnosticEnabled(WidgetRef ref) {
    if (!kDebugMode) {
      return false;
    }
    return ref.watch(syncDiagnosticModeControllerProvider).asData?.value ??
        false;
  }

  Future<void> handleAboutTap(BuildContext context, WidgetRef ref) async {
    if (!kDebugMode) {
      return;
    }
    final now = DateTime.now();
    _aboutTapTimes.add(now);
    _aboutTapTimes.removeWhere(
      (time) => now.difference(time) > _diagnosticTapWindow,
    );
    if (_aboutTapTimes.length < _diagnosticTapThreshold) {
      return;
    }
    _aboutTapTimes.clear();
    final enabled = await ref
        .read(syncDiagnosticModeControllerProvider.notifier)
        .toggle();
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            enabled ? '诊断日志模式已开启，后续会写入本地 diagnostics 日志' : '诊断日志模式已关闭',
          ),
        ),
      );
  }

  List<Widget> buildTiles(BuildContext context, WidgetRef ref) {
    if (!kDebugMode) {
      return const <Widget>[];
    }
    final diagnosticEnabled = watchDiagnosticEnabled(ref);
    final threadDiagnosticEnabled = diagnosticEnabled
        ? ref.watch(threadDetailDiagnosticControllerProvider).asData?.value ??
              false
        : false;
    return <Widget>[
      ListTile(
        key: const Key('more-composer-quill-prototype-entry'),
        leading: const Icon(Icons.edit_note_outlined),
        title: const Text('Quill Composer 原型'),
        subtitle: const Text('验证所见即所得到 Discuz BBCode 的转换'),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const ComposerQuillPrototypePage(),
            ),
          );
        },
      ),
      ListTile(
        key: const Key('more-html-renderer-prototype-entry'),
        leading: const Icon(Icons.article_outlined),
        title: const Text('HTML 正文渲染原型'),
        subtitle: const Text('验证复杂正文 HTML 的原生渲染'),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const ForumHtmlRendererPrototypePage(),
            ),
          );
        },
      ),
      if (diagnosticEnabled) ...[
        SwitchListTile(
          key: const Key('more-thread-detail-diagnostic-switch'),
          secondary: const Icon(Icons.bug_report_outlined),
          title: const Text('帖子详情滚动诊断'),
          subtitle: const Text('记录 entry 构建、render plan 和滚动操作'),
          value: threadDiagnosticEnabled,
          onChanged: (value) =>
              _setThreadDetailDiagnosticEnabled(context, ref, value),
        ),
        ListTile(
          key: const Key('more-thread-detail-diagnostic-copy-entry'),
          leading: const Icon(Icons.content_copy_outlined),
          title: const Text('复制帖子详情诊断日志'),
          subtitle: const Text('复制当前进程内最近的滚动诊断事件'),
          onTap: () => _copyThreadDetailDiagnosticLog(context, ref),
        ),
      ],
    ];
  }

  Future<void> _setThreadDetailDiagnosticEnabled(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    try {
      await ref
          .read(threadDetailDiagnosticControllerProvider.notifier)
          .setEnabled(enabled);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('帖子详情诊断设置失败：$error')));
    }
  }

  Future<void> _copyThreadDetailDiagnosticLog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final text = ref
        .read(threadDetailDiagnosticControllerProvider.notifier)
        .exportText();
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text.trim().isEmpty ? '暂无帖子详情诊断日志' : '帖子详情诊断日志已复制'),
      ),
    );
  }
}
