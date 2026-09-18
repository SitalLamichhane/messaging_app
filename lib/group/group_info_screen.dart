import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hiddenly/group/group_api_service.dart';
import 'package:hiddenly/group/group_call_screen.dart';
import 'package:hiddenly/group/group_models.dart';
import 'package:image_picker/image_picker.dart';

class GroupInfoScreen extends StatefulWidget {
  final String conversationId;

  const GroupInfoScreen({super.key, required this.conversationId});

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  final _picker = ImagePicker();
  GroupDetails? _group;
  bool _loading = true;
  bool _busy = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final group = await GroupApiService.getGroup(widget.conversationId);
      if (mounted) setState(() => _group = group);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editSubject() async {
    final group = _group!;
    final controller = TextEditingController(text: group.subject);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Group subject'),
        content: TextField(controller: controller, maxLength: 100, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty || value == group.subject) return;
    await _run(() async {
      _group = await GroupApiService.updateGroup(
        conversationId: widget.conversationId,
        subject: value,
      );
      if (mounted) setState(() {});
    });
  }

  Future<void> _editDescription() async {
    final group = _group!;
    final controller = TextEditingController(text: group.description);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Group description'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          maxLength: 2048,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value == group.description) return;
    await _run(() async {
      _group = await GroupApiService.updateGroup(
        conversationId: widget.conversationId,
        description: value,
      );
      if (mounted) setState(() {});
    });
  }

  Future<void> _changeImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(children: [
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
        ]),
      ),
    );
    if (source == null) return;
    final picked = await _picker.pickImage(source: source, imageQuality: 85, maxWidth: 1600);
    if (picked == null) return;
    await _run(() async {
      _group = await GroupApiService.updateGroup(
        conversationId: widget.conversationId,
        image: File(picked.path),
      );
      if (mounted) setState(() {});
    });
  }

  Future<void> _addParticipants() async {
    final group = _group!;
    final selected = <String, GroupMember>{};
    final controller = TextEditingController();
    List<GroupMember> results = [];
    bool searching = false;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> search() async {
            final q = controller.text.trim();
            if (q.isEmpty) return;
            setSheetState(() => searching = true);
            try {
              final all = await GroupApiService.searchUsers(q);
              final ids = group.members.map((e) => e.id).toSet();
              setSheetState(() => results = all.where((u) => !ids.contains(u.id)).toList());
            } finally {
              setSheetState(() => searching = false);
            }
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * .72,
                child: Column(
                  children: [
                    Row(children: [
                      const Expanded(
                        child: Text('Add participants', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                      ),
                      TextButton(
                        onPressed: selected.isEmpty ? null : () => Navigator.pop(sheetContext, true),
                        child: const Text('Add'),
                      ),
                    ]),
                    TextField(
                      controller: controller,
                      onSubmitted: (_) => search(),
                      decoration: InputDecoration(
                        hintText: 'Search name or number',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: searching
                            ? const Padding(
                                padding: EdgeInsets.all(14),
                                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                              )
                            : IconButton(icon: const Icon(Icons.arrow_forward), onPressed: search),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: results.length,
                        itemBuilder: (_, i) {
                          final user = results[i];
                          final checked = selected.containsKey(user.id);
                          return CheckboxListTile(
                            value: checked,
                            title: Text(user.name),
                            subtitle: user.phone.isEmpty ? null : Text(user.phone),
                            secondary: _avatar(user, 22),
                            onChanged: (_) => setSheetState(() {
                              if (checked) {
                                selected.remove(user.id);
                              } else {
                                selected[user.id] = user;
                              }
                            }),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    controller.dispose();
    if (confirmed != true || selected.isEmpty) return;
    await _run(() async {
      _group = await GroupApiService.addMembers(
        conversationId: widget.conversationId,
        userIds: selected.keys.toList(),
      );
      if (mounted) setState(() {});
    });
  }

  Future<void> _memberActions(GroupMember member) async {
    final group = _group!;
    if (member.isCurrentUser) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: Icon(member.isBlockedByMe ? Icons.lock_open : Icons.block),
            title: Text(member.isBlockedByMe ? 'Unblock ${member.name}' : 'Block ${member.name}'),
            subtitle: const Text('Blocking does not remove this person from the group.'),
            onTap: () => Navigator.pop(context, member.isBlockedByMe ? 'unblock' : 'block'),
          ),
          if (group.isCurrentUserAdmin)
            ListTile(
              leading: Icon(member.isAdmin ? Icons.person_remove_alt_1 : Icons.admin_panel_settings_outlined),
              title: Text(member.isAdmin ? 'Dismiss as admin' : 'Make group admin'),
              onTap: () => Navigator.pop(context, member.isAdmin ? 'dismiss_admin' : 'make_admin'),
            ),
          if (group.isCurrentUserAdmin)
            ListTile(
              leading: const Icon(Icons.person_remove_outlined, color: Colors.red),
              title: Text('Remove ${member.name}', style: const TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
        ]),
      ),
    );

    if (action == null) return;
    await _run(() async {
      if (action == 'block') await GroupApiService.blockMember(member.id);
      if (action == 'unblock') await GroupApiService.unblockMember(member.id);
      if (action == 'make_admin' || action == 'dismiss_admin') {
        _group = await GroupApiService.setAdmin(
          conversationId: widget.conversationId,
          userId: member.id,
          makeAdmin: action == 'make_admin',
        );
      }
      if (action == 'remove') {
        _group = await GroupApiService.removeMember(
          conversationId: widget.conversationId,
          userId: member.id,
        );
      }
      if (action == 'block' || action == 'unblock') await _reload();
      if (mounted) setState(() {});
    });
  }

  Future<void> _openPermissions() async {
    var permissions = _group!.permissions;
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('Group permissions', style: TextStyle(fontWeight: FontWeight.w700))),
              SwitchListTile(
                title: const Text('Edit group settings'),
                subtitle: const Text('Only admins'),
                value: permissions.onlyAdminsCanEditInfo,
                onChanged: (v) => setSheetState(() => permissions = GroupPermissions(
                  onlyAdminsCanEditInfo: v,
                  onlyAdminsCanSendMessages: permissions.onlyAdminsCanSendMessages,
                  onlyAdminsCanAddMembers: permissions.onlyAdminsCanAddMembers,
                )),
              ),
              SwitchListTile(
                title: const Text('Send messages'),
                subtitle: const Text('Only admins'),
                value: permissions.onlyAdminsCanSendMessages,
                onChanged: (v) => setSheetState(() => permissions = GroupPermissions(
                  onlyAdminsCanEditInfo: permissions.onlyAdminsCanEditInfo,
                  onlyAdminsCanSendMessages: v,
                  onlyAdminsCanAddMembers: permissions.onlyAdminsCanAddMembers,
                )),
              ),
              SwitchListTile(
                title: const Text('Add other members'),
                subtitle: const Text('Only admins'),
                value: permissions.onlyAdminsCanAddMembers,
                onChanged: (v) => setSheetState(() => permissions = GroupPermissions(
                  onlyAdminsCanEditInfo: permissions.onlyAdminsCanEditInfo,
                  onlyAdminsCanSendMessages: permissions.onlyAdminsCanSendMessages,
                  onlyAdminsCanAddMembers: v,
                )),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await _run(() async {
                        _group = await GroupApiService.updatePermissions(
                          conversationId: widget.conversationId,
                          permissions: permissions,
                        );
                        if (mounted) setState(() {});
                      });
                    },
                    child: const Text('Save'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startCall(bool video) async {
    await _run(() async {
      final creds = await GroupApiService.startCall(
        conversationId: widget.conversationId,
        video: video,
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GroupCallScreen(
            callId: creds.call.callId,
            conversationId: widget.conversationId,
            groupName: _group!.subject,
            serverUrl: creds.url,
            token: creds.token,
            roomName: creds.call.roomName,
            startWithVideo: video,
          ),
        ),
      );
    });
  }

  Future<void> _exit() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Exit group?'),
        content: const Text('You will no longer be able to send or receive messages in this group.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Exit', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (yes != true) return;
    await _run(() async {
      await GroupApiService.exitGroup(widget.conversationId);
      if (mounted) Navigator.pop(context, 'exited');
    });
  }

  Widget _avatar(GroupMember member, double radius) {
    final u = member.avatarUrl.trim();
    return CircleAvatar(
      radius: radius,
      backgroundImage: u.startsWith('http') ? NetworkImage(u) : null,
      child: u.startsWith('http') ? null : Text(member.name.isEmpty ? '?' : member.name[0].toUpperCase()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error.isNotEmpty || _group == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error.isEmpty ? 'Group not available' : _error),
          TextButton(onPressed: _reload, child: const Text('Try again')),
        ])),
      );
    }

    final g = _group!;
    final canEditInfo = g.isCurrentUserAdmin || !g.permissions.onlyAdminsCanEditInfo;
    final canAdd = g.isCurrentUserAdmin || !g.permissions.onlyAdminsCanAddMembers;

    return Scaffold(
      appBar: AppBar(title: const Text('Group info')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const SizedBox(height: 16),
            Center(
              child: GestureDetector(
                onTap: canEditInfo ? _changeImage : null,
                child: CircleAvatar(
                  radius: 64,
                  backgroundImage: g.imageUrl.startsWith('http') ? NetworkImage(g.imageUrl) : null,
                  child: g.imageUrl.startsWith('http') ? null : const Icon(Icons.groups_rounded, size: 54),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Center(child: Text(g.subject, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600))),
            Center(child: Text('Group · ${g.members.length} participants')),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _RoundAction(icon: Icons.call, label: 'Audio', onTap: () => _startCall(false)),
                const SizedBox(width: 24),
                _RoundAction(icon: Icons.videocam, label: 'Video', onTap: () => _startCall(true)),
                if (canAdd) ...[
                  const SizedBox(width: 24),
                  _RoundAction(icon: Icons.person_add_alt_1, label: 'Add', onTap: _addParticipants),
                ],
              ],
            ),
            const Divider(height: 32),
            ListTile(
              title: Text(g.description.isEmpty ? 'Add group description' : g.description),
              subtitle: const Text('Group description'),
              trailing: canEditInfo ? const Icon(Icons.edit_outlined) : null,
              onTap: canEditInfo ? _editDescription : null,
            ),
            if (canEditInfo)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit group subject'),
                onTap: _editSubject,
              ),
            if (g.isCurrentUserAdmin)
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('Group permissions'),
                onTap: _openPermissions,
              ),
            const Divider(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text('${g.members.length} participants', style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (canAdd)
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_add_alt_1)),
                title: const Text('Add participants'),
                onTap: _addParticipants,
              ),
            ...g.members.map((member) => ListTile(
                  leading: _avatar(member, 22),
                  title: Text(member.isCurrentUser ? '${member.name} (You)' : member.name),
                  subtitle: member.phone.isEmpty ? null : Text(member.phone),
                  trailing: member.isAdmin
                      ? const Text('Group admin', style: TextStyle(color: Color(0xFF00A884), fontSize: 12))
                      : member.isBlockedByMe
                          ? const Icon(Icons.block, size: 18)
                          : null,
                  onTap: () => _memberActions(member),
                )),
            const Divider(height: 28),
            ListTile(
              leading: const Icon(Icons.exit_to_app, color: Colors.red),
              title: const Text('Exit group', style: TextStyle(color: Colors.red)),
              onTap: _exit,
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _RoundAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const SizedBox(),
        ),
        Transform.translate(
          offset: const Offset(0, -52),
          child: SizedBox(width: 52, height: 52, child: Icon(icon, color: const Color(0xFF00A884))),
        ),
        Transform.translate(
          offset: const Offset(0, -45),
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
      ]),
    );
  }
}
