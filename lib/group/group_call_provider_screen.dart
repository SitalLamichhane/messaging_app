import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hiddenly/core/group%20provider/group_call_provider.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:provider/provider.dart';


/// Rendering-only call screen. GroupCallProvider owns Room and call lifecycle.
class GroupCallProviderScreen extends StatelessWidget {
  final String groupName;

  const GroupCallProviderScreen({
    super.key,
    required this.groupName,
  });

  @override
  Widget build(BuildContext context) {
    final calls = context.watch<GroupCallProvider>();
    final participants = calls.participants;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        calls.setMinimized(true);
        Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF05070A),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: 'Back to chat',
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
            onPressed: () {
              calls.setMinimized(true);
              Navigator.of(context).pop();
            },
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                groupName.trim().isEmpty ? 'Group call' : groupName.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                '${participants.length} participant${participants.length == 1 ? '' : 's'} · ${_duration(calls.elapsed)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          actions: [
            if (calls.cameraEnabled)
              IconButton(
                tooltip: 'Switch camera',
                onPressed: calls.switchCamera,
                icon: const Icon(Icons.flip_camera_ios_rounded),
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: _CallBody(calls: calls),
              ),
              _Controls(calls: calls),
            ],
          ),
        ),
      ),
    );
  }

  static String _duration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '${value.inMinutes.toString().padLeft(2, '0')}:$seconds';
  }
}

class _CallBody extends StatelessWidget {
  final GroupCallProvider calls;

  const _CallBody({required this.calls});

  @override
  Widget build(BuildContext context) {
    if (calls.lifecycle == GroupCallLifecycle.starting ||
        calls.lifecycle == GroupCallLifecycle.joining ||
        calls.lifecycle == GroupCallLifecycle.connecting) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (calls.lifecycle == GroupCallLifecycle.failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 56, color: Colors.white),
              const SizedBox(height: 14),
              Text(
                calls.error ?? 'Could not connect to group call',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    final participants = calls.participants;
    if (participants.isEmpty) {
      return const Center(
        child: Text(
          'Waiting for participants…',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final columns = participants.length == 1 ? 1 : (width >= 900 ? 3 : 2);

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: participants.length == 1 ? 0.8 : 0.76,
      ),
      itemCount: participants.length,
      itemBuilder: (context, index) {
        final participant = participants[index];
        return _ParticipantTile(
          participant: participant,
          displayName: calls.participantName(participant),
          videoTrack: calls.videoTrackFor(participant),
          micEnabled: calls.participantMicrophoneEnabled(participant),
          isLocal: participant is LocalParticipant,
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  final GroupCallProvider calls;

  const _Controls({required this.calls});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
      decoration: BoxDecoration(
        color: const Color(0xFF11141A),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ControlButton(
            icon: calls.microphoneEnabled
                ? Icons.mic_rounded
                : Icons.mic_off_rounded,
            onTap: calls.toggleMicrophone,
          ),
          _ControlButton(
            icon: calls.cameraEnabled
                ? Icons.videocam_rounded
                : Icons.videocam_off_rounded,
            onTap: calls.toggleCamera,
          ),
          _ControlButton(
            icon: calls.speakerEnabled
                ? Icons.volume_up_rounded
                : Icons.volume_off_rounded,
            onTap: calls.toggleSpeaker,
          ),
          _ControlButton(
            icon: Icons.call_end_rounded,
            danger: true,
            onTap: () async {
              await calls.leaveCurrentCall();
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final FutureOr<void> Function() onTap;
  final bool danger;

  const _ControlButton({
    required this.icon,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: () => onTap(),
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: danger
              ? const Color(0xFFDC2626)
              : const Color(0xFF252A31),
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  final Participant participant;
  final String displayName;
  final VideoTrack? videoTrack;
  final bool micEnabled;
  final bool isLocal;

  const _ParticipantTile({
    required this.participant,
    required this.displayName,
    required this.videoTrack,
    required this.micEnabled,
    required this.isLocal,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        color: const Color(0xFF161A20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (videoTrack != null)
              VideoTrackRenderer(videoTrack!)
            else
              Center(
                child: CircleAvatar(
                  radius: 42,
                  backgroundColor: const Color(0xFF303640),
                  child: Text(
                    displayName.trim().isEmpty
                        ? '?'
                        : displayName.trim()[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      isLocal ? '$displayName (You)' : displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (!micEnabled)
                    const Icon(Icons.mic_off_rounded,
                        color: Colors.white, size: 18),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
