import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hiddenly/group/group_api_service.dart';

import 'package:livekit_client/livekit_client.dart';

class GroupCallScreen extends StatefulWidget {
  final String callId;
  final String conversationId;
  final String groupName;
  final String serverUrl;
  final String token;
  final String roomName;
  final bool startWithVideo;

  const GroupCallScreen({
    super.key,
    required this.callId,
    required this.conversationId,
    required this.groupName,
    required this.serverUrl,
    required this.token,
    required this.roomName,
    required this.startWithVideo,
  });

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
  Room? _room;
  bool _connecting = true;
  bool _leaving = false;
  bool _mic = true;
  bool _camera = false;
  bool _speaker = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _camera = widget.startWithVideo;
    unawaited(_connect());
  }

  Future<void> _connect() async {
    // Keep the same Room() construction style as your current livekit_client 2.5 code.
    final room = Room();
    room.addListener(_changed);
    _room = room;
    try {
      await room.connect(widget.serverUrl, widget.token);
      final local = room.localParticipant;
      if (local == null) {
        throw StateError('LiveKit local participant was not created.');
      }
      await local.setMicrophoneEnabled(true);
      if (_camera) await local.setCameraEnabled(true);
      if (!kIsWeb) {
        try {
          await room.setSpeakerOn(true);
        } catch (_) {}
      }
      if (mounted) setState(() => _connecting = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = 'Could not join group call: $e';
        });
      }
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  List<Participant> _participants(Room room) {
    final list = <Participant>[?room.localParticipant, ...room.remoteParticipants.values];
    list.sort((a, b) {
      if (a.isSpeaking != b.isSpeaking) return a.isSpeaking ? -1 : 1;
      return _name(a).compareTo(_name(b));
    });
    return list;
  }

  String _name(Participant p) => p.name.trim().isNotEmpty ? p.name.trim() : p.identity;

  VideoTrack? _video(Participant p) {
    for (final pub in p.videoTrackPublications) {
      if (!pub.muted && pub.track is VideoTrack) return pub.track as VideoTrack;
    }
    return null;
  }

  Future<void> _toggleMic() async {
    final local = _room?.localParticipant;
    if (local == null) return;
    final next = !_mic;
    await local.setMicrophoneEnabled(next);
    if (mounted) setState(() => _mic = next);
  }

  Future<void> _toggleCamera() async {
    final local = _room?.localParticipant;
    if (local == null) return;
    final next = !_camera;
    await local.setCameraEnabled(next);
    if (mounted) setState(() => _camera = next);
  }

  Future<void> _toggleSpeaker() async {
    final room = _room;
    if (room == null || kIsWeb) return;
    final next = !_speaker;
    await room.setSpeakerOn(next);
    if (mounted) setState(() => _speaker = next);
  }

  Future<void> _switchCamera() async {
    final local = _room?.localParticipant;
    if (local == null || !_camera) return;
    for (final pub in local.videoTrackPublications) {
      final track = pub.track;
      if (track is LocalVideoTrack) {
        final options = track.currentOptions;
        if (options is CameraCaptureOptions) {
          await track.setCameraPosition(
            options.cameraPosition == CameraPosition.front
                ? CameraPosition.back
                : CameraPosition.front,
          );
        }
        return;
      }
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    try {
      await GroupApiService.leaveCall(widget.callId);
    } catch (_) {}
    final room = _room;
    _room = null;
    if (room != null) {
      room.removeListener(_changed);
      try { await room.disconnect(); } catch (_) {}
      try { await room.dispose(); } catch (_) {}
    }
    if (mounted) Navigator.maybePop(context);
  }

  @override
  void dispose() {
    final room = _room;
    _room = null;
    if (room != null) {
      room.removeListener(_changed);
      unawaited(room.disconnect());
      unawaited(room.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    final participants = room == null ? <Participant>[] : _participants(room);
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF111B21),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.groupName, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                _connecting ? 'Connecting…' : '${participants.length} participant${participants.length == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
              ),
            ],
          ),
          actions: [
            if (_camera) IconButton(onPressed: _switchCamera, icon: const Icon(Icons.flip_camera_ios_outlined)),
          ],
        ),
        body: _connecting
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF00A884)))
            : _error.isNotEmpty
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error, style: const TextStyle(color: Colors.white))))
                : Column(
                    children: [
                      Expanded(
                        child: GridView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: participants.length,
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: participants.length <= 1 ? 1 : 2,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: .78,
                          ),
                          itemBuilder: (_, i) {
                            final p = participants[i];
                            final track = _video(p);
                            return Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF202C33),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (track != null)
                                    VideoTrackRenderer(track)
                                  else
                                    Center(
                                      child: CircleAvatar(
                                        radius: 38,
                                        child: Text(_name(p).isEmpty ? '?' : _name(p)[0].toUpperCase(), style: const TextStyle(fontSize: 28)),
                                      ),
                                    ),
                                  Positioned(
                                    left: 10,
                                    right: 10,
                                    bottom: 10,
                                    child: Row(children: [
                                      Expanded(
                                        child: Text(
                                          p is LocalParticipant ? '${_name(p)} (You)' : _name(p),
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (p.isSpeaking) const Icon(Icons.graphic_eq, color: Color(0xFF00A884)),
                                    ]),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      Container(
                        color: const Color(0xFF202C33),
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _CallButton(icon: _speaker ? Icons.volume_up : Icons.volume_off, onTap: _toggleSpeaker),
                            _CallButton(icon: _camera ? Icons.videocam : Icons.videocam_off, onTap: _toggleCamera),
                            _CallButton(icon: _mic ? Icons.mic : Icons.mic_off, onTap: _toggleMic),
                            _CallButton(icon: Icons.call_end, onTap: _leave, danger: true),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;

  const _CallButton({required this.icon, required this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(40),
      child: CircleAvatar(
        radius: 26,
        backgroundColor: danger ? Colors.red : const Color(0xFF344047),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}
