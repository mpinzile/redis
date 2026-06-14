import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_colors.dart';
import '../providers/auth_provider.dart';
import 'onboarding/onboarding_screen.dart';
import 'auth/login_screen.dart';
import 'home/home_screen.dart';

/// Minimal, elegant splash - edge-to-edge, white bg blends with system bars
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeCtrl;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    _navigate();
  }

  Future<void> _navigate() async {
    debugPrint('[Splash] started');
    // Minimum visible splash so the brand mark isn't flashed away.
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;

    final auth = context.read<AuthProvider>();

    // Wait for the auth provider to finish its (very cheap) secure-storage
    // read, but NEVER hang forever. If `_loadSession` somehow stalls (broken
    // keychain on iPad, corrupted SharedPreferences, etc.) we fall through
    // to the login/onboarding screen instead of staying on the splash.
    // Apple App Review 2.1(a) requires a usable screen quickly.
    final deadline = DateTime.now().add(const Duration(seconds: 6));
    while (auth.isLoading && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    if (!mounted) return;
    if (auth.isLoading) {
      debugPrint('[Splash] auth check timed out · defaulting to safe route');
    } else {
      debugPrint('[Splash] auth check completed (loggedIn=${auth.isLoggedIn})');
    }

    Widget dest;
    if (auth.isLoggedIn) {
      dest = const HomeScreen();
    } else if (auth.hasSeenOnboarding) {
      dest = const LoginScreen();
    } else {
      dest = const OnboardingScreen();
    }
    debugPrint('[Splash] selected initial route: ${dest.runtimeType}');


    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (_, a, __) => dest,
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: Container(
          width: double.infinity,
          height: double.infinity,
          color: AppColors.surface,
          child: Stack(
            alignment: Alignment.center,
            children: [
              FadeTransition(
                opacity: _fadeCtrl,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Image.asset(
                    'assets/images/nuru-logo-square.png',
                    width: 120,
                    height: 120,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Center(
                        child: Text(
                          'N',
                          style: GoogleFonts.inter(
                            fontSize: 36,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 48,
                child: FadeTransition(
                  opacity: CurvedAnimation(
                    parent: _fadeCtrl,
                    curve: const Interval(0.4, 1.0),
                  ),
                  child: Text(
                    'EVERY MOMENT DESERVES CARE',
                    style: GoogleFonts.inter(
                      color: AppColors.textHint,
                      fontSize: 9,
                      letterSpacing: 2.5,
                      fontWeight: FontWeight.w400,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
