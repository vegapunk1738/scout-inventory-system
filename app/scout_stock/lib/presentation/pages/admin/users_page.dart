import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:scout_stock/data/api/api_client.dart';
import 'package:scout_stock/domain/enums/user_role.dart';
import 'package:scout_stock/domain/models/managed_user.dart';
import 'package:scout_stock/presentation/pages/admin/user_upsert_page.dart';
import 'package:scout_stock/presentation/widgets/app_toast.dart';
import 'package:scout_stock/presentation/widgets/dotted_background.dart';
import 'package:scout_stock/router/app_routes.dart';
import 'package:scout_stock/state/providers/auth_providers.dart';
import 'package:scout_stock/state/providers/users_provider.dart';
import 'package:scout_stock/theme/app_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Users Admin Page — connected to backend via usersProvider
// ═══════════════════════════════════════════════════════════════════════════

class UsersAdminPage extends ConsumerStatefulWidget {
  const UsersAdminPage({super.key});

  @override
  ConsumerState<UsersAdminPage> createState() => _UsersAdminPageState();
}

class _UsersAdminPageState extends ConsumerState<UsersAdminPage> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  final Map<String, ValueNotifier<bool>> _expanded = {};

  ValueNotifier<bool> _exp(String id) =>
      _expanded.putIfAbsent(id, () => ValueNotifier<bool>(false));

  @override
  void dispose() {
    _searchCtrl.dispose();
    for (final n in _expanded.values) {
      n.dispose();
    }
    _expanded.clear();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  List<ManagedUser> _filterAndSort(List<ManagedUser> all) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all
        .where(
          (u) =>
              u.fullName.toLowerCase().contains(q) ||
              u.scoutId.toLowerCase().contains(q),
        )
        .toList(growable: false);
  }

  /// Shows error toasts. If the error has field-level validation details,
  /// fires one toast per field so each is individually readable and
  /// dismissible. Otherwise shows a single toast.
  void _showError(Object e, {required String action}) {
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
        title: action,
        subtitle: msg,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────

  /// ---------------------------------------------------------------
  /// FIX: The create/edit callbacks now perform the API call
  /// *before* the upsert page pops, via [UpsertCallbacks]. This
  /// eliminates the race between GoRouter's pop-result delivery and
  /// widget lifecycle. The upsert page calls the callback, awaits
  /// the result, and only then pops — so the API call is guaranteed
  /// to fire regardless of the parent's mounted state.
  /// ---------------------------------------------------------------

  Future<void> _onAdd() async {
    String nextId = '';
    try {
      nextId = await ref.read(usersProvider.notifier).fetchNextScoutId();
    } catch (_) {}
    if (!mounted) return;

    // Store ref-based notifier before the async gap so we don't depend
    // on `ref` being valid after the push returns.
    final notifier = ref.read(usersProvider.notifier);

    await context.push<void>(
      AppRoutes.adminUserCreate,
      extra: CreateUserArgs(
        nextScoutId: nextId,
        onSubmit: (result) async {
          final scoutId = (result['scoutId'] ?? '').toString();
          final fullName = (result['displayName'] ?? '').toString();
          final role = (result['role'] ?? 'scout').toString();
          final password = (result['password'] ?? '').toString();

          final created = await notifier.createUser(
            scoutId: scoutId,
            fullName: fullName,
            password: password,
            role: role,
          );

          // Toast is fire-and-forget; safe to check mounted here because
          // the upsert page is still on screen (it hasn't popped yet).
          if (mounted) {
            final roleLabel = role == 'admin' ? 'Admin' : 'Scout';
            AppToast.of(context).show(
              AppToastData.success(
                title: 'Created: $fullName',
                subtitle: '$roleLabel  ·  ID #${created.scoutId}',
              ),
            );
          }
        },
      ),
    );
  }

  Future<void> _onEdit(ManagedUser user) async {
    if (user.isSuperAdmin) return;

    final notifier = ref.read(usersProvider.notifier);
    final authNotifier = ref.read(authControllerProvider.notifier);

    await context.push<void>(
      AppRoutes.adminUserEdit(user.scoutId),
      extra: UserUpsertArgs(
        scoutId: user.scoutId,
        displayName: user.fullName,
        role: user.role.toJson(),
        onSubmit: (result) async {
          final newName = result['displayName'] as String?;
          final newRole = result['role'] as String?;
          final newPassword = result['newPassword'] as String?;

          final nameChanged = newName != null && newName != user.fullName;
          final roleChanged = newRole != null && newRole != user.role.toJson();
          final pwChanged =
              newPassword != null && newPassword.trim().isNotEmpty;

          if (!nameChanged && !roleChanged && !pwChanged) return;

          await notifier.updateUser(
            user.scoutId,
            fullName: nameChanged ? newName : null,
            role: roleChanged ? newRole : null,
            password: pwChanged ? newPassword : null,
          );

          // Build toast info.
          final changes = <String>[];
          if (nameChanged) changes.add('${user.fullName} → $newName');
          if (roleChanged) {
            final oldLabel = user.role.isAdmin ? 'Admin' : 'Scout';
            final newLabel = newRole == 'admin' ? 'Admin' : 'Scout';
            changes.add('$oldLabel → $newLabel');
          }
          if (pwChanged) changes.add('Password reset');

          final displayName = nameChanged ? newName : user.fullName;

          // Refresh JWT if the admin edited themselves.
          final currentUser = ref.read(currentUserProvider);
          final editedSelf =
              currentUser != null && currentUser.scoutId == user.scoutId;
          if (editedSelf && (roleChanged || nameChanged)) {
            try {
              await authNotifier.refreshSession();
            } catch (_) {}
          }

          if (mounted) {
            AppToast.of(context).show(
              AppToastData.success(
                title: 'Updated: $displayName',
                subtitle: changes.join('  ·  '),
              ),
            );
          }
        },
      ),
    );
  }

  Future<void> _onDelete(ManagedUser user) async {
    if (user.isSuperAdmin) return;

    final currentUser = ref.read(currentUserProvider);
    final isDeletingSelf =
        currentUser != null && currentUser.scoutId == user.scoutId;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isDeletingSelf
              ? 'Delete your own account?'
              : 'Delete ${user.fullName}?',
        ),
        content: Text(
          isDeletingSelf
              ? 'You will be logged out immediately and will not be able to sign back in.'
              : 'This action cannot be undone. The user will lose access immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isDeletingSelf ? 'Delete & Log Out' : 'Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(usersProvider.notifier).deleteUser(user.scoutId);

      if (isDeletingSelf) {
        await ref.read(authControllerProvider.notifier).logout();
        return;
      }

      if (!mounted) return;
      final roleLabel = user.role.isAdmin ? 'Admin' : 'Scout';
      AppToast.of(context).show(
        AppToastData.success(
          title: 'Deleted: ${user.fullName}',
          subtitle: '$roleLabel #${user.scoutId} deleted from the team',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showError(e, action: 'Could not delete ${user.fullName}');
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final emojiBase = GoogleFonts.notoColorEmoji(height: 1);
    final mediaTop = MediaQuery.of(context).padding.top;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    const navHeight = 78.0;
    const navPad = 12.0;
    final bottomFootprint = safeBottom + navHeight + navPad + 10;

    final usersAsync = ref.watch(usersProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(child: DottedBackground()),
          SafeArea(
            top: false,
            child: usersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),

              error: (err, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('😵', style: emojiBase.copyWith(fontSize: 54)),
                      const SizedBox(height: 12),
                      Text(
                        'Failed to load users',
                        style: t.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        err is ApiException
                            ? err.displayMessage
                            : 'Something went wrong. Please try again.',
                        style: t.bodyLarge?.copyWith(color: AppColors.muted),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      OutlinedButton.icon(
                        onPressed: () => ref.invalidate(usersProvider),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),

              data: (allUsers) {
                final items = _filterAndSort(allUsers);
                final scoutCount = allUsers
                    .where((u) => !u.role.isAdmin)
                    .length;
                final adminCount = allUsers.where((u) => u.role.isAdmin).length;
                final isEmpty = items.isEmpty;

                return RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () async {
                    ref.invalidate(usersProvider);
                    await ref.read(usersProvider.future);
                  },
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    cacheExtent: 900,
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            20,
                            mediaTop + 10,
                            20,
                            0,
                          ),
                          child: _UsersHeader(
                            onAdd: _onAdd,
                            onRefresh: () async {
                              ref.invalidate(usersProvider);
                              await ref.read(usersProvider.future);
                            },
                          ),
                        ),
                      ),

                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _StickyHeaderDelegate(
                          height: 70,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                            child: _SearchCard(
                              controller: _searchCtrl,
                              hintText: 'Search by name or ID…',
                              onChanged: (v) => setState(() => _query = v),
                            ),
                          ),
                        ),
                      ),

                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: _StatsRow(
                            scoutCount: scoutCount,
                            adminCount: adminCount,
                          ),
                        ),
                      ),

                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'ALL USERS',
                                  style: t.labelMedium?.copyWith(
                                    color: AppColors.muted,
                                  ),
                                ),
                              ),
                              Text(
                                'ROLE',
                                style: t.labelMedium?.copyWith(
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      if (isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 40, 20, 0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '🫂',
                                    style: emojiBase.copyWith(fontSize: 54),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'No users found',
                                    style: t.titleLarge,
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Try a different name or Scout ID',
                                    style: t.bodyLarge?.copyWith(
                                      color: AppColors.muted,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final user = items[index];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: RepaintBoundary(
                                    child: _ExpandableMemberCard(
                                      user: user,
                                      expanded: _exp(user.scoutId),
                                      radiusXl: tokens.radiusXl,
                                      onEdit: () => _onEdit(user),
                                      onDelete: () => _onDelete(user),
                                    ),
                                  ),
                                );
                              },
                              childCount: items.length,
                              addAutomaticKeepAlives: false,
                              addRepaintBoundaries: true,
                              addSemanticIndexes: false,
                            ),
                          ),
                        ),

                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                          child: Text(
                            '${allUsers.length} Total Users',
                            style: t.titleMedium?.copyWith(
                              color: AppColors.muted,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),

                      SliverToBoxAdapter(
                        child: SizedBox(height: bottomFootprint),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Private widgets
// ═══════════════════════════════════════════════════════════════════════════

class _UsersHeader extends StatefulWidget {
  const _UsersHeader({required this.onAdd, required this.onRefresh});

  final VoidCallback onAdd;
  final Future<void> Function() onRefresh;

  @override
  State<_UsersHeader> createState() => _UsersHeaderState();
}

class _UsersHeaderState extends State<_UsersHeader> {
  bool _refreshing = false;

  Future<void> _handleRefresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<AppTokens>()!;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Team Members', style: t.titleLarge),
              const SizedBox(height: 4),
              Text(
                'ADMIN VIEW',
                style: t.labelMedium?.copyWith(
                  color: AppColors.primary,
                  letterSpacing: 1.8,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 42,
          height: 42,
          child: _refreshing
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : IconButton(
                  onPressed: _handleRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                  color: AppColors.muted,
                  splashRadius: 28,
                  tooltip: 'Refresh',
                  style: IconButton.styleFrom(
                    splashFactory: NoSplash.splashFactory,
                    hoverColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                  ),
                ),
        ),
        const SizedBox(width: 6),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
            boxShadow: tokens.glowShadow,
          ),
          child: SizedBox(
            width: 42,
            height: 42,
            child: IconButton(
              onPressed: widget.onAdd,
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              splashRadius: 28,
              tooltip: 'Add user',
              style: IconButton.styleFrom(
                splashFactory: NoSplash.splashFactory,
                hoverColor: Colors.transparent,
                highlightColor: Colors.transparent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.scoutCount, required this.adminCount});

  final int scoutCount;
  final int adminCount;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final t = Theme.of(context).textTheme;

    Widget card({
      required String numberText,
      required String label,
      required Color bg,
      required Color numberColor,
      required BorderSide? border,
    }) {
      return Container(
        height: 88,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(tokens.radiusXl),
          border: border == null ? null : Border.fromBorderSide(border),
          boxShadow: tokens.cardShadow,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Column(
          children: [
            Text(
              numberText,
              style: t.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: numberColor,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(label, style: t.labelMedium?.copyWith(color: AppColors.muted)),
          ],
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: card(
            numberText: scoutCount.toString().padLeft(2, '0'),
            label: 'ACTIVE SCOUTS',
            bg: Colors.white,
            numberColor: AppColors.ink,
            border: const BorderSide(color: AppColors.outline),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: card(
            numberText: adminCount.toString().padLeft(2, '0'),
            label: 'ADMINS',
            bg: AppColors.successBg,
            numberColor: AppColors.primary,
            border: BorderSide(
              color: AppColors.primary.withValues(alpha: 0.12),
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchCard extends StatelessWidget {
  const _SearchCard({
    required this.controller,
    required this.onChanged,
    required this.hintText,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<AppTokens>()!;

    return Theme(
      data: Theme.of(context).copyWith(
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(tokens.radiusLg),
          boxShadow: tokens.cardShadow,
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            const Icon(Icons.search_rounded, color: AppColors.muted),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                style: t.bodyLarge?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.only(right: 16),
                  hintText: hintText,
                  hintStyle: t.bodyLarge?.copyWith(
                    color: const Color(0xFFB9C0C8),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (controller.text.isNotEmpty)
              IconButton(
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
                icon: const Icon(Icons.close_rounded),
                splashRadius: 20,
                tooltip: 'Clear',
                style: IconButton.styleFrom(
                  splashFactory: NoSplash.splashFactory,
                  hoverColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                ),
              ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Expandable member card — Edit + Delete (red)
// ═══════════════════════════════════════════════════════════════════════════

class _ExpandableMemberCard extends StatelessWidget {
  const _ExpandableMemberCard({
    required this.user,
    required this.expanded,
    required this.radiusXl,
    required this.onEdit,
    required this.onDelete,
  });

  final ManagedUser user;
  final ValueNotifier<bool> expanded;
  final double radiusXl;

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    final isAdmin = user.role.isAdmin;
    final isSuperAdmin = user.isSuperAdmin;
    final initials = _initials(user.fullName);

    final nameStyle = t.titleMedium?.copyWith(
      fontSize: 17,
      fontWeight: FontWeight.w800,
      color: AppColors.ink,
    );

    final subtitleStyle = t.bodyMedium?.copyWith(
      color: AppColors.muted,
      fontWeight: FontWeight.w600,
    );

    final stripColor = isSuperAdmin
        ? const Color(0xFFFFB300)
        : isAdmin
        ? AppColors.primary
        : const Color(0xFFE1E6ED);

    return ValueListenableBuilder<bool>(
      valueListenable: expanded,
      builder: (context, isOpen, _) {
        return Material(
          color: Colors.white,
          elevation: 2,
          shadowColor: const Color(0x14000000),
          borderRadius: BorderRadius.circular(radiusXl),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => expanded.value = !expanded.value,
            splashFactory: NoSplash.splashFactory,
            hoverColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(width: 6, height: 84, color: stripColor),
                    const SizedBox(width: 14),
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: AppColors.background,
                          child: Text(
                            initials,
                            style: t.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (isSuperAdmin)
                          const Positioned(
                            right: -4,
                            bottom: -2,
                            child: Icon(
                              Icons.shield_rounded,
                              size: 16,
                              color: Color(0xFFFFB300),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.fullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: nameStyle,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'ID: #${user.scoutId}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: subtitleStyle,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _RoleChip(
                            role: user.role,
                            isSuperAdmin: isSuperAdmin,
                          ),
                          const SizedBox(height: 8),
                          Icon(
                            isOpen
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            color: AppColors.muted,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                AnimatedCrossFade(
                  crossFadeState: isOpen
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 160),
                  firstChild: const SizedBox.shrink(),
                  secondChild: isSuperAdmin
                      ? const _ProtectedDetailsBlock()
                      : _MemberDetailsBlock(onEdit: onEdit, onDelete: onDelete),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProtectedDetailsBlock extends StatelessWidget {
  const _ProtectedDetailsBlock();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.outline)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_rounded, size: 18, color: AppColors.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Super Admin — this account cannot be edited or deleted.',
              style: t.bodyMedium?.copyWith(
                color: AppColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberDetailsBlock extends StatelessWidget {
  const _MemberDetailsBlock({required this.onEdit, required this.onDelete});

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.outline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_rounded),
              label: const Text('Edit'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                textStyle: t.titleMedium?.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Delete'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade700,
                side: BorderSide(color: Colors.red.shade200),
                minimumSize: const Size.fromHeight(46),
                textStyle: t.titleMedium?.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role, this.isSuperAdmin = false});
  final UserRole role;
  final bool isSuperAdmin;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final isAdmin = role.isAdmin;

    final bg = isSuperAdmin
        ? const Color(0xFFFFF3D0)
        : isAdmin
        ? AppColors.primary
        : Colors.white;
    final fg = isSuperAdmin
        ? const Color(0xFF8B6914)
        : isAdmin
        ? Colors.white
        : AppColors.muted;
    final label = isSuperAdmin ? 'OWNER' : (isAdmin ? 'ADMIN' : 'SCOUT');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: isSuperAdmin
            ? Border.all(color: const Color(0xFFFFB300))
            : isAdmin
            ? null
            : Border.all(color: AppColors.outline),
      ),
      child: Text(
        label,
        style: t.labelMedium?.copyWith(color: fg, letterSpacing: 1.4),
      ),
    );
  }
}

class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  _StickyHeaderDelegate({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _StickyHeaderDelegate oldDelegate) {
    return oldDelegate.height != height || oldDelegate.child != child;
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    return parts.first.characters.take(2).toString().toUpperCase();
  }
  return '${parts.first.characters.first}${parts.last.characters.first}'
      .toUpperCase();
}
