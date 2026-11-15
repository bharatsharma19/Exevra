import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_failure.dart';
import '../core/logging/app_logger.dart';
import 'auth_provider.dart';

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
///
/// Failures belong to a signed-in session: while nobody is signed in (for
/// example during the sign-out page transition, when the main shell is
/// still on screen) a report is dropped, so it never shows on the login
/// screen or to the next user.
class FailureReporter extends Notifier<ReportedFailure?> {
  int _sequence = 0;

  @override
  ReportedFailure? build() => null;

  void report(AppFailure failure) {
    if (ref.read(currentUserIdProvider) == null) {
      AppLogger.debug('Dropped a failure report: nobody is signed in');
      return;
    }
    state = ReportedFailure(failure, ++_sequence);
  }
}

final failureReporterProvider =
    NotifierProvider<FailureReporter, ReportedFailure?>(FailureReporter.new);
