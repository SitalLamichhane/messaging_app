import 'package:hiddenly/group/group_api_service.dart';
import 'package:hiddenly/group/group_models.dart';

/// Compatibility wrapper around the new group-call endpoints.
/// Start and join now happen through a server-side GroupCallSession so every
/// participant receives a token for the same LiveKit room.
class GroupCallTokenService {
  GroupCallTokenService._();

  static Future<GroupCallJoinCredentials> start({
    required String conversationId,
    required bool isVideoCall,
  }) {
    return GroupApiService.startCall(
      conversationId: conversationId,
      video: isVideoCall,
    );
  }

  static Future<GroupCallJoinCredentials> join({
    required String callId,
  }) {
    return GroupApiService.joinCall(callId);
  }
}
