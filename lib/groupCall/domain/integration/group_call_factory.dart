import '../application/group_call_controller.dart';
import '../infrastructure/call_api_service.dart';
import '../infrastructure/livekit_call_service.dart';

import '../../../realtime/realtime_service.dart';

GroupCallController createGroupCallController({
  required int conversationId,
  required CallApiService api,
  required ConversationRealtimeService realtime,
}) {
  return GroupCallController(
    conversationId: conversationId,
    api: api,
    realtime: realtime,
    liveKit: LiveKitMediaService(),
  );
}