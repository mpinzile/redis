import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/text_styles.dart';

/// Friendly one-time guide shown the first time a user opens the check-in
/// scanner. Explains the three things gate staff most often get wrong:
///   1. point the camera at the QR
///   2. the success screen auto-closes after 5s — tap it to hold
///   3. failed scans stay until you decide what to do
///
/// Persists acknowledgement in SharedPreferences so it is shown at most
/// once per device (until the key version is bumped).
class CheckinFirstRunGuide {
  static const _prefsKey = 'checkin_scanner_guide_ack_v1';

  /// Show the guide if the user has not acknowledged it yet. Safe to call
  /// from `initState` via a post-frame callback.
  static Future<void> showIfFirstRun(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_prefsKey) == true) return;
      if (!context.mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        isDismissible: false,
        enableDrag: false,
        builder: (ctx) => const _GuideSheet(),
      );
      await prefs.setBool(_prefsKey, true);
    } catch (_) {/* guide is best-effort */}
  }
}

class _GuideSheet extends StatelessWidget {
  const _GuideSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
              width: 44, height: 4,
              decoration: BoxDecoration(color: AppColors.borderLight, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.10),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: SvgPicture.asset('assets/icons/camera-icon.svg',
                  width: 30, height: 30,
                  colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
            ),
          ),
          const SizedBox(height: 14),
          Text('Welcome to Check-In',
              textAlign: TextAlign.center,
              style: appText(size: 19, weight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('A quick 30-second guide so you and your team scan smoothly.',
              textAlign: TextAlign.center,
              style: appText(size: 13, color: AppColors.textSecondary, height: 1.4)),
          const SizedBox(height: 20),
          _step(
            icon: Icons.qr_code_scanner_rounded,
            title: 'Point at the QR code',
            body: 'Hold the phone steady. The camera reads the code automatically, no button to press.',
          ),
          const SizedBox(height: 14),
          _step(
            icon: Icons.touch_app_rounded,
            title: 'Tap to hold the success screen',
            body: 'Successful check-ins close after 5 seconds. Touch the screen any time to keep guest details open while you confirm.',
          ),
          const SizedBox(height: 14),
          _step(
            icon: Icons.error_outline_rounded,
            title: 'Failed scans wait for you',
            body: 'If a scan fails or is already used, the screen stays open so you can decide what to do next.',
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity, height: 50,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text('Yes, I understand. Start scanning',
                  style: appText(size: 14, weight: FontWeight.w700, color: Colors.white)),

            ),
          ),
        ]),
      ),
    );
  }

  Widget _step({required IconData icon, required String title, required String body}) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: AppColors.primary),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: appText(size: 14, weight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(body, style: appText(size: 12, color: AppColors.textSecondary, height: 1.4)),
        ]),
      ),
    ]);
  }
}
