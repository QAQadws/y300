import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Phase 3 keeps the production edit entry on WebView until native submit is
/// implemented in Phase 5. Tests/internal builds can override this provider.
final postEditNativeEntryGateProvider = Provider<bool>((ref) => false);
