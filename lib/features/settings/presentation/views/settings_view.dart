import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:two_camera/providers/premium/premium_provider.dart';
import 'package:two_camera/providers/rc/rc_placement_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:easy_localization/easy_localization.dart';

class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPremium = ref.watch(isPremiumProvider);
    // Responsive width limiting
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isTablet = screenWidth > 600;
    final contentWidth = isTablet ? 600.0 : screenWidth;

    return Scaffold(
      backgroundColor: Colors.black,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            backgroundColor: Colors.black.withOpacity(0.5),
            surfaceTintColor: Colors.transparent,
            pinned: true,
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(CupertinoIcons.back, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            title: Text(
              "settings_title".tr(),
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: isTablet ? 22 : 18,
                letterSpacing: 0.5,
              ),
            ),
            flexibleSpace: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Center(
              child: SizedBox(
                width: contentWidth,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isTablet ? 0 : 20.0,
                    vertical: 24.0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // PRO Upgrade Button
                      GestureDetector(
                        onTap: () {
                          if (!isPremium) {
                            showPaywallWithPlacement('default', 'premium');
                          }
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isPremium
                                  ? [
                                      const Color(0xFF34C759),
                                      const Color(0xFF1E1E1E),
                                    ]
                                  : [
                                      const Color(0xFFE5B2CA),
                                      const Color(0xFF7028E4),
                                    ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    (isPremium
                                            ? const Color(0xFF34C759)
                                            : const Color(0xFF7028E4))
                                        .withOpacity(0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: 24,
                            horizontal: 24,
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isPremium
                                      ? CupertinoIcons.checkmark_seal_fill
                                      : CupertinoIcons.star_fill,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isPremium
                                          ? "settings_premium_active".tr()
                                          : "settings_upgrade_title".tr(),
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: isTablet ? 24 : 20,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      isPremium
                                          ? "settings_premium_thanks".tr()
                                          : "settings_upgrade_subtitle".tr(),
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.9),
                                        fontSize: isTablet ? 16 : 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (!isPremium)
                                const Icon(
                                  CupertinoIcons.chevron_right,
                                  color: Colors.white,
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),

                      // Settings Links
                      Text(
                        "settings_about".tr(),
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: isTablet ? 15 : 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E1E).withOpacity(0.6),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.1),
                                width: 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                _buildSettingsItem(
                                  title: "settings_rate_us".tr(),
                                  icon: CupertinoIcons.heart_fill,
                                  iconColor: Colors.pinkAccent,
                                  onTap: () => _openUrl(
                                    'https://apps.apple.com/app/6762450435?action=write-review',
                                  ),
                                  isTablet: isTablet,
                                ),
                                _buildDivider(),
                                _buildSettingsItem(
                                  title: "settings_terms".tr(),
                                  icon: CupertinoIcons.doc_text_fill,
                                  iconColor: Colors.blueAccent,
                                  onTap: () => _openUrl(
                                    'https://sites.google.com/view/dualcamterms/ana-sayfa',
                                  ),
                                  isTablet: isTablet,
                                ),
                                _buildDivider(),
                                _buildSettingsItem(
                                  title: "settings_privacy".tr(),
                                  icon: CupertinoIcons.lock_shield_fill,
                                  iconColor: Colors.greenAccent,
                                  onTap: () => _openUrl(
                                    'https://sites.google.com/view/dualcamprivacy/ana-sayfa',
                                  ),
                                  isTablet: isTablet,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildSettingsItem({
    required String title,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
    required bool isTablet,
  }) {
    return InkWell(
      onTap: onTap,
      splashColor: Colors.white.withOpacity(0.1),
      highlightColor: Colors.white.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: isTablet ? 24 : 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isTablet ? 18 : 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              color: Colors.white.withOpacity(0.3),
              size: isTablet ? 22 : 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 1,
      margin: const EdgeInsets.only(left: 64),
      color: Colors.white.withOpacity(0.05),
    );
  }
}
