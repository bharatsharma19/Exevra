import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../../../models/profile.dart';

/// Saves [update]; resolves to the failure or null.
typedef ProfileSaver = Future<AppFailure?> Function(ProfileUpdate update);

/// Opens the edit-profile dialog. Resolves to true once the change was
/// saved.
Future<bool> showEditProfileDialog(
  BuildContext context, {
  required String name,
  required String? avatarUrl,
  required ProfileSaver onSave,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        EditProfileDialog(name: name, avatarUrl: avatarUrl, onSave: onSave),
  );
  return saved ?? false;
}

/// Name and photo link of the profile. Each field is checked as the user
/// leaves it and again on Save (the same rules as the server); a failed
/// save stays in the dialog with the reason, and leaving with edits asks
/// first.
class EditProfileDialog extends StatefulWidget {
  const EditProfileDialog({
    super.key,
    required this.name,
    required this.avatarUrl,
    required this.onSave,
  });

  final String name;
  final String? avatarUrl;
  final ProfileSaver onSave;

  @override
  State<EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<EditProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.name);
  late final _avatar = TextEditingController(text: widget.avatarUrl ?? '');
  bool _saving = false;
  AppFailure? _failure;

  @override
  void initState() {
    super.initState();
    _name.addListener(_changed);
    _avatar.addListener(_changed);
  }

  @override
  void dispose() {
    _name.dispose();
    _avatar.dispose();
    super.dispose();
  }

  void _changed() => setState(() => _failure = null);

  bool get _hasChanges =>
      _name.text.trim() != widget.name.trim() ||
      _avatar.text.trim() != (widget.avatarUrl ?? '').trim();

  static String? _validateName(String? value) {
    final name = value?.trim() ?? '';
    return ProfileUpdate(displayName: name).validate() == null
        ? null
        : friendlyMessageForKey('invalid_display_name');
  }

  static String? _validateAvatar(String? value) {
    final url = value?.trim() ?? '';
    if (url.isEmpty) return null;
    return ProfileUpdate(avatarUrl: url).validate() == null
        ? null
        : friendlyMessageForKey('invalid_avatar_url');
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_hasChanges) {
      Navigator.of(context).pop(false);
      return;
    }
    final url = _avatar.text.trim();
    setState(() {
      _saving = true;
      _failure = null;
    });
    final failure = await widget.onSave(
      ProfileUpdate(
        displayName: _name.text,
        avatarUrl: url.isEmpty ? null : url,
      ),
    );
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _saving = false;
        _failure = failure;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final failure = _failure;
    return UnsavedChangesGuard(
      hasChanges: _hasChanges && !_saving,
      child: AlertDialog(
        scrollable: true,
        title: Text(l10n.profileEditTitle),
        content: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUnfocus,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (failure != null) ...[
                Semantics(
                  liveRegion: true,
                  container: true,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        color: palette.danger,
                        size: AppSizes.iconSm,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          friendlyMessage(failure),
                          style: TextStyle(color: palette.danger),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              TextFormField(
                key: const Key('profile-edit-name'),
                controller: _name,
                maxLength: 60,
                enabled: !_saving,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                validator: _validateName,
                decoration: InputDecoration(
                  labelText: l10n.profileNameLabel,
                  helperText: l10n.profileNameHelper,
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const Key('profile-edit-photo'),
                controller: _avatar,
                enabled: !_saving,
                keyboardType: TextInputType.url,
                autocorrect: false,
                textInputAction: TextInputAction.done,
                validator: _validateAvatar,
                onFieldSubmitted: (_) => unawaited(_save()),
                decoration: InputDecoration(
                  labelText: l10n.profilePhotoLabel,
                  hintText: l10n.profilePhotoHint,
                  helperText: l10n.profilePhotoHelper,
                  helperMaxLines: 2,
                  prefixIcon: const Icon(Icons.link_rounded),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).maybePop(),
            child: Text(l10n.cancel),
          ),
          LoadingButton(
            key: const Key('profile-edit-save'),
            label: l10n.save,
            expand: false,
            isLoading: _saving,
            onPressed: () => unawaited(_save()),
          ),
        ],
      ),
    );
  }
}
