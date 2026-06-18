// lib/nickname_display_helper.dart

import 'package:hiddenly/chat_models.dart';

class NicknameDisplayHelper {
  NicknameDisplayHelper._();

  /// Messenger-style rule:
  /// If a nickname exists for this member in this conversation, show nickname.
  /// If nickname is empty/null/removed, show the latest real profile name.
  static String memberDisplayName({
    required ChatItem chat,
    required String userId,
    required String fallbackRealName,
  }) {
    final cleanUserId = userId.trim();

    if (cleanUserId.isNotEmpty) {
      final nickname = chat.memberNicknames[cleanUserId]?.trim() ?? '';

      if (nickname.isNotEmpty) {
        return nickname;
      }

      for (final member in chat.members) {
        if (member.id.toString().trim() == cleanUserId) {
          final realName = member.name.trim();

          if (realName.isNotEmpty && realName.toLowerCase() != 'unknown') {
            return realName;
          }
        }
      }
    }

    final fallback = fallbackRealName.trim();
    return fallback.isEmpty ? 'Unknown' : fallback;
  }

  /// For private chat title.
  static String privateChatTitle({
    required ChatItem chat,
    required String currentUserId,
  }) {
    if (chat.isGroup == true) {
      return chat.name.trim().isEmpty ? 'Group' : chat.name.trim();
    }

    final currentId = currentUserId.trim();

    for (final member in chat.members) {
      final memberId = member.id.toString().trim();

      if (memberId.isEmpty) continue;
      if (currentId.isNotEmpty && memberId == currentId) continue;

      return memberDisplayName(
        chat: chat,
        userId: memberId,
        fallbackRealName: member.name.trim().isNotEmpty ? member.name : chat.name,
      );
    }

    return chat.name.trim().isEmpty ? 'Unknown' : chat.name.trim();
  }
}
