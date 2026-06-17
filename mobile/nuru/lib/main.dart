import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/services/deep_link_service.dart';
import 'core/services/incoming_call_service.dart';
import 'core/services/push_notification_service.dart';
import 'core/services/checkin_session.dart';
import 'providers/auth_provider.dart';
import 'providers/locale_provider.dart';
import 'providers/wallet_provider.dart';
import 'providers/migration_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/events/event_public_view_screen.dart';
import 'screens/public_profile/public_profile_screen.dart';
import 'screens/services/public_service_screen.dart';
import 'screens/contributors/public_contribute_screen.dart';
import 'screens/common/deep_link_placeholder_screen.dart';
import 'screens/invitation/invitation_view_screen.dart';
import 'screens/tickets/ticket_verification_screen.dart';
import 'screens/home/post_detail_screen.dart';
import 'screens/moments/moment_view_screen.dart';
import 'screens/auth/set_password_screen.dart';
import 'screens/cards/public_card_view_screen.dart';
import 'widgets/rate_limit_overlay.dart';
import 'widgets/payment_verifier.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Restore an active Check-In Mode session (if any) before runApp so the
  // very first API call already carries the `X-Checkin-Session` header.
  // Fire-and-forget if shared_preferences is slow to come up.
  // ignore: discarded_futures
  CheckinSession.hydrate();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.surface,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarDividerColor: AppColors.surface,
    systemNavigationBarContrastEnforced: false,
  ));

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => WalletProvider()),
        ChangeNotifierProvider(create: (_) => MigrationProvider()),
      ],
      child: const PaymentVerifier(child: NuruApp()),
    ),
  );
}

class NuruApp extends StatefulWidget {
  const NuruApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  State<NuruApp> createState() => _NuruAppState();
}

class _NuruAppState extends State<NuruApp> {

  @override
  void initState() {
    super.initState();
    debugPrint('[Nuru] app initialization started');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // IMPORTANT: do NOT request runtime permissions at app launch.
      // Apple App Review (Guideline 2.1a) rejected v1.0(3) on iPad as
      // "irresponsive upon launch" - back-to-back permission dialogs from
      // location, camera, photos, mic and notifications made the UI appear
      // frozen. Each feature now requests its own permission lazily when
      // the user first taps it (camera inside the QR scanner screen, mic
      // inside the voice/video call screen, photos when opening the picker,
      // location when sharing a place, etc.).
      DeepLinkService.instance.init(NuruApp.navigatorKey);
      // Global voice-call ringer: polls the backend for incoming calls and
      // shows CallKit / a full-screen ringer. Safe to start before login -
      // the poll endpoint returns null while unauthenticated.
      IncomingCallService.instance.start(NuruApp.navigatorKey);
      // Push notifications (FCM) - show every backend notification on the
      // device. `initialise` internally requests the notification permission,
      // which is the only OS prompt we want during a cold start.
      PushNotificationService.instance
          .initialise(navigatorKey: NuruApp.navigatorKey)
          .then((_) => PushNotificationService.instance.registerWithBackend());
    });
  }



  @override
  Widget build(BuildContext context) {
    // We intentionally do NOT pass `locale` to MaterialApp - Swahili isn't in
    // Flutter's bundled Material localizations. Instead, `LocaleProvider` is a
    // ChangeNotifier and every screen that uses translations calls
    // `context.watch<LocaleProvider>()` (via `context.trw(...)`), which rebuilds
    // those widgets when the language changes. This is exactly how the
    // settings screen's LanguageSettingsCard already works.
    return MaterialApp(
      title: 'Nuru',
      debugShowCheckedModeBanner: false,
      navigatorKey: NuruApp.navigatorKey,
      theme: AppTheme.lightTheme,
      home: const SplashScreen(),
      onGenerateRoute: _onGenerateRoute,
      builder: (context, child) => RateLimitOverlay(child: child ?? const SizedBox.shrink()),
    );
  }

  /// Resolves deep-linked named routes (pushed by DeepLinkService) to real
  /// screens. Every supported path lands on its dedicated page; paths whose
  /// native screen does not exist yet open DeepLinkPlaceholderScreen with an
  /// "Open in browser" fallback instead of silently returning to home.
  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    final args = (settings.arguments as Map?) ?? const {};
    String s(String k) => (args[k] ?? '').toString();
    switch (settings.name) {
      case '/event':
        return MaterialPageRoute(builder: (_) => EventPublicViewScreen(eventId: s('id')));
      case '/profile':
        return MaterialPageRoute(
          builder: (_) => PublicProfileScreen(userId: s('userId'), username: s('username')),
        );
      case '/service':
        return MaterialPageRoute(builder: (_) => PublicServiceScreen(serviceId: s('id')));
      case '/contribute':
        return MaterialPageRoute(builder: (_) => PublicContributeScreen(token: s('token')));
      case '/ticket':
        return MaterialPageRoute(builder: (_) => TicketVerificationScreen(code: s('code')));
      case '/rsvp':
        return MaterialPageRoute(builder: (_) => InvitationViewScreen(code: s('code'), mode: 'rsvp'));
      case '/invitation':
        return MaterialPageRoute(builder: (_) => InvitationViewScreen(code: s('code'), mode: 'view'));
      case '/post':
        return MaterialPageRoute(builder: (_) => PostDetailScreen(postId: s('id')));
      case '/moment':
        return MaterialPageRoute(builder: (_) => MomentViewScreen(momentId: s('id')));
      case '/set-password':
        return MaterialPageRoute(builder: (_) => SetPasswordScreen(token: s('token')));
      case '/cards':
        return MaterialPageRoute(builder: (_) => PublicCardViewScreen(cardId: s('id')));
    }
    return null;
  }
}
