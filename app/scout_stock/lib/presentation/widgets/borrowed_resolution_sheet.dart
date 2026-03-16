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
// Public entry point
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
// Sheet body
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
            // ── Header ─────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(tokens.radiusLg),
                    border: Border.all(color: AppColors.outline),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    widget.itemEmoji,
                    style: emojiBase.copyWith(fontSize: 24),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Resolve $target item${target != 1 ? 's' : ''}',
                        style: t.titleLarge?.copyWith(fontSize: 18),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.itemName,
                        style: t.bodyMedium?.copyWith(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _isValid
                        ? AppColors.successBg
                        : const Color(0xFFFEF3F2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$totalAssigned/$target',
                    style: t.titleMedium?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: _isValid
                          ? AppColors.primary
                          : const Color(0xFFD92D20),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 6),
            Divider(color: AppColors.outline),
            const SizedBox(height: 6),

            // ── Info banner ────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warningBg,
                borderRadius: BorderRadius.circular(tokens.radiusLg),
              ),
              child: Text(
                'Account for $target item${target != 1 ? 's' : ''} being '
                'removed. Specify per borrower how many were returned, '
                'lost, or broken.',
                style: t.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF93370D),
                  height: 1.35,
                ),
              ),
            ),

            const SizedBox(height: 14),

            // ── Borrower cards (scrollable) ────────────────────────────
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _drafts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final draft = _drafts[i];
                  return _BorrowerResolutionCard(
                    draft: draft,
                    globalTarget: target,
                    globalAssigned: totalAssigned,
                    compact: compact,
                    tokens: tokens,
                    textTheme: t,
                    onChanged: () => setState(() {}),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            // ── Submit button ──────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                onPressed: _isValid ? _submit : null,
                icon: const Icon(Icons.check_rounded),
                label: Text('Resolve $target item${target != 1 ? 's' : ''}'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.muted.withValues(
                    alpha: 0.2,
                  ),
                  disabledForegroundColor: AppColors.muted,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(tokens.radiusXl),
                  ),
                  textStyle: t.titleMedium,
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
// Per-borrower card
// ═════════════════════════════════════════════════════════════════════════════

class _BorrowerResolutionCard extends StatelessWidget {
  const _BorrowerResolutionCard({
    required this.draft,
    required this.globalTarget,
    required this.globalAssigned,
    required this.compact,
    required this.tokens,
    required this.textTheme,
    required this.onChanged,
  });

  final _BorrowerDraft draft;
  final int globalTarget;
  final int globalAssigned;
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(tokens.radiusXl),
        border: Border.all(color: AppColors.outline, width: 1),
        boxShadow: tokens.cardShadow,
      ),
      padding: EdgeInsets.all(compact ? 10 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Borrower name row ──────────────────────────────────────
          Row(
            children: [
              // Circle avatar with black stroke — matches Me page style
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.onPrimary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.ink.withValues(alpha: 0.15),
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  _initials(draft.fullName),
                  style: textTheme.titleMedium?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      draft.fullName,
                      style: textTheme.titleMedium?.copyWith(fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '#${draft.scoutId}  ·  ${draft.maxContribution} borrowed',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasContribution)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.successBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$assigned resolved',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),

          SizedBox(height: compact ? 10 : 14),

          // ── Three steppers ─────────────────────────────────────────
          _MiniStepper(
            label: 'Returned',
            icon: Icons.keyboard_return_rounded,
            color: AppColors.primary,
            bgColor: AppColors.successBg,
            value: draft.returned,
            maxForThis: draft.maxContribution,
            globalRoom: globalRoom,
            currentAssigned: assigned,
            compact: compact,
            tokens: tokens,
            textTheme: textTheme,
            onChanged: (v) {
              _setField(draft, 'returned', v);
              onChanged();
            },
          ),
          SizedBox(height: compact ? 6 : 8),
          _MiniStepper(
            label: 'Lost',
            icon: Icons.help_outline_rounded,
            color: const Color(0xFFD92D20),
            bgColor: const Color(0xFFFEF3F2),
            value: draft.lost,
            maxForThis: draft.maxContribution,
            globalRoom: globalRoom,
            currentAssigned: assigned,
            compact: compact,
            tokens: tokens,
            textTheme: textTheme,
            onChanged: (v) {
              _setField(draft, 'lost', v);
              onChanged();
            },
          ),
          SizedBox(height: compact ? 6 : 8),
          _MiniStepper(
            label: 'Broken',
            icon: Icons.broken_image_rounded,
            color: const Color(0xFFDC6803),
            bgColor: AppColors.warningBg,
            value: draft.broken,
            maxForThis: draft.maxContribution,
            globalRoom: globalRoom,
            currentAssigned: assigned,
            compact: compact,
            tokens: tokens,
            textTheme: textTheme,
            onChanged: (v) {
              _setField(draft, 'broken', v);
              onChanged();
            },
          ),
        ],
      ),
    );
  }

  void _setField(_BorrowerDraft d, String field, int value) {
    switch (field) {
      case 'returned':
        d.returned = value;
      case 'lost':
        d.lost = value;
      case 'broken':
        d.broken = value;
    }
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Mini stepper row
// ═════════════════════════════════════════════════════════════════════════════

class _MiniStepper extends StatelessWidget {
  const _MiniStepper({
    required this.label,
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.value,
    required this.maxForThis,
    required this.globalRoom,
    required this.currentAssigned,
    required this.compact,
    required this.tokens,
    required this.textTheme,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final int value;
  final int maxForThis;
  final int globalRoom;
  final int currentAssigned;
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

    final effectiveMax =
        value +
        (canPlus ? globalRoom.clamp(0, maxForThis - currentAssigned) : 0);

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 10),
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          SizedBox(
            width: compact ? 60 : 70,
            child: Text(
              label,
              style: textTheme.titleMedium?.copyWith(
                fontSize: compact ? 13 : 14,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          const Spacer(),
          HoldIconButton(
            enabled: canMinus,
            maxCount: maxForThis,
            icon: Icons.remove_rounded,
            iconColor: canMinus ? color : disabledFg,
            fill: Colors.white,
            border: Colors.transparent,
            width: btnSize,
            height: btnSize,
            iconSize: iconSize,
            radius: tokens.radiusLg - 2,
            onTap: canMinus ? () => onChanged(value - 1) : null,
            onHoldTick: canMinus
                ? (step) => onChanged((value - step).clamp(0, maxForThis))
                : null,
          ),
          SizedBox(
            width: compact ? 36 : 42,
            child: Center(
              child: Text(
                '$value',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: compact ? 18 : 20,
                  color: color,
                ),
              ),
            ),
          ),
          HoldIconButton(
            enabled: canPlus,
            maxCount: maxForThis,
            icon: Icons.add_rounded,
            iconColor: canPlus ? color : disabledFg,
            fill: Colors.white,
            border: Colors.transparent,
            width: btnSize,
            height: btnSize,
            iconSize: iconSize,
            radius: tokens.radiusLg - 2,
            onTap: canPlus ? () => onChanged(value + 1) : null,
            onHoldTick: canPlus
                ? (step) => onChanged((value + step).clamp(0, effectiveMax))
                : null,
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}
