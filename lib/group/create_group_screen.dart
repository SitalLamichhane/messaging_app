import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hiddenly/group/group_api_service.dart';
import 'package:hiddenly/group/group_models.dart';
import 'package:image_picker/image_picker.dart';

class CreateGroupScreen extends StatefulWidget {
  final GroupMember? preselectedMember;

  const CreateGroupScreen({
    super.key,
    this.preselectedMember,
  });

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _subjectController = TextEditingController();
  final _searchController = TextEditingController();
  final _picker = ImagePicker();
  final Map<String, GroupMember> _selected = {};

  Timer? _debounce;
  File? _image;
  List<GroupMember> _results = const [];
  bool _searching = false;
  bool _creating = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    final member = widget.preselectedMember;
    if (member != null) _selected[member.id] = member;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _subjectController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  Future<void> _search() async {
    final q = _searchController.text.trim();
    if (q.isEmpty) {
      if (mounted) setState(() => _results = const []);
      return;
    }

    setState(() {
      _searching = true;
      _error = '';
    });

    try {
      final users = await GroupApiService.searchUsers(q);
      if (!mounted) return;
      setState(() => _results = users.where((u) => !u.isCurrentUser).toList());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not search contacts');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (picked != null && mounted) {
      setState(() => _image = File(picked.path));
    }
  }

  void _toggle(GroupMember user) {
    setState(() {
      if (_selected.containsKey(user.id)) {
        _selected.remove(user.id);
      } else {
        _selected[user.id] = user;
      }
    });
  }

  bool get _canCreate =>
      !_creating &&
      _subjectController.text.trim().isNotEmpty &&
      _selected.isNotEmpty;

  Future<void> _create() async {
    if (!_canCreate) return;

    setState(() {
      _creating = true;
      _error = '';
    });

    try {
      final group = await GroupApiService.createGroup(
        subject: _subjectController.text.trim(),
        memberIds: _selected.keys.toList(),
        image: _image,
      );
      if (!mounted) return;
      Navigator.pop(context, group);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const green = Color(0xFF00A884);

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New group'),
            Text(
              'Add participants',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _pickImage,
                    child: CircleAvatar(
                      radius: 30,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      backgroundImage: _image == null ? null : FileImage(_image!),
                      child: _image == null
                          ? const Icon(Icons.camera_alt_rounded, size: 28)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: TextField(
                      controller: _subjectController,
                      maxLength: 100,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Group subject',
                        hintText: 'Type group subject here',
                        counterText: '',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_selected.isNotEmpty)
              SizedBox(
                height: 92,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  scrollDirection: Axis.horizontal,
                  itemCount: _selected.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final user = _selected.values.elementAt(index);
                    return SizedBox(
                      width: 68,
                      child: Column(
                        children: [
                          Stack(
                            children: [
                              _Avatar(url: user.avatarUrl, name: user.name, radius: 25),
                              Positioned(
                                right: -2,
                                bottom: -2,
                                child: InkWell(
                                  onTap: () => _toggle(user),
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.surface,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.cancel, size: 18),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _searchController,
                keyboardType: TextInputType.text,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search name or number',
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
              ),
            ),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_error, style: const TextStyle(color: Colors.red)),
                ),
              ),
            Expanded(
              child: _searchController.text.trim().isEmpty
                  ? const Center(
                      child: Text('Search contacts to add participants'),
                    )
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final user = _results[index];
                        final checked = _selected.containsKey(user.id);
                        return ListTile(
                          leading: _Avatar(
                            url: user.avatarUrl,
                            name: user.name,
                            radius: 23,
                          ),
                          title: Text(user.name),
                          subtitle: user.phone.isEmpty ? null : Text(user.phone),
                          trailing: Checkbox(
                            value: checked,
                            activeColor: green,
                            onChanged: (_) => _toggle(user),
                          ),
                          onTap: () => _toggle(user),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _canCreate ? green : Colors.grey,
        foregroundColor: Colors.white,
        onPressed: _canCreate ? _create : null,
        child: _creating
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.check),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String url;
  final String name;
  final double radius;

  const _Avatar({required this.url, required this.name, required this.radius});

  @override
  Widget build(BuildContext context) {
    final clean = url.trim();
    return CircleAvatar(
      radius: radius,
      backgroundImage: clean.startsWith('http') ? NetworkImage(clean) : null,
      child: clean.startsWith('http')
          ? null
          : Text(name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase()),
    );
  }
}
