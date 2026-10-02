// The app shell: theme, language, toasts and the switch between first access, lock and vault.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import '../app/app_controller.dart';
import '../app/settings.dart';
import '../l10n/gen/app_localizations.dart';
import 'home/home_screen.dart';
import 'lock/lock_screen.dart';
import 'onboarding/onboarding_flow.dart';
import 'onboarding/pin_setup.dart';
import 'theme.dart';
import 'widgets/toast.dart';

/// Gives every screen access to the app controller and the toasts.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.app, required this.toasts, required super.child});

  final AppController app;
  final ToastController toasts;

  /// The app controller and toasts never change identity, so no rebuild dependency is needed
  /// (this also makes it usable from initState).
  static AppScope of(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope old) => old.app != app || old.toasts != toasts;
}

extension AppScopeX on BuildContext {
  AppController get app => AppScope.of(this).app;
  ToastController get toasts => AppScope.of(this).toasts;
  AppLocalizations get l => AppLocalizations.of(this);
}

class TheVaultApp extends StatefulWidget {
  const TheVaultApp({super.key, required this.app});
  final AppController app;

  @override
  State<TheVaultApp> createState() => _TheVaultAppState();
}

class _TheVaultAppState extends State<TheVaultApp> {
  final _toasts = ToastController();
  final _navKey = GlobalKey<NavigatorState>();
  StreamSubscription<AppNotice>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.app.notices.listen((n) {
      final ctx = _navKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      final l = AppLocalizations.of(ctx);
      _toasts.show(switch (n) {
        AppNotice.deviceRevoked => l.deviceRevoked,
        AppNotice.pinWiped => l.pinWiped,
        AppNotice.clipboardCleared => l.clipboardCleared,
      }, duration: n == AppNotice.clipboardCleared ? const Duration(milliseconds: 1600) : const Duration(seconds: 6));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _toasts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return ListenableBuilder(
      listenable: app.settings,
      builder: (context, _) => MaterialApp(
        navigatorKey: _navKey,
        title: 'The Vault',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: app.settings.themeMode,
        // "System" follows the computer's language, also when it changes while the app is open.
        locale: app.settings.chosenLocale,
        localeListResolutionCallback: (preferred, _) => AppSettings.systemLocale(preferred),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => AppScope(
          app: app,
          toasts: _toasts,
          child: Listener(
            // Any pointer activity postpones the automatic lock.
            onPointerDown: (_) => app.registerActivity(),
            onPointerSignal: (_) => app.registerActivity(),
            child: ToastHost(controller: _toasts, child: child!),
          ),
        ),
        home: const RootView(),
      ),
    );
  }
}

class RootView extends StatelessWidget {
  const RootView({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final Widget screen = switch (app.phase) {
          AppPhase.loading => const SizedBox.shrink(),
          AppPhase.onboarding => const OnboardingFlow(),
          AppPhase.needsPin => const PinSetupScreen(),
          AppPhase.locked => const LockScreen(),
          AppPhase.unlocked => const HomeScreen(),
        };
        return Scaffold(
          body: Focus(
            // Only observes key events of the focused descendants (activity for the auto-lock).
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: (_, _) {
              app.registerActivity();
              return KeyEventResult.ignored;
            },
            child: Stack(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: KeyedSubtree(key: ValueKey(app.phase), child: screen),
                ),
                if (Platform.isMacOS && app.phase != AppPhase.unlocked)
                  const Positioned(top: 0, left: 0, right: 0, height: 36, child: DragToMoveArea(child: SizedBox.expand())),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Centered column used by the first-access and lock screens.
class CenteredPage extends StatelessWidget {
  const CenteredPage({super.key, required this.children, this.width = 400, this.top});
  final List<Widget> children;
  final double width;
  final Widget? top;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.colors.bg,
      child: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
              child: SizedBox(
                width: width,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children),
              ),
            ),
          ),
          if (top != null) Positioned(top: Platform.isMacOS ? 40 : 16, left: 20, child: top!),
        ],
      ),
    );
  }
}
