import 'package:flutter/material.dart';
import 'package:hiddenly/dashboard.dart';
import 'package:hiddenly/features/auth/auth_api.dart';
import 'package:hiddenly/core/api_client.dart';

class ProfileSetupScreen extends StatefulWidget {
  final String signupToken;

  const ProfileSetupScreen({
    super.key,
    required this.signupToken,
  });

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _businessController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();

  final FocusNode _nameFocus = FocusNode();
  final FocusNode _businessFocus = FocusNode();
  final FocusNode _bioFocus = FocusNode();

  bool _isSubmitting = false;
  bool _nameTouched = false;
  bool _businessTouched = false;
  bool _bioTouched = false;

  bool get _canCompleteSetup =>
      _normalizeSpaces(_nameController.text).isNotEmpty;

  @override
  void dispose() {
    _nameController.dispose();
    _businessController.dispose();
    _bioController.dispose();
    _nameFocus.dispose();
    _businessFocus.dispose();
    _bioFocus.dispose();
    super.dispose();
  }

  String _normalizeSpaces(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  bool _startsWithLetter(String value) {
    return RegExp(r'^[A-Za-z]').hasMatch(value);
  }

  String? _validateName(String? value) {
    final text = _normalizeSpaces(value ?? '');

    if (text.isEmpty) {
      return 'Your name is required';
    }

    if (!_startsWithLetter(text)) {
      return 'Your name must start with a letter';
    }

    if (text.length < 2) {
      return 'Your name must be at least 2 characters';
    }

    return null;
  }

  String? _validateOptionalText(
    String? value, {
    required String fieldLabel,
    int maxLength = 120,
  }) {
    final text = _normalizeSpaces(value ?? '');

    if (text.isEmpty) return null;

    if (!_startsWithLetter(text)) {
      return '$fieldLabel must start with a letter';
    }

    if (text.length > maxLength) {
      return '$fieldLabel must be at most $maxLength characters';
    }

    return null;
  }

  String _getErrorMessage(dynamic error) {
    final message = error.toString();

    if (message.contains('Missing signup token')) {
      return 'Missing signup token. Please verify OTP again.';
    }

    if (message.contains('Invalid or expired signup token')) {
      return 'Invalid or expired signup token. Please request OTP again.';
    }

    if (message.contains('Full name is required')) {
      return 'Full name is required.';
    }

    if (message.contains('User not found')) {
      return 'User not found. Please verify OTP again.';
    }

    if (message.contains('connection errored') ||
        message.contains('XMLHttpRequest') ||
        message.contains('SocketException')) {
      return 'Network error. Please check your backend connection.';
    }

    return message;
  }

  Future<String> _getSignupToken() async {
    final widgetToken = widget.signupToken.trim();

    if (widgetToken.isNotEmpty) {
      return widgetToken;
    }

    final savedToken = await ApiClient.storage.read(key: 'signup_token');

    if (savedToken != null && savedToken.trim().isNotEmpty) {
      return savedToken.trim();
    }

    throw Exception('Missing signup token');
  }

  Future<void> _saveLoginData(Map<String, dynamic> data) async {
    final access = data['tokens']?['access']?.toString();
    final refresh = data['tokens']?['refresh']?.toString();

    if (access == null || access.trim().isEmpty) {
      throw Exception('Access token missing from server response');
    }

    if (refresh == null || refresh.trim().isEmpty) {
      throw Exception('Refresh token missing from server response');
    }

    await ApiClient.storage.write(
      key: 'access',
      value: access.trim(),
    );

    await ApiClient.storage.write(
      key: 'refresh',
      value: refresh.trim(),
    );

    final user = data['user'];

    if (user != null) {
      await ApiClient.storage.write(
        key: 'user_id',
        value: user['id'].toString(),
      );

      await ApiClient.storage.write(
        key: 'full_name',
        value: user['full_name']?.toString() ?? '',
      );

      await ApiClient.storage.write(
        key: 'phone',
        value: user['phone']?.toString() ?? '',
      );

      await ApiClient.storage.write(
        key: 'bio',
        value: user['bio']?.toString() ?? '',
      );
    }

    await ApiClient.storage.delete(key: 'signup_token');
  }

  Future<void> _submit() async {
    setState(() {
      _nameTouched = true;
      _businessTouched = true;
      _bioTouched = true;
    });

    final valid = _formKey.currentState?.validate() ?? false;

    if (!valid) {
      _showMessengerSnack(
        message: 'Please fix the highlighted fields.',
        isError: true,
      );
      return;
    }

    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final signupToken = await _getSignupToken();

      debugPrint('SIGNUP TOKEN USED: $signupToken');
      debugPrint('FINAL SIGNUP TOKEN BEFORE API: $signupToken');

      final response = await AuthApi.completeSignup(
        signupToken: signupToken,
        fullName: _normalizeSpaces(_nameController.text),
        bio: _normalizeSpaces(_bioController.text),
      );
      

      await _saveLoginData(response.data);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const ChatListScreen(),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      _showMessengerSnack(
        message: _getErrorMessage(e),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _showMessengerSnack({
    required String message,
    required bool isError,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        backgroundColor:
            isError ? const Color(0xFFEF4444) : const Color(0xFF1877F2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: Colors.white,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hintText,
    required IconData icon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(
        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
      ),
      prefixIcon: Icon(
        icon,
        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
      ),
      filled: true,
      fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFD7DDE7),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(
          color: Color(0xFF1877F2),
          width: 1.6,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(
          color: Color(0xFFEF4444),
          width: 1.2,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(
          color: Color(0xFFEF4444),
          width: 1.6,
        ),
      ),
      errorStyle: const TextStyle(
        color: Color(0xFFEF4444),
        fontWeight: FontWeight.w500,
      ),
    );
  }

  TextStyle _inputTextStyle() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return TextStyle(
      color: isDark ? Colors.white : const Color(0xFF0F172A),
      fontWeight: FontWeight.w500,
    );
  }

  Widget _buildSectionLabel(String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor =
        isDark ? const Color(0xFFCBD5E1) : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0F172A) : const Color(0xFFF3F5F9),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 12),
                  Text(
                    'Set up your profile',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: titleColor,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Let\'s personalize your SocialConnect experience',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      color: subtitleColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 34),
                  Container(
                    width: 170,
                    height: 170,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFE9EEF8),
                      border: Border.all(
                        color: const Color(0xFFD5DDF1),
                        width: 6,
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.person_outline_rounded,
                        size: 68,
                        color: Color(0xFF4B74DB),
                      ),
                    ),
                  ),
                  const SizedBox(height: 42),
                  _buildSectionLabel('Your Name *'),
                  TextFormField(
                    controller: _nameController,
                    focusNode: _nameFocus,
                    style: _inputTextStyle(),
                    cursorColor: const Color(0xFF1877F2),
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.name,
                    autovalidateMode: _nameTouched
                        ? AutovalidateMode.onUserInteraction
                        : AutovalidateMode.disabled,
                    onChanged: (_) {
                      setState(() {
                        _nameTouched = true;
                      });
                    },
                    onFieldSubmitted: (_) {
                      FocusScope.of(context).requestFocus(_businessFocus);
                    },
                    decoration: _inputDecoration(
                      hintText: 'Enter your full name',
                      icon: Icons.person_outline_rounded,
                    ),
                    validator: _validateName,
                  ),
                  const SizedBox(height: 24),
                  _buildSectionLabel('Business Name (optional)'),
                  TextFormField(
                    controller: _businessController,
                    focusNode: _businessFocus,
                    style: _inputTextStyle(),
                    cursorColor: const Color(0xFF1877F2),
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.text,
                    autovalidateMode: _businessTouched
                        ? AutovalidateMode.onUserInteraction
                        : AutovalidateMode.disabled,
                    onChanged: (_) {
                      setState(() {
                        _businessTouched = true;
                      });
                    },
                    onFieldSubmitted: (_) {
                      FocusScope.of(context).requestFocus(_bioFocus);
                    },
                    decoration: _inputDecoration(
                      hintText: 'Your company or business',
                      icon: Icons.business_outlined,
                    ),
                    validator: (value) => _validateOptionalText(
                      value,
                      fieldLabel: 'Business name',
                      maxLength: 80,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildSectionLabel('Bio (optional)'),
                  TextFormField(
                    controller: _bioController,
                    focusNode: _bioFocus,
                    style: _inputTextStyle(),
                    cursorColor: const Color(0xFF1877F2),
                    textInputAction: TextInputAction.done,
                    keyboardType: TextInputType.multiline,
                    minLines: 5,
                    maxLines: 5,
                    autovalidateMode: _bioTouched
                        ? AutovalidateMode.onUserInteraction
                        : AutovalidateMode.disabled,
                    onChanged: (_) {
                      setState(() {
                        _bioTouched = true;
                      });
                    },
                    onFieldSubmitted: (_) => _submit(),
                    decoration: _inputDecoration(
                      hintText: 'Tell us a bit about yourself...',
                      icon: Icons.edit_note_rounded,
                    ).copyWith(
                      alignLabelWithHint: true,
                      prefixIcon: Padding(
                        padding: const EdgeInsets.only(
                          left: 14,
                          top: 14,
                          right: 8,
                        ),
                        child: Icon(
                          Icons.edit_note_rounded,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 0,
                        minHeight: 0,
                      ),
                    ),
                    validator: (value) => _validateOptionalText(
                      value,
                      fieldLabel: 'Bio',
                      maxLength: 180,
                    ),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      onPressed:
                          _isSubmitting || !_canCompleteSetup ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: const Color(0xFF1877F2),
                        disabledBackgroundColor: const Color(0xFFAFC1F1),
                        foregroundColor: Colors.white,
                        disabledForegroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Complete Setup',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 24,
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}