// lib/call_screen.dart

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' hide MessageType;

import 'package:hiddenly/chat_data.dart';
import 'package:hiddenly/chat_models.dart';
import 'package:hiddenly/call_waiting.dart';
import 'package:hiddenly/core/api_client.dart';
import 'package:hiddenly/core/config/app_config.dart';
import 'package:hiddenly/core/call/call_socket_service.dart';
import 'package:hiddenly/core/call/call_overlay_controller.dart';
import 'package:hiddenly/core/call/call_provider.dart';
import 'package:hiddenly/core/call/call_state.dart';
import 'package:hiddenly/core/call/global_call_handler.dart';
import 'package:hiddenly/core/call/group_call_view.dart';

class CallScreen extends ConsumerStatefulWidget {
  final String name;
  final String avatarUrl;
  final bool isVideoCall;
  final ChatItem? chat;
  final String currentUserName;
  final String currentUserAvatar;

  final String currentUserId;
  final String receiverId;
  final bool isCaller;
  final Map<String, dynamic>? incomingOffer;
  final String? conversationId;
  final String? callId;

  final bool resumeExistingCall;
  final bool isGroupCall;

  const CallScreen({
    super.key,
    required this.name,
    required this.avatarUrl,
    required this.isVideoCall,
    this.chat,
    required this.currentUserId,
    required this.receiverId,
    required this.isCaller,
    this.incomingOffer,
    this.conversationId,
    this.callId,
    required this.currentUserName,
    required this.currentUserAvatar,
    this.resumeExistingCall = false,
    this.isGroupCall = false,
  });

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  static const double _previewWidth = 110;
  static const double _previewHeight = 170;
  static const double _previewMargin = 16;

  bool _didStart = false;
  bool _didSaveCallResult = false;
  bool _didPop = false;
  bool _upgradeDialogShowing = false;
  bool _isDisposed = false;

  bool _connectingAcceptedCallSocket = false;
  bool _sentAcceptedCallReady = false;

  bool _isLocalVideoMain = false;
  bool _isDraggingPreview = false;
  Offset? _previewOffset;

  ProviderSubscription<CallState>? _callListener;

  String _getRemoteDisplayName(CallState callState) {
    final receiverId = widget.receiverId.trim();

    if (widget.chat != null && receiverId.isNotEmpty) {
      final nickname = widget.chat!.memberNicknames[receiverId]?.trim() ?? '';

      if (nickname.isNotEmpty) {
        return nickname;
      }

      for (final member in widget.chat!.members) {
        if (member.id.toString().trim() == receiverId) {
          final memberName = member.name.trim();

          if (memberName.isNotEmpty) {
            return memberName;
          }
        }
      }
    }

    final stateName = callState.name?.trim() ?? '';

    if (stateName.isNotEmpty) {
      return stateName;
    }

    final widgetName = widget.name.trim();

    if (widgetName.isNotEmpty) {
      return widgetName;
    }

    return 'Unknown';
  }

  String _getDisplayName(CallState callState) {
    return _getRemoteDisplayName(callState);
  }

  String _fixAvatarUrl(String url) {
    final clean = url.trim();

    if (clean.isEmpty) return '';

    if (clean.startsWith('http://') || clean.startsWith('https://')) {
      return clean;
    }

    if (clean.startsWith('/')) {
      return '${AppConfig.serverUrl}$clean';
    }

    return '${AppConfig.serverUrl}/$clean';
  }

  String _getDisplayAvatarUrl(CallState callState) {
    final stateAvatar = callState.avatarUrl;

    if (stateAvatar != null && stateAvatar.trim().isNotEmpty) {
      return _fixAvatarUrl(stateAvatar);
    }

    return _fixAvatarUrl(widget.avatarUrl);
  }

  String _getCurrentUserAvatarUrl() {
    return _fixAvatarUrl(widget.currentUserAvatar);
  }

  Map<String, dynamic>? _normalizedIncomingOffer() {
    final raw = widget.incomingOffer;

    if (raw == null) {
      return null;
    }

    final rawPayload = raw['payload'];

    if (rawPayload is Map) {
      final payload = Map<String, dynamic>.from(rawPayload);
      final nestedPayloadOffer = payload['offer'];

      if (nestedPayloadOffer is Map) {
        final offer = Map<String, dynamic>.from(nestedPayloadOffer);

        final type = offer['type']?.toString() ?? '';
        final sdp = offer['sdp']?.toString() ?? '';

        if (type.trim().isNotEmpty && sdp.trim().isNotEmpty) {
          return offer;
        }
      }

      final payloadType = payload['type']?.toString() ?? '';
      final payloadSdp = payload['sdp']?.toString() ?? '';

      if (payloadType.trim().isNotEmpty && payloadSdp.trim().isNotEmpty) {
        return {
          'type': payloadType,
          'sdp': payloadSdp,
        };
      }
    }

    final nestedOffer = raw['offer'];

    if (nestedOffer is Map) {
      final offer = Map<String, dynamic>.from(nestedOffer);

      final type = offer['type']?.toString() ?? '';
      final sdp = offer['sdp']?.toString() ?? '';

      if (type.trim().isNotEmpty && sdp.trim().isNotEmpty) {
        return offer;
      }
    }

    final type = raw['type']?.toString() ?? '';
    final sdp = raw['sdp']?.toString() ?? '';

    if (type.trim().isNotEmpty && sdp.trim().isNotEmpty) {
      return {
        'type': type,
        'sdp': sdp,
      };
    }

    return null;
  }

  bool _receiverHasValidOffer() {
    if (widget.isCaller) {
      return true;
    }

    final offer = _normalizedIncomingOffer();

    if (offer == null) {
      return false;
    }

    final type = offer['type']?.toString() ?? '';
    final sdp = offer['sdp']?.toString() ?? '';

    return type.trim().isNotEmpty && sdp.trim().isNotEmpty;
  }

  void _safePopOrLog(String reason) {
    if (_isDisposed || !mounted) return;

    final navigator = Navigator.of(context);

    if (navigator.canPop()) {
      debugPrint('$reason: popping call route');
      navigator.pop();
      return;
    }

    debugPrint('$reason: navigator cannot pop, staying in app');
  }

  void _closeInvalidReceiverCall() {
    if (!mounted || _didPop) return;

    debugPrint(
      'CALL SCREEN BLOCKED: receiver opened without valid WebRTC SDP offer.',
    );
    debugPrint('CALL SCREEN incomingOffer: ${widget.incomingOffer}');
    debugPrint('CALL SCREEN conversationId: ${widget.conversationId}');
    debugPrint('CALL SCREEN callId: ${widget.callId}');
    debugPrint('CALL SCREEN receiverId: ${widget.receiverId}');

    final conversationId = widget.conversationId ?? widget.chat?.id;

    if (conversationId == null || conversationId.toString().trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Call connection not ready. Conversation missing.'),
        ),
      );

      Future.delayed(const Duration(milliseconds: 700), () {
        if (!mounted || _didPop) return;

        _didPop = true;
        _safePopOrLog('CALL SCREEN INVALID RECEIVER');
      });

      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Waiting for caller offer...'),
      ),
    );

    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted || _didPop) return;

      _didPop = true;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CallWaitingScreen(
            currentUserId: widget.currentUserId,
            currentUserName: widget.currentUserName,
            currentUserAvatar: widget.currentUserAvatar,
            callerId: widget.receiverId,
            callerName: widget.name,
            callerAvatar: widget.avatarUrl,
            isVideoCall: widget.isVideoCall,
            conversationId: conversationId.toString(),
            callId: widget.callId,
            chat: widget.chat,
            emitAcceptOnOpen: false,
          ),
        ),
      );
    });
  }

  Future<bool> _ensureSocketForAcceptedBackgroundCall() async {
    if (widget.isCaller) return true;

    final offer = _normalizedIncomingOffer();

    if (offer != null) return true;

    if (_connectingAcceptedCallSocket) {
      return SocketService.instance.isConnected;
    }

    final convId = widget.conversationId?.toString().trim() ??
        widget.chat?.id.toString().trim() ??
        '';

    if (convId.isEmpty) {
      debugPrint('CALL SCREEN ACCEPT SOCKET ERROR: conversationId empty');
      return false;
    }

    final parsedConversationId = int.tryParse(convId);

    if (parsedConversationId == null) {
      debugPrint(
        'CALL SCREEN ACCEPT SOCKET ERROR: invalid conversationId: $convId',
      );
      return false;
    }

    _connectingAcceptedCallSocket = true;

    try {
      String? accessToken = await ApiClient.storage.read(key: 'access');

      if (accessToken == null || accessToken.trim().isEmpty) {
        debugPrint('CALL SCREEN ACCEPT SOCKET: access empty, trying refresh');
        accessToken = await ApiClient.refreshAccessToken();
      }

      if (accessToken == null || accessToken.trim().isEmpty) {
        debugPrint('CALL SCREEN ACCEPT SOCKET ERROR: access token empty');
        return false;
      }

      final url = AppConfig.callSocketUrl(
        conversationId: parsedConversationId,
        token: accessToken.trim(),
      );

      debugPrint('========== CALL SCREEN ACCEPT SOCKET ==========');
      debugPrint('conversationId: $convId');
      debugPrint('currentUserId: ${widget.currentUserId}');
      debugPrint('callerId/receiverId: ${widget.receiverId}');
      debugPrint('callId: ${widget.callId ?? ''}');
      debugPrint('url: $url');
      debugPrint('==============================================');

      await SocketService.instance.connect(url: url);
      await Future.delayed(const Duration(milliseconds: 250));

      if (!SocketService.instance.isConnected) {
        debugPrint('CALL SCREEN ACCEPT SOCKET ERROR: socket not connected');
        return false;
      }

      debugPrint('CALL SCREEN ACCEPT SOCKET CONNECTED');
      return true;
    } catch (e, st) {
      debugPrint('CALL SCREEN ACCEPT SOCKET ERROR: $e');
      debugPrint(st.toString());
      return false;
    } finally {
      _connectingAcceptedCallSocket = false;
    }
  }

  void _sendCallReadyForAcceptedBackgroundCall() {
    if (widget.isCaller) return;

    final offer = _normalizedIncomingOffer();

    if (offer != null) return;

    if (_sentAcceptedCallReady) {
      debugPrint('CALL SCREEN CALL_READY IGNORED: already sent');
      return;
    }

    final convId = widget.conversationId?.toString().trim() ??
        widget.chat?.id.toString().trim() ??
        '';

    if (convId.isEmpty) {
      debugPrint('CALL SCREEN CALL_READY ERROR: conversationId empty');
      return;
    }

    if (widget.currentUserId.trim().isEmpty) {
      debugPrint('CALL SCREEN CALL_READY ERROR: currentUserId empty');
      return;
    }

    if (widget.receiverId.trim().isEmpty) {
      debugPrint('CALL SCREEN CALL_READY ERROR: receiverId/callerId empty');
      return;
    }

    _sentAcceptedCallReady = true;

    debugPrint('========== CALL SCREEN SENDING CALL_READY ==========');
    debugPrint('from/currentUserId: ${widget.currentUserId}');
    debugPrint('target/callerId: ${widget.receiverId}');
    debugPrint('conversationId: $convId');
    debugPrint('callId: ${widget.callId ?? ''}');
    debugPrint('===================================================');

    SocketService.instance.emit(
      CallSocketEvents.callReady,
      {
        'from': widget.currentUserId,
        'from_user': widget.currentUserId,
        'call_id': widget.callId,
        'callId': widget.callId,
        'conversation_id': convId,
        'conversationId': convId,
      },
      targetUser: widget.receiverId,
      conversationId: convId,
      queueIfDisconnected: true,
    );
  }


  void _setCallScreenVisibleAfterFirstFrame() {
    void applyVisible() {
      if (_isDisposed || !mounted) return;

      try {
        markCallScreenVisible(ref);
      } catch (e) {
        debugPrint('CALL SCREEN SET VISIBLE FLAG ERROR: $e');
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      applyVisible();

      // Extra safety for caller/sender side:
      // Sometimes lifecycle/provider flags update late and CallScreen becomes
      // SizedBox.shrink even though call/socket/WebRTC is active.
      Future.delayed(const Duration(milliseconds: 120), applyVisible);
      Future.delayed(const Duration(milliseconds: 350), applyVisible);
    });
  }

  void _setCallScreenDisposedSafely() {
    /*
      Do not update Riverpod provider synchronously inside dispose().
      Riverpod can throw:
      "Tried to modify a provider while the widget tree was building."

      So we schedule it after the current build/dispose cycle.
    */
    Future<void>(() {
      try {
        // Do not use ref if the widget is already disposed.
        // These flags are also cleared by minimize/end/auto-close before pop.
      } catch (_) {}
    });
  }

  void _clearCallOverlayFlagsNow({
    required bool callScreenVisible,
    required bool minimized,
  }) {
    if (_isDisposed || !mounted) return;

    try {
      if (!callScreenVisible && !minimized) {
        clearCallOverlayFlags(ref);
        GlobalCallHandler.instance.markCallScreenClosed();
        return;
      }

      ref.read(callScreenVisibleProvider.notifier).state = callScreenVisible;
      ref.read(callScreenMinimizedProvider.notifier).state = minimized;
      ref.read(forceCallPipSurfaceProvider.notifier).state = false;
      ref.read(openCallScreenFromPipProvider.notifier).state = false;
      ref.read(openingCallScreenProvider.notifier).state = false;
    } catch (e) {
      debugPrint('CALL SCREEN CLEAR FLAGS ERROR: $e');
    }
  }

  @override
  void initState() {
    super.initState();

    if (widget.isGroupCall) {
      return;
    }

    /*
      IMPORTANT:
      Do not modify Riverpod providers synchronously in initState().
      It crashes with:
      "Tried to modify a provider while the widget tree was building."

      So we mark CallScreen visible after the first frame.
    */
    _isDisposed = false;
    _setCallScreenVisibleAfterFirstFrame();

    _callListener = ref.listenManual<CallState>(
      callProvider,
      (previous, next) {
        if (_isDisposed || !mounted) return;

        _listenForAutoClose(next);

        if (_isDisposed || !mounted) return;

        if (next.hasPendingVideoUpgrade &&
            previous?.hasPendingVideoUpgrade != true) {
          _showVideoUpgradeRequestDialog(next);
        }

        if (next.isVideoUpgradeRejected &&
            previous?.isVideoUpgradeRejected != true) {
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Video request declined')),
          );

          ref.read(callProvider.notifier).clearVideoUpgradeRejectedFlag();
        }
      },
    );

    Future.microtask(() async {
      if (!mounted || _didStart) return;

      _didStart = true;

      debugPrint('CALL SCREEN BACKEND CALL ID: ${widget.callId}');
      debugPrint('CALL SCREEN IS CALLER: ${widget.isCaller}');
      debugPrint('CALL SCREEN RESUME EXISTING: ${widget.resumeExistingCall}');
      debugPrint('CALL SCREEN RAW INCOMING OFFER: ${widget.incomingOffer}');

      if (widget.resumeExistingCall) {
        return;
      }

      final offer = widget.isCaller ? null : _normalizedIncomingOffer();

      if (!widget.isCaller && offer == null) {
        final connected = await _ensureSocketForAcceptedBackgroundCall();

        if (!connected) {
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not connect call socket')),
          );

          Future.delayed(const Duration(milliseconds: 700), () {
            if (!mounted || _didPop) return;

            _didPop = true;
            _safePopOrLog('CALL SCREEN SOCKET CONNECT FAILED');
          });

          return;
        }
      }

      if (!mounted) return;

      await ref.read(callProvider.notifier).startCall(
            currentUserId: widget.currentUserId,
            currentUserName: widget.currentUserName,
            currentUserAvatar: widget.currentUserAvatar,
            receiverId: widget.receiverId,
            name: widget.name,
            avatarUrl: widget.avatarUrl,
            isVideoCall: widget.isVideoCall,
            isCaller: widget.isCaller,
            incomingOffer: offer,
            conversationId: widget.conversationId ?? widget.chat?.id,
            callId: widget.callId,
          );

      if (!widget.isCaller && offer == null) {
        await Future.delayed(const Duration(milliseconds: 1000));

       if (SocketService.instance.isConnected) {
       _sendCallReadyForAcceptedBackgroundCall();
      }
      }
    });
  }

  @override
  void dispose() {
    if (widget.isGroupCall) {
      super.dispose();
      return;
    }

    _isDisposed = true;

    try {
      _callListener?.close();
    } catch (_) {}

    _callListener = null;

    /*
      Do not modify providers here.
      Flags are cleared before pop in _minimizeCall, _endCall and _listenForAutoClose.
    */
    _setCallScreenDisposedSafely();

    super.dispose();
  }

  Future<void> _showVideoUpgradeRequestDialog(CallState callState) async {
    if (!mounted || _upgradeDialogShowing) return;

    _upgradeDialogShowing = true;

    final displayName = _getDisplayName(callState);

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Switch to video call?'),
          content: Text('$displayName wants to turn on video.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Decline'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Accept'),
            ),
          ],
        );
      },
    );

    _upgradeDialogShowing = false;

    if (!mounted) return;

    if (accepted == true) {
      await ref.read(callProvider.notifier).acceptVideoUpgrade();
    } else {
      await ref.read(callProvider.notifier).rejectVideoUpgrade();
    }
  }

  Future<void> _minimizeCall() async {
    final callState = ref.read(callProvider);

    if (_isFinalStatus(callState.status)) {
      return;
    }

    /*
      FINAL FLOW:
      - BACK from CallScreen never ends the call.
      - BACK only turns the active call into the in-app mini call overlay.
      - The route is popped so ChatList/Profile/previous screen is visible behind it.
      - MiniCallOverlay tap opens CallScreen(resumeExistingCall: true), so WebRTC/socket
        are reused and no waiting/opening screen appears.
    */
    try {
      minimizeCallInsideApp(ref);
      GlobalCallHandler.instance.markCallScreenClosed();
    } catch (e) {
      debugPrint('CALL SCREEN MINIMIZE ERROR: $e');
    }

    if (!mounted) return;

    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      debugPrint('CALL SCREEN MINIMIZE: popping call route, call continues');
      navigator.pop();
    } else {
      debugPrint('CALL SCREEN MINIMIZE: navigator cannot pop, staying on call route');
    }
  }

  void _swapVideoScreens(CallState callState) {
    if (!mounted) return;
    if (!callState.isVideoCall) return;
    if (_isFinalStatus(callState.status)) return;

    setState(() {
      _isLocalVideoMain = !_isLocalVideoMain;
    });
  }

  Future<void> _doubleTapSwitchCamera(CallState callState) async {
    if (!mounted) return;
    if (!callState.isVideoCall) return;
    if (_isFinalStatus(callState.status)) return;

    try {
      await ref.read(callProvider.notifier).switchCamera();
    } catch (e) {
      debugPrint('DOUBLE TAP SWITCH CAMERA ERROR: $e');
    }
  }

  Offset _defaultPreviewOffset(Size screenSize, EdgeInsets padding) {
    return Offset(
      screenSize.width - _previewWidth - _previewMargin,
      screenSize.height - _previewHeight - padding.bottom - 118,
    );
  }

  Offset _clampPreviewOffset(
    Offset offset,
    Size screenSize,
    EdgeInsets padding,
  ) {
    final minX = _previewMargin;
    final maxX = math.max(
      minX,
      screenSize.width - _previewWidth - _previewMargin,
    );

    final minY = padding.top + 64;
    final maxY = math.max(
      minY,
      screenSize.height - _previewHeight - padding.bottom - 106,
    );

    return Offset(
      offset.dx.clamp(minX, maxX).toDouble(),
      offset.dy.clamp(minY, maxY).toDouble(),
    );
  }

  Offset _snapPreviewOffset(
    Offset offset,
    Size screenSize,
    EdgeInsets padding,
  ) {
    final leftX = _previewMargin;
    final rightX = screenSize.width - _previewWidth - _previewMargin;

    final snapLeft = offset.dx + (_previewWidth / 2) < screenSize.width / 2;

    return _clampPreviewOffset(
      Offset(snapLeft ? leftX : rightX, offset.dy),
      screenSize,
      padding,
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
    }

    return '$minutes:$seconds';
  }

  String _callStatusText(CallState callState) {
    if (callState.isVideoUpgradeRequesting) {
      return 'Requesting video...';
    }

    if (callState.hasPendingVideoUpgrade) {
      return 'Video request received';
    }

    switch (callState.status) {
      case CallStatus.connected:
        return _formatDuration(callState.duration);
      case CallStatus.calling:
        return 'Calling...';
      case CallStatus.ringing:
        return 'Ringing...';
      case CallStatus.rejected:
        return 'Call rejected';
      case CallStatus.busy:
        return 'User busy';
      case CallStatus.timeout:
        return 'No answer';
      case CallStatus.missed:
        return 'Missed call';
      case CallStatus.failed:
        return 'Call failed';
      case CallStatus.ended:
        return 'Call ended';
      default:
        return widget.isCaller ? 'Calling...' : 'Connecting...';
    }
  }

  bool _isFinalStatus(CallStatus status) {
    return status == CallStatus.ended ||
        status == CallStatus.failed ||
        status == CallStatus.rejected ||
        status == CallStatus.busy ||
        status == CallStatus.timeout ||
        status == CallStatus.missed;
  }

  void _saveCallResultIfNeeded(CallState callState) {
    if (_didSaveCallResult) return;
    if (widget.chat == null) return;

    _didSaveCallResult = true;

    final isVideoCall = callState.isVideoCall;

    final answered = callState.duration.inSeconds > 0 ||
        callState.status == CallStatus.connected ||
        callState.status == CallStatus.ended;

    String text;

    if (callState.status == CallStatus.rejected) {
      text = isVideoCall ? 'Video call rejected' : 'Voice call rejected';
    } else if (callState.status == CallStatus.missed ||
        callState.status == CallStatus.timeout) {
      text = isVideoCall ? 'Missed video call' : 'Missed voice call';
    } else {
      text = isVideoCall ? 'Video call ended' : 'Voice call ended';
    }

    AppChatData.addMessage(
      widget.chat!,
      ChatMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        type: MessageType.call,
        text: text,
        isMe: widget.isCaller,
        sentAt: DateTime.now(),
        isSeen: true,
        callType: isVideoCall ? CallEntryType.video : CallEntryType.voice,
        callDuration: callState.duration,
        callAnswered: answered,
      ),
    );
  }

  Future<void> _endCall() async {
    if (_didPop || !mounted) return;

    final notifier = ref.read(callProvider.notifier);
    final callState = ref.read(callProvider);

    _clearCallOverlayFlagsNow(
      callScreenVisible: false,
      minimized: false,
    );

    _saveCallResultIfNeeded(callState);

    try {
      await notifier.endCall(emitSocket: true);
    } catch (e) {
      debugPrint('END CALL ERROR: $e');
    }

    if (!mounted || _didPop) return;

    _didPop = true;
    _safePopOrLog('CALL SCREEN END');
  }

  void _listenForAutoClose(CallState callState) {
    if (_isDisposed || !mounted) return;
    if (!_isFinalStatus(callState.status)) return;
    if (_didPop) return;

    _clearCallOverlayFlagsNow(
      callScreenVisible: false,
      minimized: false,
    );

    _saveCallResultIfNeeded(callState);

    Future.delayed(const Duration(milliseconds: 700), () {
      if (_isDisposed || !mounted || _didPop) return;

      _didPop = true;
      _safePopOrLog('CALL SCREEN AUTO CLOSE');
    });
  }

  Future<void> _handleVideoCameraButton(CallState callState) async {
    if (!mounted) return;
    if (_isFinalStatus(callState.status)) return;
    if (callState.status != CallStatus.connected) return;
    if (callState.hasPendingVideoUpgrade) return;

    try {
      final notifier = ref.read(callProvider.notifier);

      if (callState.isVideoCall) {
        notifier.toggleCamera();
      } else if (!callState.isVideoUpgradeRequesting) {
        await notifier.requestVideoUpgrade();
      }
    } catch (e) {
      debugPrint('Video/camera button UI error: $e');
    }
  }

  bool _isPipLikeSize(BoxConstraints constraints) {
    return constraints.maxWidth < 320 || constraints.maxHeight < 520;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isGroupCall) {
      final groupChat = widget.chat;

      if (groupChat == null) {
        return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: Text(
              'Group call error: chat missing',
              style: TextStyle(color: Colors.white),
            ),
          ),
        );
      }

      return GroupCallView(
        chat: groupChat,
        currentUserId: widget.currentUserId,
        currentUserName: widget.currentUserName,
        currentUserAvatar: widget.currentUserAvatar,
        isVideoCall: widget.isVideoCall,
        isCaller: widget.isCaller,
        callerId: widget.receiverId,
        incomingOffer: widget.incomingOffer,
        callId: widget.callId,
      );
    }

    final callState = ref.watch(callProvider);
    final isCallScreenVisible = ref.watch(callScreenVisibleProvider);

    /*
      Messenger-style restore flow:
      - Normal CallScreen open must always be visible.
      - Back/minimize hides this route and shows MiniCallOverlay.
      - Home/PiP hides normal controls and lets main/lifecycle show PiP surface.
      - Safety: if visibility is false by mistake during a fresh sender call,
        restore it automatically to prevent black screen while call is active.
    */
    if (!isCallScreenVisible) {
      final isReallyMinimized = ref.watch(callScreenMinimizedProvider);
      final isPipSurface = ref.watch(forceCallPipSurfaceProvider);

      if (!isReallyMinimized && !isPipSurface) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _isDisposed) return;
          markCallScreenVisible(ref);
        });
      }

      return const SizedBox.shrink();
    }

    final displayName = _getRemoteDisplayName(callState);
    final displayAvatarUrl = _getDisplayAvatarUrl(callState);
    final hasAvatar = displayAvatarUrl.trim().isNotEmpty;
    final isVideoCall = callState.isVideoCall;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (!didPop && mounted) {
          await _minimizeCall();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final isPipLike = _isPipLikeSize(constraints);

            return Stack(
              children: [
                Positioned.fill(
                  child: isVideoCall
                      ? _buildVideoMainBackground(
                          callState,
                          hasAvatar,
                          displayName,
                          displayAvatarUrl,
                        )
                      : _buildVoiceCallBackground(hasAvatar, displayAvatarUrl),
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: isPipLike
                            ? [
                                Colors.black.withOpacity(0.04),
                                Colors.black.withOpacity(0.12),
                              ]
                            : [
                                Colors.black.withOpacity(0.18),
                                Colors.black.withOpacity(0.40),
                                Colors.black.withOpacity(0.68),
                              ],
                      ),
                    ),
                  ),
                ),

                /*
                  Do not show the inner small camera preview inside PiP.
                  PiP is already a small window.
                */
                if (isVideoCall && !isPipLike)
                  _buildMovableVideoPreview(
                    callState,
                    hasAvatar,
                    displayName,
                    displayAvatarUrl,
                  ),

                /*
                  PiP mode: only show video/fallback.
                  Hide header, name, status, and buttons to avoid overflow.
                */
                if (!isPipLike)
                  SafeArea(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              _TopCircleButton(
                                icon: Icons.arrow_back,
                                asyncOnTap: _minimizeCall,
                              ),
                              const Spacer(),
                              if (isVideoCall)
                                _TopCircleButton(
                                  icon: Icons.flip_camera_ios_outlined,
                                  asyncOnTap: () async {
                                    if (!mounted) return;

                                    try {
                                      await ref
                                          .read(callProvider.notifier)
                                          .switchCamera();
                                    } catch (_) {}
                                  },
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (!isVideoCall) ...[
                          CircleAvatar(
                            radius: 52,
                            backgroundColor: const Color(0xFF1F2937),
                            backgroundImage:
                                hasAvatar ? NetworkImage(displayAvatarUrl) : null,
                            child: !hasAvatar
                                ? Text(
                                    displayName.isNotEmpty
                                        ? displayName[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 34,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(height: 18),
                        ],
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _callStatusText(callState),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.86),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 18,
                            runSpacing: 14,
                            children: [
                              _MessengerCallButton(
                                icon: callState.isMicOff
                                    ? Icons.mic_off_rounded
                                    : Icons.mic_none_rounded,
                                bgColor: const Color(0x33FFFFFF),
                                onTap: () {
                                  if (!mounted) return;

                                  try {
                                    ref.read(callProvider.notifier).toggleMic();
                                  } catch (_) {}
                                },
                              ),
                              _MessengerCallButton(
                                icon: callState.isSpeakerOn
                                    ? Icons.volume_up_rounded
                                    : Icons.volume_down_rounded,
                                bgColor: const Color(0x33FFFFFF),
                                onTap: () {
                                  if (!mounted) return;

                                  try {
                                    ref
                                        .read(callProvider.notifier)
                                        .toggleSpeaker();
                                  } catch (_) {}
                                },
                              ),
                              _MessengerCallButton(
                                icon: Icons.call_end_rounded,
                                bgColor: const Color(0xFFFF3B30),
                                size: 64,
                                iconSize: 30,
                                asyncOnTap: _endCall,
                              ),
                              _MessengerCallButton(
                                icon: callState.isVideoCall
                                    ? (callState.isCameraOff
                                        ? Icons.videocam_off_rounded
                                        : Icons.videocam_rounded)
                                    : Icons.videocam_rounded,
                                bgColor: const Color(0x33FFFFFF),
                                asyncOnTap: () async {
                                  await _handleVideoCameraButton(callState);
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildVideoMainBackground(
    CallState callState,
    bool hasRemoteAvatar,
    String remoteName,
    String remoteAvatarUrl,
  ) {
    if (_isLocalVideoMain) {
      return _buildLocalVideoBackground(callState);
    }

    return _buildRemoteVideoBackground(
      callState,
      hasRemoteAvatar,
      remoteName,
      remoteAvatarUrl,
    );
  }

  Widget _buildMovableVideoPreview(
    CallState callState,
    bool hasRemoteAvatar,
    String remoteName,
    String remoteAvatarUrl,
  ) {
    final media = MediaQuery.of(context);
    final screenSize = media.size;
    final padding = media.padding;

    final rawOffset = _previewOffset ??
        _defaultPreviewOffset(
          screenSize,
          padding,
        );

    final clampedOffset = _clampPreviewOffset(
      rawOffset,
      screenSize,
      padding,
    );

    return AnimatedPositioned(
      duration:
          _isDraggingPreview ? Duration.zero : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      left: clampedOffset.dx,
      top: clampedOffset.dy,
      width: _previewWidth,
      height: _previewHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _swapVideoScreens(callState);
        },
        onDoubleTap: () async {
          await _doubleTapSwitchCamera(callState);
        },
        onPanStart: (_) {
          setState(() {
            _isDraggingPreview = true;
          });
        },
        onPanUpdate: (details) {
          final current = _previewOffset ??
              _defaultPreviewOffset(
                screenSize,
                padding,
              );

          setState(() {
            _previewOffset = _clampPreviewOffset(
              current + details.delta,
              screenSize,
              padding,
            );
          });
        },
        onPanEnd: (_) {
          final current = _previewOffset ??
              _defaultPreviewOffset(
                screenSize,
                padding,
              );

          setState(() {
            _isDraggingPreview = false;
            _previewOffset = _snapPreviewOffset(
              current,
              screenSize,
              padding,
            );
          });
        },
        onPanCancel: () {
          setState(() {
            _isDraggingPreview = false;
          });
        },
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.22),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.32),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _isLocalVideoMain
                  ? _buildRemotePreviewContent(
                      callState,
                      hasRemoteAvatar,
                      remoteName,
                      remoteAvatarUrl,
                    )
                  : _buildLocalPreview(callState),
              Positioned(
                top: 7,
                right: 7,
                child: Container(
                  width: 25,
                  height: 25,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.42),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.touch_app_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRemoteVideoBackground(
    CallState callState,
    bool hasAvatar,
    String displayName,
    String displayAvatarUrl,
  ) {
    final remoteRenderer = callState.remoteRenderer;

    if (callState.isVideoCall &&
        !callState.isRemoteCameraOff &&
        !_isFinalStatus(callState.status) &&
        remoteRenderer != null &&
        remoteRenderer.srcObject != null) {
      return RTCVideoView(
        remoteRenderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }

    return _remoteCameraOffBackground(
      hasAvatar,
      displayName,
      displayAvatarUrl,
    );
  }

  Widget _buildRemotePreviewContent(
    CallState callState,
    bool hasAvatar,
    String displayName,
    String displayAvatarUrl,
  ) {
    final remoteRenderer = callState.remoteRenderer;

    if (callState.isVideoCall &&
        !callState.isRemoteCameraOff &&
        !_isFinalStatus(callState.status) &&
        remoteRenderer != null &&
        remoteRenderer.srcObject != null) {
      return RTCVideoView(
        remoteRenderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }

    return _previewFallback(
      avatarUrl: displayAvatarUrl,
      hasAvatar: hasAvatar,
      icon: Icons.person_rounded,
    );
  }

  Widget _buildLocalVideoBackground(CallState callState) {
    final localRenderer = callState.localRenderer;

    if (!_isFinalStatus(callState.status) &&
        !callState.isCameraOff &&
        localRenderer != null &&
        localRenderer.srcObject != null) {
      return RTCVideoView(
        localRenderer,
        mirror: true,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }

    final currentAvatar = _getCurrentUserAvatarUrl();
    final hasAvatar = currentAvatar.isNotEmpty;

    return _localCameraOffBackground(
      hasAvatar,
      currentAvatar,
      callState.isCameraOff ? 'Camera is off' : 'Starting camera...',
    );
  }

  Widget _localCameraOffBackground(
    bool hasAvatar,
    String displayAvatarUrl,
    String label,
  ) {
    return Container(
      color: const Color(0xFF111827),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasAvatar)
            Opacity(
              opacity: 0.25,
              child: Image.network(
                displayAvatarUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 46,
                      backgroundColor: const Color(0xFF1F2937),
                      backgroundImage:
                          hasAvatar ? NetworkImage(displayAvatarUrl) : null,
                      child: !hasAvatar
                          ? const Icon(
                              Icons.videocam_off_rounded,
                              color: Colors.white,
                              size: 32,
                            )
                          : null,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _remoteCameraOffBackground(
    bool hasAvatar,
    String displayName,
    String displayAvatarUrl,
  ) {
    return Container(
      color: const Color(0xFF111827),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasAvatar)
            Opacity(
              opacity: 0.25,
              child: Image.network(
                displayAvatarUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 46,
                      backgroundColor: const Color(0xFF1F2937),
                      backgroundImage:
                          hasAvatar ? NetworkImage(displayAvatarUrl) : null,
                      child: !hasAvatar
                          ? Text(
                              displayName.isNotEmpty
                                  ? displayName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Camera is off',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewFallback({
    required String avatarUrl,
    required bool hasAvatar,
    required IconData icon,
  }) {
    return Container(
      color: const Color(0xFF111827),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasAvatar)
            Opacity(
              opacity: 0.20,
              child: Image.network(
                avatarUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          Center(
            child: CircleAvatar(
              radius: 26,
              backgroundColor: const Color(0xFF374151),
              backgroundImage: hasAvatar ? NetworkImage(avatarUrl) : null,
              child: !hasAvatar
                  ? Icon(
                      icon,
                      color: Colors.white,
                      size: 24,
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceCallBackground(bool hasAvatar, String displayAvatarUrl) {
    // Keep audio calls clean. The previous implementation stretched the
    // contact avatar over the whole screen, creating an unwanted image/shadow
    // behind the profile photo and controls.
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF172033),
                Color(0xFF0D1422),
                Color(0xFF030712),
              ],
              stops: [0.0, 0.52, 1.0],
            ),
          ),
        ),
        Align(
          alignment: const Alignment(0, -0.62),
          child: IgnorePointer(
            child: Container(
              width: 310,
              height: 310,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF1877F2).withOpacity(0.16),
                    const Color(0xFF1877F2).withOpacity(0.05),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.48, 1.0],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLocalPreview(CallState callState) {
    final localRenderer = callState.localRenderer;

    if (_isFinalStatus(callState.status)) {
      return const SizedBox();
    }

    if (callState.isCameraOff) {
      return _previewFallback(
        avatarUrl: _getCurrentUserAvatarUrl(),
        hasAvatar: _getCurrentUserAvatarUrl().isNotEmpty,
        icon: Icons.videocam_off_rounded,
      );
    }

    if (localRenderer == null || localRenderer.srcObject == null) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.white,
          strokeWidth: 2.4,
        ),
      );
    }

    return RTCVideoView(
      localRenderer,
      mirror: true,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  }
}

class _MessengerCallButton extends StatelessWidget {
  final IconData icon;
  final Color bgColor;
  final VoidCallback? onTap;
  final Future<void> Function()? asyncOnTap;
  final double size;
  final double iconSize;

  const _MessengerCallButton({
    required this.icon,
    required this.bgColor,
    this.onTap,
    this.asyncOnTap,
    this.size = 56,
    this.iconSize = 26,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: asyncOnTap != null
          ? () async {
              await asyncOnTap!();
            }
          : onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: iconSize,
        ),
      ),
    );
  }
}

class _TopCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Future<void> Function()? asyncOnTap;

  const _TopCircleButton({
    required this.icon,
    this.onTap,
    this.asyncOnTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: asyncOnTap != null
          ? () async {
              await asyncOnTap!();
            }
          : onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.28),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }
} 