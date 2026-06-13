// lib/call_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' hide MessageType;

import 'package:messaging_app/chat_data.dart';
import 'package:messaging_app/chat_models.dart';
import 'package:messaging_app/call_waiting.dart';
import 'package:messaging_app/core/api_client.dart';
import 'package:messaging_app/core/config/app_config.dart';
import 'package:messaging_app/core/call/call_socket_service.dart';
import 'package:messaging_app/core/call/call_overlay_controller.dart';
import 'package:messaging_app/core/call/call_provider.dart';
import 'package:messaging_app/core/call/call_state.dart';

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
  });

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  bool _didStart = false;
  bool _didSaveCallResult = false;
  bool _didPop = false;
  bool _upgradeDialogShowing = false;

  bool _connectingAcceptedCallSocket = false;
  bool _sentAcceptedCallReady = false;

  ProviderSubscription<CallState>? _callListener;

  String _getDisplayName(CallState callState) {
    final stateName = callState.name;

    if (stateName != null && stateName.trim().isNotEmpty) {
      return stateName.trim();
    }

    final widgetName = widget.name.trim();

    if (widgetName.isNotEmpty) {
      return widgetName;
    }

    return 'Unknown';
  }

  String _getDisplayAvatarUrl(CallState callState) {
    final stateAvatar = callState.avatarUrl;

    if (stateAvatar != null && stateAvatar.trim().isNotEmpty) {
      return stateAvatar.trim();
    }

    return widget.avatarUrl.trim();
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
    if (!mounted) return;

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

    /*
      If offer already exists, socket should already be connected from the
      normal IncomingCallScreen / CallWaitingScreen flow.
    */
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

    /*
      Only send call_ready when CallScreen was opened directly from
      killed/background ANSWER and no SDP offer exists yet.
    */
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

  @override
  void initState() {
    super.initState();

    ref.read(callScreenMinimizedProvider.notifier).state = false;

    _callListener = ref.listenManual<CallState>(
      callProvider,
      (previous, next) {
        _listenForAutoClose(next);

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

      /*
        Do not redirect receiver to CallWaitingScreen here.

        For killed/background ANSWER:
        - CallScreen opens directly.
        - CallScreen connects /ws/call/<conversation_id>/.
        - CallProvider starts without offer and waits for call_offer.
        - CallScreen sends call_ready after provider socket handlers are ready.
      */
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

      /*
        Send call_ready after CallProvider has registered call_offer handler.
        This avoids missing the caller's resent offer.
      */
      if (!widget.isCaller && offer == null) {
        await Future.delayed(const Duration(milliseconds: 200));
        _sendCallReadyForAcceptedBackgroundCall();
      }
    });
  }

  @override
  void dispose() {
    _callListener?.close();
    _callListener = null;
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
      if (mounted) {
        _safePopOrLog('CALL SCREEN MINIMIZE FINAL STATUS');
      }
      return;
    }

    /*
      Inside app:
      Show Messenger-like floating mini call screen.

      Do NOT call Android PiP here.
      Background/home PiP is handled globally by CallLifecycleWatcher.
    */
    ref.read(callScreenMinimizedProvider.notifier).state = true;

    if (mounted) {
      _safePopOrLog('CALL SCREEN MINIMIZE');
    }
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

    ref.read(callScreenMinimizedProvider.notifier).state = false;

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
    if (!_isFinalStatus(callState.status)) return;
    if (_didPop || !mounted) return;

    ref.read(callScreenMinimizedProvider.notifier).state = false;

    _saveCallResultIfNeeded(callState);

    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted || _didPop) return;

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

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callProvider);

    final displayName = _getDisplayName(callState);
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
        body: Stack(
          children: [
            Positioned.fill(
              child: isVideoCall
                  ? _buildRemoteVideoBackground(
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
                    colors: [
                      Colors.black.withOpacity(0.18),
                      Colors.black.withOpacity(0.40),
                      Colors.black.withOpacity(0.68),
                    ],
                  ),
                ),
              ),
            ),
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
                  Text(
                    displayName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
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
                  if (isVideoCall)
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Container(
                        margin: const EdgeInsets.only(right: 16, bottom: 18),
                        width: 110,
                        height: 170,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: const Color(0xFF111827),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.22),
                            width: 1,
                          ),
                        ),
                        child: _buildLocalPreview(callState),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
                              ref.read(callProvider.notifier).toggleSpeaker();
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
        ],
      ),
    );
  }

  Widget _buildVoiceCallBackground(bool hasAvatar, String displayAvatarUrl) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF111827),
            Color(0xFF0F172A),
            Color(0xFF030712),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: hasAvatar
          ? Center(
              child: Opacity(
                opacity: 0.12,
                child: Image.network(
                  displayAvatarUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildLocalPreview(CallState callState) {
    final localRenderer = callState.localRenderer;

    if (_isFinalStatus(callState.status)) {
      return const SizedBox();
    }

    if (callState.isCameraOff) {
      return const Center(
        child: Icon(
          Icons.videocam_off_rounded,
          color: Colors.white70,
          size: 34,
        ),
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