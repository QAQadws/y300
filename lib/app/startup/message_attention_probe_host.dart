import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/messages/application/message_attention_probe_runtime_provider.dart';

/// Owns foreground eligibility for optional calibration across all App routes.
class MessageAttentionProbeHost extends ConsumerStatefulWidget {
  const MessageAttentionProbeHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<MessageAttentionProbeHost> createState() =>
      _MessageAttentionProbeHostState();
}

class _MessageAttentionProbeHostState
    extends ConsumerState<MessageAttentionProbeHost>
    with WidgetsBindingObserver {
  final Object _host = Object();
  MessageAttentionProbeRuntime? _runtime;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ready = true;
      _sync();
    });
  }

  void _sync() {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _runtime?.setForeground(
      _ready && (lifecycle == null || lifecycle == AppLifecycleState.resumed),
      host: _host,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _sync();

  @override
  Widget build(BuildContext context) {
    final runtime = ref.watch(messageAttentionProbeRuntimeProvider);
    if (!identical(runtime, _runtime)) {
      _runtime?.setForeground(false, host: _host);
      _runtime = runtime;
      _sync();
    }
    return widget.child;
  }

  @override
  void dispose() {
    _runtime?.setForeground(false, host: _host);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
