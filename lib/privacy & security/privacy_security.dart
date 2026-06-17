import 'package:flutter/material.dart';

class PrivacySecurityScreen extends StatelessWidget {
  const PrivacySecurityScreen({super.key});

  static const Color primary = Color(0xFF6C3DFF);
  static const Color darkText = Color(0xFF070B2D);
  static const Color greyText = Color(0xFF60657D);
  static const Color green = Color(0xFF16A45F);

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
              const SizedBox(height: 28),
              _privacyBanner(),

              const SizedBox(height: 28),

              /*
              
              // ================= PRIVACY SECTION START =================

              const Text(
                "Privacy",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: darkText,
                ),
              ),

              const SizedBox(height: 14),

              _settingCard(
                icon: Icons.person_rounded,
                iconColor: primary,
                bgColor: Color(0xFFEFE9FF),
                title: "Data & Privacy",
                subtitle: "Manage your personal data and permissions",
                onTap: () {},
              ),

              SizedBox(height: 12),

              _settingCard(
                icon: Icons.visibility_rounded,
                iconColor: primary,
                bgColor: Color(0xFFEFE9FF),
                title: "Profile Visibility",
                subtitle: "Control who can see your profile and activity",
                onTap: () {},
              ),

              SizedBox(height: 12),

              _settingCard(
                icon: Icons.download_rounded,
                iconColor: primary,
                bgColor: Color(0xFFEFE9FF),
                title: "Download My Data",
                subtitle: "Request a copy of your data",
                onTap: () {},
              ),

              SizedBox(height: 12),

              _settingCard(
                icon: Icons.delete_rounded,
                iconColor: primary,
                bgColor: Color(0xFFEFE9FF),
                title: "Delete My Account",
                subtitle: "Permanently delete your account and data",
                onTap: () {},
              ),

              // ================= PRIVACY SECTION END =================


              SizedBox(height: 26),


              // ================= SECURITY SECTION START =================

              const Text(
                "Security",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: darkText,
                ),
              ),

              const SizedBox(height: 14),

              _settingCard(
                icon: Icons.lock_rounded,
                iconColor: green,
                bgColor: Color(0xFFE3F7EC),
                title: "Change Password",
                subtitle: "Update your password regularly",
                onTap: () {},
              ),

              SizedBox(height: 12),

              _settingCard(
                icon: Icons.verified_user_rounded,
                iconColor: green,
                bgColor: Color(0xFFE3F7EC),
                title: "Two-Factor Authentication",
                subtitle: "Add an extra layer of security",
                trailingText: "On",
                onTap: () {},
              ),

              SizedBox(height: 12),

              _settingCard(
                icon: Icons.desktop_windows_rounded,
                iconColor: green,
                bgColor: Color(0xFFE3F7EC),
                title: "Active Sessions",
                subtitle: "Manage your active sessions and devices",
                onTap: () {},
              ),

              SizedBox(height: 12),

              _settingCard(
                icon: Icons.security_rounded,
                iconColor: green,
                bgColor: Color(0xFFE3F7EC),
                title: "Security Alerts",
                subtitle: "View recent security activity and alerts",
                onTap: () {},
              ),

              // ================= SECURITY SECTION END =================

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
            child: Icon(
              Icons.arrow_back,
              size: 30,
              color: darkText,
            ),
          ),
        ),
        const SizedBox(width: 18),
        const Text(
          "Privacy & Security",
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: darkText,
          ),
        ),
      ],
    );
  }

  Widget _privacyBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F2FF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFE4DAFF),
        ),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Your privacy matters",
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    color: darkText,
                  ),
                ),
                SizedBox(height: 14),
                Text(
                  "Manage your data, security settings,\nand control your privacy.",
                  style: TextStyle(
                    fontSize: 18,
                    height: 1.4,
                    color: greyText,
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 104,
            width: 104,
            decoration: BoxDecoration(
              color: primary.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.shield_rounded,
              size: 66,
              color: primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingCard({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    String? trailingText,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
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
                height: 58,
                width: 58,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 32,
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
              if (trailingText != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    trailingText,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: green,
                    ),
                  ),
                ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 32,
                color: darkText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}