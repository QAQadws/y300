import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:y300/app/theme/app_theme.dart';

/// 通用骨架块，供启动页和列表加载态复用。
class SkeletonBlock extends StatelessWidget {
  const SkeletonBlock({
    super.key,
    required this.height,
    this.width,
    this.borderRadius = 12,
  });

  final double height;
  final double? width;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// 论坛首页加载态骨架。
class ForumHomeSkeleton extends StatelessWidget {
  const ForumHomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: 4,
      separatorBuilder: (_, index) => const SizedBox(height: 12),
      itemBuilder: (_, index) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBlock(height: 18, width: 160),
              SizedBox(height: 10),
              SkeletonBlock(height: 14),
              SizedBox(height: 8),
              SkeletonBlock(height: 14, width: 220),
            ],
          ),
        );
      },
    );
  }
}

Widget appSkeletonPreviewShell(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: SafeArea(child: child),
    ),
  );
}

@Preview(
  name: 'Skeleton block',
  group: 'Shared/AppSkeleton',
  size: Size(220, 120),
  wrapper: appSkeletonPreviewShell,
)
Widget skeletonBlockPreview() {
  return const Center(
    child: SkeletonBlock(
      height: 18,
      width: 160,
    ),
  );
}

@Preview(
  name: 'Forum home skeleton',
  group: 'Shared/AppSkeleton',
  size: Size(393, 852),
  wrapper: appSkeletonPreviewShell,
)
Widget forumHomeSkeletonPreview() {
  return const ForumHomeSkeleton();
}
