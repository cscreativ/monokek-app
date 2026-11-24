import 'package:flutter/material.dart';

/// shadcn "neutral" tokens from mono-kep-tauri/src/app/globals.css (oklch → sRGB),
/// plus the slate palette the kitchen screens use.
class AppColors {
  // light
  static const background = Color(0xFFFFFFFF);
  static const foreground = Color(0xFF0A0A0A);
  static const card = Color(0xFFFFFFFF);
  static const primary = Color(0xFF171717);
  static const onPrimary = Color(0xFFFAFAFA);
  static const muted = Color(0xFFF5F5F5);
  static const mutedForeground = Color(0xFF737373);
  static const border = Color(0xFFE5E5E5);
  static const destructive = Color(0xFFE7000B);
  // dark
  static const darkBackground = Color(0xFF0A0A0A);
  static const darkForeground = Color(0xFFFAFAFA);
  static const darkCard = Color(0xFF171717);
  static const darkPrimary = Color(0xFFE5E5E5);
  static const darkOnPrimary = Color(0xFF171717);
  static const darkMuted = Color(0xFF262626);
  static const darkMutedForeground = Color(0xFFA3A3A3);
  static const darkBorder = Color(0x1AFFFFFF);
  static const darkDestructive = Color(0xFFFF6467);
  // slate (kitchen)
  static const slate50 = Color(0xFFF8FAFC);
  static const slate400 = Color(0xFF94A3B8);
  static const slate900 = Color(0xFF0F172A);
  static const slate950 = Color(0xFF020617);
  // semantic
  static const success = Color(0xFF10B981);
  static const warning = Color(0xFFF59E0B);
  static const orange = Color(0xFFF97316);
  static const info = Color(0xFF3B82F6);
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final bg = dark ? AppColors.darkBackground : AppColors.background;
  final fg = dark ? AppColors.darkForeground : AppColors.foreground;
  final primary = dark ? AppColors.darkPrimary : AppColors.primary;
  final onPrimary = dark ? AppColors.darkOnPrimary : AppColors.onPrimary;
  final card = dark ? AppColors.darkCard : AppColors.card;
  final muted = dark ? AppColors.darkMuted : AppColors.muted;
  final border = dark ? AppColors.darkBorder : AppColors.border;
  final destructive = dark ? AppColors.darkDestructive : AppColors.destructive;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: primary,
    onPrimary: onPrimary,
    secondary: muted,
    onSecondary: fg,
    error: destructive,
    onError: Colors.white,
    surface: bg,
    onSurface: fg,
    surfaceContainerHighest: muted,
    outline: border,
    onSurfaceVariant: dark ? AppColors.darkMutedForeground : AppColors.mutedForeground,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    cardColor: card,
    dividerColor: border,
    // Black-weight titles are the app's signature (font-black uppercase italic tracking-tighter).
    textTheme: ThemeData(brightness: brightness).textTheme.apply(bodyColor: fg, displayColor: fg),
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: muted.withValues(alpha: 0.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: primary, width: 1.5)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5),
      ),
    ),
  );
}

/// font-black uppercase italic tracking-tighter
const titleStyle = TextStyle(fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, letterSpacing: -1);

/// text-[10px] font-black uppercase tracking-widest
const microLabelStyle = TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2);

/// Button styles for screens that are ALWAYS dark (slate950), whatever the app theme. The theme's default
/// button colours (primary) are dark in the light theme and nearly invisible on such a background.
final ButtonStyle onDarkOutlinedButton = OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54));
final ButtonStyle onDarkFilledButton = FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.slate950);
