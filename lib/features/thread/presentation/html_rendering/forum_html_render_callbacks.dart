import 'dart:async';

import 'package:flutter/foundation.dart';

@immutable
class ForumHtmlRenderCallbacks {
  const ForumHtmlRenderCallbacks({this.onTapUrl});

  final FutureOr<bool> Function(String url)? onTapUrl;
}
