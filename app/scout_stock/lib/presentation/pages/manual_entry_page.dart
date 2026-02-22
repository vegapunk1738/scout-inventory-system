import 'package:flutter/material.dart';
import 'package:scout_stock/presentation/widgets/dotted_background.dart';
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
    final okFormat = RegExp(r'^[A-Z0-9]+(?:-[A-Z0-9]+)*$').hasMatch(code);

    final notFound = code.endsWith('-0000');

    return okFormat && code.length >= 4 && !notFound;
  }

  Future<void> _openBucket() async {
    final code = _controller.text.trim().toUpperCase();

    if (code.isEmpty) {
      _focusNode.requestFocus();
      await _fieldKey.currentState?.triggerInvalid();
      return;
    }

    if (!_mockBucketExists(code)) {
      _focusNode.requestFocus();
      await _fieldKey.currentState?.triggerInvalid();
      return;
    }

    FocusScope.of(context).unfocus();

    Navigator.of(context).pop<String>(code);
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
                ),

                const SizedBox(height: 16),
                Text(
                  'Tip: Use the keypad below to enter numbers.',
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
        respectKeyboardInset: true, 
      ),
    );
  }
}
