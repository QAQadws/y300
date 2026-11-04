import 'package:flutter/widgets.dart';

bool forumHtmlValidImageSize(Size size) =>
    size.width.isFinite &&
    size.height.isFinite &&
    size.width > 0 &&
    size.height > 0;

Widget forumHtmlClipImage(Widget child) => ClipRRect(
  borderRadius: const BorderRadius.all(Radius.circular(4)),
  clipBehavior: Clip.antiAlias,
  child: child,
);
