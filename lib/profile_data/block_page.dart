import 'package:flutter/material.dart';

class MessengerBlockPage extends StatelessWidget {
  final String name;
  final bool isBlocked;

  const MessengerBlockPage({
    super.key,
    required this.name,
    required this.isBlocked,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayName = name.trim().isEmpty ? 'this person' : name.trim();

    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF0F2F5);
    final cardColor = isDark ? const Color(0xFF111827) : Colors.white;
    final primaryText = isDark ? Colors.white : const Color(0xFF111827);
    final secondaryText =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF65676B);
    final dividerColor =
        isDark ? const Color(0xFF243041) : const Color(0xFFE4E6EB);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Color(0xFF1877F2),
                      size: 22,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      isBlocked
                          ? 'Unblock on Messenger'
                          : 'Block on Messenger',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: primaryText,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: dividerColor),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isBlocked
                              ? const Color(0x141877F2)
                              : const Color(0x14EF4444),
                        ),
                        child: Icon(
                          isBlocked
                              ? Icons.lock_open_rounded
                              : Icons.block_rounded,
                          size: 42,
                          color: isBlocked
                              ? const Color(0xFF1877F2)
                              : const Color(0xFFEF4444),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        isBlocked
                            ? 'Unblock $displayName?'
                            : 'Block $displayName on Messenger?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: primaryText,
                          fontSize: 24,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        isBlocked
                            ? 'They will be able to message and call you again.'
                            : 'They won’t be able to message or call you on Messenger.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: secondaryText,
                          fontSize: 15,
                          height: 1.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isBlocked
                              ? const Color(0x141877F2)
                              : const Color(0x14EF4444),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: isBlocked
                                  ? const Color(0xFF1877F2)
                                  : const Color(0xFFEF4444),
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                isBlocked
                                    ? 'After unblocking, this person can message and call you again.'
                                    : 'After blocking, this person cannot message or call you.',
                                style: TextStyle(
                                  color: primaryText,
                                  fontSize: 13.5,
                                  height: 1.45,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: isBlocked
                                ? const Color(0xFF1877F2)
                                : const Color(0xFFEF4444),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(context, !isBlocked);
                          },
                          child: Text(
                            isBlocked ? 'Unblock' : 'Block',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: secondaryText,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
