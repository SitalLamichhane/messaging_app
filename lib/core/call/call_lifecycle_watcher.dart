// lib/core/call/call_lifecycle_watcher.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simple_pip_mode/simple_pip.dart';

import 'package:messaging_app/core/call/call_overlay_controller.dart';
import 'package:messaging_app/core/call/call_provider.dart';
import 'package:messaging_app/core/call/call_state.dart';

class CallLifecycleWatcher extends ConsumerStatefulWidget {
  final Widget child;

  const CallLifecycleWatcher({
    super.key,
    required this.child,
  });

  @override
  ConsumerState<CallLifecycleWatcher> createState() =>
      _CallLifecycleWatcherState();
}

class _CallLifecycleWatcherState extends ConsumerState<CallLifecycleWatcher>
    with WidgetsBindingObserver {
  bool _enteringPip = false;
  bool _endingBecauseDetached = false;

  bool _isFinalStatus(CallStatus status) {
    return status == CallStatus.ended ||
        status == CallStatus.failed ||
        status == CallStatus.rejected ||
        status == CallStatus.busy ||
        status == CallStatus.timeout ||
        status == CallStatus.missed;
  }

  bool _hasActiveCall(CallState state) {
    final hasUsers = state.currentUserId?.trim().isNotEmpty == true &&
        state.receiverId?.trim().isNotEmpty == true;

    return hasUsers && !_isFinalStatus(state.status);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState lifecycleState) async {
    final callState = ref.read(callProvider);

    if (!_hasActiveCall(callState)) {
      return;
    }

    if (lifecycleState == AppLifecycleState.paused) {
      await _enterPipForBackground(callState);
      return;
    }

    if (lifecycleState == AppLifecycleState.detached) {
      await _endCallBecauseAppKilled();
      return;
    }
  }

  Future<void> _enterPipForBackground(CallState callState) async {
    if (_enteringPip) return;
    if (!callState.isVideoCall) return;
    if (_isFinalStatus(callState.status)) return;

    _enteringPip = true;

    try {
      await SimplePip().enterPipMode();
    } catch (e) {
      debugPrint('GLOBAL CALL PiP ERROR: $e');
    } finally {
      _enteringPip = false;
    }
  }

  Future<void> _endCallBecauseAppKilled() async {
    if (_endingBecauseDetached) return;

    final callState = ref.read(callProvider);

    if (!_hasActiveCall(callState)) {
      return;
    }

    _endingBecauseDetached = true;

    try {
      ref.read(callScreenMinimizedProvider.notifier).state = false;

      await ref.read(callProvider.notifier).endCall(
            emitSocket: true,
          );

      debugPrint('CALL ENDED BECAUSE APP DETACHED/KILLED');
    } catch (e) {
      debugPrint('END CALL ON APP KILLED ERROR: $e');
    } finally {
      _endingBecauseDetached = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}