import 'package:flutter/material.dart';
import 'package:scout_stock/presentation/widgets/glowing_action_button.dart';

import '../../theme/app_theme.dart';
import '../widgets/attention_text_field_widget.dart';

class ManualEntryPage extends StatefulWidget {
  const ManualEntryPage({super.key});

  @override
  State<ManualEntryPage> createState() => _ManualEntryPageState();
}

class _ManualEntryPageState extends State<ManualEntryPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  final _fieldKey = GlobalKey<AttentionTextFieldState>();

  @override
  void initState() {
    super.initState();

    // Focus immediately (green outline).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool _mockBucketExists(String code) {
    // Format: letters/numbers with optional dash groups (no leading/trailing dash)
    final okFormat = RegExp(r'^[A-Z0-9]+(?:-[A-Z0-9]+)*$').hasMatch(code);

    // Mock rule: treat codes ending with "-0000" as "not found"
    final notFound = code.endsWith('-0000');

    return okFormat && code.length >= 4 && !notFound;
  }

  Future<void> _openBucket() async {
    final code = _controller.text.trim().toUpperCase();

    if (code.isEmpty) {
      _focusNode.requestFocus();
      await _fieldKey.currentState?.triggerInvalid();
      if (!mounted) return;
    }

    if (!_mockBucketExists(code)) {
      _focusNode.requestFocus();
      await _fieldKey.currentState?.triggerInvalid();
      if (!mounted) return;
    }

    FocusScope.of(context).unfocus();
    debugPrint('Entered Bucket Code : $code');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Back',
        ),
        title: Text('Back to Scanner', style: textTheme.titleMedium),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 140),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Manual Entry', style: textTheme.displaySmall),
            const SizedBox(height: 12),
            Text(
              'Enter the ID directly if the barcode is\ndamaged or unreadable.',
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
              hintText: 'e.g. XXXX-XXXX-1111',
              onSubmitted: (_) => _openBucket(),
              // optional overrides:
              // allowPattern: r'[A-Za-z0-9-]',
              // maxLength: 32,
              // uppercase: true,
            ),

            const SizedBox(height: 16),
            Text(
              'Tip: Use the keypad below to enter numbers.',
              style: textTheme.bodyMedium?.copyWith(color: AppColors.muted),
            ),
          ],
        ),
      ),

      bottomNavigationBar: GlowingActionButton(
        label: 'Open Bucket',
        icon: const Icon(Icons.search),
        onPressed: _openBucket,
        respectKeyboardInset: true, // keeps the nice lift when keyboard opens
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({
    required this.child,
    required this.borderRadius,
    required this.shadows,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final List<BoxShadow> shadows;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: shadows),
      child: child,
    );
  }
}
