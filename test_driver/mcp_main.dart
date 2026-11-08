import 'package:flutter_driver/driver_extension.dart';
import 'package:y300/main.dart' as app;

/// MCP interaction entrypoint; the production entrypoint stays driver-free.
Future<void> main() async {
  enableFlutterDriverExtension();
  await app.main();
}
