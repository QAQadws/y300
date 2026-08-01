import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Phase 3 keeps the production edit entry on WebView until native submit is
/// implemented in Phase 5. Tests/internal builds can override this provider.
/// Native post editing is the production path in Phase 5. Unsupported or
/// untrusted forms still fail closed to the WebView fallback.
final postEditNativeEntryGateProvider = Provider<bool>((ref) => true);
