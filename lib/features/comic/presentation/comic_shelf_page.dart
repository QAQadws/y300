import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/presentation/controllers/comic_shelf_controller.dart';

class ComicShelfPage extends ConsumerWidget {
  const ComicShelfPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(comicShelfControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('漫画书架'),
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('加载书架失败：$error', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('comic-shelf-retry-button'),
                  onPressed: () => ref.read(comicShelfControllerProvider.notifier).refresh(),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const Center(
              child: Text('书架还是空的，去帖子详情把喜欢的漫画加入书架吧'),
            );
          }

          return GridView.builder(
            key: const Key('comic-shelf-grid'),
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 2 / 3,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return _ComicGridTile(
                title: item.title,
                coverUrl: item.coverImageUrl,
              );
            },
          );
        },
      ),
    );
  }
}

class _ComicGridTile extends StatelessWidget {
  const _ComicGridTile({
    required this.title,
    required this.coverUrl,
  });

  final String title;
  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: coverUrl == null
                ? const Icon(Icons.image_not_supported_outlined)
                : Image.network(
                    coverUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(Icons.broken_image_outlined);
                    },
                  ),
          ),
          // 标题覆盖在封面底部，满足“图上叠字”的书架展示要求。
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x00000000),
                    Color(0xA6000000),
                    Color(0xCC000000),
                  ],
                ),
              ),
              child: _TwoLineEllipsisText(
                title,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TwoLineEllipsisText extends StatelessWidget {
  const _TwoLineEllipsisText(
    this.text, {
    this.style,
  });

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final defaultStyle = DefaultTextStyle.of(context).style;
        final effectiveStyle = style ?? defaultStyle;

        final painter = TextPainter(
          text: TextSpan(text: text, style: effectiveStyle),
          textDirection: Directionality.of(context),
          maxLines: 2,
          ellipsis: '···',
        )..layout(maxWidth: constraints.maxWidth);

        final displayText = painter.didExceedMaxLines
            ? _truncateToTwoLines(
                source: text,
                maxWidth: constraints.maxWidth,
                style: effectiveStyle,
                textDirection: Directionality.of(context),
              )
            : text;

        return Text(
          displayText,
          maxLines: 2,
          overflow: TextOverflow.clip,
          style: effectiveStyle,
        );
      },
    );
  }

  String _truncateToTwoLines({
    required String source,
    required double maxWidth,
    required TextStyle style,
    required TextDirection textDirection,
  }) {
    if (source.isEmpty) {
      return source;
    }

    var low = 0;
    var high = source.length;
    var best = '';

    while (low <= high) {
      final mid = (low + high) ~/ 2;
      final candidate = '${source.substring(0, mid)}···';
      final painter = TextPainter(
        text: TextSpan(text: candidate, style: style),
        textDirection: textDirection,
        maxLines: 2,
      )..layout(maxWidth: maxWidth);

      if (painter.didExceedMaxLines) {
        high = mid - 1;
      } else {
        best = candidate;
        low = mid + 1;
      }
    }

    return best.isEmpty ? '···' : best;
  }
}
