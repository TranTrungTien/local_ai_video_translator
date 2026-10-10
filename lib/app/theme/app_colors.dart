import 'package:flutter/material.dart';

abstract class AppColors {
  // Backgrounds
  static const Color background = Color(0xFF0B0E17);
  static const Color surface = Color(0xFF131722);
  static const Color surfaceCard = Color(0xFF191E2C);
  static const Color surfaceCardBorder = Color(0xFF262C3F);
  
  // Accents & Glows
  static const Color primary = Color(0xFF6C5CE7);
  static const Color primaryLight = Color(0xFF8C7CFF);
  static const Color primaryGlow = Color(0x666C5CE7);
  
  static const Color secondary = Color(0xFFA855F7);
  static const Color cyanAccent = Color(0xFF00F2FE);
  static const Color cyanGlow = Color(0x4000F2FE);

  // Text
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  // Status Colors
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF6C5CE7), Color(0xFF8C7CFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [Color(0xFF0B0E17), Color(0xFF111523)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient cardGlowGradient = LinearGradient(
    colors: [Color(0x336C5CE7), Color(0x056C5CE7)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cyanGradient = LinearGradient(
    colors: [Color(0xFF4FACFE), Color(0xFF00F2FE)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
