part of 'forum_body_inline_plan_preparation.dart';

/// One actual native inline row, with its original child/source plan. Text
/// roles remain text: an unbroken mixed word does not become a ruby/RT node.
/// This numeric value neither authorizes source coverage nor owns resources.
final class ForumBodyIntrinsicInlineMetrics {
  const ForumBodyIntrinsicInlineMetrics._(
    this.input,
    this.fragment,
    this.baseline,
  );
  final ForumBodyInlinePageContent input;
  final ForumBodyTextPageFragment fragment;
  final double baseline;
  Size get size => Size(fragment.width, fragment.height);
  int get nativeHandleCount => input.nativeHandleCountFor(fragment);
}
