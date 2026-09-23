import 'package:flutter/material.dart';
import 'package:hiddenly/groupCall/domain/infrastructure/livekit_call_service.dart';
import 'package:livekit_client/livekit_client.dart';
class ParticipantTile extends StatelessWidget {
  final Participant participant;
  final LiveKitMediaService liveKit;
  final bool isLocal;

  const ParticipantTile({
    super.key,
    required this.participant,
    required this.liveKit,
    required this.isLocal,
  });

  @override
  Widget build(BuildContext context) {
    final track =
        liveKit.videoTrackFor(participant);

    final name =
        liveKit.displayNameFor(participant);

    final avatar =
        liveKit.avatarFor(participant);

    return Container(
      margin: const EdgeInsets.all(3),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF202C33),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: participant.isSpeaking
              ? const Color(0xFF25D366)
              : Colors.white12,
          width:
              participant.isSpeaking ? 3 : 1,
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
            bottom: 8,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isLocal
                        ? '$name (You)'
                        : name,
                    maxLines: 1,
                    overflow:
                        TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight:
                          FontWeight.w600,
                    ),
                  ),
                ),
                if (participant.isMuted)
                  const Icon(
                    Icons.mic_off_rounded,
                    size: 17,
                    color: Colors.white,
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
    final trimmed = name.trim();

    String initial = '?';

    if (trimmed.isNotEmpty) {
      initial = trimmed.characters.first.toUpperCase();
    }

    return Center(
      child: CircleAvatar(
        radius: 48,

        backgroundImage:
            avatarUrl.trim().isNotEmpty
                ? NetworkImage(
                    avatarUrl.trim(),
                  )
                : null,

        child: avatarUrl.trim().isEmpty
            ? Text(
                initial,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                ),
              )
            : null,
      ),
    );
  }
}