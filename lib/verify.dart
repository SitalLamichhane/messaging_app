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
  State<OtpVerificationScreen> createState() =>
      _OtpVerificationScreenState();
}

class _OtpVerificationScreenState
    extends State<OtpVerificationScreen> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());

  final List<FocusNode> _focusNodes =
      List.generate(6, (_) => FocusNode());

  int _secondsRemaining = 60;

  bool _isTimerRunning = false;
  bool _isVerifying = false;
  bool _isResending = false;

  int _timerId = 0;

  @override
  void initState() {
    super.initState();

    _startTimer();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNodes.first.requestFocus();
      }
    });
  }

  // ============================================================
  // TOP MESSAGE
  // ============================================================

  void _showTopMessage(
    String message, {
    bool isError = true,
  }) {
    if (!mounted) return;

    final overlay = Overlay.of(context);

    final entry = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 16,
          right: 16,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: isError
                    ? Colors.red
                    : Colors.green,
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
                    isError
                        ? Icons.error_outline
                        : Icons.check_circle,
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
        );
      },
    );

    overlay.insert(entry);

    Future.delayed(
      const Duration(seconds: 2),
      () {
        if (entry.mounted) {
          entry.remove();
        }
      },
    );
  }

  // ============================================================
  // TIMER
  // ============================================================

  Future<void> _startTimer() async {
    _timerId++;

    final currentTimerId = _timerId;

    if (!mounted) return;

    setState(() {
      _isTimerRunning = true;
    });

    while (
        _secondsRemaining > 0 &&
        mounted &&
        currentTimerId == _timerId) {
      await Future.delayed(
        const Duration(seconds: 1),
      );

      if (!mounted ||
          currentTimerId != _timerId) {
        return;
      }

      setState(() {
        _secondsRemaining--;
      });
    }

    if (!mounted ||
        currentTimerId != _timerId) {
      return;
    }

    setState(() {
      _isTimerRunning = false;
    });
  }

  // ============================================================
  // OTP
  // ============================================================

  String get enteredCode =>
      _controllers
          .map(
            (controller) =>
                controller.text.trim(),
          )
          .join();

  bool get isCodeComplete =>
      enteredCode.length == 6;

  void _onOtpChanged(
    String value,
    int index,
  ) {
    // Handles paste of complete/multiple digit OTP.
    if (value.length > 1) {
      final digits = value
          .replaceAll(
            RegExp(r'[^0-9]'),
            '',
          )
          .split('');

      for (
        int i = 0;
        i < digits.length &&
            (index + i) < 6;
        i++
      ) {
        _controllers[index + i].text =
            digits[i];
      }

      final nextIndex =
          (index + digits.length)
              .clamp(0, 5);

      if (nextIndex < 5) {
        _focusNodes[nextIndex]
            .requestFocus();
      } else {
        _focusNodes[5].unfocus();
      }

      setState(() {});

      return;
    }

    if (value.isNotEmpty) {
      if (index < 5) {
        _focusNodes[index + 1]
            .requestFocus();
      } else {
        _focusNodes[index].unfocus();
      }
    } else {
      if (index > 0) {
        _focusNodes[index - 1]
            .requestFocus();
      }
    }

    setState(() {});
  }

  void _onKeyEvent(
    KeyEvent event,
    int index,
  ) {
    if (
        event is KeyDownEvent &&
        event.logicalKey ==
            LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1]
          .requestFocus();

      _controllers[index - 1]
          .clear();

      setState(() {});
    }
  }

  // ============================================================
  // ERROR MESSAGE
  // ============================================================

  String _getErrorMessage(dynamic error) {
    String message =
        error.toString().trim();

    // Remove Dart Exception prefix.
    message = message.replaceFirst(
      'Exception: ',
      '',
    );

    final lowerMessage =
        message.toLowerCase();

    if (
        lowerMessage.contains(
          'invalid otp',
        ) ||
        lowerMessage.contains(
          'invalid code',
        )) {
      return 'Invalid OTP.';
    }

    if (
        lowerMessage.contains(
          'otp expired',
        ) ||
        lowerMessage.contains(
          'expired otp',
        )) {
      return 'OTP expired. Please request again.';
    }

    if (
        lowerMessage.contains(
          'too many attempts',
        )) {
      return 'Too many attempts. Please request OTP again.';
    }

    if (
        lowerMessage.contains(
          'otp not requested',
        )) {
      return 'OTP not requested. Please request OTP first.';
    }

    if (
        lowerMessage.contains(
          'unable to connect',
        ) ||
        lowerMessage.contains(
          'connection refused',
        ) ||
        lowerMessage.contains(
          'connection error',
        )) {
      return 'Unable to connect to server. Please try again.';
    }

    if (
        lowerMessage.contains(
          'timeout',
        )) {
      return 'Request timed out. Please try again.';
    }

    if (message.isEmpty) {
      return 'Unable to verify OTP.';
    }

    return message;
  }

  // ============================================================
  // VERIFY OTP
  // ============================================================

  Future<void> _verifyCode() async {
    if (
        !isCodeComplete ||
        _isVerifying) {
      return;
    }

    // Hide keyboard.
    FocusScope.of(context).unfocus();

    setState(() {
      _isVerifying = true;
    });

    try {
      final phone =
          widget.phoneNumber.trim();

      final code =
          enteredCode.trim();

      debugPrint(
        '========== VERIFY OTP ==========',
      );

      debugPrint(
        'Phone: $phone',
      );

      debugPrint(
        'Code entered: $code',
      );

      final response =
          await AuthApi.verifyOtp(
        phone: phone,
        code: code,
      );

      debugPrint(
        'Verify response: ${response.data}',
      );

      final dynamic rawData =
          response.data;

      if (rawData is! Map) {
        throw Exception(
          'Invalid server response.',
        );
      }

      final data =
          Map<String, dynamic>.from(
        rawData,
      );

      final responseType =
          data['type']
              ?.toString()
              .trim();

      // ========================================================
      // LOGIN
      // ========================================================

      if (responseType == 'login') {
        final tokens =
            data['tokens'];

        if (tokens is! Map) {
          throw Exception(
            'Authentication tokens missing.',
          );
        }

        final accessToken =
            tokens['access']
                ?.toString()
                .trim();

        final refreshToken =
            tokens['refresh']
                ?.toString()
                .trim();

        if (
            accessToken == null ||
            accessToken.isEmpty) {
          throw Exception(
            'Access token missing from server response.',
          );
        }

        if (
            refreshToken == null ||
            refreshToken.isEmpty) {
          throw Exception(
            'Refresh token missing from server response.',
          );
        }

        // Save access token.
        await ApiClient.storage.write(
          key: 'access',
          value: accessToken,
        );

        // Save refresh token.
        await ApiClient.storage.write(
          key: 'refresh',
          value: refreshToken,
        );

        // Save user details.
        final user =
            data['user'];

        if (user is Map) {
          if (user['id'] != null) {
            await ApiClient.storage.write(
              key: 'user_id',
              value:
                  user['id'].toString(),
            );
          }

          await ApiClient.storage.write(
            key: 'full_name',
            value:
                user['full_name']
                    ?.toString() ??
                '',
          );

          await ApiClient.storage.write(
            key: 'phone',
            value:
                user['phone']
                    ?.toString() ??
                phone,
          );
        } else {
          await ApiClient.storage.write(
            key: 'phone',
            value: phone,
          );
        }

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                const ChatListScreen(),
          ),
        );

        return;
      }

      // ========================================================
      // SIGNUP
      // ========================================================

      if (responseType == 'signup') {
        final signupToken =
            data['signup_token']
                ?.toString()
                .trim();

        if (
            signupToken == null ||
            signupToken.isEmpty) {
          throw Exception(
            'Signup token missing from server response.',
          );
        }

        await ApiClient.storage.write(
          key: 'signup_token',
          value: signupToken,
        );

        await ApiClient.storage.write(
          key: 'phone',
          value: phone,
        );

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ProfileSetupScreen(
              signupToken:
                  signupToken,
            ),
          ),
        );

        return;
      }

      throw Exception(
        'Unknown response from server.',
      );
    } catch (e, stackTrace) {
      debugPrint(
        '========== VERIFY OTP ERROR ==========',
      );

      debugPrint(
        'Error: $e',
      );

      debugPrint(
        'StackTrace: $stackTrace',
      );

      debugPrint(
        '======================================',
      );

      if (!mounted) return;

      final message =
          _getErrorMessage(e);

      _showTopMessage(
        message,
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isVerifying = false;
        });
      }
    }
  }

  // ============================================================
  // RESEND OTP
  // ============================================================

  Future<void> _resendCode() async {
    if (
        _secondsRemaining != 0 ||
        _isTimerRunning ||
        _isResending) {
      return;
    }

    setState(() {
      _isResending = true;
    });

    try {
      final phone =
          widget.phoneNumber.trim();

      await AuthApi.sendOtp(
        phone,
      );

      // Clear OTP boxes.
      for (
        final controller
        in _controllers
      ) {
        controller.clear();
      }

      // Focus first box.
      _focusNodes.first
          .requestFocus();

      if (!mounted) return;

      setState(() {
        _secondsRemaining = 60;
      });

      _startTimer();

      _showTopMessage(
        'OTP resent successfully.',
        isError: false,
      );
    } catch (e) {
      if (!mounted) return;

      _showTopMessage(
        _getErrorMessage(e),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isResending = false;
        });
      }
    }
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _timerId++;

    for (
      final controller
      in _controllers
    ) {
      controller.dispose();
    }

    for (
      final focusNode
      in _focusNodes
    ) {
      focusNode.dispose();
    }

    super.dispose();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final textTheme =
        Theme.of(context)
            .textTheme;

    final isDark =
        Theme.of(context)
                .brightness ==
            Brightness.dark;

    final size =
        MediaQuery.of(context)
            .size;

    final width =
        size.width;

    final contentWidth =
        width > 700
            ? 420.0
            : width;

    final canResend =
        _secondsRemaining == 0 &&
        !_isTimerRunning &&
        !_isResending;

    final titleColor =
        isDark
            ? Colors.white
            : const Color(
                0xFF06163A,
              );

    final subTitleColor =
        isDark
            ? const Color(
                0xFFCBD5E1,
              )
            : const Color(
                0xFF6B7B93,
              );

    final backColor =
        isDark
            ? Colors.white
            : const Color(
                0xFF111827,
              );

    return Scaffold(
      body: SafeArea(
        child:
            SingleChildScrollView(
          padding:
              const EdgeInsets.fromLTRB(
            18,
            8,
            18,
            20,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(
                maxWidth:
                    contentWidth,
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .center,
                children: [
                  // Back button
                  Align(
                    alignment:
                        Alignment
                            .centerLeft,
                    child: InkWell(
                      borderRadius:
                          BorderRadius
                              .circular(
                        10,
                      ),
                      onTap: () =>
                          Navigator
                              .maybePop(
                        context,
                      ),
                      child: Padding(
                        padding:
                            const EdgeInsets
                                .symmetric(
                          horizontal:
                              2,
                          vertical:
                              4,
                        ),
                        child: Icon(
                          Icons
                              .arrow_back_rounded,
                          color:
                              backColor,
                          size: 24,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(
                    height: 18,
                  ),

                  // Shield
                  Container(
                    width: 88,
                    height: 88,
                    decoration:
                        const BoxDecoration(
                      color: Color(
                        0xFFE7EDF8,
                      ),
                      shape:
                          BoxShape.circle,
                    ),
                    child:
                        const Center(
                      child: Icon(
                        Icons
                            .shield_outlined,
                        size: 40,
                        color: Color(
                          0xFF5A82EA,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(
                    height: 20,
                  ),

                  Text(
                    'Verify your number',
                    textAlign:
                        TextAlign.center,
                    style:
                        textTheme
                            .displayLarge
                            ?.copyWith(
                      color:
                          titleColor,
                    ),
                  ),

                  const SizedBox(
                    height: 10,
                  ),

                  Text(
                    'We\'ve sent a 6-digit code to',
                    textAlign:
                        TextAlign.center,
                    style:
                        textTheme
                            .bodyLarge
                            ?.copyWith(
                      color:
                          subTitleColor,
                    ),
                  ),

                  const SizedBox(
                    height: 6,
                  ),

                  Text(
                    widget
                        .phoneNumber,
                    textAlign:
                        TextAlign.center,
                    style:
                        textTheme
                            .titleLarge
                            ?.copyWith(
                      color:
                          titleColor,
                    ),
                  ),

                  const SizedBox(
                    height: 24,
                  ),

                  // OTP boxes
                  Wrap(
                    alignment:
                        WrapAlignment
                            .center,
                    spacing: 8,
                    runSpacing: 8,
                    children:
                        List.generate(
                      6,
                      (index) {
                        return _OtpBox(
                          controller:
                              _controllers[
                                  index],
                          focusNode:
                              _focusNodes[
                                  index],
                          autoFocus:
                              index ==
                                  0,
                          onChanged:
                              (value) =>
                                  _onOtpChanged(
                            value,
                            index,
                          ),
                          onKeyEvent:
                              (event) =>
                                  _onKeyEvent(
                            event,
                            index,
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(
                    height: 22,
                  ),

                  Text(
                    'Didn\'t receive the code?',
                    textAlign:
                        TextAlign.center,
                    style:
                        textTheme
                            .bodyLarge
                            ?.copyWith(
                      color:
                          subTitleColor,
                    ),
                  ),

                  const SizedBox(
                    height: 8,
                  ),

                  InkWell(
                    onTap:
                        canResend
                            ? _resendCode
                            : null,
                    borderRadius:
                        BorderRadius
                            .circular(
                      8,
                    ),
                    child: Padding(
                      padding:
                          const EdgeInsets
                              .symmetric(
                        horizontal:
                            8,
                        vertical:
                            4,
                      ),
                      child: Text(
                        _isResending
                            ? 'Resending...'
                            : canResend
                                ? 'Resend now'
                                : 'Resend in ${_secondsRemaining}s',
                        textAlign:
                            TextAlign
                                .center,
                        style:
                            textTheme
                                .bodyLarge
                                ?.copyWith(
                          fontWeight:
                              FontWeight
                                  .w700,
                          color:
                              canResend
                                  ? const Color(
                                      0xFF4A73E8,
                                    )
                                  : const Color(
                                      0xFFA9BDF0,
                                    ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(
                    height: 24,
                  ),

                  // Verify button
                  SizedBox(
                    width:
                        double.infinity,
                    height: 50,
                    child:
                        ElevatedButton(
                      onPressed:
                          isCodeComplete &&
                                  !_isVerifying
                              ? _verifyCode
                              : null,
                      style:
                          ElevatedButton
                              .styleFrom(
                        backgroundColor:
                            const Color(
                          0xFF4A73E8,
                        ),
                        disabledBackgroundColor:
                            const Color(
                          0xFFB9C9F3,
                        ),
                        foregroundColor:
                            Colors.white,
                        disabledForegroundColor:
                            Colors.white,
                        elevation: 0,
                        shape:
                            RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius
                                  .circular(
                            16,
                          ),
                        ),
                      ),
                      child:
                          _isVerifying
                              ? const SizedBox(
                                  width:
                                      22,
                                  height:
                                      22,
                                  child:
                                      CircularProgressIndicator(
                                    strokeWidth:
                                        2.4,
                                    valueColor:
                                        AlwaysStoppedAnimation<
                                            Color>(
                                      Colors
                                          .white,
                                    ),
                                  ),
                                )
                              : Text(
                                  'Verify',
                                  style:
                                      textTheme
                                          .labelLarge,
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

// ============================================================
// OTP BOX
// ============================================================

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
  Widget build(
    BuildContext context,
  ) {
    final isDark =
        Theme.of(context)
                .brightness ==
            Brightness.dark;

    return KeyboardListener(
      focusNode:
          FocusNode(),
      onKeyEvent:
          onKeyEvent,
      child:
          AnimatedBuilder(
        animation:
            Listenable.merge(
          [
            focusNode,
            controller,
          ],
        ),
        builder:
            (context, child) {
          final isFocused =
              focusNode
                  .hasFocus;

          final hasValue =
              controller
                  .text
                  .isNotEmpty;

          return AnimatedContainer(
            duration:
                const Duration(
              milliseconds:
                  180,
            ),
            width: 46,
            height: 56,
            decoration:
                BoxDecoration(
              color:
                  isFocused
                      ? (
                          isDark
                              ? const Color(
                                  0xFF1D4ED8,
                                )
                              : const Color(
                                  0xFFF4F8FF,
                                )
                        )
                      : hasValue
                          ? (
                              isDark
                                  ? const Color(
                                      0xFF1E293B,
                                    )
                                  : const Color(
                                      0xFFF8FBFF,
                                    )
                            )
                          : (
                              isDark
                                  ? const Color(
                                      0xFF1E293B,
                                    )
                                  : Colors
                                      .white
                            ),
              borderRadius:
                  BorderRadius
                      .circular(
                14,
              ),
              border:
                  Border.all(
                color:
                    isFocused
                        ? const Color(
                            0xFF4A73E8,
                          )
                        : hasValue
                            ? const Color(
                                0xFFBFD1F8,
                              )
                            : (
                                isDark
                                    ? const Color(
                                        0xFF334155,
                                      )
                                    : const Color(
                                        0xFFDCE3F0,
                                      )
                              ),
                width:
                    isFocused
                        ? 1.8
                        : 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color:
                      isFocused
                          ? const Color(
                              0xFF4A73E8,
                            ).withOpacity(
                              0.10,
                            )
                          : Colors
                              .black
                              .withOpacity(
                                0.03,
                              ),
                  blurRadius:
                      isFocused
                          ? 14
                          : 8,
                  offset:
                      const Offset(
                    0,
                    4,
                  ),
                ),
              ],
            ),
            child:
                TextField(
              controller:
                  controller,
              focusNode:
                  focusNode,
              autofocus:
                  autoFocus,
              keyboardType:
                  TextInputType
                      .number,
              textAlign:
                  TextAlign
                      .center,
              maxLength: 1,
              cursorColor:
                  isDark
                      ? Colors
                          .white
                      : const Color(
                          0xFF2563EB,
                        ),
              inputFormatters: [
                FilteringTextInputFormatter
                    .digitsOnly,
              ],
              style:
                  TextStyle(
                fontSize: 22,
                fontWeight:
                    FontWeight
                        .w800,
                color:
                    isDark
                        ? Colors
                            .white
                        : isFocused
                            ? const Color(
                                0xFF2563EB,
                              )
                            : const Color(
                                0xFF0F172A,
                              ),
              ),
              decoration:
                  const InputDecoration(
                counterText:
                    '',
                border:
                    InputBorder
                        .none,
                contentPadding:
                    EdgeInsets
                        .symmetric(
                  vertical:
                      11,
                ),
              ),
              onChanged:
                  onChanged,
            ),
          );
        },
      ),
    );
  }
}