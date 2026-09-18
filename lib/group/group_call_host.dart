import 'package:flutter/material.dart';
import 'package:hiddenly/core/group%20provider/group_call_provider.dart';
import 'package:hiddenly/core/group%20provider/group_chat_provider.dart';
import 'package:hiddenly/group/group_call_provider_screen.dart';
import 'package:provider/provider.dart';

/// Put this once in MaterialApp.builder.
///
/// It supplies:
/// 1. incoming group-call overlay globally,
/// 2. minimized "return to call" pill while media stays connected.
class GroupCallHost extends StatelessWidget {
  final Widget child;

  const GroupCallHost({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer2<GroupCallProvider, GroupChatProvider>(
      builder: (context, calls, groups, _) {
        final incoming = calls.primaryIncomingCall;
        final current = calls.currentCall;

        return Stack(
          children: [
            child,
            if (incoming != null && current?.callId != incoming.callId)
              _IncomingGroupCallCard(
                groupName: groups.group(incoming.conversationId)?.subject ??
                    'Group call',
                callerName: incoming.startedByName,
                video: incoming.isVideo,
                onDecline: () => calls.declineCall(incoming.callId),
                onJoin: () async {
                  final navigator = Navigator.of(context, rootNavigator: true);
                  final ok = await calls.joinCall(incoming.callId);
                  if (!ok || !context.mounted) return;

                  await navigator.push(
                    MaterialPageRoute<void>(
                      builder: (_) => GroupCallProviderScreen(
                        groupName:
                            groups.group(incoming.conversationId)?.subject ??
                                'Group call',
                      ),
                    ),
                  );
                },
              ),
            if (calls.inCall && calls.minimized)
              _OngoingCallPill(
                text: groups.group(current?.conversationId ?? '')?.subject ??
                    'Group call',
                onTap: () async {
                  calls.setMinimized(false);
                  await Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute<void>(
                      builder: (_) => GroupCallProviderScreen(
                        groupName: groups
                                .group(current?.conversationId ?? '')
                                ?.subject ??
                            'Group call',
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

class _IncomingGroupCallCard extends StatelessWidget {
  final String groupName;
  final String callerName;
  final bool video;
  final VoidCallback onDecline;
  final VoidCallback onJoin;

  const _IncomingGroupCallCard({
    required this.groupName,
    required this.callerName,
    required this.video,
    required this.onDecline,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 12,
      right: 12,
      top: MediaQuery.paddingOf(context).top + 10,
      child: Material(
        color: const Color(0xFF111827),
        elevation: 14,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFF1F2937),
                child: Icon(
                  video ? Icons.videocam_rounded : Icons.call_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      groupName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$callerName started a ${video ? 'video' : 'voice'} call',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              IconButton.filled(
                onPressed: onDecline,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                ),
                icon: const Icon(Icons.call_end_rounded),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: onJoin,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                ),
                icon: const Icon(Icons.call_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OngoingCallPill extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _OngoingCallPill({
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 14,
      right: 14,
      top: MediaQuery.paddingOf(context).top + 8,
      child: Material(
        color: const Color(0xFF075E54),
        elevation: 10,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.call_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Text(
                  'Tap to return',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
