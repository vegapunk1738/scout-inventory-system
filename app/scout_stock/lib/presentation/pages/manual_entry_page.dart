import 'package:flutter/material.dart';
import 'package:scout_stock/presentation/widgets/dotted_background.dart';
import 'package:scout_stock/presentation/widgets/glowing_action_button.dart';

import '../../theme/app_theme.dart';
import '../widgets/attention_text_field_widget.dart';

/// SSB-XXX-NNN where XXX = 3 uppercase letters, NNN = 3 digits.
final RegExp _ssbPattern = RegExp(r'^SSB-[A-Z]{3}-\d{3}$');

/// The locked prefix that the user cannot delete or modify.
const String _prefix = 'SSB-';

class ManualEntryPage extends StatefulWidget {
  const ManualEntryPage({super.key});

  @override
  State<ManualEntryPage> createState() => _ManualEntryPageState();
}

class _ManualEntryPageState extends State<ManualEntryPage> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();
  final _fieldKey = GlobalKey<AttentionTextFieldState>();

  /// Guard to prevent recursive controller listener calls.
  bool _formatting = false;

  @override
  void initState() {
    super.initState();

    _controller = TextEditingController(text: _prefix);
    _controller.selection = TextSelection.collapsed(offset: _prefix.length);
    _controller.addListener(_enforceFormat);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_enforceFormat);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Format enforcement
  // ═════════════════════════════════════════════════════════════════════════
  //
  // Pattern:  SSB-[A-Z]{0,3}(-[0-9]{0,3})?
  //
  // Rules:
  //   • "SSB-" prefix is immutable — any edit that shortens it restores it.
  //   • Positions 4–6: only uppercase A-Z.
  //   • Position 7: auto-inserted "-" once the 3rd letter is typed.
  //   • Positions 8–10: only digits 0-9.
  //   • Total max length: 11  (SSB-XXX-000).
  //   • Cursor is never allowed before position 4.
  // ═════════════════════════════════════════════════════════════════════════

  static final _letterRe = RegExp(r'[A-Z]');
  static final _digitRe = RegExp(r'[0-9]');

  void _enforceFormat() {
    if (_formatting) return;
    _formatting = true;

    try {
      final raw = _controller.text.toUpperCase();
      final cursorPos = _controller.selection.baseOffset;

      // ── 1. If the prefix was damaged, restore it ────────────────────
      if (raw.length < _prefix.length || !raw.startsWith(_prefix)) {
        _apply(_prefix, _prefix.length);
        return;
      }

      // ── 2. Extract user chars after prefix (strip dashes) ───────────
      final afterPrefix = raw.substring(_prefix.length).replaceAll('-', '');

      // Split into letters (first 3) and digits (next 3).
      final letterBuf = StringBuffer();
      final digitBuf = StringBuffer();

      for (int i = 0; i < afterPrefix.length; i++) {
        final ch = afterPrefix[i];
        if (letterBuf.length < 3 && _letterRe.hasMatch(ch)) {
          letterBuf.write(ch);
        } else if (letterBuf.length == 3 &&
            digitBuf.length < 3 &&
            _digitRe.hasMatch(ch)) {
          digitBuf.write(ch);
        }
        // Anything else is silently dropped.
      }

      final letters = letterBuf.toString();
      final digits = digitBuf.toString();

      // ── 3. Rebuild the formatted string ─────────────────────────────
      final buf = StringBuffer(_prefix);
      buf.write(letters);

      // Auto-insert the dash once all 3 letters are present.
      if (letters.length == 3) {
        buf.write('-');
        buf.write(digits);
      }

      final formatted = buf.toString();

      // ── 4. Compute the new cursor position ──────────────────────────
      //    Count how many "user characters" (non-dash, non-prefix) were
      //    before the cursor in the raw text, then walk the formatted
      //    string to map that count back to a position.
      final safeCursor = cursorPos.clamp(0, raw.length);

      int userCharsBefore = 0;
      for (int i = _prefix.length; i < safeCursor; i++) {
        if (raw[i] != '-') userCharsBefore++;
      }

      int newCursor = _prefix.length;
      int counted = 0;
      while (newCursor < formatted.length && counted < userCharsBefore) {
        if (formatted[newCursor] != '-') counted++;
        newCursor++;
      }

      // Nudge past the auto-dash so the cursor lands where the user
      // expects to type next.
      if (newCursor < formatted.length && formatted[newCursor] == '-') {
        newCursor++;
      }

      newCursor = newCursor.clamp(_prefix.length, formatted.length);

      // ── 5. Apply only if something changed ──────────────────────────
      if (_controller.text != formatted ||
          _controller.selection.baseOffset != newCursor) {
        _apply(formatted, newCursor);
      }
    } finally {
      _formatting = false;
    }
  }

  void _apply(String text, int cursor) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: cursor.clamp(0, text.length),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Actions
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> _openBucket() async {
    final code = _controller.text.trim().toUpperCase();

    if (!_ssbPattern.hasMatch(code)) {
      _focusNode.requestFocus();
      await _fieldKey.currentState?.triggerInvalid();
      return;
    }

    FocusScope.of(context).unfocus();
    Navigator.of(context).pop<String>(code);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Build
  // ═════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Back',
        ),
        title: Text('Back to Scanner', style: textTheme.titleMedium),
        centerTitle: false,
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: DottedBackground()),
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 140),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Manual Entry', style: textTheme.displaySmall),
                const SizedBox(height: 12),
                Text(
                  'Enter the bucket code directly if the barcode is\n'
                  'damaged or unreadable.',
                  style: textTheme.bodyLarge?.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 34),
                Text(
                  'ENTER BUCKET CODE',
                  style: textTheme.labelMedium?.copyWith(color: AppColors.ink),
                ),
                const SizedBox(height: 12),

                AttentionTextField(
                  key: _fieldKey,
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  hintText: '',

                  // Allow letters, digits, and dashes through the base filter.
                  // Our controller listener handles the real masking.
                  allowPattern: r'[A-Za-z0-9-]',
                  uppercase: true,
                  maxLength: 11,

                  onSubmitted: (_) => _openBucket(),
                ),

                const SizedBox(height: 16),
                Text(
                  'Format: SSB-XXX-000 (3 letters, 3 digits)',
                  style: textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: GlowingActionButton(
        label: 'Open Bucket',
        icon: const Icon(Icons.search),
        onPressed: _openBucket,
        respectKeyboardInset: false,
      ),
    );
  }
}