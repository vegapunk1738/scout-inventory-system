import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:scout_stock/data/api/api_client.dart';
import 'package:scout_stock/domain/models/managed_user.dart'
    show kSuperAdminScoutId;
import 'package:scout_stock/presentation/widgets/app_toast.dart';
import 'package:scout_stock/presentation/widgets/dotted_background.dart';
import 'package:scout_stock/presentation/widgets/glowing_action_button.dart';
import 'package:scout_stock/theme/app_theme.dart';

import '../../widgets/attention_text_field_widget.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Callback type used by both create and edit flows.
//
// The upsert page calls this *before* popping, so the API request is
// guaranteed to fire regardless of the parent page's lifecycle state.
// ═══════════════════════════════════════════════════════════════════════════

/// Async callback that performs the actual API mutation.
/// Throws on failure so the upsert page can surface the error and let the
/// user retry without losing their input.
typedef UpsertSubmitCallback =
    Future<void> Function(Map<String, dynamic> result);

/// Navigation args for editing an existing user.
class UserUpsertArgs {
  const UserUpsertArgs({
    required this.scoutId,
    required this.displayName,
    required this.role,
    required this.onSubmit,
  });

  final String scoutId;
  final String displayName;

  /// 'scout' | 'admin'
  final String role;

  /// Called with the form payload. Must complete the API call before
  /// returning. Throw to signal failure.
  final UpsertSubmitCallback onSubmit;
}

/// Passed as extra when navigating to the create page.
class CreateUserArgs {
  const CreateUserArgs({required this.nextScoutId, required this.onSubmit});

  final String nextScoutId;

  /// Called with the form payload. Must complete the API call before
  /// returning. Throw to signal failure.
  final UpsertSubmitCallback onSubmit;
}

enum _UserRole { scout, admin }

extension on _UserRole {
  String get apiValue => this == _UserRole.admin ? 'admin' : 'scout';
  String get label => this == _UserRole.admin ? 'Admin' : 'Scout';
  IconData get icon => this == _UserRole.admin
      ? Icons.shield_rounded
      : Icons.directions_walk_rounded;
}

_UserRole _roleFromApi(String raw) =>
    raw == 'admin' ? _UserRole.admin : _UserRole.scout;

class UserUpsertPage extends StatefulWidget {
  const UserUpsertPage({super.key, this.editArgs, this.createArgs});

  final UserUpsertArgs? editArgs;
  final CreateUserArgs? createArgs;

  @override
  State<UserUpsertPage> createState() => _UserUpsertPageState();
}

class _UserUpsertPageState extends State<UserUpsertPage> {
  final _nameCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  final _nameFocus = FocusNode();
  final _idFocus = FocusNode();

  final _nameKey = GlobalKey<AttentionTextFieldState>();
  final _idKey = GlobalKey<AttentionTextFieldState>();
  final _pwKey = GlobalKey<AttentionTextFieldState>();
  final _newPwKey = GlobalKey<AttentionTextFieldState>();
  final _confirmPwKey = GlobalKey<AttentionTextFieldState>();

  late _UserRole _role;
  bool _saving = false;
  bool _pwObscure = true;
  bool _newPwObscure = true;
  bool _confirmPwObscure = true;

  // Inline validation errors — null means no error shown yet.
  String? _nameError;
  String? _idError;
  String? _pwError;
  String? _newPwError;
  String? _confirmPwError;

  bool get _isEdit => widget.editArgs != null;
  bool get _isSuperAdmin =>
      _isEdit && widget.editArgs!.scoutId == kSuperAdminScoutId;

  @override
  void initState() {
    super.initState();

    final edit = widget.editArgs;
    _role = _roleFromApi(edit?.role ?? 'scout');

    if (edit != null) {
      _nameCtrl.text = edit.displayName;
      _idCtrl.text = edit.scoutId;
    } else if (widget.createArgs != null) {
      _idCtrl.text = widget.createArgs!.nextScoutId;
    }

    _nameCtrl.addListener(_validateNameLive);
    _passwordCtrl.addListener(_validatePasswordLive);
    _newPasswordCtrl.addListener(_validateNewPasswordLive);
    _confirmPasswordCtrl.addListener(_validateConfirmLive);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isSuperAdmin) _nameFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _idCtrl.dispose();
    _passwordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _nameFocus.dispose();
    _idFocus.dispose();
    super.dispose();
  }

  // ── Live validation (clears errors as user fixes them) ─────────────────

  void _validateNameLive() {
    if (_nameError != null && _nameCtrl.text.trim().length >= 2) {
      setState(() => _nameError = null);
    }
  }

  void _validatePasswordLive() {
    if (_pwError != null && _passwordCtrl.text.length >= 6) {
      setState(() => _pwError = null);
    }
  }

  void _validateNewPasswordLive() {
    if (_newPwError != null && _newPasswordCtrl.text.length >= 6) {
      setState(() => _newPwError = null);
    }
    if (_confirmPwError != null &&
        _confirmPasswordCtrl.text == _newPasswordCtrl.text) {
      setState(() => _confirmPwError = null);
    }
  }

  void _validateConfirmLive() {
    if (_confirmPwError != null &&
        _confirmPasswordCtrl.text == _newPasswordCtrl.text) {
      setState(() => _confirmPwError = null);
    }
  }

  // ── Full validation on submit ──────────────────────────────────────────

  bool _validate() {
    String? nameErr;
    String? idErr;
    String? pwErr;
    String? newPwErr;
    String? confirmPwErr;

    final name = _nameCtrl.text.trim();
    final id = _idCtrl.text.trim();

    if (name.isEmpty) {
      nameErr = 'Name is required';
    } else if (name.length < 2) {
      nameErr = 'Must be at least 2 characters';
    } else if (name.length > 100) {
      nameErr = 'Must be at most 100 characters';
    }

    if (!_isEdit) {
      if (id.isEmpty) {
        idErr = 'Scout ID is required';
      } else if (!RegExp(r'^\d+$').hasMatch(id)) {
        idErr = 'Must contain only digits';
      } else if (id.length > 10) {
        idErr = 'Must be at most 10 digits';
      }
    }

    if (!_isEdit) {
      final pw = _passwordCtrl.text;
      if (pw.isEmpty) {
        pwErr = 'Password is required';
      } else if (pw.length < 6) {
        pwErr = 'Must be at least 6 characters';
      } else if (pw.length > 128) {
        pwErr = 'Must be at most 128 characters';
      }
    }

    if (_isEdit) {
      final newPw = _newPasswordCtrl.text;
      final confirm = _confirmPasswordCtrl.text;
      final wantsPwChange = newPw.isNotEmpty || confirm.isNotEmpty;

      if (wantsPwChange) {
        if (newPw.length < 6) {
          newPwErr = 'Must be at least 6 characters';
        } else if (newPw.length > 128) {
          newPwErr = 'Must be at most 128 characters';
        }

        if (newPwErr == null && confirm != newPw) {
          confirmPwErr = 'Passwords do not match';
        }
      }
    }

    setState(() {
      _nameError = nameErr;
      _idError = idErr;
      _pwError = pwErr;
      _newPwError = newPwErr;
      _confirmPwError = confirmPwErr;
    });

    if (nameErr != null) {
      _nameFocus.requestFocus();
      _nameKey.currentState?.triggerInvalid();
      return false;
    }
    if (idErr != null) {
      _idFocus.requestFocus();
      _idKey.currentState?.triggerInvalid();
      return false;
    }
    if (pwErr != null) {
      _pwKey.currentState?.triggerInvalid();
      return false;
    }
    if (newPwErr != null) {
      _newPwKey.currentState?.triggerInvalid();
      return false;
    }
    if (confirmPwErr != null) {
      _confirmPwKey.currentState?.triggerInvalid();
      return false;
    }

    return true;
  }

  // ── Error display ──────────────────────────────────────────────────────

  /// Shows API errors on this page so the user can see what went wrong
  /// and retry without losing their input.
  void _showSubmitError(Object e) {
    if (!mounted) return;

    if (e is ApiException && e.hasFieldErrors) {
      final toast = AppToast.of(context);
      for (final fe in e.fieldErrors) {
        toast.show(
          AppToastData.error(
            title: fe.label,
            subtitle: fe.message,
            duration: const Duration(seconds: 6),
          ),
        );
      }
      return;
    }

    final msg = e is ApiException
        ? e.message
        : 'Something went wrong. Please try again.';
    AppToast.of(context).show(
      AppToastData.error(
        title: _isEdit ? 'Update failed' : 'Creation failed',
        subtitle: msg,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  // ── Submit ─────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_saving || _isSuperAdmin) return;
    if (!_validate()) return;

    final name = _nameCtrl.text.trim();
    final scoutId = _idCtrl.text.trim();

    setState(() => _saving = true);

    // FIX: Unfocus *after* setting saving state, and wrap everything in
    // try/finally so _saving is always reset on failure.
    try {
      FocusScope.of(context).unfocus();

      // Build the result payload.
      final Map<String, dynamic> payload;
      if (!_isEdit) {
        payload = {
          'displayName': name,
          'scoutId': scoutId,
          'role': _role.apiValue,
          'password': _passwordCtrl.text,
        };
      } else {
        final newPw = _newPasswordCtrl.text;
        final confirm = _confirmPasswordCtrl.text;
        final wantsPwChange = newPw.isNotEmpty && confirm.isNotEmpty;
        payload = {
          'displayName': name,
          'scoutId': scoutId,
          'role': _role.apiValue,
          if (wantsPwChange) 'newPassword': newPw,
        };
      }

      // FIX: Call the mutation callback *here*, while we're still mounted
      // and have a valid context. The callback performs the API call.
      // Only pop on success — on failure the user stays on the form.
      final callback = _isEdit
          ? widget.editArgs!.onSubmit
          : widget.createArgs!.onSubmit;
      await callback(payload);

      // API call succeeded — now pop.
      if (mounted) context.pop();
    } catch (e) {
      // FIX: Surface the error on this page so the user can see it and
      // retry. The old code would have silently swallowed this because
      // the error was only catchable on the parent page — which might
      // already be unmounted.
      _showSubmitError(e);
    } finally {
      // FIX: Always reset _saving so the button is never permanently
      // disabled. Without this, a failed API call or a pop() that
      // doesn't navigate would leave the form in a dead state.
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Styles ─────────────────────────────────────────────────────────────

  TextStyle _fieldTextStyle(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return (t.bodyLarge ?? const TextStyle()).copyWith(
      color: AppColors.ink,
      fontWeight: FontWeight.w700,
      fontSize: 16,
      height: 1.2,
    );
  }

  TextStyle _hintStyle(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return (t.bodyLarge ?? const TextStyle()).copyWith(
      color: const Color(0xFFB9C0C8),
      fontWeight: FontWeight.w700,
      fontSize: 16,
      height: 1.2,
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final t = Theme.of(context).textTheme;

    final title = _isEdit ? 'Edit User' : 'Create New User';
    final subtitle = _isSuperAdmin
        ? 'This is the Super Admin account. It cannot be modified.'
        : _isEdit
        ? 'Update the details for this team member.'
        : 'Fill in the details to add a new team member.';

    final hintStyle = t.bodyMedium?.copyWith(color: AppColors.muted);
    final errorStyle = t.bodyMedium?.copyWith(
      color: Colors.red.shade700,
      fontWeight: FontWeight.w600,
    );

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
          tooltip: 'Back',
        ),
        title: Text('Back to Users', style: t.titleMedium),
        centerTitle: false,
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: DottedBackground()),
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 160),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.displaySmall),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  style: t.bodyLarge?.copyWith(
                    color: _isSuperAdmin
                        ? Colors.orange.shade800
                        : AppColors.muted,
                  ),
                ),

                if (_isSuperAdmin) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3D0),
                      borderRadius: BorderRadius.circular(tokens.radiusLg),
                      border: Border.all(color: const Color(0xFFFFB300)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.lock_rounded,
                          color: Color(0xFF8B6914),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'This account is protected. Name, role, and credentials cannot be changed.',
                            style: t.bodyMedium?.copyWith(
                              color: const Color(0xFF8B6914),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 28),

                Text('Role Selection', style: t.titleMedium),
                const SizedBox(height: 12),
                IgnorePointer(
                  ignoring: _isSuperAdmin,
                  child: Opacity(
                    opacity: _isSuperAdmin ? 0.5 : 1.0,
                    child: _RoleSegmented(
                      radius: tokens.radiusXl,
                      value: _role,
                      onChanged: (r) => setState(() => _role = r),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Scouts can scan and move inventory. Admins manage users and settings.',
                  style: hintStyle,
                ),
                const SizedBox(height: 26),

                Text('Full Name', style: t.titleMedium),
                const SizedBox(height: 10),
                AttentionTextField(
                  key: _nameKey,
                  controller: _nameCtrl,
                  focusNode: _nameFocus,
                  autofocus: !_isSuperAdmin,
                  hintText: 'e.g. Ahmad Mohsen',
                  centeredLayout: false,
                  textAlign: TextAlign.start,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.name,
                  allowPattern: r'[^\n]',
                  uppercase: false,
                  maxLength: 100,
                  readOnly: _isSuperAdmin,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 18,
                  ),
                  textStyle: _fieldTextStyle(context),
                  hintStyle: _hintStyle(context),
                  suffixIcon: const Icon(
                    Icons.person_rounded,
                    color: AppColors.muted,
                  ),
                  onSubmitted: (_) {
                    if (!_isEdit) {
                      _idFocus.requestFocus();
                    } else {
                      _submit();
                    }
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  _nameError ?? '2–100 characters',
                  style: _nameError != null ? errorStyle : hintStyle,
                ),

                const SizedBox(height: 18),

                Text('Scout ID', style: t.titleMedium),
                const SizedBox(height: 10),
                AttentionTextField(
                  key: _idKey,
                  controller: _idCtrl,
                  focusNode: _idFocus,
                  hintText: 'e.g. 0003',
                  centeredLayout: false,
                  textAlign: TextAlign.start,
                  textCapitalization: TextCapitalization.none,
                  keyboardType: TextInputType.number,
                  textInputAction: _isEdit
                      ? TextInputAction.done
                      : TextInputAction.next,
                  allowPattern: r'[0-9]',
                  uppercase: false,
                  maxLength: 10,
                  readOnly: _isEdit,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 18,
                  ),
                  textStyle: _fieldTextStyle(context),
                  hintStyle: _hintStyle(context),
                  suffixIcon: const Icon(
                    Icons.badge_rounded,
                    color: AppColors.muted,
                  ),
                  onSubmitted: (_) {
                    if (_isEdit) _submit();
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  _idError ??
                      (_isEdit
                          ? 'Scout ID cannot be changed after creation.'
                          : 'Auto-assigned. You can change it if needed.'),
                  style: _idError != null ? errorStyle : hintStyle,
                ),

                const SizedBox(height: 24),

                if (!_isSuperAdmin) ...[
                  if (!_isEdit) ...[
                    Text('Password', style: t.titleMedium),
                    const SizedBox(height: 10),
                    AttentionTextField(
                      key: _pwKey,
                      controller: _passwordCtrl,
                      hintText: 'Enter a password',
                      centeredLayout: false,
                      textAlign: TextAlign.start,
                      textCapitalization: TextCapitalization.none,
                      keyboardType: TextInputType.visiblePassword,
                      textInputAction: TextInputAction.done,
                      allowPattern: r'[^\n]',
                      uppercase: false,
                      maxLength: 128,
                      obscureText: _pwObscure,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 18,
                      ),
                      textStyle: _fieldTextStyle(context),
                      hintStyle: _hintStyle(context),
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setState(() => _pwObscure = !_pwObscure),
                        icon: Icon(
                          _pwObscure
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                          color: AppColors.muted,
                        ),
                        splashRadius: 22,
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _pwError ?? 'Must be at least 6 characters.',
                      style: _pwError != null ? errorStyle : hintStyle,
                    ),
                  ] else ...[
                    Text('New Password', style: t.titleMedium),
                    const SizedBox(height: 10),
                    AttentionTextField(
                      key: _newPwKey,
                      controller: _newPasswordCtrl,
                      hintText: 'Leave blank to keep current',
                      centeredLayout: false,
                      textAlign: TextAlign.start,
                      textCapitalization: TextCapitalization.none,
                      keyboardType: TextInputType.visiblePassword,
                      textInputAction: TextInputAction.next,
                      allowPattern: r'[^\n]',
                      uppercase: false,
                      maxLength: 128,
                      obscureText: _newPwObscure,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 18,
                      ),
                      textStyle: _fieldTextStyle(context),
                      hintStyle: _hintStyle(context),
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setState(() => _newPwObscure = !_newPwObscure),
                        icon: Icon(
                          _newPwObscure
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                          color: AppColors.muted,
                        ),
                        splashRadius: 22,
                      ),
                      onSubmitted: (_) {},
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _newPwError ??
                          'At least 6 characters. Leave blank to keep current password.',
                      style: _newPwError != null ? errorStyle : hintStyle,
                    ),

                    const SizedBox(height: 18),

                    Text('Confirm New Password', style: t.titleMedium),
                    const SizedBox(height: 10),
                    AttentionTextField(
                      key: _confirmPwKey,
                      controller: _confirmPasswordCtrl,
                      hintText: 'Re-type the new password',
                      centeredLayout: false,
                      textAlign: TextAlign.start,
                      textCapitalization: TextCapitalization.none,
                      keyboardType: TextInputType.visiblePassword,
                      textInputAction: TextInputAction.done,
                      allowPattern: r'[^\n]',
                      uppercase: false,
                      maxLength: 128,
                      obscureText: _confirmPwObscure,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 18,
                      ),
                      textStyle: _fieldTextStyle(context),
                      hintStyle: _hintStyle(context),
                      suffixIcon: IconButton(
                        onPressed: () => setState(
                          () => _confirmPwObscure = !_confirmPwObscure,
                        ),
                        icon: Icon(
                          _confirmPwObscure
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                          color: AppColors.muted,
                        ),
                        splashRadius: 22,
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _confirmPwError ?? 'Must match the new password above.',
                      style: _confirmPwError != null ? errorStyle : hintStyle,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _isSuperAdmin
          ? null
          : GlowingActionButton(
              label: _isEdit ? 'Save Changes' : 'Create User',
              icon: const Icon(Icons.check_rounded),
              onPressed: _saving ? null : _submit,
              loading: _saving,
              respectKeyboardInset: false,
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Role segmented control
// ═══════════════════════════════════════════════════════════════════════════

class _RoleSegmented extends StatelessWidget {
  const _RoleSegmented({
    required this.radius,
    required this.value,
    required this.onChanged,
  });

  final double radius;
  final _UserRole value;
  final ValueChanged<_UserRole> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final t = Theme.of(context).textTheme;

    Widget option(_UserRole role) {
      final selected = value == role;

      final bg = selected ? Colors.white : Colors.white.withValues(alpha: 0);

      final shadow = tokens.cardShadow
          .map(
            (s) => selected
                ? s
                : BoxShadow(
                    color: s.color.withValues(alpha: 0),
                    blurRadius: 0,
                    spreadRadius: 0,
                    offset: s.offset,
                  ),
          )
          .toList();

      return Expanded(
        child: InkWell(
          onTap: () => onChanged(role),
          splashFactory: NoSplash.splashFactory,
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            height: 62,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(radius - 6),
              boxShadow: shadow,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  role.icon,
                  size: 20,
                  color: selected ? AppColors.ink : AppColors.muted,
                ),
                const SizedBox(width: 10),
                Text(
                  role.label,
                  style: t.titleMedium?.copyWith(
                    color: selected ? AppColors.ink : AppColors.muted,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFFE9EDF2),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          option(_UserRole.scout),
          const SizedBox(width: 8),
          option(_UserRole.admin),
        ],
      ),
    );
  }
}
