import 'package:flutter/material.dart';
import 'package:y300/features/comic/presentation/widgets/add_to_shelf_button.dart';

/// 通用候选入架操作行。
///
/// 用于 thread_detail 中漫画/小说等不同内容类型的“候选 + 入架”交互，
/// 统一布局与按钮行为，避免不同模块各自维护一份 UI。
class CandidateShelfActionRow extends StatelessWidget {
  const CandidateShelfActionRow({
    super.key,
    required this.label,
    required this.inShelf,
    required this.isLoading,
    required this.onPressed,
  });

  final String label;
  final bool inShelf;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        AddToShelfButton(
          inShelf: inShelf,
          onPressed: isLoading ? null : onPressed,
        ),
      ],
    );
  }
}
