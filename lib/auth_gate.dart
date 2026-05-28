

import 'package:flutter/material.dart';
import 'package:messaging_app/core/api_client.dart';
import 'package:messaging_app/dashboard.dart';
import 'package:messaging_app/login_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    _checkSavedLogin();
  }

  Future<void> _checkSavedLogin() async {
    final access = await ApiClient.storage.read(key: 'access');
    final refresh = await ApiClient.storage.read(key: 'refresh');

    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    if (access != null && access.trim().isNotEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ChatListScreen()),
      );
      return;
    }

    if (refresh != null && refresh.trim().isNotEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ChatListScreen()),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}