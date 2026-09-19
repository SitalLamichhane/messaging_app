import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../infrastructure/livekit_call_service.dart';

class ParticipantTile extends StatelessWidget {
  final Participant participant;
  final LiveKitCallService liveKit;
  final bool isLocal;

  const ParticipantTile({
    super.key,
    required this.participant,
    required this.liveKit,
    required this.isLocal,
  });

  @override
  Widget build(BuildContext context) {
    final track = liveKit.videoTrackFor(participant);
    final name = liveKit.displayNameFor(participant);
    final avatar = liveKit.avatarFor(participant);
    final speaking = participant.isSpeaking;

    return Container(
      margin: const EdgeInsets.all(4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: speaking
              ? Colors.greenAccent
              : Colors.white12,
          width: speaking ? 3 : 1,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (track != null)
            VideoTrackRenderer(
              track,
              fit: VideoViewFit.cover,
            )
          else
            _AvatarFallback(
              name: name,
              avatarUrl: avatar,
            ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 9,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isLocal ? '$name (You)' : name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (participant.isMuted)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(
                      Icons.mic_off,
                      size: 18,
                      color: Colors.white,
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

class _AvatarFallback extends StatelessWidget {
  final String name;
  final String avatarUrl;

  const _AvatarFallback({
    required this.name,
    required this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty
        ? '?'
        : name.trim().characters.first.toUpperCase();

    return ColoredBox(
      color: const Color(0xFF202C33),
      child: Center(
        child: CircleAvatar(
          radius: 48,
          backgroundImage: avatarUrl.isNotEmpty
              ? NetworkImage(avatarUrl)
              : null,
          child: avatarUrl.isEmpty
              ? Text(
                  letter,
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
