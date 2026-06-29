import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddenly/verify.dart';
import 'package:hiddenly/features/auth/auth_api.dart';
import 'package:hiddenly/core/api_client.dart';
import 'package:hiddenly/dashboard.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  String fullPhoneNumber = '';
  bool _isLoading = false;

  bool get isButtonEnabled =>
      fullPhoneNumber.isNotEmpty && !_isLoading;

  Future<void> onContinue() async {
    FocusScope.of(context).unfocus();

    if (fullPhoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid phone number')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final savedPhone = await ApiClient.storage.read(key: 'phone');
      final access = await ApiClient.storage.read(key: 'access');
      final refresh = await ApiClient.storage.read(key: 'refresh');

      final hasToken =
          (access != null && access.trim().isNotEmpty) ||
          (refresh != null && refresh.trim().isNotEmpty);

      if (savedPhone == fullPhoneNumber && hasToken) {
        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ChatListScreen()),
        );
        return;
      }

      await AuthApi.sendOtp(fullPhoneNumber);

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              OtpVerificationScreen(phoneNumber: fullPhoneNumber),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }

    if (mounted) {
      setState(() => _isLoading = false);
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

    final fieldBg =
        isDark ? const Color(0xFF1E293B) : const Color(0xFFF5F6F8);

    final fieldBorder =
        isDark ? const Color(0xFF334155) : const Color(0xFFD9DEE8);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
              child: SizedBox(
                width: cardWidth,
                child: Column(
                  children: [
                    const SizedBox(height: 20),

                    // ICON
                    // LOGO
                  SizedBox(
                  width: 120,
                  height: 120,
                   child: Image.asset(
                     'assets/icon.png',
                   fit: BoxFit.contain,
                     ),
                     ),

                    const SizedBox(height: 34),

                    Text(
                 'Welcome to Hiddenly',
                  textAlign: TextAlign.center,
                   style: TextStyle(
                      color: titleColor,
                    fontSize: 32,
                      fontWeight: FontWeight.w700,
                     letterSpacing: 0.3,
                     ),
                    ),

                    const SizedBox(height: 14),

                    Text(
                      'Enter your phone number to get started',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyLarge
                          ?.copyWith(color: subTitleColor),
                    ),

                    const SizedBox(height: 52),

                    // PHONE FIELD (BEST METHOD)
                    IntlPhoneField(
                      initialCountryCode: 'NP',
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'Phone Number',
                        filled: true,
                        fillColor: fieldBg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: fieldBorder),
                        ),
                      ),
                      style: TextStyle(color: titleColor),
                      dropdownTextStyle: TextStyle(color: titleColor),

                      onChanged: (phone) {
                        setState(() {
                          fullPhoneNumber = phone.completeNumber;
                        });

                        if (phone.countryISOCode == 'NP' &&
                            phone.number.length >= 10) {
                          FocusScope.of(context).unfocus();
                        }
                      },
                    ),

                    const SizedBox(height: 30),

                    // BUTTON
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed:
                            isButtonEnabled ? onContinue : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4A73E8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : const Text("Continue"),
                      ),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
