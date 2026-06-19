import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddenly/profile.dart';
import 'package:hiddenly/dashboard.dart';
import 'package:hiddenly/features/auth/auth_api.dart';
import 'package:hiddenly/core/api_client.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String phoneNumber;

  const OtpVerificationScreen({
    super.key,
    required this.phoneNumber,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());

  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  int _secondsRemaining = 60;
  bool _isTimerRunning = false;
  bool _isVerifying = false;
  bool _isResending = false;
  int _timerId = 0;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }


  void _showTopMessage(String message, {bool isError = true}) {
    final overlay = Overlay.of(context);

    final entry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 12,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isError ? Colors.red : Colors.green,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  isError ? Icons.error_outline : Icons.check_circle,
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
        ),
      ),
    );

    overlay.insert(entry);

    Future.delayed(const Duration(seconds: 2), () {
      if (entry.mounted) {
        entry.remove();
      }
    });
  }

  Future<void> _startTimer() async {
    _timerId++;
    final currentTimerId = _timerId;

    setState(() {
      _isTimerRunning = true;
    });

    while (_secondsRemaining > 0 && mounted && currentTimerId == _timerId) {
      await Future.delayed(const Duration(seconds: 1));

      if (!mounted || currentTimerId != _timerId) return;

      setState(() {
        _secondsRemaining--;
      });
    }

    if (!mounted || currentTimerId != _timerId) return;

    setState(() {
      _isTimerRunning = false;
    });
  }

  String get enteredCode =>
      _controllers.map((controller) => controller.text).join();

  bool get isCodeComplete => enteredCode.length == 6;

  void _onOtpChanged(String value, int index) {
    if (value.length > 1) {
      final chars = value.split('');
      for (int i = 0; i < chars.length && (index + i) < 6; i++) {
        _controllers[index + i].text = chars[i];
      }

      final nextIndex = (index + value.length).clamp(0, 5);
      _focusNodes[nextIndex].requestFocus();
      setState(() {});
      return;
    }

    if (value.isNotEmpty) {
      if (index < 5) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
      }
    } else {
      if (index > 0) {
        _focusNodes[index - 1].requestFocus();
      }
    }

    setState(() {});
  }

  void _onKeyEvent(KeyEvent event, int index) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
      _controllers[index - 1].clear();
      setState(() {});
    }
  }

  String _getErrorMessage(dynamic error) {
    final message = error.toString();

    if (message.contains('Invalid OTP')) {
      return 'Invalid OTP.';
    }

    if (message.contains('OTP expired')) {
      return 'OTP expired. Please request again.';
    }

    if (message.contains('Too many attempts')) {
      return 'Too many attempts. Please request OTP again.';
    }

    if (message.contains('OTP not requested')) {
      return 'OTP not requested. Please request OTP first.';
    }

    return message;
  }

  Future<void> _verifyCode() async {
    if (!isCodeComplete || _isVerifying) return;

    setState(() {
      _isVerifying = true;
    });

    try {
      final response = await AuthApi.verifyOtp(
  phone: widget.phoneNumber.trim(),
  code: enteredCode,
);

      final data = response.data;

        if (data['type'] == 'login') {
           await ApiClient.storage.write(
              key: 'access',
               value: data['tokens']['access'].toString().trim(),
         );

        await ApiClient.storage.write(
       key: 'refresh',
        value: data['tokens']['refresh'].toString().trim(),
          );

        if (data['user'] != null) {
          await ApiClient.storage.write(
            key: 'user_id',
            value: data['user']['id'].toString(),
          );

          await ApiClient.storage.write(
            key: 'full_name',
            value: data['user']['full_name']?.toString() ?? '',
          );

          await ApiClient.storage.write(
            key: 'phone',
            value: data['user']['phone']?.toString() ?? '',
          );
        }

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const ChatListScreen(),
          ),
        );
      } else if (data['type'] == 'signup') {
  final signupToken = data['signup_token']?.toString().trim();

  if (signupToken == null || signupToken.isEmpty) {
    throw Exception('Signup token missing from server response.');
  }

  await ApiClient.storage.write(
    key: 'signup_token',
    value: signupToken,
  );

  if (!mounted) return;

  Navigator.pushReplacement(
    context,
    MaterialPageRoute(
      builder: (_) => ProfileSetupScreen(
        signupToken: signupToken,
      ),
    ),
  );
}else {
        throw Exception('Unknown response from server.');
      }
    } catch (e) {
      if (!mounted) return;

      _showTopMessage(_getErrorMessage(e), isError: true);
    }

    if (mounted) {
      setState(() {
        _isVerifying = false;
      });
    }
  }

 Future<void> _resendCode() async {
  if (_secondsRemaining != 0 || _isTimerRunning || _isResending) return;

  setState(() {
    _isResending = true;
  });

  try {
    // ✅ Do not remove country code
    final sendPhone = widget.phoneNumber.trim();

    await AuthApi.sendOtp(sendPhone);

    for (final controller in _controllers) {
      controller.clear();
    }

    _focusNodes.first.requestFocus();

    if (!mounted) return;

    setState(() {
      _secondsRemaining = 60;
    });

    _startTimer();

    _showTopMessage('OTP resent successfully.', isError: false);
  } catch (e) {
    if (!mounted) return;

    _showTopMessage(_getErrorMessage(e), isError: true);
  }

  if (mounted) {
    setState(() {
      _isResending = false;
    });
  }
}

  @override
  void dispose() {
    _timerId++;
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final width = size.width;

    final contentWidth = width > 700 ? 420.0 : width;
    final canResend = _secondsRemaining == 0 && !_isTimerRunning;

    final titleColor = isDark ? Colors.white : const Color(0xFF06163A);
    final subTitleColor =
        isDark ? const Color(0xFFCBD5E1) : const Color(0xFF6B7B93);
    final backColor = isDark ? Colors.white : const Color(0xFF111827);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => Navigator.maybePop(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 4,
                        ),
                        child: Icon(
                          Icons.arrow_back_rounded,
                          color: backColor,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: 88,
                    height: 88,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE7EDF8),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.shield_outlined,
                        size: 40,
                        color: Color(0xFF5A82EA),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Verify your number',
                    textAlign: TextAlign.center,
                    style: textTheme.displayLarge?.copyWith(
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'We\'ve sent a 6-digit code to',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyLarge?.copyWith(
                      color: subTitleColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.phoneNumber,
                    textAlign: TextAlign.center,
                    style: textTheme.titleLarge?.copyWith(
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(
                      6,
                      (index) => _OtpBox(
                        controller: _controllers[index],
                        focusNode: _focusNodes[index],
                        autoFocus: index == 0,
                        onChanged: (value) => _onOtpChanged(value, index),
                        onKeyEvent: (event) => _onKeyEvent(event, index),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Didn\'t receive the code?',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyLarge?.copyWith(
                      color: subTitleColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: canResend ? _resendCode : null,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text(
                        _isResending
                            ? 'Resending...'
                            : canResend
                                ? 'Resend now'
                                : 'Resend in ${_secondsRemaining}s',
                        textAlign: TextAlign.center,
                        style: textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: canResend
                              ? const Color(0xFF4A73E8)
                              : const Color(0xFFA9BDF0),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed:
                          isCodeComplete && !_isVerifying ? _verifyCode : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4A73E8),
                        disabledBackgroundColor: const Color(0xFFB9C9F3),
                        foregroundColor: Colors.white,
                        disabledForegroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isVerifying
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              'Verify',
                              style: textTheme.labelLarge,
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

class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool autoFocus;
  final ValueChanged<String> onChanged;
  final ValueChanged<KeyEvent> onKeyEvent;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.autoFocus,
    required this.onChanged,
    required this.onKeyEvent,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: onKeyEvent,
      child: AnimatedBuilder(
        animation: Listenable.merge([focusNode, controller]),
        builder: (context, child) {
          final isFocused = focusNode.hasFocus;
          final hasValue = controller.text.isNotEmpty;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 46,
            height: 56,
            decoration: BoxDecoration(
              color: isFocused
                  ? (isDark ? const Color(0xFF1D4ED8) : const Color(0xFFF4F8FF))
                  : hasValue
                      ? (isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFF8FBFF))
                      : (isDark ? const Color(0xFF1E293B) : Colors.white),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isFocused
                    ? const Color(0xFF4A73E8)
                    : hasValue
                        ? const Color(0xFFBFD1F8)
                        : (isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFDCE3F0)),
                width: isFocused ? 1.8 : 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: isFocused
                      ? const Color(0xFF4A73E8).withOpacity(0.10)
                      : Colors.black.withOpacity(0.03),
                  blurRadius: isFocused ? 14 : 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: TextField(
  controller: controller,
  focusNode: focusNode,
  autofocus: autoFocus,
  keyboardType: TextInputType.number,
  textAlign: TextAlign.center,
  maxLength: 1,
  cursorColor: isDark ? Colors.white : const Color(0xFF2563EB),
  inputFormatters: [
    FilteringTextInputFormatter.digitsOnly,
  ],
  style: TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    color: isDark
        ? Colors.white
        : isFocused
            ? const Color(0xFF2563EB)
            : const Color(0xFF0F172A),
  ),
  decoration: const InputDecoration(
    counterText: '',
    border: InputBorder.none,
    contentPadding: EdgeInsets.symmetric(vertical: 11),
  ),
  onChanged: onChanged,
),
          );
        },
      ),
    );
  }
}