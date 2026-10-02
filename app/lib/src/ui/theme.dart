// Visual tokens from docs/DESIGN.md: monochrome, Geist for text, Geist Mono for values.
import 'package:flutter/material.dart';

const kSans = 'Geist';
const kMono = 'GeistMono';

@immutable
class VaultColors extends ThemeExtension<VaultColors> {
  const VaultColors({
    required this.bg,
    required this.sidebar,
    required this.hover,
    required this.selected,
    required this.divider,
    required this.inputBg,
    required this.inputBorder,
    required this.text,
    required this.text2,
    required this.text3,
    required this.primary,
    required this.onPrimary,
    required this.danger,
    required this.toastBg,
    required this.toastText,
    required this.shadow,
  });

  final Color bg, sidebar, hover, selected, divider, inputBg, inputBorder;
  final Color text, text2, text3, primary, onPrimary, danger, toastBg, toastText, shadow;

  static const light = VaultColors(
    bg: Color(0xFFFFFFFF),
    sidebar: Color(0xFFF5F5F5),
    hover: Color(0xFFF2F2F2),
    selected: Color(0xFFEBEBEB),
    divider: Color(0xFFEBEBEB),
    inputBg: Color(0xFFFAFAFA),
    inputBorder: Color(0xFFE3E3E3),
    text: Color(0xFF111111),
    text2: Color(0xFF707070),
    text3: Color(0xFFA8A8A8),
    primary: Color(0xFF111111),
    onPrimary: Color(0xFFFFFFFF),
    danger: Color(0xFFD93025),
    toastBg: Color(0xFF111111),
    toastText: Color(0xFFFFFFFF),
    shadow: Color(0x1F000000),
  );

  static const dark = VaultColors(
    bg: Color(0xFF0F0F10),
    sidebar: Color(0xFF161617),
    hover: Color(0xFF1A1A1C),
    selected: Color(0xFF252527),
    divider: Color(0xFF232325),
    inputBg: Color(0xFF151517),
    inputBorder: Color(0xFF2C2C2E),
    text: Color(0xFFEDEDED),
    text2: Color(0xFF9A9A9A),
    text3: Color(0xFF5E5E5E),
    primary: Color(0xFFEDEDED),
    onPrimary: Color(0xFF111111),
    danger: Color(0xFFFF6B5E),
    toastBg: Color(0xFFEDEDED),
    toastText: Color(0xFF111111),
    shadow: Color(0x66000000),
  );

  @override
  VaultColors copyWith() => this;

  @override
  VaultColors lerp(ThemeExtension<VaultColors>? other, double t) {
    if (other is! VaultColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return VaultColors(
      bg: l(bg, other.bg),
      sidebar: l(sidebar, other.sidebar),
      hover: l(hover, other.hover),
      selected: l(selected, other.selected),
      divider: l(divider, other.divider),
      inputBg: l(inputBg, other.inputBg),
      inputBorder: l(inputBorder, other.inputBorder),
      text: l(text, other.text),
      text2: l(text2, other.text2),
      text3: l(text3, other.text3),
      primary: l(primary, other.primary),
      onPrimary: l(onPrimary, other.onPrimary),
      danger: l(danger, other.danger),
      toastBg: l(toastBg, other.toastBg),
      toastText: l(toastText, other.toastText),
      shadow: l(shadow, other.shadow),
    );
  }
}

/// Text styles of the design (colors applied by [VaultText.of]).
class VaultText {
  VaultText(this.c);
  final VaultColors c;

  static VaultText of(BuildContext context) => VaultText(Theme.of(context).extension<VaultColors>()!);

  TextStyle get title => TextStyle(fontFamily: kSans, fontSize: 28, height: 34 / 28, fontWeight: FontWeight.w600, letterSpacing: -0.5, color: c.text);
  TextStyle get key => TextStyle(fontFamily: kSans, fontSize: 13, height: 20 / 13, fontWeight: FontWeight.w400, color: c.text2);
  TextStyle get value => TextStyle(fontFamily: kMono, fontSize: 13, height: 20 / 13, fontWeight: FontWeight.w400, color: c.text);
  TextStyle get description => TextStyle(fontFamily: kSans, fontSize: 14, height: 22 / 14, fontWeight: FontWeight.w400, color: c.text);
  TextStyle get listTitle => TextStyle(fontFamily: kSans, fontSize: 13.5, height: 18 / 13.5, fontWeight: FontWeight.w500, color: c.text);
  TextStyle get listSubtitle => TextStyle(fontFamily: kSans, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w400, color: c.text2);
  TextStyle get sidebar => TextStyle(fontFamily: kSans, fontSize: 13, height: 18 / 13, fontWeight: FontWeight.w500, color: c.text);
  TextStyle get body => TextStyle(fontFamily: kSans, fontSize: 13, height: 20 / 13, fontWeight: FontWeight.w400, color: c.text);
  TextStyle get bodyStrong => body.copyWith(fontWeight: FontWeight.w600);
  TextStyle get small => TextStyle(fontFamily: kSans, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w400, color: c.text2);
  TextStyle get tiny => TextStyle(fontFamily: kSans, fontSize: 11, height: 14 / 11, fontWeight: FontWeight.w500, color: c.text3);
  TextStyle get headline => TextStyle(fontFamily: kSans, fontSize: 24, height: 30 / 24, fontWeight: FontWeight.w600, letterSpacing: -0.4, color: c.text);
  TextStyle get subhead => TextStyle(fontFamily: kSans, fontSize: 14, height: 22 / 14, fontWeight: FontWeight.w400, color: c.text2);
  TextStyle get section => TextStyle(fontFamily: kSans, fontSize: 13, height: 18 / 13, fontWeight: FontWeight.w600, color: c.text);
  TextStyle get monoLarge => TextStyle(fontFamily: kMono, fontSize: 20, height: 28 / 20, fontWeight: FontWeight.w500, letterSpacing: 1, color: c.text);
}

extension VaultThemeX on BuildContext {
  VaultColors get colors => Theme.of(this).extension<VaultColors>()!;
  VaultText get text => VaultText(colors);
}

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? VaultColors.dark : VaultColors.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.primary,
    onPrimary: c.onPrimary,
    secondary: c.text2,
    onSecondary: c.bg,
    error: c.danger,
    onError: c.onPrimary,
    surface: c.bg,
    onSurface: c.text,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: kSans,
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    dividerColor: c.divider,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: c.hover,
    focusColor: c.primary.withValues(alpha: 0.12),
    visualDensity: VisualDensity.compact,
    extensions: [c],
  );
  return base.copyWith(
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.primary,
      selectionColor: c.primary.withValues(alpha: 0.18),
      selectionHandleColor: c.primary,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: c.toastBg, borderRadius: BorderRadius.circular(6)),
      textStyle: TextStyle(fontFamily: kSans, fontSize: 12, color: c.toastText),
      waitDuration: const Duration(milliseconds: 500),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(c.text3.withValues(alpha: 0.5)),
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(3),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: c.shadow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: c.divider)),
      textStyle: TextStyle(fontFamily: kSans, fontSize: 13, color: c.text),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.bg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.divider)),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: c.primary,
      inactiveTrackColor: c.selected,
      thumbColor: c.primary,
      overlayColor: c.primary.withValues(alpha: 0.08),
      trackHeight: 3,
    ),
  );
}
