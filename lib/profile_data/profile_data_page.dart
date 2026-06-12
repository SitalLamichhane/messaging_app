// lib/profile_data/profile_data_page.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:messaging_app/core/profile/profile_provider.dart';
import 'package:provider/provider.dart';

class ProfileDataPage extends StatefulWidget {
  const ProfileDataPage({super.key});

  @override
  State<ProfileDataPage> createState() => _ProfileDataPageState();
}

class _ProfileDataPageState extends State<ProfileDataPage> {
  final ImagePicker _picker = ImagePicker();

  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _businessController;
  late TextEditingController _bioController;

  bool _showPhoneNumber = true;
  bool _activeStatus = true;
  bool _messageRequests = true;

  File? _selectedImage;
  String _networkImageUrl = '';

  @override
  void initState() {
    super.initState();

    final profile = context.read<ProfileProvider>().profile;

    _nameController = TextEditingController(text: profile.fullName);
    _phoneController = TextEditingController(text: profile.phone);
    _businessController = TextEditingController(text: profile.businessName);
    _bioController = TextEditingController(text: profile.bio);
    _networkImageUrl = profile.imageUrl;

    _nameController.addListener(_refresh);
    _phoneController.addListener(_refresh);
    _businessController.addListener(_refresh);
    _bioController.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _nameController.removeListener(_refresh);
    _phoneController.removeListener(_refresh);
    _businessController.removeListener(_refresh);
    _bioController.removeListener(_refresh);

    _nameController.dispose();
    _phoneController.dispose();
    _businessController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 75,
      maxWidth: 1200,
      maxHeight: 1200,
    );

    if (picked == null) return;

    setState(() {
      _selectedImage = File(picked.path);
    });
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
                  'Change profile image',
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
                    _pickImage(ImageSource.camera);
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
                    _pickImage(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Full name is required'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final ok = await context.read<ProfileProvider>().updateProfile(
          fullName: name,
          businessName: _businessController.text.trim(),
          bio: _bioController.text.trim(),
          image: _selectedImage,
        );

    if (!mounted) return;

    if (ok) {
      Navigator.pop(context, true);
      return;
    }

    final error = context.read<ProfileProvider>().error ?? 'Profile update failed';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _initial() {
    final name = _nameController.text.trim();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProfileProvider>();

    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF0F2F5);
    final cardColor = isDark ? const Color(0xFF111827) : Colors.white;
    final primaryText = isDark ? Colors.white : const Color(0xFF111827);
    final secondaryText =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF65676B);
    final dividerColor =
        isDark ? const Color(0xFF243041) : const Color(0xFFE4E6EB);
    final subtleBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF3F4F6);
    const accent = Color(0xFF1877F2);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(
              textTheme: textTheme,
              primaryText: primaryText,
              accent: accent,
              isSaving: provider.isSaving,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: Column(
                  children: [
                    _buildHeaderCard(
                      textTheme: textTheme,
                      cardColor: cardColor,
                      primaryText: primaryText,
                      secondaryText: secondaryText,
                      dividerColor: dividerColor,
                    ),
                    const SizedBox(height: 16),
                    _buildInfoCard(
                      cardColor: cardColor,
                      dividerColor: dividerColor,
                      primaryText: primaryText,
                      secondaryText: secondaryText,
                      subtleBg: subtleBg,
                    ),
                    const SizedBox(height: 16),
                    // _buildPrivacyCard(
                    //   cardColor: cardColor,
                    //   dividerColor: dividerColor,
                    //   primaryText: primaryText,
                    //   secondaryText: secondaryText,
                    // ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar({
    required TextTheme textTheme,
    required Color primaryText,
    required Color accent,
    required bool isSaving,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: isSaving ? null : () => Navigator.pop(context, false),
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Color(0xFF1877F2),
              size: 22,
            ),
          ),
          Expanded(
            child: Text(
              'Profile details',
              textAlign: TextAlign.center,
              style: textTheme.titleLarge?.copyWith(
                color: primaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: isSaving ? null : _saveProfile,
            child: isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    'Save',
                    style: textTheme.titleMedium?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard({
    required TextTheme textTheme,
    required Color cardColor,
    required Color primaryText,
    required Color secondaryText,
    required Color dividerColor,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: dividerColor),
      ),
      child: Column(
        children: [
          Container(
            height: 170,
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFBFD7FF), Color(0xFFE8F0FF)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -54),
            child: GestureDetector(
              onTap: _showImagePickerSheet,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 116,
                    height: 116,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: cardColor, width: 5),
                    ),
                    child: ClipOval(
                      child: _selectedImage != null
                          ? Image.file(
                              _selectedImage!,
                              fit: BoxFit.cover,
                            )
                          : _networkImageUrl.trim().isNotEmpty
                              ? Image.network(
                                  _networkImageUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return _fallbackImage();
                                  },
                                )
                              : _fallbackImage(),
                    ),
                  ),
                  Positioned(
                    right: -2,
                    bottom: 2,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1877F2),
                        shape: BoxShape.circle,
                        border: Border.all(color: cardColor, width: 3),
                      ),
                      child: const Icon(
                        Icons.camera_alt_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              children: [
                Text(
                  _nameController.text.trim().isEmpty
                      ? 'User Name'
                      : _nameController.text.trim(),
                  style: textTheme.headlineSmall?.copyWith(
                    color: primaryText,
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                if (_showPhoneNumber && _phoneController.text.trim().isNotEmpty)
                  _buildMiniInfoRow(
                    icon: Icons.phone_outlined,
                    text: _phoneController.text.trim(),
                    secondaryText: secondaryText,
                  ),
                if (_businessController.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _buildMiniInfoRow(
                    icon: Icons.business_center_outlined,
                    text: _businessController.text.trim(),
                    secondaryText: secondaryText,
                  ),
                ],
                if (_bioController.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    _bioController.text.trim(),
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(
                      color: primaryText.withOpacity(0.9),
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallbackImage() {
    return Container(
      color: const Color(0xFF1877F2),
      alignment: Alignment.center,
      child: Text(
        _initial(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 46,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildMiniInfoRow({
    required IconData icon,
    required String text,
    required Color secondaryText,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: secondaryText),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              color: secondaryText,
              fontWeight: FontWeight.w600,
              fontSize: 14.5,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard({
    required Color cardColor,
    required Color dividerColor,
    required Color primaryText,
    required Color secondaryText,
    required Color subtleBg,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: dividerColor),
      ),
      child: Column(
        children: [
          _SectionTitle(
            title: 'Info',
            icon: Icons.info_outline_rounded,
            primaryText: primaryText,
          ),
          _EditableFieldTile(
            label: 'Full name',
            controller: _nameController,
            enabled: true,
            primaryText: primaryText,
            secondaryText: secondaryText,
            dividerColor: dividerColor,
            subtleBg: subtleBg,
          ),
          _EditableFieldTile(
            label: 'Phone number',
            controller: _phoneController,
            enabled: false,
            primaryText: primaryText,
            secondaryText: secondaryText,
            dividerColor: dividerColor,
            subtleBg: subtleBg,
            readOnlyBadge: 'Not editable',
          ),
          _EditableFieldTile(
            label: 'Business',
            controller: _businessController,
            enabled: true,
            primaryText: primaryText,
            secondaryText: secondaryText,
            dividerColor: dividerColor,
            subtleBg: subtleBg,
          ),
          _EditableFieldTile(
            label: 'Bio',
            controller: _bioController,
            enabled: true,
            primaryText: primaryText,
            secondaryText: secondaryText,
            dividerColor: dividerColor,
            subtleBg: subtleBg,
            maxLines: 4,
            showDivider: false,
          ),
        ],
      ),
    );
  }

  // Widget _buildPrivacyCard({
  //   required Color cardColor,
  //   required Color dividerColor,
  //   required Color primaryText,
  //   required Color secondaryText,
  // }) {
  //   return Container(
  //     width: double.infinity,
  //     decoration: BoxDecoration(
  //       color: cardColor,
  //       borderRadius: BorderRadius.circular(24),
  //       border: Border.all(color: dividerColor),
  //     ),
  //     child: Column(
  //       children: [
  //         _SectionTitle(
  //           title: 'Privacy',
  //           icon: Icons.lock_outline_rounded,
  //           primaryText: primaryText,
  //         ),
  //         _SwitchTileRow(
  //           title: 'Show phone number',
  //           subtitle: 'Allow people to see your number',
  //           value: _showPhoneNumber,
  //           onChanged: (value) {
  //             setState(() {
  //               _showPhoneNumber = value;
  //             });
  //           },
  //           primaryText: primaryText,
  //           secondaryText: secondaryText,
  //           dividerColor: dividerColor,
  //         ),
  //         _SwitchTileRow(
  //           title: 'Active status',
  //           subtitle: 'Show when you are active',
  //           value: _activeStatus,
  //           onChanged: (value) {
  //             setState(() {
  //               _activeStatus = value;
  //             });
  //           },
  //           primaryText: primaryText,
  //           secondaryText: secondaryText,
  //           dividerColor: dividerColor,
  //         ),
  //         _SwitchTileRow(
  //           title: 'Message requests',
  //           subtitle: 'Receive message requests from others',
  //           value: _messageRequests,
  //           onChanged: (value) {
  //             setState(() {
  //               _messageRequests = value;
  //             });
  //           },
  //           primaryText: primaryText,
  //           secondaryText: secondaryText,
  //           dividerColor: dividerColor,
  //           showDivider: false,
  //         ),
  //       ],
  //     ),
  //   );
  // }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color primaryText;

  const _SectionTitle({
    required this.title,
    required this.icon,
    required this.primaryText,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
      child: Row(
        children: [
          Icon(
            icon,
            color: const Color(0xFF1877F2),
            size: 20,
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(
              color: primaryText,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EditableFieldTile extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool enabled;
  final Color primaryText;
  final Color secondaryText;
  final Color dividerColor;
  final Color subtleBg;
  final bool showDivider;
  final int maxLines;
  final String? readOnlyBadge;

  const _EditableFieldTile({
    required this.label,
    required this.controller,
    required this.enabled,
    required this.primaryText,
    required this.secondaryText,
    required this.dividerColor,
    required this.subtleBg,
    this.showDivider = true,
    this.maxLines = 1,
    this.readOnlyBadge,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: secondaryText,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (readOnlyBadge != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x141877F2),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        readOnlyBadge!,
                        style: const TextStyle(
                          color: Color(0xFF1877F2),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                enabled: enabled,
                readOnly: !enabled,
                maxLines: maxLines,
                style: TextStyle(
                  color: primaryText,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: subtleBg,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(
                      color: Color(0xFF1877F2),
                      width: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Divider(
              height: 1,
              thickness: 1,
              color: dividerColor,
            ),
          ),
      ],
    );
  }
}

class _SwitchTileRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color primaryText;
  final Color secondaryText;
  final Color dividerColor;
  final bool showDivider;

  const _SwitchTileRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.primaryText,
    required this.secondaryText,
    required this.dividerColor,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: primaryText,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: secondaryText,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: Colors.white,
                activeTrackColor: const Color(0xFF1877F2),
              ),
            ],
          ),
        ),
        if (showDivider)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Divider(
              height: 1,
              thickness: 1,
              color: dividerColor,
            ),
          ),
      ],
    );
  }
}
