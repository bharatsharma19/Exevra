import 'dart:async';

import 'package:expense_manager/core/errors/app_failure.dart';
import 'package:expense_manager/core/platform/device_time_zone.dart';
import 'package:expense_manager/core/storage/preferences.dart';
import 'package:expense_manager/data/ai/ai_chat_client.dart';
import 'package:expense_manager/data/ai/ai_chat_models.dart';
import 'package:expense_manager/data/repositories/ai_report_repository.dart';
import 'package:expense_manager/data/repositories/expense_repository.dart';
import 'package:expense_manager/data/repositories/group_repository.dart';
import 'package:expense_manager/data/repositories/profile_repository.dart';
import 'package:expense_manager/features/chat/widgets/safe_markdown.dart';
import 'package:expense_manager/providers/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

/// One request the fake assistant received.
class FakeCall {
  FakeCall(this.request);

  final AiChatRequest request;
  final StreamController<AiStreamEvent> controller =
      StreamController<AiStreamEvent>();
  bool aborted = false;
  bool cancelled = false;

  List<AiTurn> get turns => request.messages;

  void emit(AiStreamEvent event) {
    if (!controller.isClosed) controller.add(event);
  }

  /// Emits [events] and closes the stream.
  Future<void> finish(List<AiStreamEvent> events) async {
    events.forEach(emit);
    await controller.close();
  }

  Future<void> fail(AiErrorCode code) => failWith(AiChatException(code));

  Future<void> failWith(AiChatException error) async {
    if (controller.isClosed) return;
    controller.addError(error);
    await controller.close();
  }
}

/// An [AiChatApi] driven by the test.
class FakeAiChatApi implements AiChatApi {
  final List<FakeCall> calls = [];

  FakeCall get last => calls.last;

  @override
  Stream<AiStreamEvent> stream(
    AiChatRequest request, {
    Future<void>? abortTrigger,
  }) {
    final call = FakeCall(request);
    unawaited(abortTrigger?.then((_) => call.aborted = true));
    call.controller.onCancel = () => call.cancelled = true;
    calls.add(call);
    return call.controller.stream;
  }
}

class FakeAiReportRepository implements AiReportRepository {
  final List<AiReport> reports = [];
  AppFailure? failWith;

  @override
  Future<void> submit(AiReport report) async {
    final failure = failWith;
    if (failure != null) throw failure;
    reports.add(report);
  }
}

/// A container like [TestBackend.container] with the assistant faked.
Future<ProviderContainer> chatContainer(
  TestBackend backend,
  FakeAiChatApi api, {
  Map<String, Object> prefs = const {},
  FakeAiReportRepository? reports,
  List<Uri>? launched,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final preferences = await SharedPreferences.getInstance();
  return ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      authServiceProvider.overrideWithValue(backend.auth),
      profileRepositoryProvider.overrideWithValue(backend.profiles),
      groupRepositoryProvider.overrideWithValue(backend.groups),
      expenseRepositoryProvider.overrideWithValue(backend.expenses),
      deviceTimeZoneProvider.overrideWith((ref) async => 'Asia/Kolkata'),
      aiChatApiProvider.overrideWithValue(api),
      aiReportRepositoryProvider.overrideWithValue(
        reports ?? FakeAiReportRepository(),
      ),
      externalLinkLauncherProvider.overrideWithValue((uri) async {
        launched?.add(uri);
        return true;
      }),
    ],
  );
}
