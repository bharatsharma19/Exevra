import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_palette.dart';

/// The category's icon on a soft tint of its stable palette colour.
///
/// Decorative: the category name is always shown next to it as text.
class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({required this.category, this.size = 40, super.key});

  final String category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = context.palette.categoryColor(category);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.16),
        ),
        child: Icon(
          AppConstants.getCategoryIcon(category),
          color: color,
          size: size / 2,
        ),
      ),
    );
  }
}
