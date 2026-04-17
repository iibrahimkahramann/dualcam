import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';

class OnboardingView extends StatefulWidget {
  const OnboardingView({super.key});

  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<OnboardingView> {
  final PageController _controller = PageController();
  int _currentPage = 0;
  static const int _totalPages = 3;

  void _next() {
    if (_currentPage < _totalPages - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    if (mounted) context.go('/home');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isTablet = size.width > 600;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            // Pages — en altta, böylece butonlar üstte kalır
            PageView(
              controller: _controller,
              onPageChanged: (i) => setState(() => _currentPage = i),
              children: [
                _Page1(isTablet: isTablet, screenSize: size),
                _Page2(isTablet: isTablet, screenSize: size),
                _Page3(isTablet: isTablet, screenSize: size),
              ],
            ),

            // Skip
            Positioned(
              top: 8,
              right: 16,
              child: TextButton(
                onPressed: _finish,
                child: Text(
                  'onboarding_skip'.tr(),
                  style: TextStyle(
                    color: const Color(0xFF999999),
                    fontSize: isTablet ? 18 : 16,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),

            // Bottom: dots + button
            Positioned(
              left: 24,
              right: 24,
              bottom: 24,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Dot indicators
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_totalPages, (i) {
                      final active = i == _currentPage;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: active ? 28 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: active
                              ? Colors.black
                              : const Color(0xFFD0D0D0),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  SizedBox(height: isTablet ? 24 : 20),

                  // Button
                  SizedBox(
                    width: double.infinity,
                    height: isTablet ? 64 : 56,
                    child: ElevatedButton(
                      onPressed: _next,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        _currentPage == _totalPages - 1
                            ? 'onboarding_get_started'.tr()
                            : 'onboarding_continue'.tr(),
                        style: TextStyle(
                          fontSize: isTablet ? 19 : 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shared page layout — illüstrasyon sabit yükseklikte, yazılar hep aynı hizada ──

class _PageLayout extends StatelessWidget {
  final bool isTablet;
  final Size screenSize;
  final Widget illustration;
  final String titleKey;
  final String subtitleKey;

  const _PageLayout({
    required this.isTablet,
    required this.screenSize,
    required this.illustration,
    required this.titleKey,
    required this.subtitleKey,
  });

  @override
  Widget build(BuildContext context) {
    // Sabit illüstrasyon alanı yüksekliği — tüm sayfalarda aynı
    final illustrationBoxH = screenSize.height * 0.38;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: screenSize.width * 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(height: screenSize.height * 0.07),
          // Sabit yükseklikte kutu: içerik ne kadar olursa olsun yazılar aynı noktadan başlar
          SizedBox(
            height: illustrationBoxH,
            child: Center(child: illustration),
          ),
          SizedBox(height: screenSize.height * 0.04),
          Text(
            titleKey.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isTablet ? 38 : 30,
              fontWeight: FontWeight.bold,
              color: Colors.black,
              height: 1.2,
            ),
          ),
          SizedBox(height: screenSize.height * 0.02),
          Text(
            subtitleKey.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isTablet ? 18 : 15,
              color: const Color(0xFF999999),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Page 1 ────────────────────────────────────────────────────────────────

class _Page1 extends StatelessWidget {
  final bool isTablet;
  final Size screenSize;
  const _Page1({required this.isTablet, required this.screenSize});

  @override
  Widget build(BuildContext context) {
    final boxH = screenSize.height * 0.38;
    final cardW9x16 = screenSize.width * 0.33;
    final cardH9x16 = boxH * 0.82;
    final cardW16x9 = screenSize.width * 0.50;
    final cardH16x9 = boxH * 0.50;

    return _PageLayout(
      isTablet: isTablet,
      screenSize: screenSize,
      titleKey: 'onboarding_1_title',
      subtitleKey: 'onboarding_1_subtitle',
      illustration: SizedBox(
        width: screenSize.width * 0.84,
        height: boxH,
        child: Stack(
          children: [
            Positioned(
              top: boxH * 0.18,
              left: screenSize.width * 0.27,
              child: _VideoCard(
                label: '16:9',
                width: cardW16x9,
                height: cardH16x9,
                color: const Color(0xFFF0F0F0),
              ),
            ),
            Positioned(
              top: boxH * 0.04,
              left: screenSize.width * 0.04,
              child: _VideoCard(
                label: '9:16',
                width: cardW9x16,
                height: cardH9x16,
                color: const Color(0xFFE0E0E0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Page 2 ────────────────────────────────────────────────────────────────

class _Page2 extends StatelessWidget {
  final bool isTablet;
  final Size screenSize;
  const _Page2({required this.isTablet, required this.screenSize});

  @override
  Widget build(BuildContext context) {
    final cardW = screenSize.width * 0.36;
    final cardH = screenSize.height * 0.26;

    return _PageLayout(
      isTablet: isTablet,
      screenSize: screenSize,
      titleKey: 'onboarding_2_title',
      subtitleKey: 'onboarding_2_subtitle',
      illustration: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _PlatformCard(
            icon: Icons.open_in_new_rounded,
            title: 'onboarding_2_tiktok'.tr(),
            badge: '9:16',
            width: cardW,
            height: cardH,
          ),
          SizedBox(width: screenSize.width * 0.04),
          _PlatformCard(
            icon: Icons.play_arrow_rounded,
            title: 'onboarding_2_youtube'.tr(),
            badge: '16:9',
            width: cardW,
            height: cardH,
          ),
        ],
      ),
    );
  }
}

// ─── Page 3 ────────────────────────────────────────────────────────────────

class _Page3 extends StatelessWidget {
  final bool isTablet;
  final Size screenSize;
  const _Page3({required this.isTablet, required this.screenSize});

  @override
  Widget build(BuildContext context) {
    final cellSize = (screenSize.width * 0.84 - 32) / 3;

    final features = [
      (Icons.bolt, 'feature_flash'.tr()),
      (Icons.center_focus_strong_outlined, 'feature_focus'.tr()),
      (Icons.wb_sunny_outlined, 'feature_exposure'.tr()),
      (Icons.timer_outlined, 'feature_timer'.tr()),
      (Icons.grid_on_outlined, 'feature_grid'.tr()),
      (Icons.search_rounded, 'feature_zoom'.tr()),
    ];

    return _PageLayout(
      isTablet: isTablet,
      screenSize: screenSize,
      titleKey: 'onboarding_3_title',
      subtitleKey: 'onboarding_3_subtitle',
      illustration: Wrap(
        spacing: 16,
        runSpacing: 16,
        alignment: WrapAlignment.center,
        children: features.map((f) {
          return SizedBox(
            width: cellSize,
            child: _FeatureCell(icon: f.$1, label: f.$2, size: cellSize),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Shared widgets ─────────────────────────────────────────────────────────

class _VideoCard extends StatelessWidget {
  final String label;
  final double width;
  final double height;
  final Color color;

  const _VideoCard({
    required this.label,
    required this.width,
    required this.height,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.play_arrow_rounded,
            size: width * 0.22,
            color: Colors.black38,
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: width * 0.10,
              color: Colors.black45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlatformCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String badge;
  final double width;
  final double height;

  const _PlatformCard({
    required this.icon,
    required this.title,
    required this.badge,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(width * 0.08),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: width * 0.20, color: Colors.black87),
          ),
          SizedBox(height: height * 0.06),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: width * 0.10,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
              height: 1.3,
            ),
          ),
          SizedBox(height: height * 0.05),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: width * 0.10,
              vertical: height * 0.025,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFE0E0E0),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              badge,
              style: TextStyle(
                fontSize: width * 0.09,
                color: Colors.black54,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureCell extends StatelessWidget {
  final IconData icon;
  final String label;
  final double size;

  const _FeatureCell({
    required this.icon,
    required this.label,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.all(size * 0.18),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F2F2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, size: size * 0.28, color: Colors.black87),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.black54,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}
