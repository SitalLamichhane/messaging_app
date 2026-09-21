import 'package:flutter/material.dart';

import 'package:hiddenly/groupCall/domain/application/group_call_controller.dart';
import 'package:hiddenly/groupCall/domain/call_models.dart';

class OngoingCallBanner
    extends StatelessWidget {
  final GroupCallController controller;
  final Future<void> Function() onJoin;

  const OngoingCallBanner({
    super.key,
    required this.controller,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final call =
            controller
                .activeDiscoveredCall;

        if (call == null ||
            !call.isActive) {
          return const SizedBox.shrink();
        }

        final joinedCount =
            call.participants
                .where(
                  (participant) =>
                      participant.status ==
                      CallParticipantStatus
                          .joined,
                )
                .length;

        return Material(
          color:
              const Color(0xFF075E54),
          child: InkWell(
            onTap:
                controller.isBusy
                    ? null
                    : () {
                        onJoin();
                      },
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              child: Row(
                children: [
                  Icon(
                    call.isVideo
                        ? Icons
                            .videocam_rounded
                        : Icons
                            .call_rounded,
                    color: Colors.white,
                  ),
                  const SizedBox(
                    width: 10,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        const Text(
                          'Ongoing group call',
                          style: TextStyle(
                            color:
                                Colors.white,
                            fontWeight:
                                FontWeight
                                    .w700,
                          ),
                        ),
                        Text(
                          joinedCount > 0
                              ? '$joinedCount in call • Tap to join'
                              : 'Tap to join',
                          style:
                              const TextStyle(
                            color:
                                Colors
                                    .white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (controller.isBusy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child:
                          CircularProgressIndicator(
                        strokeWidth: 2,
                        color:
                            Colors.white,
                      ),
                    )
                  else
                    const Icon(
                      Icons
                          .chevron_right_rounded,
                      color:
                          Colors.white,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}