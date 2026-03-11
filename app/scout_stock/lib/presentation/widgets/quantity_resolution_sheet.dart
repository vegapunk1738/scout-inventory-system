import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:scout_stock/domain/models/bucket.dart';
import 'package:scout_stock/state/providers/buckets_provider.dart';
import 'package:scout_stock/theme/app_theme.dart';

// ─── Resolution status ──────────────────────────────────────────────────────

enum ResolutionStatus {
  /// Not yet resolved by admin.
  pending,

  /// Scout returned the item normally.
  returned,

  /// Item is lost — stock will be decreased.
  lost,

  /// Item is damaged — stock will be decreased.
  damaged;

  String get label {
    switch (this) {
      case ResolutionStatus.pending:
        return 'Pending';
      case ResolutionStatus.returned:
        return 'Returned';
      case ResolutionStatus.lost:
        return 'Lost';
      case ResolutionStatus.damaged:
        return 'Damaged';
    }
  }

  IconData get icon {
    switch (this) {
      case ResolutionStatus.pending:
        return Icons.hourglass_empty_rounded;
      case ResolutionStatus.returned:
        return Icons.check_circle_rounded;
      case ResolutionStatus.lost:
        return Icons.help_outline_rounded;
      case ResolutionStatus.damaged:
        return Icons.warning_amber_rounded;
    }
  }

  Color color(BuildContext context) {
    switch (this) {
      case ResolutionStatus.pending:
        return AppColors.muted;
      case ResolutionStatus.returned:
        return AppColors.primary;
      case ResolutionStatus.lost:
        return const Color(0xFFB54708);
      case ResolutionStatus.damaged:
        return const Color(0xFFD92D20);
    }
  }

  Color bgColor(BuildContext context) {
    switch (this) {
      case ResolutionStatus.pending:
        return const Color(0xFFF2F4F7);
      case ResolutionStatus.returned:
        return AppColors.successBg;
      case ResolutionStatus.lost:
        return const Color(0xFFFEF0C7);
      case ResolutionStatus.damaged:
        return const Color(0xFFFEE4E2);
    }
  }

  /// Maps to backend status field for the resolve API.
  String get apiValue {
    switch (this) {
      case ResolutionStatus.returned:
        return 'returned';
      case ResolutionStatus.lost:
        return 'lost';
      case ResolutionStatus.damaged:
        return 'damaged';
      case ResolutionStatus.pending:
        return 'returned'; // fallback, should not be sent
    }
  }
}

// ─── Borrower resolution draft ──────────────────────────────────────────────

class _BorrowerDraft {
  _BorrowerDraft({
    required this.borrower,
    required this.status,
    required this.resolveQty,
  });

  final BorrowerInfo borrower;
  ResolutionStatus status;

  /// How many items to resolve for this borrower (1..borrower.borrowed).
  int resolveQty;
}

// ─── Show resolution sheet ──────────────────────────────────────────────────

/// Shows the resolution bottom sheet. Returns `true` if resolutions were
/// submitted, `false` if cancelled.
Future<bool> showQuantityResolutionSheet(
  BuildContext context, {
  required WidgetRef ref,
  required String bucketId,
  required String itemTypeId,
  required String itemName,
  required String itemEmoji,
  required int currentQuantity,
  required int requestedQuantity,
  required int currentlyBorrowed,
  required List<BorrowerInfo> borrowers,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _QuantityResolutionSheet(
      ref: ref,
      bucketId: bucketId,
      itemTypeId: itemTypeId,
      itemName: itemName,
      itemEmoji: itemEmoji,
      currentQuantity: currentQuantity,
      requestedQuantity: requestedQuantity,
      currentlyBorrowed: currentlyBorrowed,
      borrowers: borrowers,
    ),
  );

  return result == true;
}

// ─── Sheet widget ───────────────────────────────────────────────────────────

class _QuantityResolutionSheet extends StatefulWidget {
  const _QuantityResolutionSheet({
    required this.ref,
    required this.bucketId,
    required this.itemTypeId,
    required this.itemName,
    required this.itemEmoji,
    required this.currentQuantity,
    required this.requestedQuantity,
    required this.currentlyBorrowed,
    required this.borrowers,
  });

  final WidgetRef ref;
  final String bucketId;
  final String itemTypeId;
  final String itemName;
  final String itemEmoji;
  final int currentQuantity;
  final int requestedQuantity;
  final int currentlyBorrowed;
  final List<BorrowerInfo> borrowers;

  @override
  State<_QuantityResolutionSheet> createState() =>
      _QuantityResolutionSheetState();
}

class _QuantityResolutionSheetState extends State<_QuantityResolutionSheet> {
  late final List<_BorrowerDraft> _drafts;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _drafts = widget.borrowers
        .map(
          (b) => _BorrowerDraft(
            borrower: b,
            status: ResolutionStatus.pending,
            resolveQty: b.borrowed,
          ),
        )
        .toList();
  }

  /// Total items that will be resolved (freed).
  int get _totalToResolve {
    return _drafts
        .where((d) => d.status != ResolutionStatus.pending)
        .fold<int>(0, (sum, d) => sum + d.resolveQty);
  }

  /// How many need to be freed for the requested quantity to work.
  int get _neededToFree => widget.currentlyBorrowed - widget.requestedQuantity;

  bool get _canSubmit =>
      _totalToResolve >= _neededToFree &&
      _drafts.every((d) => d.status != ResolutionStatus.pending);

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    try {
      final resolutions = _drafts
          .where((d) => d.status != ResolutionStatus.pending)
          .map((d) => {
              'user_id': d.borrower.userId,
              'quantity': d.resolveQty,
              'status': d.status.apiValue,
          })
          .toList();

      await widget.ref.read(bucketsProvider.notifier).resolveBorrowed(
            widget.bucketId,
            widget.itemTypeId,
            resolutions: resolutions,
          );

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to resolve: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final emojiBase = GoogleFonts.notoColorEmoji(height: 1);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    final resolved = _totalToResolve;
    final needed = _neededToFree;
    final progress = needed > 0 ? (resolved / needed).clamp(0.0, 1.0) : 1.0;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD0D5DD),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFFBD38D),
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.warning_amber_rounded,
                          color: Color(0xFFB54708),
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Resolve Borrowed Items',
                            style: t.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Items must be accounted for before decreasing stock',
                            style: t.bodySmall?.copyWith(
                              color: AppColors.muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Item info card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(tokens.radiusLg),
                    border: Border.all(color: AppColors.outline),
                  ),
                  child: Row(
                    children: [
                      Text(widget.itemEmoji,
                          style: emojiBase.copyWith(fontSize: 28)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.itemName,
                              style: t.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            RichText(
                              text: TextSpan(
                                style: t.bodySmall?.copyWith(
                                  color: AppColors.muted,
                                  fontWeight: FontWeight.w700,
                                ),
                                children: [
                                  TextSpan(
                                      text:
                                          '${widget.currentlyBorrowed} borrowed'),
                                  const TextSpan(text: '  ·  '),
                                  TextSpan(
                                      text:
                                          'stock ${widget.currentQuantity} → ${widget.requestedQuantity}'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // Progress bar
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'RESOLUTION PROGRESS',
                          style: t.labelSmall?.copyWith(
                            color: AppColors.muted,
                            letterSpacing: 1.2,
                          ),
                        ),
                        Text(
                          '$resolved / $needed resolved',
                          style: t.labelSmall?.copyWith(
                            color: progress >= 1.0
                                ? AppColors.primary
                                : const Color(0xFFB54708),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: const Color(0xFFE5E7EB),
                        color: progress >= 1.0
                            ? AppColors.primary
                            : const Color(0xFFD97706),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),

          const Divider(height: 1),

          // Borrower list
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              itemCount: _drafts.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final draft = _drafts[index];
                return _BorrowerCard(
                  draft: draft,
                  tokens: tokens,
                  onStatusChanged: (status) {
                    setState(() => draft.status = status);
                  },
                  onQtyChanged: (qty) {
                    setState(
                        () => draft.resolveQty = qty.clamp(1, draft.borrower.borrowed));
                  },
                );
              },
            ),
          ),

          // Bottom action
          Container(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              safeBottom + bottomInset + 16,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: AppColors.outline),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_canSubmit && _drafts.any((d) => d.status == ResolutionStatus.pending))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Set a status for each borrower to continue',
                      style: t.bodySmall?.copyWith(
                        color: const Color(0xFFB54708),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: _canSubmit && !_submitting ? _submit : null,
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(
                      _submitting ? 'Resolving…' : 'Confirm Resolutions',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          _canSubmit ? AppColors.primary : AppColors.muted,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(tokens.radiusXl),
                      ),
                      textStyle: t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Borrower card ──────────────────────────────────────────────────────────

class _BorrowerCard extends StatelessWidget {
  const _BorrowerCard({
    required this.draft,
    required this.tokens,
    required this.onStatusChanged,
    required this.onQtyChanged,
  });

  final _BorrowerDraft draft;
  final AppTokens tokens;
  final ValueChanged<ResolutionStatus> onStatusChanged;
  final ValueChanged<int> onQtyChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final b = draft.borrower;
    final statusColor = draft.status.color(context);
    final statusBg = draft.status.bgColor(context);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(tokens.radiusXl),
        border: Border.all(
          color: draft.status == ResolutionStatus.pending
              ? AppColors.outline
              : statusColor.withValues(alpha: 0.3),
          width: draft.status == ResolutionStatus.pending ? 1 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // User info row
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: statusBg,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      b.fullName.isNotEmpty
                          ? b.fullName[0].toUpperCase()
                          : '?',
                      style: t.titleMedium?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b.fullName,
                        style: t.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'Scout #${b.scoutId}  ·  ${b.borrowed} borrowed',
                        style: t.bodySmall?.copyWith(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Status chips
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Row(
              children: [
                for (final status in [
                  ResolutionStatus.returned,
                  ResolutionStatus.lost,
                  ResolutionStatus.damaged,
                ]) ...[
                  Expanded(
                    child: _StatusChip(
                      status: status,
                      isSelected: draft.status == status,
                      onTap: () => onStatusChanged(status),
                    ),
                  ),
                  if (status != ResolutionStatus.damaged)
                    const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Status chip ────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.status,
    required this.isSelected,
    required this.onTap,
  });

  final ResolutionStatus status;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final color = status.color(context);
    final bgColor = status.bgColor(context);

    return Material(
      color: isSelected ? bgColor : const Color(0xFFF9FAFB),
      borderRadius: BorderRadius.circular(tokens.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(tokens.radiusLg),
            border: Border.all(
              color: isSelected
                  ? color.withValues(alpha: 0.4)
                  : AppColors.outline,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                status.icon,
                size: 20,
                color: isSelected ? color : AppColors.muted,
              ),
              const SizedBox(height: 4),
              Text(
                status.label,
                style: t.labelSmall?.copyWith(
                  color: isSelected ? color : AppColors.muted,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}