// // Replace your existing _createGroupWithThisUser() in ChatSettingsScreen
// // with this version.

// Future<void> _createGroupWithThisUser() async {
//   final targetUserId = _targetUserIdForBlock();

//   if (targetUserId.trim().isEmpty) {
//     _showSnackBar('User not found');
//     return;
//   }

//   final createdGroup = await Navigator.push<ChatItem>(
//     context,
//     MaterialPageRoute(
//       builder: (_) => CreateGroupChatScreen(
//         currentUserId: widget.currentUserId,
//         preSelectedUser: ChatUser(
//           id: targetUserId,
//           name: widget.chat.name,
//           avatarUrl: _resolvedChatAvatarUrl(),
//           isOnline: widget.chat.isOnline,
//         ),
//       ),
//     ),
//   );

//   if (createdGroup == null || !mounted) {
//     return;
//   }

//   AppChatData.notify();

//   _showSnackBar(
//     '${createdGroup.name} created',
//   );

//   // Return the newly-created group to the chat screen that opened settings.
//   Navigator.pop<ChatItem>(
//     context,
//     createdGroup,
//   );
// }
