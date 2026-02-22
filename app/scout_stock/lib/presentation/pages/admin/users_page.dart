import 'package:flutter/material.dart';
import 'package:scout_stock/presentation/widgets/dotted_background.dart';
import 'package:scout_stock/theme/app_theme.dart';

enum MemberRole { scout, admin }

class TeamMember {
  const TeamMember({required this.id, required this.name, required this.role});

  final String id; // digits only, display as #id
  final String name;
  final MemberRole role;
}

class UsersAdminPage extends StatefulWidget {
  const UsersAdminPage({super.key});

  @override
  State<UsersAdminPage> createState() => _UsersAdminPageState();
}

class _UsersAdminPageState extends State<UsersAdminPage> {
  final _searchCtrl = TextEditingController();
  String _query = "";

  late final List<TeamMember> _seed = (List<TeamMember>.of(_mockMembers())
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));

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

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final mediaTop = MediaQuery.of(context).padding.top;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    final q = _query.trim().toLowerCase();
    final items = q.isEmpty
        ? _seed
        : _seed
              .where(
                (m) =>
                    m.name.toLowerCase().contains(q) ||
                    m.id.toLowerCase().contains(q),
              )
              .toList(growable: false);

    final scoutCount = _seed.where((m) => m.role == MemberRole.scout).length;
    final adminCount = _seed.where((m) => m.role == MemberRole.admin).length;

    final isEmpty = items.isEmpty;

    // Match AdminShell bottom nav footprint (height 78 + padding 12)
    const navHeight = 78.0;
    const navPad = 12.0;
    final bottomFootprint = safeBottom + navHeight + navPad + 10;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(child: DottedBackground()),
          SafeArea(
            top: false,
            child: CustomScrollView(
              cacheExtent: 900,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, mediaTop + 10, 20, 0),
                    child: _UsersHeader(
                      onAdd: () => _showSnack("Create user coming soon"),
                    ),
                  ),
                ),

                // ✅ FIX #1: Sticky search with transparent header background
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
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 40, 20, 0),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.group_off_rounded,
                              size: 44,
                              color: AppColors.muted.withValues(alpha: 0.75),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'No users found',
                              style: t.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Try a different name or ID.',
                              style: t.bodyMedium,
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
                          final m = items[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: RepaintBoundary(
                              child: _ExpandableMemberCard(
                                member: m,
                                expanded: _exp(m.id),
                                radiusXl: tokens.radiusXl,
                                onEdit: () =>
                                    _showSnack("Edit profile coming soon"),
                                onPromoteDemote: () => _showSnack(
                                  m.role == MemberRole.scout
                                      ? "Promote coming soon"
                                      : "Demote coming soon",
                                ),
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
                      '${_seed.length} Total Users',
                      style: t.titleMedium?.copyWith(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),

                // ✅ FIX #3: tighter bottom spacer (matches nav footprint)
                SliverToBoxAdapter(child: SizedBox(height: bottomFootprint)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UsersHeader extends StatelessWidget {
  const _UsersHeader({required this.onAdd});

  final VoidCallback onAdd;

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
              Text('Team Members', style: t.headlineMedium),
              const SizedBox(height: 4),
              Text(
                'SCOUT OPS • ADMIN VIEW',
                style: t.labelMedium?.copyWith(
                  color: AppColors.primary,
                  letterSpacing: 1.8,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
            boxShadow: tokens.glowShadow,
          ),
          child: SizedBox(
            width: 56,
            height: 56,
            child: IconButton(
              onPressed: onAdd,
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

class _ExpandableMemberCard extends StatelessWidget {
  const _ExpandableMemberCard({
    required this.member,
    required this.expanded,
    required this.radiusXl,
    required this.onEdit,
    required this.onPromoteDemote,
  });

  final TeamMember member;
  final ValueNotifier<bool> expanded;
  final double radiusXl;

  final VoidCallback onEdit;
  final VoidCallback onPromoteDemote;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    final isAdmin = member.role == MemberRole.admin;
    final initials = _initials(member.name);

    final nameStyle = t.titleMedium?.copyWith(
      fontSize: 17,
      fontWeight: FontWeight.w800,
      color: AppColors.ink,
    );

    final subtitleStyle = t.bodyMedium?.copyWith(
      color: AppColors.muted,
      fontWeight: FontWeight.w600,
    );

    final stripColor = isAdmin ? AppColors.primary : const Color(0xFFE1E6ED);

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
                              member.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: nameStyle,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "ID: #${member.id}",
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
                          _RoleChip(role: member.role),
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
                  // ✅ FIX #2: details block white so buttons are clear
                  secondChild: _MemberDetailsBlock(
                    isAdmin: isAdmin,
                    onEdit: onEdit,
                    onPromoteDemote: onPromoteDemote,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MemberDetailsBlock extends StatelessWidget {
  const _MemberDetailsBlock({
    required this.isAdmin,
    required this.onEdit,
    required this.onPromoteDemote,
  });

  final bool isAdmin;
  final VoidCallback onEdit;
  final VoidCallback onPromoteDemote;

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
              onPressed: onPromoteDemote,
              icon: Icon(
                isAdmin
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
              ),
              label: Text(isAdmin ? 'Demote' : 'Promote'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
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
  const _RoleChip({required this.role});
  final MemberRole role;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final isAdmin = role == MemberRole.admin;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isAdmin ? AppColors.primary : Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: isAdmin ? null : Border.all(color: AppColors.outline),
      ),
      child: Text(
        isAdmin ? 'ADMIN' : 'SCOUT',
        style: t.labelMedium?.copyWith(
          color: isAdmin ? Colors.white : AppColors.muted,
          letterSpacing: 1.4,
        ),
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
  final parts = name.trim().split(RegExp(r"\s+"));
  if (parts.isEmpty) return "?";
  if (parts.length == 1) {
    return parts.first.characters.take(2).toString().toUpperCase();
  }
  return "${parts.first.characters.first}${parts.last.characters.first}"
      .toUpperCase();
}

List<TeamMember> _mockMembers() {
  return const <TeamMember>[
    TeamMember(id: '8821', name: 'Sarah Jenkins', role: MemberRole.admin),
    TeamMember(id: '9942', name: 'Mike Ross', role: MemberRole.scout),
    TeamMember(id: '9102', name: 'David Chen', role: MemberRole.scout),
    TeamMember(id: '7731', name: 'Alex Liu', role: MemberRole.scout),
    TeamMember(id: '3321', name: 'Emily Rose', role: MemberRole.scout),
    TeamMember(id: '1044', name: 'Nora Khalil', role: MemberRole.scout),
    TeamMember(id: '1180', name: 'Omar Farid', role: MemberRole.scout),
    TeamMember(id: '1207', name: 'Maya Haddad', role: MemberRole.scout),
    TeamMember(id: '1312', name: 'Karim Nassar', role: MemberRole.scout),
    TeamMember(id: '1455', name: 'Layla Saad', role: MemberRole.scout),
    TeamMember(id: '1566', name: 'Hadi Mansour', role: MemberRole.scout),
    TeamMember(id: '1601', name: 'Jana Youssef', role: MemberRole.scout),
    TeamMember(id: '1718', name: 'Fadi Salim', role: MemberRole.scout),
    TeamMember(id: '1833', name: 'Tala Aoun', role: MemberRole.scout),
    TeamMember(id: '1950', name: 'Rami Habib', role: MemberRole.scout),
    TeamMember(id: '2039', name: 'Mariam Daher', role: MemberRole.scout),
    TeamMember(id: '2144', name: 'Tony Ziad', role: MemberRole.scout),
    TeamMember(id: '2277', name: 'Celine Rouhana', role: MemberRole.scout),
    TeamMember(id: '2388', name: 'Elias Jabbour', role: MemberRole.scout),
    TeamMember(id: '2499', name: 'Hala Fares', role: MemberRole.scout),
    TeamMember(id: '2551', name: 'Ziad Bou Saab', role: MemberRole.admin),
    TeamMember(id: '2610', name: 'Rita Nakhle', role: MemberRole.scout),
    TeamMember(id: '2745', name: 'Samir Douaihy', role: MemberRole.scout),
    TeamMember(id: '2871', name: 'Nada Chahine', role: MemberRole.scout),
    TeamMember(id: '2924', name: 'Issa Melki', role: MemberRole.scout),
    TeamMember(id: '3090', name: 'Nabil Gerges', role: MemberRole.scout),
    TeamMember(id: '3166', name: 'Admin Ops', role: MemberRole.admin),
  ];
}
