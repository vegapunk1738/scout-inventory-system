import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:scout_stock/domain/models/managed_user.dart' show kSuperAdminScoutId;
import 'package:scout_stock/presentation/widgets/dotted_background.dart';
import 'package:scout_stock/presentation/widgets/glowing_action_button.dart';
import 'package:scout_stock/theme/app_theme.dart';

import '../../widgets/attention_text_field_widget.dart';

/// Navigation args for editing an existing user.
/// For create mode, push the route with no extra.
class UserUpsertArgs {
  const UserUpsertArgs({
    required this.scoutId,
    required this.displayName,
    required this.role,
  });

  final String scoutId;
  final String displayName;

  /// 'scout' | 'admin'
  final String role;
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
  const UserUpsertPage({super.key, this.editArgs});

  final UserUpsertArgs? editArgs;

  @override
  State<UserUpsertPage> createState() => _UserUpsertPageState();
}

class _UserUpsertPageState extends State<UserUpsertPage> {
  final _nameCtrl = TextEditingController();
  final _idCtrl = TextEditingController();

  // Create mode password
  final _passwordCtrl = TextEditingController();

  // Edit mode password
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

  bool _pwTouched = false;
  bool _pwObscure = true;
  bool _newPwObscure = true;
  bool _confirmPwObscure = true;

  bool get _isEdit => widget.editArgs != null;

  /// Derived from the scout_id constant — no extra arg needed.
  bool get _isSuperAdmin =>
      _isEdit && widget.editArgs!.scoutId == kSuperAdminScoutId;

  @override
  void initState() {
    super.initState();

    final args = widget.editArgs;
    _role = _roleFromApi(args?.role ?? 'scout');

    if (args != null) {
      _nameCtrl.text = args.displayName;
      _idCtrl.text = args.scoutId;
    }

    _seedCreatePassword();

    _idCtrl.addListener(() {
      if (!_isEdit) _seedCreatePassword();
    });

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

  void _seedCreatePassword() {
    if (_isEdit) return;
    if (_pwTouched) return;

    final id = _idCtrl.text.trim();
    if (id.isEmpty) {
      _passwordCtrl.text = '';
      return;
    }

    _passwordCtrl.text = 'Temp-$id!';
  }

  String _generateScoutId() {
    final r = math.Random();
    return (1000 + r.nextInt(9000)).toString();
  }

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

  Future<void> _submit() async {
    if (_saving || _isSuperAdmin) return;

    final name = _nameCtrl.text.trim();
    final rawId = _idCtrl.text.trim();

    if (name.isEmpty) {
      _nameFocus.requestFocus();
      await _nameKey.currentState?.triggerInvalid();
      return;
    }

    String scoutId = rawId;
    if (!_isEdit && scoutId.isEmpty) {
      scoutId = _generateScoutId();
      _idCtrl.text = scoutId;
      _seedCreatePassword();
    }

    if (scoutId.isEmpty) {
      _idFocus.requestFocus();
      await _idKey.currentState?.triggerInvalid();
      return;
    }

    // Create payload — pop result to caller (UsersPage calls the API).
    if (!_isEdit) {
      String pw = _passwordCtrl.text;
      if (pw.trim().isEmpty) {
        pw = 'Temp-$scoutId!';
        _passwordCtrl.text = pw;
      }

      setState(() => _saving = true);
      FocusScope.of(context).unfocus();

      context.pop<Map<String, dynamic>>({
        'displayName': name,
        'scoutId': scoutId,
        'role': _role.apiValue,
        'password': pw,
      });
      return;
    }

    // Edit payload.
    final newPw = _newPasswordCtrl.text;
    final confirm = _confirmPasswordCtrl.text;

    final wantsPwChange = newPw.trim().isNotEmpty || confirm.trim().isNotEmpty;
    if (wantsPwChange && newPw != confirm) {
      await _newPwKey.currentState?.triggerInvalid();
      await _confirmPwKey.currentState?.triggerInvalid(haptics: false);
      return;
    }

    if (wantsPwChange && newPw.trim().length < 6) {
      await _newPwKey.currentState?.triggerInvalid();
      return;
    }

    setState(() => _saving = true);
    FocusScope.of(context).unfocus();

    context.pop<Map<String, dynamic>>({
      'displayName': name,
      'scoutId': scoutId,
      'role': _role.apiValue,
      if (wantsPwChange && newPw.trim().isNotEmpty) 'newPassword': newPw,
    });
  }

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

                // ── Super Admin banner ─────────────────────────────────
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
                        const Icon(Icons.lock_rounded,
                            color: Color(0xFF8B6914)),
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

                // ── Role ───────────────────────────────────────────────
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
                  style: t.bodyMedium?.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 26),

                // ── Full Name ──────────────────────────────────────────
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
                  maxLength: 48,
                  readOnly: _isSuperAdmin,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 18,
                  ),
                  textStyle: _fieldTextStyle(context),
                  hintStyle: _hintStyle(context),
                  suffixIcon: const Icon(Icons.person_rounded,
                      color: AppColors.muted),
                  onSubmitted: (_) => _idFocus.requestFocus(),
                ),

                const SizedBox(height: 18),

                // ── Scout ID ───────────────────────────────────────────
                Text('Scout ID', style: t.titleMedium),
                const SizedBox(height: 10),
                AttentionTextField(
                  key: _idKey,
                  controller: _idCtrl,
                  focusNode: _idFocus,
                  hintText: 'e.g. 1287',
                  centeredLayout: false,
                  textAlign: TextAlign.start,
                  textCapitalization: TextCapitalization.none,
                  keyboardType: TextInputType.number,
                  textInputAction:
                      _isEdit ? TextInputAction.done : TextInputAction.next,
                  allowPattern: r'[0-9]',
                  uppercase: false,
                  maxLength: 10,
                  readOnly: _isEdit, // scout_id is immutable after creation.
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 18,
                  ),
                  textStyle: _fieldTextStyle(context),
                  hintStyle: _hintStyle(context),
                  suffixIcon: const Icon(Icons.badge_rounded,
                      color: AppColors.muted),
                  onSubmitted: (_) {
                    if (_isEdit) _submit();
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  _isEdit
                      ? 'ID is the primary identifier and can\'t be changed here.'
                      : 'Auto-generated if left blank.',
                  style: t.bodyMedium?.copyWith(color: AppColors.muted),
                ),

                const SizedBox(height: 24),

                // ── Password fields (hidden for super admin) ───────────
                if (!_isSuperAdmin) ...[
                  if (!_isEdit) ...[
                    Text('Password', style: t.titleMedium),
                    const SizedBox(height: 10),
                    AttentionTextField(
                      key: _pwKey,
                      controller: _passwordCtrl,
                      hintText: 'Temp-1287!',
                      centeredLayout: false,
                      textAlign: TextAlign.start,
                      textCapitalization: TextCapitalization.none,
                      keyboardType: TextInputType.visiblePassword,
                      textInputAction: TextInputAction.done,
                      allowPattern: r'[^\n]',
                      uppercase: false,
                      maxLength: 64,
                      obscureText: _pwObscure,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 18,
                      ),
                      textStyle: _fieldTextStyle(context),
                      hintStyle: _hintStyle(context),
                      onChanged: (_) => _pwTouched = true,
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
                    const SizedBox(height: 8),
                    Text(
                      'Default password is Temp-{ID}!. You can change it before creating.',
                      style:
                          t.bodyMedium?.copyWith(color: AppColors.muted),
                    ),
                  ] else ...[
                    Text('New Password', style: t.titleMedium),
                    const SizedBox(height: 10),
                    AttentionTextField(
                      key: _newPwKey,
                      controller: _newPasswordCtrl,
                      hintText: 'Leave blank to keep current password',
                      centeredLayout: false,
                      textAlign: TextAlign.start,
                      textCapitalization: TextCapitalization.none,
                      keyboardType: TextInputType.visiblePassword,
                      textInputAction: TextInputAction.next,
                      allowPattern: r'[^\n]',
                      uppercase: false,
                      maxLength: 64,
                      obscureText: _newPwObscure,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 18,
                      ),
                      textStyle: _fieldTextStyle(context),
                      hintStyle: _hintStyle(context),
                      suffixIcon: IconButton(
                        onPressed: () => setState(
                            () => _newPwObscure = !_newPwObscure),
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
                      maxLength: 64,
                      obscureText: _confirmPwObscure,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 18,
                      ),
                      textStyle: _fieldTextStyle(context),
                      hintStyle: _hintStyle(context),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() =>
                            _confirmPwObscure = !_confirmPwObscure),
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
                    const SizedBox(height: 8),
                    Text(
                      'Leave both password fields empty to keep the current password.',
                      style:
                          t.bodyMedium?.copyWith(color: AppColors.muted),
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

      // Use transparent *white* (not Colors.transparent which is
      // transparent *black*) so the lerp stays white → invisible white
      // instead of white → grey → invisible.
      final bg = selected
          ? Colors.white
          : Colors.white.withValues(alpha: 0);

      // Keep the same number of shadows so AnimatedContainer can
      // smoothly lerp instead of jumping between list lengths.
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