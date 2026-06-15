import 'package:flutter/material.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  static const Color primary = Color(0xFF5B2DFF);
  static const Color darkText = Color(0xFF070B2D);
  static const Color greyText = Color(0xFF60657D);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFD),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _topBar(context),
              const SizedBox(height: 24),
              _helpBanner(),
              const SizedBox(height: 24),

              const Text(
                "Quick Actions",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: darkText,
                ),
              ),

              const SizedBox(height: 14),

              // This card opens the create support ticket page.
              _quickActionCard(
                icon: Icons.add_box_rounded,
                iconColor: primary,
                bgColor: const Color(0xFFEDE8FF),
                title: "Create a Support Ticket",
                subtitle: "Report an issue or ask for help",
                onTap: () {
                  // TODO: Navigate to CreateTicketScreen
                  // Navigator.push(context, MaterialPageRoute(
                  //   builder: (_) => const CreateTicketScreen(),
                  // ));
                },
              ),

              const SizedBox(height: 12),

              // This card opens the user's previous support tickets.
              _quickActionCard(
                icon: Icons.list_rounded,
                iconColor: const Color(0xFF1F73F2),
                bgColor: const Color(0xFFEAF2FF),
                title: "My Tickets",
                subtitle: "View your previous tickets",
                onTap: () {
                  // TODO: Navigate to MyTicketsScreen
                },
              ),

              const SizedBox(height: 12),

              // This card opens FAQ questions and answers.
              _quickActionCard(
                icon: Icons.question_mark_rounded,
                iconColor: const Color(0xFF12A85B),
                bgColor: const Color(0xFFE4F7EC),
                title: "FAQs",
                subtitle: "Find answers to common questions",
                onTap: () {
                  // TODO: Navigate to FAQsScreen
                },
              ),

              const SizedBox(height: 12),

              // This card opens contact support options.
              _quickActionCard(
                icon: Icons.mail_rounded,
                iconColor: const Color(0xFFFF8200),
                bgColor: const Color(0xFFFFF0DE),
                title: "Contact Us",
                subtitle: "Reach out to our support team",
                onTap: () {
                  // TODO: Navigate to ContactUsScreen
                },
              ),

              const SizedBox(height: 12),

              // This card opens app/server status page.
              _quickActionCard(
                icon: Icons.monitor_heart_rounded,
                iconColor: const Color(0xFF1769FF),
                bgColor: const Color(0xFFEAF2FF),
                title: "App Status",
                subtitle: "Check our system status",
                onTap: () {
                  // TODO: Navigate to AppStatusScreen
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(50),
          onTap: () => Navigator.pop(context),
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(
              Icons.arrow_back,
              size: 30,
              color: darkText,
            ),
          ),
        ),
        const SizedBox(width: 18),
        const Text(
          "Help & Support",
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: darkText,
          ),
        ),
      ],
    );
  }

  Widget _helpBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF4B29E8),
            Color(0xFF7C2DFF),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: primary.withOpacity(0.22),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                height: 92,
                width: 92,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.headset_mic_rounded,
                  size: 54,
                  color: primary,
                ),
              ),
              const SizedBox(width: 20),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Hi, how can we help you?",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      "Search for help articles or\ncreate a support ticket",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            height: 70,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.search,
                  size: 34,
                  color: Color(0xFF5F6278),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    "Search for help articles...",
                    style: TextStyle(
                      fontSize: 20,
                      color: Color(0xFF7B7F96),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActionCard({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          minHeight: 102,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFFE7E8F0),
            ),
          ),
          child: Row(
            children: [
              Container(
                height: 64,
                width: 64,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 34,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: darkText,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 16,
                        color: greyText,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 34,
                color: darkText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}