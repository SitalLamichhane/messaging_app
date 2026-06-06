import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' hide MessageType;
import 'package:simple_pip_mode/simple_pip.dart';

import 'package:messaging_app/chat_data.dart';
import 'package:messaging_app/chat_models.dart';
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
    required this.currentUserName,
    required this.currentUserAvatar,
  });

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen>
    with WidgetsBindingObserver {
  bool _didStart = false;
  bool _didSaveCallResult = false;
  bool _didPop = false;
  bool _upgradeDialogShowing = false;

  ProviderSubscription<CallState>? _callListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _callListener = ref.listenManual<CallState>(
      callProvider,
      (previous, next) {
        _listenForAutoClose(next);

        if (next.hasPendingVideoUpgrade &&
            previous?.hasPendingVideoUpgrade != true) {
          _showVideoUpgradeRequestDialog();
        }

        if (next.isVideoUpgradeRejected &&
            previous?.isVideoUpgradeRejected != true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Video request declined')),
          );
          ref.read(callProvider.notifier).clearVideoUpgradeRejectedFlag();
        }
      },
    );

    Future.microtask(() {
      if (!mounted || _didStart) return;

      _didStart = true;

      ref.read(callProvider.notifier).startCall(
            currentUserId: widget.currentUserId,
            currentUserName: widget.currentUserName,
            currentUserAvatar: widget.currentUserAvatar,
            receiverId: widget.receiverId,
            name: widget.name,
            avatarUrl: widget.avatarUrl,
            isVideoCall: widget.isVideoCall,
            isCaller: widget.isCaller,
            incomingOffer: widget.incomingOffer,
            conversationId: widget.conversationId ?? widget.chat?.id,
          );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _callListener?.close();
    _callListener = null;

    final callState = ref.read(callProvider);

    if (_isFinalStatus(callState.status)) {
      try {
        ref.read(callProvider.notifier).disposeCall();
      } catch (_) {}
    }

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    final callState = ref.read(callProvider);

    if (state == AppLifecycleState.paused &&
        callState.isVideoCall &&
        !_isFinalStatus(callState.status)) {
      try {
        await SimplePip().enterPipMode();
      } catch (e) {
        debugPrint('PiP error: $e');
      }
    }
  }

  Future<void> _showVideoUpgradeRequestDialog() async {
    if (!mounted || _upgradeDialogShowing) return;

    _upgradeDialogShowing = true;

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Switch to video call?'),
          content: Text('${widget.name} wants to turn on video.'),
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
      await _endCall();
      return;
    }

    if (callState.isVideoCall) {
      try {
        await SimplePip().enterPipMode();
        return;
      } catch (e) {
        debugPrint('PiP minimize error: $e');
      }
    }

    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
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

    final callState = ref.read(callProvider);
    _saveCallResultIfNeeded(callState);

    try {
      await ref.read(callProvider.notifier).endCall(emitSocket: true);
    } catch (_) {}

    if (!mounted) return;

    _didPop = true;

    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  void _listenForAutoClose(CallState callState) {
    if (!_isFinalStatus(callState.status)) return;
    if (_didPop) return;

    _saveCallResultIfNeeded(callState);

    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted || _didPop) return;

      _didPop = true;

      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    });
  }

  Future<void> _switchAudioVideo(CallState callState) async {
    if (!mounted) return;
    if (_isFinalStatus(callState.status)) return;
    if (callState.status != CallStatus.connected) return;

    try {
      final notifier = ref.read(callProvider.notifier);

      if (callState.isVideoCall || callState.isVideoUpgradeRequesting) {
        await notifier.switchToAudioCall();
      } else {
        await notifier.requestVideoUpgrade();
      }
    } catch (e) {
      debugPrint('Switch audio/video UI error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callProvider);
    final hasAvatar = widget.avatarUrl.trim().isNotEmpty;
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
                  ? _buildRemoteVideoBackground(callState, hasAvatar)
                  : _buildVoiceCallBackground(hasAvatar),
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
                  if (!isVideoCall || callState.isCameraOff) ...[
                    CircleAvatar(
                      radius: 52,
                      backgroundColor: const Color(0xFF1F2937),
                      backgroundImage:
                          hasAvatar ? NetworkImage(widget.avatarUrl) : null,
                      child: !hasAvatar
                          ? Text(
                              widget.name.isNotEmpty
                                  ? widget.name[0].toUpperCase()
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
                    widget.name,
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
                          icon: callState.isVideoCall ||
                                  callState.isVideoUpgradeRequesting
                              ? Icons.call_rounded
                              : Icons.videocam_rounded,
                          bgColor: const Color(0x33FFFFFF),
                          asyncOnTap: () async {
                            await _switchAudioVideo(callState);
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

  Widget _buildRemoteVideoBackground(CallState callState, bool hasAvatar) {
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

    if (hasAvatar) {
      return Image.network(
        widget.avatarUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _emptyVideoBackground(),
      );
    }

    return _emptyVideoBackground();
  }

  Widget _emptyVideoBackground() {
    return Container(
      color: const Color(0xFF111827),
      child: const Center(
        child: Icon(
          Icons.person,
          color: Colors.white54,
          size: 90,
        ),
      ),
    );
  }

  Widget _buildVoiceCallBackground(bool hasAvatar) {
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
                  widget.avatarUrl,
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