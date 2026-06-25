
import 'package:flutter/material.dart';

class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({super.key});

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  static const Color primary = Color(0xFF5B2DFF);
  static const Color darkText = Color(0xFF070B2D);
  static const Color greyText = Color(0xFF60657D);

  final TextEditingController _searchController = TextEditingController();

  final List<String> helpArticles = [
    "How to create support ticket",
    "Call not connecting",
    "Message not sending",
    "Profile update problem",
    "Notification not working",
    "App status issue",
  ];

  List<String> searchResults = [];

  void _searchHelp(String value) {
    setState(() {
      searchResults = helpArticles
          .where((item) => item.toLowerCase().contains(value.toLowerCase()))
          .toList();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
              const SizedBox(height: 20),
              _helpBanner(),

              const SizedBox(height: 18),

              // ================= HELP INFO TEXT =================

              const Text(
                "We’re here to help you",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: darkText,
                ),
              ),

              const SizedBox(height: 10),

              const Text(
                "Find answers quickly using search or browse help articles below. "
                "If you still need help, you can create a support ticket or contact our support team anytime.",
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: greyText,
                ),
              ),

              const SizedBox(height: 18),

              const Text(
                "24/7 Support",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: darkText,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                "Our support system is available 24/7. "
                "We respond to tickets as quickly as possible to resolve your issues.",
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: greyText,
                ),
              ),

              const SizedBox(height: 24),

              // ================= END HELP TEXT =================

              if (_searchController.text.isNotEmpty)
                ...searchResults.map(
                  (item) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.article, color: primary),
                    title: Text(item),
                    onTap: () {
                      debugPrint("Open article: $item");
                    },
                  ),
                ),

              // const SizedBox(height: 18),

              // const Text(
              //   "Quick Actions",
              //   style: TextStyle(
              //     fontSize: 20,
              //     fontWeight: FontWeight.w800,
              //     color: darkText,
              //   ),
              // ),

              const SizedBox(height: 14),

              /*

              _quickActionCard(
                icon: Icons.add_box_rounded,
                iconColor: primary,
                bgColor: Color(0xFFEDE8FF),
                title: "Create a Support Ticket",
                subtitle: "Report an issue or ask for help",
                onTap: () {},
              ),

              SizedBox(height: 12),

              _quickActionCard(
                icon: Icons.list_rounded,
                iconColor: Color(0xFF1F73F2),
                bgColor: Color(0xFFEAF2FF),
                title: "My Tickets",
                subtitle: "View your previous tickets",
                onTap: () {},
              ),

              SizedBox(height: 12),

              _quickActionCard(
                icon: Icons.question_mark_rounded,
                iconColor: Color(0xFF12A85B),
                bgColor: Color(0xFFE4F7EC),
                title: "FAQs",
                subtitle: "Find answers to common questions",
                onTap: () {},
              ),

              SizedBox(height: 12),

              _quickActionCard(
                icon: Icons.mail_rounded,
                iconColor: Color(0xFFFF8200),
                bgColor: Color(0xFFFFF0DE),
                title: "Contact Us",
                subtitle: "Reach out to our support team",
                onTap: () {},
              ),

              SizedBox(height: 12),

              _quickActionCard(
                icon: Icons.monitor_heart_rounded,
                iconColor: Color(0xFF1769FF),
                bgColor: Color(0xFFEAF2FF),
                title: "App Status",
                subtitle: "Check our system status",
                onTap: () {},
              ),

              */
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
            child: Icon(Icons.arrow_back, size: 30, color: darkText),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF4B29E8), Color(0xFF7C2DFF)],
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                height: 72,
                width: 72,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.headset_mic_rounded,
                  size: 42,
                  color: primary,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Hi, how can we help you?",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      "Search help articles or create a support ticket anytime",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _searchHelp,
              decoration: const InputDecoration(
                border: InputBorder.none,
                icon: Icon(Icons.search, color: Color(0xFF5F6278)),
                hintText: "Search for help articles...",
                hintStyle: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF7B7F96),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}//Gitpush