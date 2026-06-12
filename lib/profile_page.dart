// lib/profile_page.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:messaging_app/calls.dart';
import 'package:messaging_app/core/profile/profile_provider.dart';
import 'package:messaging_app/dashboard.dart';
import 'package:messaging_app/login_page.dart';
import 'package:messaging_app/profile_data/profile_data_page.dart';
import 'package:messaging_app/theme_controller.dart';
// import 'package:messaging_app/pages.dart'; // PagesScreen temporarily commented
import 'package:provider/provider.dart';

class ProfileScreen extends StatefulWidget {
  final String chatId;
  final String chatName;

  final String currentUserId;
  final String currentUserName;
  final String currentUserAvatar;

  const ProfileScreen({
    super.key,
    required this.chatId,
    required this.chatName,
    this.currentUserId = '',
    this.currentUserName = '',
    this.currentUserAvatar = '',
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _selectedBottomIndex = 2;
  bool _notificationsEnabled = true;

  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProfileProvider>().loadProfile();
    });
  }

  Future<void> _openProfileDataPage(UserProfile profile) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const ProfileDataPage(),
      ),
    );

    if (!mounted) return;

    if (result == true) {
      await context.read<ProfileProvider>().loadProfile();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _pickAndUploadImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 75,
        maxWidth: 1200,
        maxHeight: 1200,
      );

      if (picked == null) return;

      final file = File(picked.path);

      setState(() {
        _selectedImage = file;
      });

      final ok = await context.read<ProfileProvider>().updateProfileImage(file);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Profile image updated' : 'Image upload failed'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      if (!ok) {
        setState(() {
          _selectedImage = null;
        });
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Image picker error: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showImagePickerSheet() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF111827) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Update profile image',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0x141877F2),
                    child: Icon(
                      Icons.camera_alt_rounded,
                      color: Color(0xFF1877F2),
                    ),
                  ),
                  title: const Text('Take photo'),
                  subtitle: const Text('Use camera instantly'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickAndUploadImage(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0x141877F2),
                    child: Icon(
                      Icons.photo_library_rounded,
                      color: Color(0xFF1877F2),
                    ),
                  ),
                  title: const Text('Choose from gallery'),
                  subtitle: const Text('Upload image from phone'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickAndUploadImage(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _onBottomNavTap(int index) {
    if (_selectedBottomIndex == index) return;

    final profile = context.read<ProfileProvider>().profile;

    Widget? page;

    if (index == 0) {
      page = ChatListScreen(
        currentUserId: profile.id,
        currentUserName: profile.fullName,
        currentUserAvatar: profile.imageUrl,
      );
    } else if (index == 1) {
      page = CallHistoryScreen(
        currentUserId: profile.id,
        currentUserName: profile.fullName,
        currentUserAvatar: profile.imageUrl,
      );
    }

    // PagesScreen temporarily commented.
    // else if (index == 2) {
    //   page = const PagesScreen();
    // }

    else if (index == 2) {
      return;
    }

    if (page != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => page!),
      );
    }
  }

  Future<void> _showLogoutDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final textTheme = Theme.of(context).textTheme;

        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Logout',
            style: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            'Are you sure you want to logout?',
            style: textTheme.bodyLarge,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );

    if (result == true && mounted) {
      await context.read<ProfileProvider>().logoutLocal();

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (route) => false,
      );
    }
  }

  String _displayName(UserProfile profile) {
    if (profile.fullName.trim().isNotEmpty) return profile.fullName.trim();
    if (widget.currentUserName.trim().isNotEmpty) {
      return widget.currentUserName.trim();
    }
    if (widget.chatName.trim().isNotEmpty) return widget.chatName.trim();
    return 'User';
  }

  String _initial(UserProfile profile) {
    final name = _displayName(profile);
    return name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProfileProvider>();
    final profile = provider.profile;

    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF0F2F5);
    final cardColor = isDark ? const Color(0xFF111827) : Colors.white;
    final primaryText = isDark ? Colors.white : const Color(0xFF111827);
    final secondaryText =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF65676B);
    final dividerColor =
        isDark ? const Color(0xFF243041) : const Color(0xFFE4E6EB);
    const accent = Color(0xFF1877F2);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: provider.isLoading && profile.fullName.trim().isEmpty
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (provider.error != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      color: const Color(0xFFEF4444),
                      child: Text(
                        provider.error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: provider.loadProfile,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Column(
                          children: [
                            _buildFacebookHeader(
                              profile: profile,
                              textTheme: textTheme,
                              isDark: isDark,
                              primaryText: primaryText,
                              secondaryText: secondaryText,
                              dividerColor: dividerColor,
                              accent: accent,
                              cardColor: cardColor,
                            ),
                            const SizedBox(height: 12),
                            _buildMenuCard(
                              profile: profile,
                              cardColor: cardColor,
                              dividerColor: dividerColor,
                              primaryText: primaryText,
                              secondaryText: secondaryText,
                              accent: accent,
                            ),
                            const SizedBox(height: 14),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: _showLogoutDialog,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 50,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isDark
                                            ? const Color(0xFF2A1A1A)
                                            : const Color(0xFFFFF1F1),
                                      ),
                                      child: const Icon(
                                        Icons.logout_rounded,
                                        color: Color(0xFFEF4444),
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Text(
                                        'Logout',
                                        style: textTheme.titleLarge?.copyWith(
                                          color: const Color(0xFFEF4444),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.chevron_right_rounded,
                                      color: Color(0xFFEF4444),
                                      size: 26,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _buildBottomNavigation(
                    bgColor: bgColor,
                    dividerColor: dividerColor,
                    accent: accent,
                    secondaryText: secondaryText,
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildFacebookHeader({
    required UserProfile profile,
    required TextTheme textTheme,
    required bool isDark,
    required Color primaryText,
    required Color secondaryText,
    required Color dividerColor,
    required Color accent,
    required Color cardColor,
  }) {
    final name = _displayName(profile);
    final image = profile.imageUrl.trim();

    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              height: 220,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: isDark
                    ? const LinearGradient(
                        colors: [Color(0xFF1E293B), Color(0xFF111827)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : const LinearGradient(
                        colors: [Color(0xFFBFD7FF), Color(0xFFE7F0FF)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
              ),
            ),
            Positioned(
              bottom: -54,
              child: GestureDetector(
                onTap: _showImagePickerSheet,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: cardColor, width: 6),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 22,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: _selectedImage != null
                            ? Image.file(
                                _selectedImage!,
                                fit: BoxFit.cover,
                              )
                            : image.isNotEmpty
                                ? Image.network(
                                    image,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return _imageFallback(accent, profile);
                                    },
                                  )
                                : _imageFallback(accent, profile),
                      ),
                    ),
                    if (context.watch<ProfileProvider>().isSaving)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.35),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 66),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              Text(
                name,
                textAlign: TextAlign.center,
                style: textTheme.headlineMedium?.copyWith(
                  color: primaryText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              if (profile.phone.trim().isNotEmpty)
                Text(
                  profile.phone.trim(),
                  textAlign: TextAlign.center,
                  style: textTheme.bodyLarge?.copyWith(
                    color: secondaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (profile.businessName.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  profile.businessName.trim(),
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: secondaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (profile.bio.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  profile.bio.trim(),
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: primaryText.withOpacity(0.88),
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _openProfileDataPage(profile),
                  icon: const Icon(Icons.edit_rounded, size: 20),
                  label: const Text('Edit Profile'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Divider(color: dividerColor, height: 1),
            ],
          ),
        ),
      ],
    );
  }

  Widget _imageFallback(Color accent, UserProfile profile) {
    return Container(
      color: accent,
      alignment: Alignment.center,
      child: Text(
        _initial(profile),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 56,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildMenuCard({
    required UserProfile profile,
    required Color cardColor,
    required Color dividerColor,
    required Color primaryText,
    required Color secondaryText,
    required Color accent,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: dividerColor),
        ),
        child: Column(
          children: [
            // PagesScreen temporarily commented
            // ProfileMenuTile(
            //   icon: Icons.description_outlined,
            //   title: 'My Pages',
            //   subtitle: 'Manage your business pages',
            //   circleColor: const Color(0xFFEFF3FB),
            //   iconColor: accent,
            //   textColor: primaryText,
            //   subtitleColor: secondaryText,
            //   dividerColor: dividerColor,
            //   onTap: () {
            //     Navigator.push(
            //       context,
            //       MaterialPageRoute(builder: (_) => const PagesScreen()),
            //     );
            //   },
            // ),
            ProfileSwitchTile(
              icon: Icons.notifications_none_outlined,
              title: 'Notifications',
              subtitle: _notificationsEnabled ? 'Enabled' : 'Disabled',
              circleColor: const Color(0xFFEFF3FB),
              iconColor: accent,
              textColor: primaryText,
              subtitleColor: secondaryText,
              dividerColor: dividerColor,
              value: _notificationsEnabled,
              onChanged: (value) {
                setState(() {
                  _notificationsEnabled = value;
                });
              },
            ),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: appThemeMode,
              builder: (context, themeMode, _) {
                final isGlobalDark = themeMode == ThemeMode.dark;

                return ProfileSwitchTile(
                  icon: Icons.dark_mode_outlined,
                  title: 'Dark Mode',
                  subtitle: isGlobalDark ? 'On' : 'Off',
                  circleColor: const Color(0xFFEFF3FB),
                  iconColor: accent,
                  textColor: primaryText,
                  subtitleColor: secondaryText,
                  dividerColor: dividerColor,
                  value: isGlobalDark,
                  onChanged: setAppDarkMode,
                );
              },
            ),
            // Refresh Profile permanently removed.
            // Profile image change is only available from the top circular image.
            // ProfileMenuTile(
            //   icon: Icons.refresh_rounded,
            //   title: 'Refresh Profile',
            //   subtitle: 'Reload profile from backend',
            //   circleColor: const Color(0xFFEFF3FB),
            //   iconColor: accent,
            //   textColor: primaryText,
            //   subtitleColor: secondaryText,
            //   dividerColor: dividerColor,
            //   onTap: () {
            //     context.read<ProfileProvider>().loadProfile();
            //   },
            // ),
            // ProfileMenuTile(
            //   icon: Icons.image_outlined,
            //   title: 'Change Profile Image',
            //   subtitle: 'Camera or gallery',
            //   circleColor: const Color(0xFFEFF3FB),
            //   iconColor: accent,
            //   textColor: primaryText,
            //   subtitleColor: secondaryText,
            //   dividerColor: dividerColor,
            //   onTap: _showImagePickerSheet,
            // ),
            ProfileMenuTile(
              icon: Icons.shield_outlined,
              title: 'Privacy & Security',
              subtitle: 'Manage your data',
              circleColor: const Color(0xFFEFF3FB),
              iconColor: accent,
              textColor: primaryText,
              subtitleColor: secondaryText,
              dividerColor: dividerColor,
              onTap: () {},
            ),
            ProfileMenuTile(
              icon: Icons.help_outline_rounded,
              title: 'Help & Support',
              subtitle: 'Get help with SocialConnect',
              circleColor: const Color(0xFFEFF3FB),
              iconColor: accent,
              textColor: primaryText,
              subtitleColor: secondaryText,
              dividerColor: dividerColor,
              showDivider: false,
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavigation({
    required Color bgColor,
    required Color dividerColor,
    required Color accent,
    required Color secondaryText,
  }) {
    final textTheme = Theme.of(context).textTheme;

    final items = [
      _BottomNavItemData(Icons.chat_bubble_outline, 'Chats'),
      _BottomNavItemData(Icons.call_outlined, 'Calls'),

      // PagesScreen temporarily commented
      // _BottomNavItemData(Icons.description_outlined, 'Pages'),

      _BottomNavItemData(Icons.person_outline, 'Profile'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          top: BorderSide(color: dividerColor, width: 1),
        ),
      ),
      padding: const EdgeInsets.only(top: 6, bottom: 10),
      child: Row(
        children: List.generate(items.length, (index) {
          final isSelected = _selectedBottomIndex == index;

          return Expanded(
            child: InkWell(
              onTap: () => _onBottomNavTap(index),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 72,
                    height: 3,
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  Icon(
                    items[index].icon,
                    size: 24,
                    color: isSelected ? accent : secondaryText,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    items[index].label,
                    style: textTheme.labelMedium?.copyWith(
                      color: isSelected ? accent : secondaryText,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class ProfileMenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color circleColor;
  final Color iconColor;
  final Color textColor;
  final Color subtitleColor;
  final Color dividerColor;
  final VoidCallback onTap;
  final bool showDivider;

  const ProfileMenuTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.circleColor,
    required this.iconColor,
    required this.textColor,
    required this.subtitleColor,
    required this.dividerColor,
    required this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: circleColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: iconColor, size: 23),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: subtitleColor,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: subtitleColor,
                  size: 26,
                ),
              ],
            ),
          ),
          if (showDivider)
            Padding(
              padding: const EdgeInsets.only(left: 72),
              child: Divider(color: dividerColor, height: 1),
            ),
        ],
      ),
    );
  }
}

class ProfileSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color circleColor;
  final Color iconColor;
  final Color textColor;
  final Color subtitleColor;
  final Color dividerColor;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool showDivider;

  const ProfileSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.circleColor,
    required this.iconColor,
    required this.textColor,
    required this.subtitleColor,
    required this.dividerColor,
    required this.value,
    required this.onChanged,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: circleColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 23),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: subtitleColor,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                activeColor: const Color(0xFF1877F2),
              ),
            ],
          ),
        ),
        if (showDivider)
          Padding(
            padding: const EdgeInsets.only(left: 72),
            child: Divider(color: dividerColor, height: 1),
          ),
      ],
    );
  }
}

class _BottomNavItemData {
  final IconData icon;
  final String label;

  const _BottomNavItemData(this.icon, this.label);
}
