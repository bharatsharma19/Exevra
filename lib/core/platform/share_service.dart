import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../logging/app_logger.dart';

/// Opens the platform share sheet.
abstract interface class ShareService {
  /// Shares [text]. Returns false when no share sheet could be shown, so
  /// the caller can fall back to copying.
  Future<bool> shareText(String text, {String? subject});
}

class PlusShareService implements ShareService {
  const PlusShareService();

  @override
  Future<bool> shareText(String text, {String? subject}) async {
    try {
      // `unavailable` only means the platform reports no result; the sheet
      // was still shown.
      await SharePlus.instance.share(ShareParams(text: text, subject: subject));
      return true;
    } on Exception catch (error) {
      AppLogger.warn('Share sheet unavailable', error.runtimeType);
      return false;
    }
  }
}

final shareServiceProvider = Provider<ShareService>(
  (ref) => const PlusShareService(),
);
