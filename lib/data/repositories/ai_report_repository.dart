import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_failure.dart';
import '../supabase_client_provider.dart';

/// Why a user reports an assistant answer (`ai_reports.reason`).
enum AiReportReason {
  offensive('offensive', 'Offensive'),
  harmful('harmful', 'Harmful or unsafe'),
  inaccurate('inaccurate', 'Inaccurate'),
  other('other', 'Something else');

  const AiReportReason(this.wire, this.label);

  final String wire;
  final String label;
}

/// A report of one assistant answer.
class AiReport {
  AiReport({
    required this.userId,
    required this.reason,
    required String messageExcerpt,
    this.provider,
    String? note,
  }) : messageExcerpt = _clip(messageExcerpt.trim(), maxExcerptLength),
       note = _cleanNote(note);

  static const int maxExcerptLength = 2000;
  static const int maxNoteLength = 500;

  final String userId;
  final AiReportReason reason;
  final String messageExcerpt;

  /// The provider that wrote the answer (`AiProvider.name`), when known.
  final String? provider;
  final String? note;

  Map<String, Object> toRow() => {
    'user_id': userId,
    'reason': reason.wire,
    'message_excerpt': messageExcerpt,
    'provider': ?provider,
    'note': ?note,
  };

  static String? _cleanNote(String? note) {
    final trimmed = note?.trim() ?? '';
    return trimmed.isEmpty ? null : _clip(trimmed, maxNoteLength);
  }

  /// Cuts [text] to at most [max] UTF-16 units without splitting a
  /// surrogate pair.
  static String _clip(String text, int max) {
    if (text.length <= max) return text;
    var end = max;
    final last = text.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) end--;
    return text.substring(0, end);
  }
}

/// Stores reports of assistant answers for review.
abstract interface class AiReportRepository {
  /// Throws [AppFailure].
  Future<void> submit(AiReport report);
}

final aiReportRepositoryProvider = Provider<AiReportRepository>(
  (ref) => SupabaseAiReportRepository(ref.watch(supabaseClientProvider)),
);

class SupabaseAiReportRepository implements AiReportRepository {
  SupabaseAiReportRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<void> submit(AiReport report) {
    return ErrorMapper.guard(() async {
      if (report.messageExcerpt.isEmpty) {
        throw const AppFailure.validation(key: 'report_empty');
      }
      await _client.from('ai_reports').insert(report.toRow());
    });
  }
}
