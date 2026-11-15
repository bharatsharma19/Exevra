import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_failure.dart';

/// A failure to show once, with a sequence number so the same failure
/// reported twice is shown twice.
class ReportedFailure {
  const ReportedFailure(this.failure, this.sequence);

  final AppFailure failure;
  final int sequence;
}

/// Single surface for background action failures (save, delete, switch
/// group, ...). The main shell listens and shows each one in a snack bar,
/// so an error is shown exactly once.
class FailureReporter extends Notifier<ReportedFailure?> {
  int _sequence = 0;

  @override
  ReportedFailure? build() => null;

  void report(AppFailure failure) {
    state = ReportedFailure(failure, ++_sequence);
  }
}

final failureReporterProvider =
    NotifierProvider<FailureReporter, ReportedFailure?>(FailureReporter.new);
