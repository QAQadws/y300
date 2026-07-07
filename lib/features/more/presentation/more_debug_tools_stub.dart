import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MoreDebugTools {
  const MoreDebugTools();

  bool watchDiagnosticEnabled(WidgetRef ref) => false;

  String aboutSubtitle(WidgetRef ref) => '应用信息';

  Future<void> handleAboutTap(BuildContext context, WidgetRef ref) async {}

  List<Widget> buildTiles(BuildContext context, WidgetRef ref) {
    return const <Widget>[];
  }
}
