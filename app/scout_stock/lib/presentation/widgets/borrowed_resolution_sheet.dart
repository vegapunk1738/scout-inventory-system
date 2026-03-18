import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:scout_stock/domain/models/bucket.dart';
import 'package:scout_stock/presentation/widgets/hold_icon_button.dart';
import 'package:scout_stock/theme/app_theme.dart';

// ═════════════════════════════════════════════════════════════════════════════
// Data classes
// ═════════════════════════════════════════════════════════════════════════════

class _BorrowerDraft {
  _BorrowerDraft({
    required this.userId,
    required this.fullName,
    required this.scoutId,
    required this.maxContribution,
    required int initialAssigned,
  }) : returned = initialAssigned,
       lost = 0,
       broken = 0;

  final String userId;
  final String fullName;
  final String scoutId;
  final int maxContribution;

  int returned;
  int lost;
  int broken;

  int get assigned => returned + lost + broken;

  List<Map<String, dynamic>> toResolutions() {
    final list = <Map<String, dynamic>>[];
    if (returned > 0) {
      list.add({'user_id': userId, 'quantity': returned, 'status': 'returned'});
    }
    if (lost > 0) {
      list.add({'user_id': userId, 'quantity': lost, 'status': 'lost'});
    }
    if (broken > 0) {
      list.add({'user_id': userId, 'quantity': broken, 'status': 'damaged'});
    }
    return list;
  }
}

class ResolutionResult {
  const ResolutionResult({required this.resolutions});
  final List<Map<String, dynamic>> resolutions;
}

// ═════════════════════════════════════════════════════════════════════════════
// Bulk data classes
// ═════════════════════════════════════════════════════════════════════════════

class BulkResolutionEntry {
  const BulkResolutionEntry({
    required this.itemId,
    required this.itemName,
    required this.itemEmoji,
    required this.borrowers,
    this.bucketId,
    this.resolveCount,
  });

  final String itemId;
  final String itemName;
  final String itemEmoji;
  final List<BorrowerInfo> borrowers;

  /// The bucket this item belongs to. Needed when resolving items
  /// across multiple buckets (e.g. user deletion).
  final String? bucketId;

  final int? resolveCount;
}

class BulkResolutionResult {
  const BulkResolutionResult({required this.resolutionsByItemId});
  final Map<String, List<Map<String, dynamic>>> resolutionsByItemId;
}

// ═════════════════════════════════════════════════════════════════════════════
// Public entry point — single item
// ═════════════════════════════════════════════════════════════════════════════

Future<ResolutionResult?> showBorrowedResolutionSheet(
  BuildContext context, {
  required String itemName,
  required String itemEmoji,
  required List<BorrowerInfo> borrowers,
  int? resolveCount,
}) {
  final totalBorrowed = borrowers.fold<int>(0, (s, b) => s + b.borrowed);
  final effectiveResolveCount = resolveCount ?? totalBorrowed;

  return showModalBottomSheet<ResolutionResult>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
    ),
    builder: (context) => _ResolutionSheetBody(
      itemName: itemName,
      itemEmoji: itemEmoji,
      borrowers: borrowers,
      resolveCount: effectiveResolveCount,
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// Public entry point — bulk (multiple items at once)
// ═════════════════════════════════════════════════════════════════════════════

/// Shows a bottom sheet for resolving multiple item types at once.
///
/// Used for both bucket deletion (all items in one bucket) and user
/// deletion (all items a user has borrowed across buckets).
///
/// [subtitle] appears below the title (e.g. bucket name or user name).
/// [bannerText] overrides the default info banner; if null a default is used.
/// [buttonLabel] overrides the submit button text (defaults to "Resolve & Delete").
Future<BulkResolutionResult?> showBulkBorrowedResolutionSheet(
  BuildContext context, {
  required String subtitle,
  required List<BulkResolutionEntry> entries,
  String? bannerText,
  String buttonLabel = 'Resolve & Delete',
}) {
  return showModalBottomSheet<BulkResolutionResult>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.90,
    ),
    builder: (context) => _BulkResolutionSheetBody(
      subtitle: subtitle,
      entries: entries,
      bannerText: bannerText,
      buttonLabel: buttonLabel,
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// Single-item sheet body
// ═════════════════════════════════════════════════════════════════════════════

class _ResolutionSheetBody extends StatefulWidget {
  const _ResolutionSheetBody({
    required this.itemName,
    required this.itemEmoji,
    required this.borrowers,
    required this.resolveCount,
  });

  final String itemName;
  final String itemEmoji;
  final List<BorrowerInfo> borrowers;
  final int resolveCount;

  @override
  State<_ResolutionSheetBody> createState() => _ResolutionSheetBodyState();
}

class _ResolutionSheetBodyState extends State<_ResolutionSheetBody> {
  late final List<_BorrowerDraft> _drafts;

  @override
  void initState() {
    super.initState();
    var remaining = widget.resolveCount;
    _drafts = widget.borrowers.map((b) {
      final give = remaining.clamp(0, b.borrowed);
      remaining -= give;
      return _BorrowerDraft(
        userId: b.userId,
        fullName: b.fullName,
        scoutId: b.scoutId,
        maxContribution: b.borrowed,
        initialAssigned: give,
      );
    }).toList();
  }

  int get _totalAssigned => _drafts.fold<int>(0, (sum, d) => sum + d.assigned);
  bool get _isValid => _totalAssigned == widget.resolveCount;

  void _submit() {
    if (!_isValid) return;
    final resolutions = <Map<String, dynamic>>[];
    for (final d in _drafts) {
      resolutions.addAll(d.toResolutions());
    }
    Navigator.of(context).pop(ResolutionResult(resolutions: resolutions));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final compact = MediaQuery.sizeOf(context).width < 380;
    final emojiBase = GoogleFonts.notoColorEmoji(height: 1);
    final totalAssigned = _totalAssigned;
    final target = widget.resolveCount;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(tokens.radiusLg),
                    border: Border.all(color: AppColors.outline),
                  ),
                  alignment: Alignment.center,
                  child: Text(widget.itemEmoji, style: emojiBase.copyWith(fontSize: 24)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Resolve $target item${target != 1 ? 's' : ''}', style: t.titleLarge?.copyWith(fontSize: 18)),
                      const SizedBox(height: 2),
                      Text(widget.itemName, style: t.bodyMedium?.copyWith(color: AppColors.muted, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _isValid ? AppColors.successBg : const Color(0xFFFEF3F2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$totalAssigned/$target', style: t.titleMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w900, color: _isValid ? AppColors.primary : const Color(0xFFD92D20))),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Divider(color: AppColors.outline),
            const SizedBox(height: 6),
            Container(
              width: double.infinity, padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.warningBg, borderRadius: BorderRadius.circular(tokens.radiusLg)),
              child: Text(
                'Account for $target item${target != 1 ? 's' : ''} being removed. Specify per borrower how many were returned, lost, or broken.',
                style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: const Color(0xFF93370D), height: 1.35),
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true, itemCount: _drafts.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) => _BorrowerResolutionCard(
                  draft: _drafts[i], globalTarget: target, globalAssigned: totalAssigned,
                  compact: compact, tokens: tokens, textTheme: t, onChanged: () => setState(() {}),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity, height: 56,
              child: FilledButton.icon(
                onPressed: _isValid ? _submit : null,
                icon: const Icon(Icons.check_rounded),
                label: Text('Resolve $target item${target != 1 ? 's' : ''}'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.muted.withValues(alpha: 0.2), disabledForegroundColor: AppColors.muted,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(tokens.radiusXl)), textStyle: t.titleMedium,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Bulk resolution sheet body — flat lazy list
// ═════════════════════════════════════════════════════════════════════════════

class _BulkItemDrafts {
  _BulkItemDrafts({
    required this.itemId,
    required this.itemName,
    required this.itemEmoji,
    required this.resolveCount,
    required this.drafts,
  });

  final String itemId;
  final String itemName;
  final String itemEmoji;
  final int resolveCount;
  final List<_BorrowerDraft> drafts;

  int get totalAssigned => drafts.fold<int>(0, (s, d) => s + d.assigned);
  bool get isFulfilled => totalAssigned == resolveCount;
}

sealed class _FlatEntry { const _FlatEntry(); }
class _HeaderEntry extends _FlatEntry { const _HeaderEntry(this.groupIndex); final int groupIndex; }
class _CardEntry extends _FlatEntry { const _CardEntry(this.groupIndex, this.draftIndex); final int groupIndex; final int draftIndex; }
class _DividerEntry extends _FlatEntry { const _DividerEntry(); }

class _BulkResolutionSheetBody extends StatefulWidget {
  const _BulkResolutionSheetBody({
    required this.subtitle,
    required this.entries,
    this.bannerText,
    this.buttonLabel = 'Resolve & Delete',
  });

  final String subtitle;
  final List<BulkResolutionEntry> entries;
  final String? bannerText;
  final String buttonLabel;

  @override
  State<_BulkResolutionSheetBody> createState() => _BulkResolutionSheetBodyState();
}

class _BulkResolutionSheetBodyState extends State<_BulkResolutionSheetBody> {
  late final List<_BulkItemDrafts> _itemDrafts;
  late List<_FlatEntry> _flat;

  @override
  void initState() {
    super.initState();
    _itemDrafts = widget.entries.map((entry) {
      final totalBorrowed = entry.borrowers.fold<int>(0, (s, b) => s + b.borrowed);
      final target = entry.resolveCount ?? totalBorrowed;
      var remaining = target;
      final drafts = entry.borrowers.map((b) {
        final give = remaining.clamp(0, b.borrowed);
        remaining -= give;
        return _BorrowerDraft(userId: b.userId, fullName: b.fullName, scoutId: b.scoutId, maxContribution: b.borrowed, initialAssigned: give);
      }).toList();
      return _BulkItemDrafts(itemId: entry.itemId, itemName: entry.itemName, itemEmoji: entry.itemEmoji, resolveCount: target, drafts: drafts);
    }).toList();
    _buildFlat();
  }

  void _buildFlat() {
    final list = <_FlatEntry>[];
    for (int g = 0; g < _itemDrafts.length; g++) {
      list.add(_HeaderEntry(g));
      for (int d = 0; d < _itemDrafts[g].drafts.length; d++) {
        list.add(_CardEntry(g, d));
      }
      if (g < _itemDrafts.length - 1) list.add(const _DividerEntry());
    }
    _flat = list;
  }

  int get _grandTarget => _itemDrafts.fold<int>(0, (s, g) => s + g.resolveCount);
  int get _grandAssigned => _itemDrafts.fold<int>(0, (s, g) => s + g.totalAssigned);
  bool get _isValid => _itemDrafts.every((g) => g.isFulfilled);

  void _submit() {
    if (!_isValid) return;
    final map = <String, List<Map<String, dynamic>>>{};
    for (final group in _itemDrafts) {
      final resolutions = <Map<String, dynamic>>[];
      for (final d in group.drafts) {
        resolutions.addAll(d.toResolutions());
      }
      map[group.itemId] = resolutions;
    }
    Navigator.of(context).pop(BulkResolutionResult(resolutionsByItemId: map));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final compact = MediaQuery.sizeOf(context).width < 380;
    final emojiBase = GoogleFonts.notoColorEmoji(height: 1);
    final grandTarget = _grandTarget;
    final grandAssigned = _grandAssigned;

    final defaultBanner =
        'There ${grandTarget == 1 ? 'is' : 'are'} $grandTarget borrowed item${grandTarget != 1 ? 's' : ''} '
        'across ${_itemDrafts.length} item type${_itemDrafts.length != 1 ? 's' : ''}. '
        'Resolve all of them to proceed.';

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(tokens.radiusLg), border: Border.all(color: AppColors.outline)),
                  alignment: Alignment.center,
                  child: Icon(Icons.inventory_2_outlined, size: 24, color: AppColors.ink),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Resolve all borrowed', style: t.titleLarge?.copyWith(fontSize: 18)),
                      const SizedBox(height: 2),
                      Text(widget.subtitle, style: t.bodyMedium?.copyWith(color: AppColors.muted, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: _isValid ? AppColors.successBg : const Color(0xFFFEF3F2), borderRadius: BorderRadius.circular(10)),
                  child: Text('$grandAssigned/$grandTarget', style: t.titleMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w900, color: _isValid ? AppColors.primary : const Color(0xFFD92D20))),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Divider(color: AppColors.outline),
            const SizedBox(height: 6),
            Container(
              width: double.infinity, padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.warningBg, borderRadius: BorderRadius.circular(tokens.radiusLg)),
              child: Text(widget.bannerText ?? defaultBanner, style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: const Color(0xFF93370D), height: 1.35)),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: ListView.builder(
                itemCount: _flat.length,
                itemBuilder: (context, index) {
                  final entry = _flat[index];
                  return switch (entry) {
                    _HeaderEntry(:final groupIndex) => _buildHeader(groupIndex, tokens: tokens, textTheme: t, emojiBase: emojiBase),
                    _CardEntry(:final groupIndex, :final draftIndex) => _buildCard(groupIndex, draftIndex, compact: compact, tokens: tokens, textTheme: t),
                    _DividerEntry() => Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Divider(color: AppColors.outline, height: 1)),
                  };
                },
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity, height: 56,
              child: FilledButton.icon(
                onPressed: _isValid ? _submit : null,
                icon: const Icon(Icons.check_rounded),
                label: Text(widget.buttonLabel),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFD92D20), foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.muted.withValues(alpha: 0.2), disabledForegroundColor: AppColors.muted,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(tokens.radiusXl)), textStyle: t.titleMedium,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(int groupIndex, {required AppTokens tokens, required TextTheme textTheme, required TextStyle emojiBase}) {
    final group = _itemDrafts[groupIndex];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(tokens.radiusLg - 2), border: Border.all(color: AppColors.outline)),
            alignment: Alignment.center,
            child: Text(group.itemEmoji, style: emojiBase.copyWith(fontSize: 18)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(group.itemName, style: textTheme.titleMedium?.copyWith(fontSize: 15, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: group.isFulfilled ? AppColors.successBg : const Color(0xFFFEF3F2), borderRadius: BorderRadius.circular(8)),
            child: Text('${group.totalAssigned}/${group.resolveCount}', style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w900, fontSize: 12, color: group.isFulfilled ? AppColors.primary : const Color(0xFFD92D20))),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(int groupIndex, int draftIndex, {required bool compact, required AppTokens tokens, required TextTheme textTheme}) {
    final group = _itemDrafts[groupIndex];
    final draft = group.drafts[draftIndex];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _BorrowerResolutionCard(draft: draft, globalTarget: group.resolveCount, globalAssigned: group.totalAssigned, compact: compact, tokens: tokens, textTheme: textTheme, onChanged: () => setState(() {})),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Per-borrower card (shared)
// ═════════════════════════════════════════════════════════════════════════════

class _BorrowerResolutionCard extends StatelessWidget {
  const _BorrowerResolutionCard({
    required this.draft, required this.globalTarget, required this.globalAssigned,
    required this.compact, required this.tokens, required this.textTheme, required this.onChanged,
  });

  final _BorrowerDraft draft;
  final int globalTarget, globalAssigned;
  final bool compact;
  final AppTokens tokens;
  final TextTheme textTheme;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final assigned = draft.assigned;
    final hasContribution = assigned > 0;
    final globalRoom = globalTarget - globalAssigned;

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(tokens.radiusXl), border: Border.all(color: AppColors.outline, width: 1), boxShadow: tokens.cardShadow),
      padding: EdgeInsets.all(compact ? 10 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: AppColors.onPrimary, shape: BoxShape.circle, border: Border.all(color: AppColors.ink.withValues(alpha: 0.15), width: 1.5)),
                alignment: Alignment.center,
                child: Text(_initials(draft.fullName), style: textTheme.titleMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(draft.fullName, style: textTheme.titleMedium?.copyWith(fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('#${draft.scoutId}  ·  ${draft.maxContribution} borrowed', style: textTheme.bodySmall?.copyWith(color: AppColors.muted, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              if (hasContribution)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.successBg, borderRadius: BorderRadius.circular(8)),
                  child: Text('$assigned resolved', style: textTheme.bodySmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 12)),
                ),
            ],
          ),
          SizedBox(height: compact ? 10 : 14),
          _MiniStepper(label: 'Returned', icon: Icons.keyboard_return_rounded, color: AppColors.primary, bgColor: AppColors.successBg, value: draft.returned, maxForThis: draft.maxContribution, globalRoom: globalRoom, currentAssigned: assigned, compact: compact, tokens: tokens, textTheme: textTheme, onChanged: (v) { draft.returned = v; onChanged(); }),
          SizedBox(height: compact ? 6 : 8),
          _MiniStepper(label: 'Lost', icon: Icons.help_outline_rounded, color: const Color(0xFFD92D20), bgColor: const Color(0xFFFEF3F2), value: draft.lost, maxForThis: draft.maxContribution, globalRoom: globalRoom, currentAssigned: assigned, compact: compact, tokens: tokens, textTheme: textTheme, onChanged: (v) { draft.lost = v; onChanged(); }),
          SizedBox(height: compact ? 6 : 8),
          _MiniStepper(label: 'Broken', icon: Icons.broken_image_rounded, color: const Color(0xFFDC6803), bgColor: AppColors.warningBg, value: draft.broken, maxForThis: draft.maxContribution, globalRoom: globalRoom, currentAssigned: assigned, compact: compact, tokens: tokens, textTheme: textTheme, onChanged: (v) { draft.broken = v; onChanged(); }),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Mini stepper row (shared)
// ═════════════════════════════════════════════════════════════════════════════

class _MiniStepper extends StatelessWidget {
  const _MiniStepper({
    required this.label, required this.icon, required this.color, required this.bgColor,
    required this.value, required this.maxForThis, required this.globalRoom, required this.currentAssigned,
    required this.compact, required this.tokens, required this.textTheme, required this.onChanged,
  });

  final String label;
  final IconData icon;
  final Color color, bgColor;
  final int value, maxForThis, globalRoom, currentAssigned;
  final bool compact;
  final AppTokens tokens;
  final TextTheme textTheme;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final canMinus = value > 0;
    final canPlus = currentAssigned < maxForThis && globalRoom > 0;
    final height = compact ? 44.0 : 48.0;
    final btnSize = compact ? 34.0 : 38.0;
    final iconSize = compact ? 18.0 : 20.0;
    final disabledFg = AppColors.muted.withValues(alpha: 0.35);
    final effectiveMax = value + (canPlus ? globalRoom.clamp(0, maxForThis - currentAssigned) : 0);

    return Container(
      height: height,
      decoration: BoxDecoration(color: bgColor.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(tokens.radiusLg), border: Border.all(color: color.withValues(alpha: 0.15))),
      child: Row(
        children: [
          const SizedBox(width: 10),
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          SizedBox(width: compact ? 60 : 70, child: Text(label, style: textTheme.titleMedium?.copyWith(fontSize: compact ? 13 : 14, fontWeight: FontWeight.w800, color: color))),
          const Spacer(),
          HoldIconButton(enabled: canMinus, maxCount: maxForThis, icon: Icons.remove_rounded, iconColor: canMinus ? color : disabledFg, fill: Colors.white, border: Colors.transparent, width: btnSize, height: btnSize, iconSize: iconSize, radius: tokens.radiusLg - 2, onTap: canMinus ? () => onChanged(value - 1) : null, onHoldTick: canMinus ? (step) => onChanged((value - step).clamp(0, maxForThis)) : null),
          SizedBox(width: compact ? 36 : 42, child: Center(child: Text('$value', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, fontSize: compact ? 18 : 20, color: color)))),
          HoldIconButton(enabled: canPlus, maxCount: maxForThis, icon: Icons.add_rounded, iconColor: canPlus ? color : disabledFg, fill: Colors.white, border: Colors.transparent, width: btnSize, height: btnSize, iconSize: iconSize, radius: tokens.radiusLg - 2, onTap: canPlus ? () => onChanged(value + 1) : null, onHoldTick: canPlus ? (step) => onChanged((value + step).clamp(0, effectiveMax)) : null),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}