import 'package:flutter/material.dart';

/// Antigravity High-Fidelity Color System
class AppColors {
  AppColors._();

  // Primary Neon Brand Accents
  static const Color primaryCyan = Color(0xFF00E5FF);
  static const Color primaryViolet = Color(0xFF8B5CF6);
  static const Color primaryIndigo = Color(0xFF6366F1);
  static const Color primaryEmerald = Color(0xFF10B981);
  static const Color primaryRose = Color(0xFFF43F5E);
  static const Color primaryAmber = Color(0xFFF59E0B);
  static const Color primaryBlue = Color(0xFF3B82F6);

  // Dark Theme Palette (Space & Deep Obsidian)
  static const Color darkBackground = Color(0xFF070B14);
  static const Color darkCard = Color(0xFF0F172A);
  static const Color darkCardElevated = Color(0xFF1E293B);
  static const Color darkSurface = Color(0xFF131D31);
  static const Color darkBorder = Color(0x1FFFFFFF);
  static const Color darkTextPrimary = Color(0xFFF8FAFC);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkTextTertiary = Color(0xFF64748B);

  // Light Theme Palette (Crisp Titanium & Platinum)
  static const Color lightBackground = Color(0xFFF8FAFC);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightCardElevated = Color(0xFFF1F5F9);
  static const Color lightSurface = Color(0xFFE2E8F0);
  static const Color lightBorder = Color(0x14000000);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF475569);
  static const Color lightTextTertiary = Color(0xFF94A3B8);

  // Glassmorphic Accents
  static const Color glassWhite = Color(0x1AFFFFFF);
  static const Color glassWhiteBorder = Color(0x33FFFFFF);
  static const Color glassDark = Color(0x660F172A);
  static const Color glassDarkBorder = Color(0x2E38BDF8);

  // Status & Semantics
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // Category Color Map
  static const Map<String, Color> categoryColors = {
    'Food': Color(0xFFF59E0B),
    'Transport': Color(0xFF3B82F6),
    'Housing': Color(0xFF8B5CF6),
    'Entertainment': Color(0xFFEC4899),
    'Healthcare': Color(0xFF10B981),
    'Utilities': Color(0xFF06B6D4),
    'Shopping': Color(0xFFF97316),
    'Personal': Color(0xFF6366F1),
    'Education': Color(0xFF14B8A6),
    'Other': Color(0xFF64748B),
  };

  static Color getCategoryColor(String category) {
    return categoryColors[category] ?? const Color(0xFF00E5FF);
  }

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryCyan, primaryViolet],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cyanEmeraldGradient = LinearGradient(
    colors: [primaryCyan, primaryEmerald],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient violetRoseGradient = LinearGradient(
    colors: [primaryViolet, primaryRose],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkCardGradient = LinearGradient(
    colors: [Color(0xFF131D31), Color(0xFF0B1324)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient glassOverlayGradient = LinearGradient(
    colors: [Color(0x22FFFFFF), Color(0x05FFFFFF)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}
