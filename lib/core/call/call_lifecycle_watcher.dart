// lib/core/call/call_lifecycle_watcher.dart

import 'package:flutter/material.dart' hide AspectRatio;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simple_pip_mode/aspect_ratio.dart';
import 'package:simple_pip_mode/simple_pip.dart';

import 'package:messaging_app/call_screen.dart';
import 'package:messaging_app/core/call/call_overlay_controller.dart';
import 'package:messaging_app/core/call/call_provider.dart';
import 'package:messaging_app/core/call/call_state.dart';
import 'package:messaging_app/core/call/global_call_handler.dart';

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
  final SimplePip _pip = SimplePip();

  static const MethodChannel _nativePipChannel =
      MethodChannel('messaging_app/native_pip');

  ProviderSubscription<CallState>? _callStateSubscription;
  ProviderSubscription<bool>? _callScreenVisibleSubscription;
  ProviderSubscription<bool>? _callScreenMinimizedSubscription;
  ProviderSubscription<bool>? _forceCallPipSurfaceSubscription;

  bool _enteringPip = false;
  bool _openingFullCallFromPip = false;
  DateTime? _lastOpenCallScreenAt;

  static const AspectRatio _callPipRatio = (9, 16);

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

  /*
    HOME -> PiP is allowed only from:
    1. real CallScreen, or
    2. in-app mini call overlay.

    It is NOT allowed from ChatList/Profile/Settings unless the mini call
    overlay is already active. This prevents normal app screens from becoming
    PiP content.
  */
  bool _isCallUiActiveForHomePip() {
    final isCallScreenVisible = ref.read(callScreenVisibleProvider);
    final isMiniOverlayVisible = ref.read(callScreenMinimizedProvider);
    final isPreparingPip = ref.read(forceCallPipSurfaceProvider);

    return (isCallScreenVisible || isMiniOverlayVisible) && !isPreparingPip;
  }

  bool _nativeShouldTreatCallActive(CallState state) {
    return _hasActiveCall(state) && _isCallUiActiveForHomePip();
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    _nativePipChannel.setMethodCallHandler(_handleNativePipMethod);

    _callStateSubscription = ref.listenManual<CallState>(
      callProvider,
      (previous, next) {
        _syncNativeCallActive(next);

        if (!_hasActiveCall(next)) {
          _clearAllCallUiFlags();
        }
      },
    );

    _callScreenVisibleSubscription = ref.listenManual<bool>(
      callScreenVisibleProvider,
      (_, __) => _syncNativeCallActive(ref.read(callProvider)),
    );

    _callScreenMinimizedSubscription = ref.listenManual<bool>(
      callScreenMinimizedProvider,
      (_, __) => _syncNativeCallActive(ref.read(callProvider)),
    );

    _forceCallPipSurfaceSubscription = ref.listenManual<bool>(
      forceCallPipSurfaceProvider,
      (_, __) => _syncNativeCallActive(ref.read(callProvider)),
    );

    Future.microtask(() {
      if (!mounted) return;
      _syncNativeCallActive(ref.read(callProvider));
      _preparePip();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nativePipChannel.setMethodCallHandler(null);

    try {
      _callStateSubscription?.close();
    } catch (_) {}
    _callStateSubscription = null;

    try {
      _callScreenVisibleSubscription?.close();
    } catch (_) {}
    _callScreenVisibleSubscription = null;

    try {
      _callScreenMinimizedSubscription?.close();
    } catch (_) {}
    _callScreenMinimizedSubscription = null;

    try {
      _forceCallPipSurfaceSubscription?.close();
    } catch (_) {}
    _forceCallPipSurfaceSubscription = null;

    try {
      _nativePipChannel.invokeMethod('setCallActive', false);
    } catch (_) {}

    super.dispose();
  }

  Future<dynamic> _handleNativePipMethod(MethodCall call) async {
    final callState = ref.read(callProvider);

    debugPrint('NATIVE PIP METHOD: ${call.method}');
    debugPrint('ACTIVE CALL: ${_hasActiveCall(callState)}');
    debugPrint('CALL STATUS: ${callState.status}');
    debugPrint('CALLSCREEN VISIBLE: ${ref.read(callScreenVisibleProvider)}');
    debugPrint('MINI OVERLAY VISIBLE: ${ref.read(callScreenMinimizedProvider)}');
    debugPrint('FORCE PIP SURFACE: ${ref.read(forceCallPipSurfaceProvider)}');

    if (!_hasActiveCall(callState)) {
      _clearAllCallUiFlags();
      await _syncNativeCallActive(callState);
      return null;
    }

    if (call.method == 'onUserLeaveHint') {
      if (!_isCallUiActiveForHomePip()) {
        debugPrint(
          'HOME/PIP IGNORED: user is not on CallScreen or active mini overlay.',
        );
        await _syncNativeCallActive(callState);
        return null;
      }

      await _enterCallOnlyPip(callState);
      return null;
    }

    if (call.method == 'onPipExited' || call.method == 'onActivityResume') {
      final shouldOpen = ref.read(openCallScreenFromPipProvider) ||
          ref.read(forceCallPipSurfaceProvider) ||
          ref.read(appWasInPhonePipProvider);

      if (shouldOpen) {
        _openCallScreenAfterPip(callState);
      } else {
        debugPrint('PIP EXIT/RESUME IGNORED: no PiP-open flag set.');
      }
      return null;
    }

    if (call.method == 'onPipEntered') {
      debugPrint('CALL PIP ENTERED CONFIRMED BY ANDROID');
      return null;
    }

    return null;
  }

  Future<void> _preparePip() async {
    try {
      final isPipAvailable = await SimplePip.isPipAvailable;
      final isAutoPipAvailable = await SimplePip.isAutoPipAvailable;

      debugPrint('PIP available: $isPipAvailable');
      debugPrint('AUTO PIP available: $isAutoPipAvailable');
      debugPrint('AUTO PIP DISABLED: manual active-call PiP only');
    } catch (e) {
      debugPrint('PIP PREPARE ERROR: $e');
    }
  }

  Future<void> _syncNativeCallActive(CallState state) async {
    try {
      await _nativePipChannel.invokeMethod(
        'setCallActive',
        _nativeShouldTreatCallActive(state),
      );
    } catch (e) {
      debugPrint('NATIVE SET CALL ACTIVE ERROR: $e');
    }
  }

  void _setFlags({
    required bool callScreenVisible,
    required bool forceCallPipSurface,
    required bool openCallScreenFromPip,
    required bool minimized,
  }) {
    void apply() {
      if (!mounted) return;

      ref.read(callScreenVisibleProvider.notifier).state = callScreenVisible;
      ref.read(forceCallPipSurfaceProvider.notifier).state =
          forceCallPipSurface;
      ref.read(openCallScreenFromPipProvider.notifier).state =
          openCallScreenFromPip;
      ref.read(callScreenMinimizedProvider.notifier).state = minimized;
    }

    try {
      apply();
    } catch (e) {
      debugPrint('CALL UI FLAG SET FAILED, RETRY AFTER FRAME: $e');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          apply();
        } catch (e2) {
          debugPrint('CALL UI FLAG POST FRAME SET FAILED: $e2');
        }
      });
    }
  }

  @override
  Future<void> didChangeAppLifecycleState(
    AppLifecycleState lifecycleState,
  ) async {
    final callState = ref.read(callProvider);

    debugPrint('CALL LIFECYCLE STATE: $lifecycleState');
    debugPrint('ACTIVE CALL: ${_hasActiveCall(callState)}');
    debugPrint('CALL STATUS: ${callState.status}');

    await _syncNativeCallActive(callState);

    if (!_hasActiveCall(callState)) {
      _clearAllCallUiFlags();
      return;
    }

    if (lifecycleState == AppLifecycleState.resumed) {
      final shouldOpen = ref.read(openCallScreenFromPipProvider) ||
          ref.read(forceCallPipSurfaceProvider) ||
          ref.read(appWasInPhonePipProvider);

      if (shouldOpen) {
        _openCallScreenAfterPip(callState);
      }
      return;
    }

    if (lifecycleState == AppLifecycleState.detached) {
      debugPrint('CALL DETACHED: not ending call from Flutter');
      return;
    }
  }

  Future<void> _enterCallOnlyPip(CallState callState) async {
    if (_enteringPip) return;

    if (!_hasActiveCall(callState)) {
      _clearAllCallUiFlags();
      return;
    }

    if (!_isCallUiActiveForHomePip()) {
      debugPrint('CALL PIP IGNORED: user is not on call UI.');
      await _syncNativeCallActive(callState);
      return;
    }

    _enteringPip = true;
    final wasMiniOverlayOpen = ref.read(callScreenMinimizedProvider);

    try {
      debugPrint('HOME FROM CALLSCREEN/MINI OVERLAY -> CALL ONLY PIP');

      await _syncNativeCallActive(callState);

      /*
        Force main.dart to draw only the call surface BEFORE Android captures
        PiP. This prevents ChatList/Profile/Settings from appearing in PiP.
      */
      preparePhoneHomePip(ref);

      await Future.delayed(const Duration(milliseconds: 90));

      if (!_hasActiveCall(ref.read(callProvider))) {
        debugPrint('CALL PIP CANCELLED: call ended before entering PiP');
        _clearAllCallUiFlags();
        return;
      }

      bool nativeEntered = false;
      try {
        nativeEntered =
            await _nativePipChannel.invokeMethod<bool>('enterCallPip') ?? false;
      } catch (e) {
        debugPrint('NATIVE ENTER PIP ERROR: $e');
      }

      if (nativeEntered) {
        debugPrint('CALL PIP ENTERED BY NATIVE MAINACTIVITY');
        return;
      }

      final isPipAvailable = await SimplePip.isPipAvailable;
      if (!isPipAvailable) {
        debugPrint('CALL PIP FAILED: PiP not available');
        _restoreAfterFailedPip(wasMiniOverlayOpen);
        return;
      }

      await _pip.enterPipMode(
        aspectRatio: _callPipRatio,
        autoEnter: false,
        seamlessResize: true,
      );

      debugPrint('CALL PIP ENTERED BY SIMPLE_PIP FALLBACK');
    } catch (e, st) {
      debugPrint('CALL PIP ENTER ERROR: $e');
      debugPrint(st.toString());
      _restoreAfterFailedPip(wasMiniOverlayOpen);
    } finally {
      _enteringPip = false;
    }
  }

  void _restoreAfterFailedPip(bool wasMiniOverlayOpen) {
    if (wasMiniOverlayOpen) {
      _setFlags(
        callScreenVisible: false,
        forceCallPipSurface: false,
        openCallScreenFromPip: false,
        minimized: true,
      );
    } else {
      _setFlags(
        callScreenVisible: true,
        forceCallPipSurface: false,
        openCallScreenFromPip: false,
        minimized: false,
      );
    }
  }

  void _openCallScreenAfterPip(CallState callState) {
    if (!_hasActiveCall(callState)) {
      _clearAllCallUiFlags();
      return;
    }

    /*
      Temporary call-only surface is allowed only while we push CallScreen.
      The permanent black-screen bug happens when forceCallPipSurface remains
      true after the route is already pushed. So _openFullCallScreenFromPip()
      always clears forceCallPipSurface immediately after push starts.
    */
    _setFlags(
      callScreenVisible: false,
      forceCallPipSurface: true,
      openCallScreenFromPip: false,
      minimized: false,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openFullCallScreenFromPip(ref.read(callProvider));
    });
  }

  Future<void> _openFullCallScreenFromPip(CallState callState) async {
    if (!_hasActiveCall(callState)) {
      _clearAllCallUiFlags();
      return;
    }

    final now = DateTime.now();
    if (_lastOpenCallScreenAt != null &&
        now.difference(_lastOpenCallScreenAt!).inMilliseconds < 700) {
      debugPrint('OPEN CALLSCREEN FROM PIP SKIPPED: debounce');
      _clearStuckPipSurfaceButKeepCall(callState);
      return;
    }

    if (_openingFullCallFromPip || ref.read(openingCallScreenProvider)) {
      debugPrint('OPEN CALLSCREEN FROM PIP SKIPPED: already opening');
      _clearStuckPipSurfaceButKeepCall(callState);
      return;
    }

    _lastOpenCallScreenAt = now;
    _openingFullCallFromPip = true;

    if (!lockCallScreenOpening(ref)) {
      _openingFullCallFromPip = false;
      return;
    }

    debugPrint('PIP ZOOM/TAP -> ONE CALLSCREEN RESUME');

    NavigatorState? navigator;
    for (int attempt = 0; attempt < 20; attempt++) {
      navigator = GlobalCallHandler.navigatorKey.currentState;
      if (navigator != null && navigator.mounted) break;

      debugPrint('PIP ZOOM WAITING NAVIGATOR: attempt ${attempt + 1}');
      await Future.delayed(const Duration(milliseconds: 80));
    }

    if (navigator == null || !navigator.mounted) {
      debugPrint('OPEN CALLSCREEN FROM PIP ERROR: navigator still null');
      _openingFullCallFromPip = false;
      unlockCallScreenOpening(ref);
      _clearStuckPipSurfaceButKeepCall(callState);
      return;
    }

    try {
      // IMPORTANT:
      // Do NOT use pushAndRemoveUntil here. It can remove/replace routes while
      // the call providers/renderers are still active and can create black
      // screen or duplicate navigation state. We push exactly one resume route.
      await navigator.push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => CallScreen(
            name: callState.name?.trim().isNotEmpty == true
                ? callState.name!.trim()
                : 'Unknown',
            avatarUrl: callState.avatarUrl?.trim() ?? '',
            isVideoCall: callState.isVideoCall,
            currentUserId: callState.currentUserId?.trim() ?? '',
            currentUserName: '',
            currentUserAvatar: '',
            receiverId: callState.receiverId?.trim() ?? '',
            isCaller: callState.isCaller,
            incomingOffer: null,
            conversationId: null,
            callId: null,
            resumeExistingCall: true,
          ),
        ),
      );
    } catch (e, st) {
      debugPrint('OPEN CALLSCREEN FROM PIP PUSH ERROR: $e');
      debugPrint(st.toString());
      _clearStuckPipSurfaceButKeepCall(callState);
    } finally {
      if (mounted) {
        markCallScreenVisible(ref);
      }

      Future.delayed(const Duration(milliseconds: 450), () {
        if (!mounted) return;
        _openingFullCallFromPip = false;
        unlockCallScreenOpening(ref);
      });
    }
  }

  void _clearStuckPipSurfaceButKeepCall(CallState callState) {
    if (!_hasActiveCall(callState)) {
      _clearAllCallUiFlags();
      return;
    }

    _setFlags(
      callScreenVisible: false,
      forceCallPipSurface: false,
      openCallScreenFromPip: false,
      minimized: true,
    );
  }

  void _clearAllCallUiFlags() {
    _setFlags(
      callScreenVisible: false,
      forceCallPipSurface: false,
      openCallScreenFromPip: false,
      minimized: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
