import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hiddenly/group/group_api_service.dart';
import 'package:hiddenly/group/group_models.dart';

/// Owns GROUP METADATA state only:
/// subject/image/description, members, admins, permissions, block flags,
/// invitation link and group typing display state.
///
/// ChatProvider remains the owner of messages, reactions, pins and the normal
/// per-conversation chat socket.
class GroupChatProvider extends ChangeNotifier {
  final Map<String, GroupDetails> _groups = <String, GroupDetails>{};
  final Set<String> _loading = <String>{};
  final Set<String> _mutating = <String>{};
  final Map<String, String> _errors = <String, String>{};

  /// conversationId -> userId -> display name
  final Map<String, Map<String, String>> _typingUsers =
      <String, Map<String, String>>{};

  /// conversationId:userId -> expiry timer
  final Map<String, Timer> _typingTimers = <String, Timer>{};

  GroupDetails? group(String conversationId) => _groups[conversationId.trim()];

  bool isLoading(String conversationId) =>
      _loading.contains(conversationId.trim());

  bool isMutating(String conversationId) =>
      _mutating.contains(conversationId.trim());

  String? errorFor(String conversationId) => _errors[conversationId.trim()];

  List<GroupMember> members(String conversationId) =>
      List.unmodifiable(group(conversationId)?.members ?? const <GroupMember>[]);

  List<GroupMember> admins(String conversationId) => members(conversationId)
      .where((member) => member.isAdmin)
      .toList(growable: false);

  GroupMember? member(String conversationId, String userId) {
    final id = userId.trim();
    for (final item in members(conversationId)) {
      if (item.id.trim() == id) return item;
    }
    return null;
  }

  bool canEditInfo(String conversationId) {
    final value = group(conversationId);
    if (value == null || !value.isCurrentUserMember) return false;
    if (!value.permissions.onlyAdminsCanEditInfo) return true;
    return value.isCurrentUserAdmin;
  }

  bool canAddMembers(String conversationId) {
    final value = group(conversationId);
    if (value == null || !value.isCurrentUserMember) return false;
    if (!value.permissions.onlyAdminsCanAddMembers) return true;
    return value.isCurrentUserAdmin;
  }

  bool canSendMessages(String conversationId) {
    final value = group(conversationId);
    if (value == null) return true; // Do not block UI while details are loading.
    if (!value.isCurrentUserMember) return false;
    if (!value.permissions.onlyAdminsCanSendMessages) return true;
    return value.isCurrentUserAdmin;
  }

  void seed(GroupDetails value) {
    _groups[value.conversationId] = value;
    _errors.remove(value.conversationId);
    notifyListeners();
  }

  Future<GroupDetails?> loadGroup(
    String conversationId, {
    bool force = false,
    bool silent = false,
  }) async {
    final id = conversationId.trim();
    if (id.isEmpty) return null;

    if (!force && _groups.containsKey(id)) {
      return _groups[id];
    }

    if (_loading.contains(id)) {
      return _groups[id];
    }

    _loading.add(id);
    _errors.remove(id);
    if (!silent) notifyListeners();

    try {
      final value = await GroupApiService.getGroup(id);
      _groups[id] = value;
      return value;
    } catch (e) {
      _errors[id] = e.toString();
      return null;
    } finally {
      _loading.remove(id);
      notifyListeners();
    }
  }

  Future<GroupDetails?> refreshGroup(String conversationId) =>
      loadGroup(conversationId, force: true, silent: true);

  Future<T?> _mutation<T>({
    required String conversationId,
    required Future<T> Function() run,
  }) async {
    final id = conversationId.trim();
    if (id.isEmpty || _mutating.contains(id)) return null;

    _mutating.add(id);
    _errors.remove(id);
    notifyListeners();

    try {
      return await run();
    } catch (e) {
      _errors[id] = e.toString();
      return null;
    } finally {
      _mutating.remove(id);
      notifyListeners();
    }
  }

  Future<bool> updateInfo({
    required String conversationId,
    String? subject,
    String? description,
    File? image,
  }) async {
    final result = await _mutation<GroupDetails>(
      conversationId: conversationId,
      run: () => GroupApiService.updateGroup(
        conversationId: conversationId,
        subject: subject,
        description: description,
        image: image,
      ),
    );

    if (result == null) return false;
    seed(result);
    return true;
  }

  Future<bool> addMembers({
    required String conversationId,
    required List<String> userIds,
  }) async {
    final clean = userIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (clean.isEmpty) return false;

    final result = await _mutation<GroupDetails>(
      conversationId: conversationId,
      run: () => GroupApiService.addMembers(
        conversationId: conversationId,
        userIds: clean,
      ),
    );

    if (result == null) return false;
    seed(result);
    return true;
  }

  Future<bool> removeMember({
    required String conversationId,
    required String userId,
  }) async {
    final result = await _mutation<GroupDetails>(
      conversationId: conversationId,
      run: () => GroupApiService.removeMember(
        conversationId: conversationId,
        userId: userId,
      ),
    );

    if (result == null) return false;
    seed(result);
    return true;
  }

  Future<bool> setAdmin({
    required String conversationId,
    required String userId,
    required bool makeAdmin,
  }) async {
    final result = await _mutation<GroupDetails>(
      conversationId: conversationId,
      run: () => GroupApiService.setAdmin(
        conversationId: conversationId,
        userId: userId,
        makeAdmin: makeAdmin,
      ),
    );

    if (result == null) return false;
    seed(result);
    return true;
  }

  Future<bool> updatePermissions({
    required String conversationId,
    required GroupPermissions permissions,
  }) async {
    final result = await _mutation<GroupDetails>(
      conversationId: conversationId,
      run: () => GroupApiService.updatePermissions(
        conversationId: conversationId,
        permissions: permissions,
      ),
    );

    if (result == null) return false;
    seed(result);
    return true;
  }

  /// Blocking does not remove a user from the shared group.
  Future<bool> blockMember({
    required String conversationId,
    required String userId,
  }) async {
    final result = await _mutation<bool>(
      conversationId: conversationId,
      run: () async {
        await GroupApiService.blockMember(userId);
        return true;
      },
    );

    if (result != true) return false;
    await refreshGroup(conversationId);
    return true;
  }

  Future<bool> unblockMember({
    required String conversationId,
    required String userId,
  }) async {
    final result = await _mutation<bool>(
      conversationId: conversationId,
      run: () async {
        await GroupApiService.unblockMember(userId);
        return true;
      },
    );

    if (result != true) return false;
    await refreshGroup(conversationId);
    return true;
  }

  Future<bool> exitGroup(String conversationId) async {
    final id = conversationId.trim();
    final result = await _mutation<bool>(
      conversationId: id,
      run: () async {
        await GroupApiService.exitGroup(id);
        return true;
      },
    );

    if (result != true) return false;

    _groups.remove(id);
    clearTyping(id);
    notifyListeners();
    return true;
  }

  Future<bool> deleteGroupForMe(String conversationId) async {
    final id = conversationId.trim();
    final result = await _mutation<bool>(
      conversationId: id,
      run: () async {
        await GroupApiService.deleteGroupForMe(id);
        return true;
      },
    );

    if (result != true) return false;
    _groups.remove(id);
    clearTyping(id);
    notifyListeners();
    return true;
  }

  Future<String?> resetInviteLink(String conversationId) async {
    final result = await _mutation<String>(
      conversationId: conversationId,
      run: () => GroupApiService.resetInviteLink(conversationId),
    );

    if (result == null) return null;
    await refreshGroup(conversationId);
    return result;
  }

  /// Feed the normal conversation socket event here as well as to ChatProvider.
  /// This allows group-specific typing labels without moving message ownership.
  void handleConversationSocketEvent({
    required String conversationId,
    required Map<String, dynamic> event,
  }) {
    final action = (event['action'] ?? event['type'] ?? '').toString();
    if (action != 'typing') return;

    final senderId = (event['sender_id'] ??
            event['senderId'] ??
            event['sender']?['id'] ??
            '')
        .toString()
        .trim();

    if (senderId.isEmpty) return;

    final typing = event['is_typing'] == true || event['typing'] == true;
    final senderName = (event['sender_name'] ??
            event['senderName'] ??
            event['sender']?['name'] ??
            member(conversationId, senderId)?.name ??
            'Someone')
        .toString()
        .trim();

    setTyping(
      conversationId: conversationId,
      userId: senderId,
      userName: senderName.isEmpty ? 'Someone' : senderName,
      typing: typing,
    );
  }

  void setTyping({
    required String conversationId,
    required String userId,
    required String userName,
    required bool typing,
  }) {
    final conversation = conversationId.trim();
    final user = userId.trim();
    if (conversation.isEmpty || user.isEmpty) return;

    final key = '$conversation:$user';
    _typingTimers.remove(key)?.cancel();

    final map = _typingUsers.putIfAbsent(
      conversation,
      () => <String, String>{},
    );

    if (!typing) {
      map.remove(user);
      if (map.isEmpty) _typingUsers.remove(conversation);
      notifyListeners();
      return;
    }

    map[user] = userName.trim().isEmpty ? 'Someone' : userName.trim();

    // Safety expiry protects against a missing "typing false" event.
    _typingTimers[key] = Timer(const Duration(seconds: 6), () {
      final active = _typingUsers[conversation];
      active?.remove(user);
      if (active != null && active.isEmpty) {
        _typingUsers.remove(conversation);
      }
      _typingTimers.remove(key);
      notifyListeners();
    });

    notifyListeners();
  }

  List<String> typingNames(String conversationId) =>
      List.unmodifiable(_typingUsers[conversationId.trim()]?.values ?? const []);

  String typingLabel(String conversationId) {
    final names = typingNames(conversationId);
    if (names.isEmpty) return '';
    if (names.length == 1) return '${names.first} is typing…';
    if (names.length == 2) return '${names[0]} and ${names[1]} are typing…';
    return '${names.length} people are typing…';
  }

  void clearTyping(String conversationId) {
    final id = conversationId.trim();
    _typingUsers.remove(id);

    final timerKeys = _typingTimers.keys
        .where((key) => key.startsWith('$id:'))
        .toList(growable: false);
    for (final key in timerKeys) {
      _typingTimers.remove(key)?.cancel();
    }
    notifyListeners();
  }

  /// Global user-event socket handler for group metadata events.
  Future<void> handleRealtimeEvent({
    required String eventName,
    required Map<String, dynamic> payload,
  }) async {
    if (eventName == 'group_created') {
      final raw = payload['group'];
      if (raw is Map) {
        seed(GroupDetails.fromJson(Map<String, dynamic>.from(raw)));
      }
      return;
    }

    if (eventName == 'group_updated' || eventName == 'group_members_changed') {
      final id = (payload['conversation_id'] ?? payload['conversationId'] ?? '')
          .toString()
          .trim();
      if (id.isNotEmpty) {
        await refreshGroup(id);
      }
    }
  }

  void clearError(String conversationId) {
    if (_errors.remove(conversationId.trim()) != null) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    _typingTimers.clear();
    super.dispose();
  }
}
