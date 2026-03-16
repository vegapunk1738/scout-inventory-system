import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:scout_stock/data/api/api_client.dart';
import 'package:scout_stock/presentation/widgets/app_toast.dart';
import 'package:scout_stock/presentation/widgets/dotted_background.dart';
import 'package:scout_stock/presentation/widgets/glowing_action_button.dart';
import 'package:scout_stock/presentation/widgets/hold_icon_button.dart';
import 'package:scout_stock/theme/app_theme.dart';

import '../../widgets/attention_text_field_widget.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Callback type — the upsert page calls this *before* popping so the API
// request fires regardless of the parent page's lifecycle state.
// ═══════════════════════════════════════════════════════════════════════════

/// Async callback that performs the actual API mutation.
/// Throws on failure so the upsert page can surface the error and let the
/// user retry without losing their input.
typedef BucketUpsertSubmitCallback =
    Future<void> Function(Map<String, dynamic> result);

/// Passed as extra when navigating to the create page.
class CreateBucketArgs {
  const CreateBucketArgs({required this.onSubmit});

  /// Called with the form payload. Must complete the API call before
  /// returning. Throw to signal failure.
  final BucketUpsertSubmitCallback onSubmit;
}

/// Navigation args for editing an existing bucket.
class BucketUpsertArgs {
  const BucketUpsertArgs({
    required this.barcode,
    required this.name,
    required this.onSubmit,
    this.bucketId,
    this.contents = const [],
    @Deprecated('Bucket emojis are no longer used in the UI.')
    this.emoji = '🪣',
  });

  /// Backend UUID — null in create mode.
  final String? bucketId;

  /// Bucket barcode / ID (Code128 content), e.g. "SSB-COO-104".
  final String barcode;
  final String name;

  /// Kept for compatibility with existing callers, but ignored in the UI.
  @Deprecated('Bucket emojis are no longer used in the UI.')
  final String emoji;

  final List<BucketContentSeed> contents;

  /// Called with the form payload. Must complete the API call before
  /// returning. Throw to signal failure.
  final BucketUpsertSubmitCallback onSubmit;
}

class BucketContentSeed {
  const BucketContentSeed({
    this.id,
    required this.name,
    required this.emoji,
    required this.quantity,
    this.borrowed = 0,
  });

  /// Backend item_type UUID — null for brand-new items.
  final String? id;
  final String name;
  final String emoji;
  final int quantity;

  /// How many are currently borrowed. Used to enforce min quantity.
  final int borrowed;
}

class BucketUpsertPage extends StatefulWidget {
  const BucketUpsertPage({super.key, this.editArgs, this.createArgs});

  final BucketUpsertArgs? editArgs;
  final CreateBucketArgs? createArgs;

  @override
  State<BucketUpsertPage> createState() => _BucketUpsertPageState();
}

class _BucketUpsertPageState extends State<BucketUpsertPage> {
  final _nameCtrl = TextEditingController();
  final _nameFocus = FocusNode();
  final _nameKey = GlobalKey<AttentionTextFieldState>();

  final _scrollCtrl = ScrollController();
  final _rng = math.Random.secure();

  bool _saving = false;

  // Create-mode: digits are generated once and kept stable while typing.
  late final String _digits3 = (_rng.nextInt(1000)).toString().padLeft(3, '0');

  // Edit-mode: barcode is fixed.
  String? _fixedBarcode;

  final List<_ContentDraft> _items = [];

  bool get _isEdit => widget.editArgs != null;

  @override
  void initState() {
    super.initState();

    final args = widget.editArgs;
    if (args != null) {
      _nameCtrl.text = args.name;
      _fixedBarcode = args.barcode;

      for (final c in args.contents) {
        _items.add(
          _ContentDraft(
            existingId: c.id,
            emoji: c.emoji.isNotEmpty ? c.emoji : '📦',
            name: c.name,
            quantity: c.quantity.clamp(1, 999),
            borrowed: c.borrowed,
          ),
        );
      }
    }

    _nameCtrl.addListener(() {
      if (!_isEdit) setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nameFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nameFocus.dispose();
    _scrollCtrl.dispose();
    for (final it in _items) {
      it.dispose();
    }
    super.dispose();
  }

  String _abbrev3(String raw) {
    final clean = raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    if (clean.isEmpty) return '---';

    final lettersOnly = clean.replaceAll(RegExp(r'[^A-Z]'), '');
    if (lettersOnly.length >= 3) return lettersOnly.substring(0, 3);

    return clean.length >= 3 ? clean.substring(0, 3) : clean.padRight(3, 'X');
  }

  String get _abbreviation => _abbrev3(_nameCtrl.text.trim());

  String get _barcode {
    if (_isEdit) return _fixedBarcode ?? 'SSB-???-???';
    final ab = _abbreviation;
    return 'SSB-$ab-$_digits3';
  }

  bool _isValidName(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return false;
    if (!RegExp(r'[A-Za-z0-9]').hasMatch(s)) return false;
    return true;
  }

  Future<void> _pickItemEmoji(_ContentDraft item) async {
    final picked = await _showEmojiPicker(context, selected: item.emoji);
    if (picked == null) return;
    setState(() => item.emoji = picked);
  }

  void _addItem() {
    setState(() {
      final it = _ContentDraft(emoji: '📦', name: '', quantity: 1);
      _items.add(it);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToBottom();
        it.focusNode.requestFocus();
      });
    });
  }

  void _removeItem(int index) {
    final item = _items[index];

    if (item.borrowed > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot remove "${item.nameCtrl.text}" — '
            '${item.borrowed} currently borrowed',
          ),
        ),
      );
      return;
    }

    setState(() {
      final it = _items.removeAt(index);
      it.dispose();
    });
  }

  void _scrollToBottom() {
    if (!_scrollCtrl.hasClients) return;
    final max = _scrollCtrl.position.maxScrollExtent;
    _scrollCtrl.animateTo(
      max,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  void _onDelta(_ContentDraft item, int delta) {
    if (delta == 0) return;
    setState(() {
      final minQty = math.max(1, item.borrowed);
      final next = (item.quantity + delta).clamp(minQty, 999);
      item.quantity = next;
    });
  }

  // ── Error display ──────────────────────────────────────────────────────

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
    if (_saving) return;

    final name = _nameCtrl.text.trim();
    if (!_isValidName(name)) {
      _nameFocus.requestFocus();
      await _nameKey.currentState?.triggerInvalid();
      return;
    }

    // Validate item names.
    int firstInvalid = -1;
    for (var i = 0; i < _items.length; i++) {
      final it = _items[i];
      final ok = _isValidName(it.nameCtrl.text);
      if (!ok && firstInvalid == -1) firstInvalid = i;
    }

    if (firstInvalid != -1) {
      final bad = _items[firstInvalid];
      bad.focusNode.requestFocus();

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;

        final ctx = bad.cardKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 260),
          );
        }
        await bad.nameKey.currentState?.triggerInvalid();
      });

      return;
    }

    // Validate abbreviation for create mode.
    if (!_isEdit && !RegExp(r'^[A-Z]{3}$').hasMatch(_abbreviation)) {
      _nameFocus.requestFocus();
      await _nameKey.currentState?.triggerInvalid();
      return;
    }

    setState(() => _saving = true);

    try {
      FocusScope.of(context).unfocus();

      // Build the result payload.
      final payload = <String, dynamic>{
        'name': name,
        'abbreviation': _abbreviation,
        'barcode': _barcode,
        if (_isEdit && widget.editArgs?.bucketId != null)
          'bucketId': widget.editArgs!.bucketId,
        'contents': _items
            .map(
              (x) => {
                if (x.existingId != null) 'id': x.existingId!,
                'name': x.nameCtrl.text.trim(),
                'emoji': x.emoji,
                'quantity': x.quantity,
              },
            )
            .toList(),
      };

      // FIX: Call the mutation callback *here*, while we're still mounted.
      // Only pop on success — on failure the user stays on the form.
      final callback = _isEdit
          ? widget.editArgs!.onSubmit
          : widget.createArgs!.onSubmit;
      await callback(payload);

      // API call succeeded — now pop.
      if (mounted) context.pop();
    } catch (e) {
      // Surface the error on this page so the user can retry.
      _showSubmitError(e);
    } finally {
      // Always reset _saving so the button is never permanently disabled.
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final w = MediaQuery.sizeOf(context).width;
    final compact = w < 380;

    final emojiBase = GoogleFonts.notoColorEmoji(height: 1);

    final title = _isEdit ? 'Edit Bucket' : 'Create New Bucket';
    final subtitle = _isEdit
        ? 'Update the bucket name and contents.'
        : 'Create a bucket, then add the items it contains.';

    final contentsCount = _items.length;

    final bottomScrollPad = compact ? 170.0 : 190.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
          tooltip: 'Back',
        ),
        title: Text('Back to Bucket Management', style: t.titleMedium),
        centerTitle: false,
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: DottedBackground()),
          SingleChildScrollView(
            controller: _scrollCtrl,
            padding: EdgeInsets.fromLTRB(
              compact ? 18 : 24,
              compact ? 18 : 24,
              compact ? 18 : 24,
              bottomScrollPad,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.displaySmall),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  style: t.bodyLarge?.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 22),

                // Bucket name card
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(tokens.radiusXl),
                    boxShadow: tokens.cardShadow,
                  ),
                  padding: EdgeInsets.all(compact ? 14 : 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'BUCKET NAME',
                        style: t.labelLarge?.copyWith(
                          color: AppColors.muted,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      AttentionTextField(
                        key: _nameKey,
                        controller: _nameCtrl,
                        focusNode: _nameFocus,
                        autofocus: true,
                        hintText: 'e.g. Cooking Kit 1',
                        centeredLayout: false,
                        textAlign: TextAlign.start,
                        textCapitalization: TextCapitalization.words,
                        keyboardType: TextInputType.name,
                        textInputAction: TextInputAction.done,
                        allowPattern: r'[A-Za-z0-9() ]',
                        uppercase: false,
                        maxLength: 42,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 18,
                        ),
                        textStyle: (t.bodyLarge ?? const TextStyle()).copyWith(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w900,
                          fontSize: compact ? 20 : 22,
                          height: 1.15,
                        ),
                        hintStyle: (t.bodyLarge ?? const TextStyle()).copyWith(
                          color: const Color(0xFFB9C0C8),
                          fontWeight: FontWeight.w900,
                          fontSize: compact ? 20 : 22,
                          height: 1.15,
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _BarcodePill(code: _barcode, compact: compact),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _isEdit
                                  ? 'Barcode is fixed after creation.'
                                  : 'Auto-generated from the name.',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: t.bodyMedium?.copyWith(
                                color: AppColors.muted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                Row(
                  children: [
                    Expanded(child: Text('Contents', style: t.titleLarge)),
                    _CountPill(count: contentsCount, compact: compact),
                  ],
                ),
                const SizedBox(height: 10),

                if (_items.isEmpty)
                  _EmptyContents(
                    compact: compact,
                    emojiBase: emojiBase,
                    titleStyle: t.titleMedium,
                    bodyStyle: t.bodyLarge?.copyWith(color: AppColors.muted),
                    onAdd: _addItem,
                  )
                else
                  ListView.separated(
                    physics: const NeverScrollableScrollPhysics(),
                    shrinkWrap: true,
                    itemCount: _items.length,
                    separatorBuilder: (_, _) =>
                        SizedBox(height: compact ? 10 : 12),
                    itemBuilder: (context, i) {
                      final it = _items[i];
                      return _ContentItemCard(
                        key: it.cardKey,
                        item: it,
                        compact: compact,
                        tokens: tokens,
                        textTheme: t,
                        emojiBase: emojiBase,
                        onRemove: () => _removeItem(i),
                        onDelta: (d) => _onDelta(it, d),
                        onPickEmoji: () => _pickItemEmoji(it),
                      );
                    },
                  ),

                const SizedBox(height: 14),
                if (_items.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: _addItem,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add Another Item'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(58),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(tokens.radiusXl),
                      ),
                      side: BorderSide(color: AppColors.outline, width: 1.4),
                      backgroundColor: Colors.white.withValues(alpha: 0.65),
                      textStyle: t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      foregroundColor: AppColors.ink,
                    ),
                  ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),

      bottomNavigationBar: GlowingActionButton(
        label: _isEdit ? 'Save Changes' : 'Create Bucket',
        icon: const Icon(Icons.check_rounded),
        onPressed: _saving ? null : _submit,
        loading: _saving,
        respectKeyboardInset: false,
      ),
    );
  }
}

class _ContentDraft {
  _ContentDraft({
    this.existingId,
    required this.emoji,
    required String name,
    required this.quantity,
    this.borrowed = 0,
  }) : nameCtrl = TextEditingController(text: name);

  final GlobalKey cardKey = GlobalKey();

  final GlobalKey<AttentionTextFieldState> nameKey =
      GlobalKey<AttentionTextFieldState>();

  /// Backend item_type UUID — null for brand-new items.
  final String? existingId;

  String emoji;
  final TextEditingController nameCtrl;
  final FocusNode focusNode = FocusNode();

  int quantity;

  /// How many are currently borrowed. Immutable from the form's POV.
  final int borrowed;

  void dispose() {
    nameCtrl.dispose();
    focusNode.dispose();
  }
}

class _BarcodePill extends StatelessWidget {
  const _BarcodePill({required this.code, required this.compact});

  final String code;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<AppTokens>()!;

    final fg = AppColors.primary;
    final bg = AppColors.successBg;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 8 : 9,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        border: Border.all(color: fg.withValues(alpha: 0.15)),
      ),
      child: Text(
        code,
        style: t.bodyMedium?.copyWith(
          color: fg,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count, required this.compact});

  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final t = Theme.of(context).textTheme;

    final label = count == 1 ? '1 Item' : '$count Items';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 6 : 7,
      ),
      decoration: BoxDecoration(
        color: AppColors.successBg,
        borderRadius: BorderRadius.circular(tokens.radiusLg),
      ),
      child: Text(
        label,
        style: t.bodyMedium?.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ContentItemCard extends StatelessWidget {
  const _ContentItemCard({
    super.key,
    required this.item,
    required this.compact,
    required this.tokens,
    required this.textTheme,
    required this.emojiBase,
    required this.onRemove,
    required this.onDelta,
    required this.onPickEmoji,
  });

  final _ContentDraft item;
  final bool compact;
  final AppTokens tokens;
  final TextTheme textTheme;
  final TextStyle emojiBase;

  final VoidCallback onRemove;
  final ValueChanged<int> onDelta;
  final VoidCallback onPickEmoji;

  @override
  Widget build(BuildContext context) {
    final tile = compact ? 42.0 : 48.0;
    final emojiSize = compact ? 22.0 : 26.0;

    final shadow = tokens.cardShadow.isNotEmpty
        ? [
            tokens.cardShadow.first.copyWith(
              blurRadius: 12,
              offset: const Offset(0, 7),
            ),
          ]
        : const <BoxShadow>[];

    final hasBorrowed = item.borrowed > 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(tokens.radiusXl),
        boxShadow: shadow,
      ),
      padding: EdgeInsets.all(compact ? 10 : 12),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              InkResponse(
                onTap: onPickEmoji,
                radius: 26,
                child: Container(
                  width: tile,
                  height: tile,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(tokens.radiusLg),
                    border: Border.all(color: AppColors.outline),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    item.emoji,
                    style: emojiBase.copyWith(fontSize: emojiSize),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: tile,
                  child: _ItemNameAttentionField(
                    key: item.nameKey,
                    controller: item.nameCtrl,
                    focusNode: item.focusNode,
                    compact: compact,
                    textTheme: textTheme,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _TrashSquareButton(
                size: tile,
                onTap: onRemove,
                disabled: hasBorrowed,
              ),
            ],
          ),

          if (hasBorrowed) ...[
            SizedBox(height: compact ? 8 : 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.warningBg,
                borderRadius: BorderRadius.circular(tokens.radiusLg),
                border: Border.all(color: const Color(0xFFFBD38D)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.people_outline_rounded,
                    size: 16,
                    color: Color(0xFF8A5B00),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${item.borrowed} currently borrowed',
                    style: textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF8A5B00),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'min qty: ${item.borrowed}',
                    style: textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF8A5B00),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],

          SizedBox(height: compact ? 10 : 12),
          _QtyStepperEdit(
            value: item.quantity,
            minValue: math.max(1, item.borrowed),
            compact: compact,
            onDelta: onDelta,
          ),
        ],
      ),
    );
  }
}

class _ItemNameAttentionField extends StatelessWidget {
  const _ItemNameAttentionField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.compact,
    required this.textTheme,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool compact;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final style = (textTheme.bodyLarge ?? const TextStyle()).copyWith(
      color: AppColors.ink,
      fontWeight: FontWeight.w900,
      fontSize: compact ? 16 : 17,
      height: 1.1,
    );

    final hintStyle = style.copyWith(color: const Color(0xFFB9C0C8));

    return AttentionTextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: false,
      hintText: 'Item name',
      centeredLayout: false,
      textAlign: TextAlign.start,
      textCapitalization: TextCapitalization.words,
      keyboardType: TextInputType.name,
      textInputAction: TextInputAction.next,
      allowPattern: r'[A-Za-z0-9() ]',
      uppercase: false,
      maxLength: 48,
      contentPadding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: compact ? 12 : 14,
      ),
      textStyle: style,
      hintStyle: hintStyle,
    );
  }
}

class _QtyStepperEdit extends StatelessWidget {
  const _QtyStepperEdit({
    required this.value,
    required this.compact,
    required this.onDelta,
    this.minValue = 1,
  });

  final int value;
  final bool compact;
  final ValueChanged<int> onDelta;
  final int minValue;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final t = Theme.of(context).textTheme;

    const max = 999;

    final canMinus = value > minValue;
    final canPlus = value < max;

    final height = compact ? 50.0 : 56.0;
    final btnSize = compact ? 40.0 : 44.0;
    final iconSize = compact ? 20.0 : 22.0;

    final disabledFg = AppColors.muted.withValues(alpha: 0.45);

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          const SizedBox(width: 6),
          HoldIconButton(
            enabled: canMinus,
            maxCount: max,
            icon: Icons.remove_rounded,
            iconColor: canMinus ? AppColors.primary : disabledFg,
            fill: AppColors.background,
            border: Colors.transparent,
            width: btnSize,
            height: btnSize,
            iconSize: iconSize,
            radius: tokens.radiusLg,
            onTap: canMinus ? () => onDelta(-1) : null,
            onHoldTick: canMinus ? (step) => onDelta(-step) : null,
            semanticsLabel: 'Decrease quantity',
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$value',
                    style: (compact ? t.titleLarge : t.headlineSmall)?.copyWith(
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'quantity',
                    style: t.bodySmall?.copyWith(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          HoldIconButton(
            enabled: canPlus,
            maxCount: max,
            icon: Icons.add_rounded,
            iconColor: canPlus ? AppColors.primary : disabledFg,
            fill: AppColors.background,
            border: Colors.transparent,
            width: btnSize,
            height: btnSize,
            iconSize: iconSize,
            radius: tokens.radiusLg,
            onTap: canPlus ? () => onDelta(1) : null,
            onHoldTick: canPlus ? (step) => onDelta(step) : null,
            semanticsLabel: 'Increase quantity',
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _TrashSquareButton extends StatelessWidget {
  const _TrashSquareButton({
    required this.size,
    required this.onTap,
    this.disabled = false,
  });

  final double size;
  final VoidCallback onTap;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final iconSize = size <= 44 ? 18.0 : 20.0;

    return Opacity(
      opacity: disabled ? 0.35 : 1.0,
      child: InkResponse(
        onTap: disabled ? null : onTap,
        radius: 26,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(tokens.radiusLg),
            border: Border.all(color: AppColors.outline),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.close_rounded,
            size: iconSize,
            color: AppColors.muted,
          ),
        ),
      ),
    );
  }
}

class _EmptyContents extends StatelessWidget {
  const _EmptyContents({
    required this.compact,
    required this.emojiBase,
    required this.titleStyle,
    required this.bodyStyle,
    required this.onAdd,
  });

  final bool compact;
  final TextStyle emojiBase;
  final TextStyle? titleStyle;
  final TextStyle? bodyStyle;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final t = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(tokens.radiusXl),
        border: Border.all(color: AppColors.outline),
        boxShadow: tokens.cardShadow,
      ),
      padding: EdgeInsets.all(compact ? 16 : 18),
      child: Column(
        children: [
          Text('📦', style: emojiBase.copyWith(fontSize: compact ? 46 : 54)),
          const SizedBox(height: 10),
          Text('No items yet', style: titleStyle, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'Add at least one item type to make this bucket usable.',
            style: bodyStyle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add first item'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(tokens.radiusXl),
              ),
              minimumSize: const Size.fromHeight(50),
              textStyle: t.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}

Future<String?> _showEmojiPicker(
  BuildContext context, {
  required String selected,
}) {
  const emojis = <String>[
    '📦',
    '🧰',
    '🧯',
    '⛺️',
    '🏕️',
    '🪢',
    '🧵',
    '🧻',
    '🧼',
    '🪓',
    '🔧',
    '🔩',
    '🪛',
    '🔦',
    '🧲',
    '🧪',
    '🧫',
    '🧴',
    '🧹',
    '🧺',
    '🎒',
    '🧷',
    '📎',
    '✂️',
    '📏',
    '🧱',
    '🪵',
    '🧊',
    '🔥',
    '💧',
    '⚙️',
    '🩹',
    '🩺',
    '🧤',
    '🧢',
    '🪖',
    '🥫',
    '🍳',
    '🥄',
    '🍽️',
    '🥣',
    '🍞',
    '🧃',
    '🏷️',
    '📝',
    '📍',
    '⭐️',
  ];

  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    builder: (context) {
      final tokens = Theme.of(context).extension<AppTokens>()!;
      final t = Theme.of(context).textTheme;
      final emojiBase = GoogleFonts.notoColorEmoji(height: 1);

      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Pick an emoji', style: t.titleLarge),
              const SizedBox(height: 8),
              Text(
                'One emoji only.',
                style: t.bodyMedium?.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: GridView.builder(
                  shrinkWrap: true,
                  itemCount: emojis.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 8,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  itemBuilder: (context, i) {
                    final e = emojis[i];
                    final isSel = e == selected;
                    return InkResponse(
                      onTap: () => Navigator.of(context).pop(e),
                      radius: 26,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSel
                              ? AppColors.successBg
                              : AppColors.background,
                          borderRadius: BorderRadius.circular(tokens.radiusLg),
                          border: Border.all(
                            color: isSel
                                ? AppColors.primary.withValues(alpha: 0.25)
                                : AppColors.outline,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(e, style: emojiBase.copyWith(fontSize: 20)),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
