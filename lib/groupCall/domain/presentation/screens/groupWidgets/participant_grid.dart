// import 'package:flutter/material.dart';

// import 'participant_tile.dart';

// class ParticipantGrid extends StatelessWidget {
//   final LiveKitCallService liveKit;

//   const ParticipantGrid({
//     super.key,
//     required this.liveKit,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final room = liveKit.room;
//     final participants = liveKit.participants;

//     if (room == null || participants.isEmpty) {
//       return const Center(
//         child: CircularProgressIndicator(),
//       );
//     }

//     final count = participants.length;
//     final columns = count <= 1
//         ? 1
//         : count <= 4
//             ? 2
//             : 3;

//     return GridView.builder(
//       padding: const EdgeInsets.fromLTRB(
//         8,
//         8,
//         8,
//         4,
//       ),
//       gridDelegate:
//           SliverGridDelegateWithFixedCrossAxisCount(
//         crossAxisCount: columns,
//         crossAxisSpacing: 2,
//         mainAxisSpacing: 2,
//         childAspectRatio: count <= 2 ? 0.78 : 0.88,
//       ),
//       itemCount: participants.length,
//       itemBuilder: (context, index) {
//         final participant = participants[index];

//         return ParticipantTile(
//           participant: participant,
//           liveKit: liveKit,
//           isLocal: participant.identity ==
//               room.localParticipant.identity,
//         );
//       },
//     );
//   }
// }
