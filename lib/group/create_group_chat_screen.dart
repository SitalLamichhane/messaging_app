

import 'package:flutter/material.dart';
import 'package:messaging_app/chat_detail.dart';
import 'package:messaging_app/chat_models.dart';
import 'package:messaging_app/core/chat/chat_provider.dart';
import 'package:provider/provider.dart';

class CreateGroupChatScreen extends StatefulWidget {
  final ChatUser? preSelectedUser;

  const CreateGroupChatScreen({
    super.key,
    this.preSelectedUser,
  });

  @override
  State<CreateGroupChatScreen> createState() => _CreateGroupChatScreenState();
}

class _CreateGroupChatScreenState extends State<CreateGroupChatScreen> {
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _phoneSearchController = TextEditingController();

  final Set<String> _selectedUserIds = {};

  bool _isCreating = false;
  String _phoneQuery = '';

  @override
  void initState() {
    super.initState();

    if (widget.preSelectedUser != null) {
      _selectedUserIds.add(widget.preSelectedUser!.id);
    }

    _phoneSearchController.addListener(() {
      setState(() {
        _phoneQuery = _phoneSearchController.text.trim();
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().loadConversations();
    });
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    _phoneSearchController.dispose();
    super.dispose();
  }

  String _digitsOnly(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }

  Future<void> _createGroup() async {
    final name = _groupNameController.text.trim();

    if (name.isEmpty || _selectedUserIds.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter group name and select at least 2 people'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final memberIds = _selectedUserIds
        .map((id) => int.tryParse(id))
        .whereType<int>()
        .toList();

    if (memberIds.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selected users are invalid'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isCreating = true);

    final provider = context.read<ChatProvider>();

    final group = await provider.createGroup(
      name: name,
      memberIds: memberIds,
    );

    if (!mounted) return;

    setState(() => _isCreating = false);

    if (group == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Failed to create group'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(chat: group),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();

    final allUsers = provider.conversations
        .where((chat) => chat.isGroup != true)
        .toList();

    final searchDigits = _digitsOnly(_phoneQuery);

    final users = searchDigits.isEmpty
        ? allUsers
        : allUsers.where((user) {
            final phone = _digitsOnly(
         ((user as dynamic).phone ?? '').toString(),
          );
            return phone.contains(searchDigits);
          }).toList();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0B1220) : Colors.white;
    final card = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F2F6);
    final text = isDark ? Colors.white : Colors.black87;
    final subText = isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: text),
          onPressed: _isCreating ? null : () => Navigator.pop(context),
        ),
        title: Text(
          'New group',
          style: TextStyle(
            color: text,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isCreating ? null : _createGroup,
            child: _isCreating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Create',
                    style: TextStyle(
                      color: Color(0xFF1877F2),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 28,
                  backgroundColor: Color(0xFF1877F2),
                  child: Icon(Icons.groups_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _groupNameController,
                    enabled: !_isCreating,
                    style: TextStyle(color: text),
                    decoration: InputDecoration(
                      hintText: 'Group name',
                      hintStyle: TextStyle(color: subText),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
            child: Row(
              children: [
                Text(
                  'Select people',
                  style: TextStyle(
                    color: text,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_selectedUserIds.length} selected',
                  style: TextStyle(
                    color: subText,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _phoneSearchController,
              enabled: !_isCreating,
              keyboardType: TextInputType.phone,
              style: TextStyle(color: text),
              decoration: InputDecoration(
                hintText: 'Search by phone number',
                hintStyle: TextStyle(color: subText),
                prefixIcon: const Icon(
                  Icons.phone_rounded,
                  color: Color(0xFF1877F2),
                ),
                suffixIcon: _phoneQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close_rounded, color: subText),
                        onPressed: () => _phoneSearchController.clear(),
                      )
                    : null,
                filled: true,
                fillColor: card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          if (provider.isLoading && allUsers.isEmpty)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (users.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  searchDigits.isEmpty
                      ? 'No users found.'
                      : 'No user found with this phone number.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: subText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: users.length,
                itemBuilder: (context, index) {
                  final user = users[index];
                  final selected = _selectedUserIds.contains(user.id);

                  return ListTile(
                    enabled: !_isCreating,
                    onTap: () {
                      setState(() {
                        if (selected) {
                          _selectedUserIds.remove(user.id);
                        } else {
                          _selectedUserIds.add(user.id);
                        }
                      });
                    },
                    leading: CircleAvatar(
                      backgroundImage: user.avatarUrl.trim().isNotEmpty
                          ? NetworkImage(user.avatarUrl)
                          : null,
                      child: user.avatarUrl.trim().isEmpty
                          ? Text(
                              user.name.isNotEmpty
                                  ? user.name[0].toUpperCase()
                                  : 'U',
                            )
                          : null,
                    ),
                    title: Text(
                      user.name,
                      style: TextStyle(
                        color: text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      (() {
                     final phone = ((user as dynamic).phone ?? '').toString();
                     return phone.isNotEmpty ? phone : 'No phone number';
                     })(),
                      style: TextStyle(color: subText),
                    ),
                    trailing: CircleAvatar(
                      radius: 13,
                      backgroundColor: selected
                          ? const Color(0xFF1877F2)
                          : Colors.transparent,
                      child: selected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 18,
                            )
                          : Icon(
                              Icons.circle_outlined,
                              color: subText,
                              size: 26,
                            ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}