// lib/login_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:messaging_app/verify.dart';
import 'package:messaging_app/features/auth/auth_api.dart';
import 'package:messaging_app/core/api_client.dart';
import 'package:messaging_app/dashboard.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final TextEditingController phoneController = TextEditingController();

  String selectedCountry = 'NP';
  String selectedCode = '+977';

  bool _isLoading = false;

  final List<Map<String, String>> countries = const [
    {'country': 'US', 'code': '+1'},
    {'country': 'NP', 'code': '+977'},
    {'country': 'IN', 'code': '+91'},
    {'country': 'UK', 'code': '+44'},
    {'country': 'AU', 'code': '+61'},
  ];

  @override
  void dispose() {
    phoneController.dispose();
    super.dispose();
  }

  String get phoneDigits => phoneController.text.replaceAll(RegExp(r'\D'), '');

  bool get isButtonEnabled =>
    phoneDigits.length == 10 && !_isLoading;

  Future<void> onContinue() async {
    if (phoneDigits.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Number is invalid')),
      );
      return;
    }

    final fullPhoneNumber = '$selectedCode$phoneDigits';
    final apiPhone = fullPhoneNumber;

    setState(() {
      _isLoading = true;
    });

    try {
      final savedPhone = await ApiClient.storage.read(key: 'phone');
      final access = await ApiClient.storage.read(key: 'access');
      final refresh = await ApiClient.storage.read(key: 'refresh');

      final hasToken =
          (access != null && access.trim().isNotEmpty) ||
          (refresh != null && refresh.trim().isNotEmpty);

      if (savedPhone == apiPhone && hasToken) {
        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const ChatListScreen(),
          ),
        );
        return;
      }

      await AuthApi.sendOtp(apiPhone);

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OtpVerificationScreen(
            phoneNumber: fullPhoneNumber,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = screenWidth > 700 ? 680.0 : screenWidth * 0.88;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final titleColor = isDark ? Colors.white : const Color(0xFF0E1730);
    final subTitleColor =
        isDark ? const Color(0xFFCBD5E1) : const Color(0xFF64748B);
    final fieldBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF5F6F8);
    final fieldBorder =
        isDark ? const Color(0xFF334155) : const Color(0xFFD9DEE8);
    final iconColor =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF7A869A);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
            child: SizedBox(
              width: cardWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),
                  Container(
                    width: 108,
                    height: 108,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE6EBF7),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: const Color(0xFF4A73E8),
                            width: 2.2,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.chat_bubble_outline_rounded,
                          color: Color(0xFF4A73E8),
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 34),
                  Text(
                    'Welcome to SocialConnect',
                    textAlign: TextAlign.center,
                    style: textTheme.displayLarge?.copyWith(color: titleColor),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Enter your phone number to get started',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyLarge?.copyWith(color: subTitleColor),
                  ),
                  const SizedBox(height: 52),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Phone Number',
                      style: textTheme.titleMedium?.copyWith(color: titleColor),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 120,
                        child: _CountryDropdown(
                          selectedCountry: selectedCountry,
                          selectedCode: selectedCode,
                          countries: countries,
                          onChanged: (value) {
                            if (value == null) return;

                            final item = countries.firstWhere(
                              (element) =>
                                  '${element['country']} ${element['code']}' ==
                                  value,
                            );

                            setState(() {
                              selectedCountry = item['country']!;
                              selectedCode = item['code']!;
                            });
                          },
                          backgroundColor: fieldBg,
                          borderColor: fieldBorder,
                          textColor: titleColor,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _PhoneInput(
                          controller: phoneController,
                          onChanged: (_) => setState(() {}),
                          backgroundColor: fieldBg,
                          borderColor: fieldBorder,
                          textColor: titleColor,
                          hintColor: iconColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: isButtonEnabled ? onContinue : null,
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: const Color(0xFF4A73E8),
                        disabledBackgroundColor: const Color(0xFFA9BEF0),
                        foregroundColor: Colors.white,
                        disabledForegroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Continue',
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                                const SizedBox(width: 14),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 30,
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 52),
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: textTheme.bodyLarge?.copyWith(
                        color: subTitleColor,
                        height: 1.55,
                      ),
                      children: const [
                        TextSpan(text: 'By continuing, you agree to our '),
                        TextSpan(
                          text: 'Terms of Service',
                          style: TextStyle(
                            color: Color(0xFF4A73E8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        TextSpan(text: ' and '),
                        TextSpan(
                          text: 'Privacy\nPolicy',
                          style: TextStyle(
                            color: Color(0xFF4A73E8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
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

class _CountryDropdown extends StatelessWidget {
  final String selectedCountry;
  final String selectedCode;
  final List<Map<String, String>> countries;
  final ValueChanged<String?> onChanged;
  final Color backgroundColor;
  final Color borderColor;
  final Color textColor;

  const _CountryDropdown({
    required this.selectedCountry,
    required this.selectedCode,
    required this.countries,
    required this.onChanged,
    required this.backgroundColor,
    required this.borderColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final value = '$selectedCountry $selectedCode';

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.3),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Color(0xFF6B7280),
            size: 28,
          ),
          isExpanded: true,
          dropdownColor: Theme.of(context).cardColor,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: textColor,
              ),
          items: countries.map((item) {
            final display = '${item['country']} ${item['code']}';
            return DropdownMenuItem<String>(
              value: display,
              child: Text(
                display,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: textColor,
                    ),
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _PhoneInput extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final Color backgroundColor;
  final Color borderColor;
  final Color textColor;
  final Color hintColor;

  const _PhoneInput({
    required this.controller,
    required this.onChanged,
    required this.backgroundColor,
    required this.borderColor,
    required this.textColor,
    required this.hintColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.3),
      ),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        cursorColor: const Color(0xFF4A73E8),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(10),
          PhoneNumberFormatter(),
        ],
        onChanged: onChanged,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: textColor,
            ),
        decoration: InputDecoration(
          hintText: '123 456 7890',
          hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: hintColor,
              ),
          prefixIcon: Icon(Icons.phone_outlined, color: hintColor),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 20),
        ),
      ),
    );
  }
}

class PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitsOnly = newValue.text.replaceAll(RegExp(r'\D'), '');

    String formatted = '';
    for (int i = 0; i < digitsOnly.length; i++) {
      if (i == 3 || i == 6) formatted += ' ';
      formatted += digitsOnly[i];
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}