import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'clipboard_text_writer.dart';
import 'self_copy_fingerprint_registry.dart';

final clipboardSelfCopyFingerprintRegistryProvider =
    Provider<SelfCopyFingerprintRegistry>((ref) {
      return SelfCopyFingerprintRegistry();
    });

final clipboardTextWriterProvider = Provider<ClipboardTextWriter>((ref) {
  return PlatformClipboardTextWriter(
    selfCopyRegistry: ref.watch(clipboardSelfCopyFingerprintRegistryProvider),
  );
});
