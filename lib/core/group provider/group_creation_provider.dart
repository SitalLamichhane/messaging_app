import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hiddenly/group/group_api_service.dart';
import 'package:hiddenly/group/group_models.dart';

/// State for the "New group" wizard only.
///
/// This provider intentionally does NOT own messages or existing group state.
/// It is disposed when the create-group flow is closed.
class GroupCreationProvider extends ChangeNotifier {
  final Set<String> _selectedUserIds = <String>{};
  final List<GroupMember> _searchResults = <GroupMember>[];

  Timer? _searchDebounce;

  String _query = '';
  String _subject = '';
  String _description = '';
  File? _image;

  bool _searching = false;
  bool _creating = false;
  String? _error;

  Set<String> get selectedUserIds => Set.unmodifiable(_selectedUserIds);
  List<GroupMember> get searchResults => List.unmodifiable(_searchResults);

  String get query => _query;
  String get subject => _subject;
  String get description => _description;
  File? get image => _image;

  bool get isSearching => _searching;
  bool get isCreating => _creating;
  String? get error => _error;

  int get selectedCount => _selectedUserIds.length;
  bool isSelected(String userId) => _selectedUserIds.contains(userId.trim());

  /// Backend remains the final authority for any participant-count limit.
  bool get canCreate =>
      !_creating && _subject.trim().isNotEmpty && _selectedUserIds.isNotEmpty;

  void setSubject(String value) {
    final next = value.trimLeft();
    if (_subject == next) return;
    _subject = next;
    _error = null;
    notifyListeners();
  }

  void setDescription(String value) {
    if (_description == value) return;
    _description = value;
    notifyListeners();
  }

  void setImage(File? value) {
    _image = value;
    notifyListeners();
  }

  void preselect(String userId) {
    final id = userId.trim();
    if (id.isEmpty) return;
    if (_selectedUserIds.add(id)) {
      notifyListeners();
    }
  }

  void toggleUser(String userId) {
    final id = userId.trim();
    if (id.isEmpty || _creating) return;

    if (!_selectedUserIds.remove(id)) {
      _selectedUserIds.add(id);
    }
    _error = null;
    notifyListeners();
  }

  void clearSelection() {
    if (_selectedUserIds.isEmpty) return;
    _selectedUserIds.clear();
    notifyListeners();
  }

  void scheduleSearch(String value) {
    _query = value.trim();
    _searchDebounce?.cancel();

    if (_query.isEmpty) {
      _searchResults.clear();
      _searching = false;
      _error = null;
      notifyListeners();
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(searchNow(_query));
    });
  }

  Future<void> searchNow(String value) async {
    final q = value.trim();
    _query = q;

    if (q.isEmpty) {
      _searchResults.clear();
      _searching = false;
      _error = null;
      notifyListeners();
      return;
    }

    _searching = true;
    _error = null;
    notifyListeners();

    try {
      final results = await GroupApiService.searchUsers(q);

      // Do not allow an older request to overwrite a newer search.
      if (_query != q) return;

      _searchResults
        ..clear()
        ..addAll(results.where((member) => !member.isCurrentUser));
    } catch (e) {
      if (_query == q) {
        _error = e.toString();
      }
    } finally {
      if (_query == q) {
        _searching = false;
        notifyListeners();
      }
    }
  }

  Future<GroupDetails?> create() async {
    if (_creating) return null;

    final cleanSubject = _subject.trim();
    if (cleanSubject.isEmpty) {
      _error = 'Enter a group name.';
      notifyListeners();
      return null;
    }

    if (_selectedUserIds.isEmpty) {
      _error = 'Select at least one participant.';
      notifyListeners();
      return null;
    }

    _creating = true;
    _error = null;
    notifyListeners();

    try {
      return await GroupApiService.createGroup(
        subject: cleanSubject,
        description: _description.trim(),
        memberIds: _selectedUserIds.toList(growable: false),
        image: _image,
      );
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _creating = false;
      notifyListeners();
    }
  }

  void reset() {
    _searchDebounce?.cancel();
    _selectedUserIds.clear();
    _searchResults.clear();
    _query = '';
    _subject = '';
    _description = '';
    _image = null;
    _searching = false;
    _creating = false;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }
}
