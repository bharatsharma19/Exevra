import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../about/about_screen.dart';
import '../account_deletion.dart';

/// About for a signed-in user (`/profile/about`): the About screen with
/// Delete account wired to the profile's confirm-and-delete flow.
class ProfileAboutScreen extends ConsumerWidget {
  const ProfileAboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      AboutScreen(onDeleteAccount: () => confirmAndDeleteAccount(context, ref));
}
