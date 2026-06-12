import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:messaging_app/core/api_client.dart';

class BlockProvider extends ChangeNotifier {
  bool _isLoading = false;
  String _error = '';

  final Map<String, bool> _blockedByMeMap = {};
  final Map<String, bool> _blockedMeMap = {};

  String _activeKey = '';

  bool get isLoading => _isLoading;
  String get error => _error;

  bool get isBlocked {
    if (_activeKey.isEmpty) return false;
    return _blockedByMeMap[_activeKey] == true;
  }

  bool get blockedMe {
    if (_activeKey.isEmpty) return false;
    return _blockedMeMap[_activeKey] == true;
  }

  String _key({
    required String conversationId,
    required String targetUserId,
  }) {
    return '${conversationId.trim()}:${targetUserId.trim()}';
  }

  // KEEP YOUR SAME ROUTES. Do not change these.
  String _privateBlockUrl({
    required String conversationId,
    required String targetUserId,
  }) {
    return '/chat/conversations/$conversationId/private/$targetUserId/block/';
  }

  String _privateUnblockUrl({
    required String conversationId,
    required String targetUserId,
  }) {
    return '/chat/conversations/$conversationId/private/$targetUserId/unblock/';
  }

  String _groupMemberBlockUrl({
    required String conversationId,
    required String targetUserId,
  }) {
    return '/chat/conversations/$conversationId/members/$targetUserId/block/';
  }

  String _groupMemberUnblockUrl({
    required String conversationId,
    required String targetUserId,
  }) {
    return '/chat/conversations/$conversationId/members/$targetUserId/unblock/';
  }

  bool isBlockedFor({
    required String conversationId,
    required String targetUserId,
  }) {
    final mapKey = _key(
      conversationId: conversationId,
      targetUserId: targetUserId,
    );

    return _blockedByMeMap[mapKey] == true;
  }

  bool blockedMeFor({
    required String conversationId,
    required String targetUserId,
  }) {
    final mapKey = _key(
      conversationId: conversationId,
      targetUserId: targetUserId,
    );

    return _blockedMeMap[mapKey] == true;
  }

  void setActiveChat({
    required String conversationId,
    required String targetUserId,
  }) {
    _activeKey = _key(
      conversationId: conversationId,
      targetUserId: targetUserId,
    );

    notifyListeners();
  }

  void setLocalBlocked({
    required String conversationId,
    required String targetUserId,
    required bool value,
  }) {
    final mapKey = _key(
      conversationId: conversationId,
      targetUserId: targetUserId,
    );

    _activeKey = mapKey;
    _blockedByMeMap[mapKey] = value;

    notifyListeners();
  }

  void setLocalBlockedMe({
    required String conversationId,
    required String targetUserId,
    required bool value,
  }) {
    final mapKey = _key(
      conversationId: conversationId,
      targetUserId: targetUserId,
    );

    _activeKey = mapKey;
    _blockedMeMap[mapKey] = value;

    notifyListeners();
  }

  void clearError() {
    _error = '';
    notifyListeners();
  }

  /// No API call here.
  /// Block status is restored from /chat/conversations/ member fields:
  /// is_blocked and blocked_by.
  Future<void> loadBlockStatus({
    required String conversationId,
    required String targetUserId,
    bool isGroupChat = false,
  }) async {
    final cleanConversationId = conversationId.trim();
    final cleanTargetUserId = targetUserId.trim();

    if (cleanConversationId.isEmpty || cleanTargetUserId.isEmpty) {
      _error = 'Invalid conversation or user';
      debugPrint('LOAD BLOCK STATUS ERROR: $_error');
      notifyListeners();
      return;
    }

    _activeKey = _key(
      conversationId: cleanConversationId,
      targetUserId: cleanTargetUserId,
    );

    _isLoading = false;
    _error = '';

    debugPrint('LOAD BLOCK STATUS SKIPPED: using /chat/conversations/ data only');
    debugPrint('ACTIVE BLOCK KEY: $_activeKey');

    notifyListeners();
  }

  Future<bool> setBlockStatus({
    required String conversationId,
    required String targetUserId,
    required bool blocked,
    bool isGroupChat = false,
  }) async {
    final cleanConversationId = conversationId.trim();
    final cleanTargetUserId = targetUserId.trim();

    if (cleanConversationId.isEmpty || cleanTargetUserId.isEmpty) {
      _error = 'Invalid conversation or user';
      debugPrint('SET BLOCK STATUS ERROR: $_error');
      debugPrint('conversationId: $cleanConversationId');
      debugPrint('targetUserId: $cleanTargetUserId');
      notifyListeners();
      return false;
    }

    final mapKey = _key(
      conversationId: cleanConversationId,
      targetUserId: cleanTargetUserId,
    );

    _activeKey = mapKey;
    _isLoading = true;
    _error = '';
    notifyListeners();

    try {
      final url = _buildSetBlockUrl(
        conversationId: cleanConversationId,
        targetUserId: cleanTargetUserId,
        blocked: blocked,
        isGroupChat: isGroupChat,
      );

      debugPrint('SET BLOCK STATUS URL: $url');
      debugPrint('SET BLOCK STATUS targetUserId: $cleanTargetUserId');
      debugPrint('SET BLOCK STATUS blocked: $blocked');
      debugPrint('SET BLOCK STATUS isGroupChat: $isGroupChat');

      final response = await ApiClient.dio.post(
        url,
        data: {
          'user_id': cleanTargetUserId,
          'target_user_id': cleanTargetUserId,
          'blocked': blocked,
        },
      );

      debugPrint('SET BLOCK STATUS STATUS: ${response.statusCode}');
      debugPrint('SET BLOCK STATUS DATA: ${response.data}');

      final data = response.data;

      if (data is Map) {
        if (data.containsKey('blocked') ||
            data.containsKey('is_blocked') ||
            data.containsKey('blocked_by_me') ||
            data.containsKey('is_blocked_by_me')) {
          _blockedByMeMap[mapKey] = _readBlockedByMe(data);
        } else if (data['success'] == true) {
          _blockedByMeMap[mapKey] = blocked;
        } else {
          _blockedByMeMap[mapKey] = blocked;
        }

        _blockedMeMap[mapKey] = _readBlockedMe(data);
      } else {
        _blockedByMeMap[mapKey] = blocked;
        _blockedMeMap[mapKey] = false;
      }

      if (!blocked && !(data is Map && _readBlockedMe(data))) {
        _blockedMeMap[mapKey] = false;
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } on DioException catch (e) {
      _error = _extractError(e);

      debugPrint('SET BLOCK STATUS ERROR STATUS: ${e.response?.statusCode}');
      debugPrint('SET BLOCK STATUS ERROR DATA: ${e.response?.data}');
      debugPrint('SET BLOCK STATUS ERROR MESSAGE: ${e.message}');
    } catch (e) {
      _error = e.toString();
      debugPrint('SET BLOCK STATUS ERROR: $e');
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  String _buildSetBlockUrl({
    required String conversationId,
    required String targetUserId,
    required bool blocked,
    required bool isGroupChat,
  }) {
    if (isGroupChat) {
      return blocked
          ? _groupMemberBlockUrl(
              conversationId: conversationId,
              targetUserId: targetUserId,
            )
          : _groupMemberUnblockUrl(
              conversationId: conversationId,
              targetUserId: targetUserId,
            );
    }

    return blocked
        ? _privateBlockUrl(
            conversationId: conversationId,
            targetUserId: targetUserId,
          )
        : _privateUnblockUrl(
            conversationId: conversationId,
            targetUserId: targetUserId,
          );
  }

  Future<bool> blockUser({
    required String conversationId,
    required String targetUserId,
    bool isGroupChat = false,
  }) {
    return setBlockStatus(
      conversationId: conversationId,
      targetUserId: targetUserId,
      blocked: true,
      isGroupChat: isGroupChat,
    );
  }

  Future<bool> unblockUser({
    required String conversationId,
    required String targetUserId,
    bool isGroupChat = false,
  }) {
    return setBlockStatus(
      conversationId: conversationId,
      targetUserId: targetUserId,
      blocked: false,
      isGroupChat: isGroupChat,
    );
  }

  void resetActiveOnly() {
    _activeKey = '';
    _isLoading = false;
    _error = '';
    notifyListeners();
  }

  void resetAll() {
    _activeKey = '';
    _isLoading = false;
    _error = '';
    _blockedByMeMap.clear();
    _blockedMeMap.clear();
    notifyListeners();
  }

  bool _readBlockedByMe(Map data) {
    return data['blocked'] == true ||
        data['is_blocked'] == true ||
        data['blocked_by_me'] == true ||
        data['is_blocked_by_me'] == true;
  }

  bool _readBlockedMe(Map data) {
    return data['blocked_me'] == true ||
        data['is_blocked_by_user'] == true ||
        data['blocked_by_other'] == true ||
        data['is_blocked_by_other'] == true;
  }

  String _extractError(DioException e) {
    final data = e.response?.data;

    if (data is Map) {
      final value = data['error'] ??
          data['detail'] ??
          data['message'] ??
          data['non_field_errors'];

      if (value != null) return value.toString();
    }

    if (data is String && data.trim().isNotEmpty) {
      if (data.contains('Page not found')) return 'API route not found';
      return data;
    }

    return e.message ?? 'Something went wrong';
  }
}
