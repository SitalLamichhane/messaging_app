// lib/group/group_call_screen.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

class GroupCallScreen extends StatefulWidget {
  final String serverUrl;
  final String token;
  final String roomName;
  final bool startWithVideo;

  /*
    Both `serverUrl:` and the older `url:` argument are accepted.
    This keeps older call sites compatible while using one internal field.
  */
  const GroupCallScreen({
    super.key,
    String? serverUrl,
    String? url,
    required this.token,
    required this.roomName,
    this.startWithVideo = true,
  })  : serverUrl = serverUrl ?? url ?? '',
        assert(
          (serverUrl != null && serverUrl != '') ||
              (url != null && url != ''),
          'A LiveKit server URL is required.',
        );

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
  Room? _room;

  bool _isConnecting = true;
  bool _isLeaving = false;
  bool _microphoneEnabled = true;
  bool _cameraEnabled = true;
  bool _speakerEnabled = true;

  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _cameraEnabled = widget.startWithVideo;
    unawaited(_connect());
  }

  Future<void> _connect() async {
    if (widget.serverUrl.trim().isEmpty || widget.token.trim().isEmpty) {
      if (!mounted) return;

      setState(() {
        _isConnecting = false;
        _errorMessage = 'Group-call URL or token is missing.';
      });
      return;
    }

    final room = Room();

    room.addListener(_handleRoomChanged);
    _room = room;

    try {
      /*
        livekit_client 2.5 uses an instance method:
          final room = Room();
          await room.connect(url, token);

        Room.connect(...) is not a static constructor.
      */
      await room.connect(
        widget.serverUrl.trim(),
        widget.token.trim(),
      );

      final localParticipant = room.localParticipant;

      if (localParticipant == null) {
        throw StateError('LiveKit local participant was not created.');
      }

      await localParticipant.setMicrophoneEnabled(true);

      if (_cameraEnabled) {
        try {
          await localParticipant.setCameraEnabled(true);
        } catch (error) {
          debugPrint('GROUP CALL CAMERA START ERROR: $error');
          _cameraEnabled = false;
        }
      }

      if (!kIsWeb) {
        try {
          await room.setSpeakerOn(_speakerEnabled);
        } catch (error) {
          debugPrint('GROUP CALL SPEAKER ERROR: $error');
        }
      } else if (!room.canPlaybackAudio) {
        /*
          Chrome/Safari can require a user gesture before audio playback.
          The call screen was normally opened by a user tap, so this attempt
          succeeds in most cases. A retry button is also shown when needed.
        */
        try {
          await room.startAudio();
        } catch (error) {
          debugPrint('GROUP CALL WEB AUDIO START ERROR: $error');
        }
      }

      if (!mounted) return;

      setState(() {
        _isConnecting = false;
        _errorMessage = null;
      });
    } catch (error, stackTrace) {
      debugPrint('GROUP CALL CONNECT ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      room.removeListener(_handleRoomChanged);

      try {
        await room.disconnect();
      } catch (_) {}

      try {
        await room.dispose();
      } catch (_) {}

      if (_room == room) {
        _room = null;
      }

      if (!mounted) return;

      setState(() {
        _isConnecting = false;
        _errorMessage = _friendlyConnectionError(error);
      });
    }
  }

  String _friendlyConnectionError(Object error) {
    final text = error.toString();

    if (text.contains('401') || text.toLowerCase().contains('unauthorized')) {
      return 'The group-call token is invalid or expired.';
    }

    if (text.toLowerCase().contains('permission')) {
      return 'Camera or microphone permission was denied.';
    }

    return 'Could not connect to the group call.\n$text';
  }

  void _handleRoomChanged() {
    if (!mounted) return;
    setState(() {});
  }

  List<Participant> _participants(Room room) {
    final result = <Participant>[];

    final local = room.localParticipant;
    if (local != null) {
      result.add(local);
    }

    result.addAll(room.remoteParticipants.values);

    result.sort((a, b) {
      if (a.isSpeaking == b.isSpeaking) {
        return _participantName(a).compareTo(_participantName(b));
      }

      return a.isSpeaking ? -1 : 1;
    });

    return result;
  }

  String _participantName(Participant participant) {
    final name = participant.name.trim();
    if (name.isNotEmpty) return name;

    final identity = participant.identity.trim();
    if (identity.isNotEmpty) return identity;

    return 'Participant';
  }

  VideoTrack? _videoTrackFor(Participant participant) {
    /*
      livekit_client 2.5 returns a List here.
      Do not use `.values` on videoTrackPublications.
    */
    for (final publication in participant.videoTrackPublications) {
      final track = publication.track;

      if (!publication.muted && track is VideoTrack) {
        return track;
      }
    }

    return null;
  }

  bool _participantMicrophoneEnabled(Participant participant) {
    for (final publication in participant.audioTrackPublications) {
      if (!publication.muted) {
        return true;
      }
    }

    return false;
  }

  Future<void> _toggleMicrophone() async {
    final local = _room?.localParticipant;
    if (local == null) return;

    final next = !_microphoneEnabled;

    try {
      await local.setMicrophoneEnabled(next);

      if (!mounted) return;
      setState(() => _microphoneEnabled = next);
    } catch (error) {
      _showMessage('Could not change microphone: $error');
    }
  }

  Future<void> _toggleCamera() async {
    final local = _room?.localParticipant;
    if (local == null) return;

    final next = !_cameraEnabled;

    try {
      await local.setCameraEnabled(next);

      if (!mounted) return;
      setState(() => _cameraEnabled = next);
    } catch (error) {
      _showMessage('Could not change camera: $error');
    }
  }

  Future<void> _toggleSpeaker() async {
    final room = _room;
    if (room == null) return;

    if (kIsWeb) {
      try {
        await room.startAudio();
        _showMessage('Browser audio playback enabled');
      } catch (error) {
        _showMessage('Could not start browser audio: $error');
      }
      return;
    }

    final next = !_speakerEnabled;

    try {
      await room.setSpeakerOn(next);

      if (!mounted) return;
      setState(() => _speakerEnabled = next);
    } catch (error) {
      _showMessage('Could not change speaker: $error');
    }
  }

  Future<void> _switchCamera() async {
    final local = _room?.localParticipant;
    if (local == null || !_cameraEnabled) return;

    for (final publication in local.videoTrackPublications) {
      final track = publication.track;  

      if (track is LocalVideoTrack) {
        try {
          final options = track.currentOptions;

          if (options is! CameraCaptureOptions) {
            _showMessage('The active video track is not a camera track');
            return;
          }

          final nextPosition =
              options.cameraPosition == CameraPosition.front
                  ? CameraPosition.back
                  : CameraPosition.front;

          await track.setCameraPosition(nextPosition);
        } catch (error) {
          _showMessage('Could not switch camera: $error');
        }
        return;
      }
    }
  }

  Future<void> _leaveCall() async {
    if (_isLeaving) return;

    setState(() => _isLeaving = true);

    final room = _room;
    _room = null;

    if (room != null) {
      room.removeListener(_handleRoomChanged);

      try {
        await room.disconnect();
      } catch (error) {
        debugPrint('GROUP CALL DISCONNECT ERROR: $error');
      }

      try {
        await room.dispose();
      } catch (error) {
        debugPrint('GROUP CALL DISPOSE ERROR: $error');
      }
    }

    if (!mounted) return;

    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      setState(() => _isLeaving = false);
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    final room = _room;
    _room = null;

    if (room != null) {
      room.removeListener(_handleRoomChanged);

      unawaited(() async {
        try {
          await room.disconnect();
        } catch (_) {}

        try {
          await room.dispose();
        } catch (_) {}
      }());
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) {
          unawaited(_leaveCall());
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF05070A),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          titleSpacing: 18,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.roomName.trim().isEmpty
                    ? 'Group call'
                    : widget.roomName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                _isConnecting
                    ? 'Connecting…'
                    : '${room == null ? 0 : _participants(room).length} participant(s)',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.68),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          actions: [
            if (_cameraEnabled)
              IconButton(
                tooltip: 'Switch camera',
                onPressed: _switchCamera,
                icon: const Icon(Icons.flip_camera_ios_rounded),
              ),
            const SizedBox(width: 6),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: _buildBody(room),
              ),
              _buildControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(Room? room) {
    if (_isConnecting) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    final error = _errorMessage;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Colors.white,
                size: 58,
              ),
              const SizedBox(height: 18),
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _isConnecting = true;
                    _errorMessage = null;
                  });
                  unawaited(_connect());
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    if (room == null) {
      return const Center(
        child: Text(
          'Call is not available',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    final participants = _participants(room);

    if (participants.isEmpty) {
      return const Center(
        child: Text(
          'Waiting for participants…',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final columns = participants.length == 1
        ? 1
        : width >= 900
            ? 3
            : 2;

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: participants.length == 1 ? 0.78 : 0.76,
      ),
      itemCount: participants.length,
      itemBuilder: (context, index) {
        return _ParticipantTile(
          participant: participants[index],
          videoTrack: _videoTrackFor(participants[index]),
          microphoneEnabled:
              _participantMicrophoneEnabled(participants[index]),
          displayName: _participantName(participants[index]),
          isLocal: participants[index] is LocalParticipant,
        );
      },
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
      decoration: BoxDecoration(
        color: const Color(0xFF11141A),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.07)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _CallControlButton(
            tooltip: _microphoneEnabled ? 'Mute' : 'Unmute',
            icon: _microphoneEnabled
                ? Icons.mic_rounded
                : Icons.mic_off_rounded,
            onPressed: _toggleMicrophone,
          ),
          _CallControlButton(
            tooltip: kIsWeb
                ? 'Enable browser audio'
                : (_speakerEnabled ? 'Speaker off' : 'Speaker on'),
            icon: kIsWeb
                ? Icons.volume_up_rounded
                : (_speakerEnabled
                    ? Icons.volume_up_rounded
                    : Icons.volume_down_rounded),
            onPressed: _toggleSpeaker,
          ),
          _CallControlButton(
            tooltip: _cameraEnabled ? 'Turn camera off' : 'Turn camera on',
            icon: _cameraEnabled
                ? Icons.videocam_rounded
                : Icons.videocam_off_rounded,
            onPressed: _toggleCamera,
          ),
          _CallControlButton(
            tooltip: 'Leave call',
            icon: Icons.call_end_rounded,
            backgroundColor: const Color(0xFFFF3B30),
            size: 62,
            onPressed: _isLeaving ? null : _leaveCall,
          ),
        ],
      ),
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  final Participant participant;
  final VideoTrack? videoTrack;
  final bool microphoneEnabled;
  final String displayName;
  final bool isLocal;

  const _ParticipantTile({
    required this.participant,
    required this.videoTrack,
    required this.microphoneEnabled,
    required this.displayName,
    required this.isLocal,
  });

  @override
  Widget build(BuildContext context) {
    final speaking = participant.isSpeaking;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF171B22),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: speaking
              ? const Color(0xFF36D978)
              : Colors.white.withOpacity(0.08),
          width: speaking ? 3 : 1,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (videoTrack != null)
            VideoTrackRenderer(
              videoTrack!,
              fit: VideoViewFit.cover,
            )
          else
            _ParticipantPlaceholder(name: displayName),
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.48),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      isLocal ? '$displayName (You)' : displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: microphoneEnabled
                        ? Colors.black.withOpacity(0.48)
                        : const Color(0xFFD93025),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    microphoneEnabled
                        ? Icons.mic_rounded
                        : Icons.mic_off_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ParticipantPlaceholder extends StatelessWidget {
  final String name;

  const _ParticipantPlaceholder({required this.name});

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF273142),
            Color(0xFF10141B),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: CircleAvatar(
          radius: 42,
          backgroundColor: Colors.white.withOpacity(0.12),
          child: Text(
            initial,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _CallControlButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Future<void> Function()? onPressed;
  final Color backgroundColor;
  final double size;

  const _CallControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.backgroundColor = const Color(0xFF2A303A),
    this.size = 54,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: onPressed == null
            ? backgroundColor.withOpacity(0.45)
            : backgroundColor,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed == null
              ? null
              : () {
                  unawaited(onPressed!());
                },
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              color: Colors.white,
              size: size * 0.46,
            ),
          ),
        ),
      ),
    );
  }
}
