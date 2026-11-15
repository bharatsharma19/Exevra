import 'dart:async';

import 'package:alchemist/alchemist.dart';

/// Global test configuration.
///
/// Golden tests use Alchemist's CI goldens only: text renders as blocks and
/// shadows are off, so images are identical on every OS. Platform goldens
/// (real fonts, differ per OS) are disabled.
Future<void> testExecutable(FutureOr<void> Function() testMain) {
  return AlchemistConfig.runWithConfig(
    config: const AlchemistConfig(
      platformGoldensConfig: PlatformGoldensConfig(enabled: false),
      ciGoldensConfig: CiGoldensConfig(enabled: true),
    ),
    run: () async => testMain(),
  );
}
