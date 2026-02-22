import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AttentionTextField extends StatefulWidget {
  const AttentionTextField({
    super.key,
    required this.controller,
    this.focusNode,
    this.autofocus = false,
    this.hintText,
    this.onSubmitted,
    this.onChanged,

    this.allowPattern = r'[A-Za-z0-9-]',
    this.uppercase = true,
    this.maxLength = 32,

    this.sideSpacerWidth = 56,
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 26,
    ),
    this.textStyle,
    this.hintStyle,

    this.clearErrorOnChange = true,
    this.hapticsOnError = true,
    this.shakeDistance = 10,
    this.shakeDuration = const Duration(milliseconds: 420),
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool autofocus;

  final String? hintText;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  final String allowPattern;
  final bool uppercase;
  final int maxLength;

  final double sideSpacerWidth;

  final EdgeInsets contentPadding;
  final TextStyle? textStyle;
  final TextStyle? hintStyle;

  final bool clearErrorOnChange;
  final bool hapticsOnError;

  final double shakeDistance;
  final Duration shakeDuration;

  @override
  State<AttentionTextField> createState() => AttentionTextFieldState();
}

class AttentionTextFieldState extends State<AttentionTextField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shakeController;
  late final Animation<double> _shakeX;

  bool _hasError = false;

  bool get hasError => _hasError;

  @override
  void initState() {
    super.initState();

    _shakeController = AnimationController(
      vsync: this,
      duration: widget.shakeDuration,
    );

    _shakeX = TweenSequence<double>(
      [
        TweenSequenceItem(
          tween: Tween(begin: 0, end: -widget.shakeDistance),
          weight: 1,
        ),
        TweenSequenceItem(
          tween: Tween(begin: -widget.shakeDistance, end: widget.shakeDistance),
          weight: 1,
        ),
        TweenSequenceItem(
          tween: Tween(
            begin: widget.shakeDistance,
            end: -widget.shakeDistance * 0.8,
          ),
          weight: 1,
        ),
        TweenSequenceItem(
          tween: Tween(
            begin: -widget.shakeDistance * 0.8,
            end: widget.shakeDistance * 0.8,
          ),
          weight: 1,
        ),
        TweenSequenceItem(
          tween: Tween(
            begin: widget.shakeDistance * 0.8,
            end: -widget.shakeDistance * 0.4,
          ),
          weight: 1,
        ),
        TweenSequenceItem(
          tween: Tween(
            begin: -widget.shakeDistance * 0.4,
            end: widget.shakeDistance * 0.4,
          ),
          weight: 1,
        ),
        TweenSequenceItem(
          tween: Tween(begin: widget.shakeDistance * 0.4, end: 0),
          weight: 1,
        ),
      ],
    ).animate(CurvedAnimation(parent: _shakeController, curve: Curves.easeOut));

    if (widget.clearErrorOnChange) {
      widget.controller.addListener(_handleControllerChanged);
    }
  }

  @override
  void didUpdateWidget(covariant AttentionTextField oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      if (oldWidget.clearErrorOnChange) {
        oldWidget.controller.removeListener(_handleControllerChanged);
      }
      if (widget.clearErrorOnChange) {
        widget.controller.addListener(_handleControllerChanged);
      }
    }
  }

  void _handleControllerChanged() {
    widget.onChanged?.call(widget.controller.text);
    if (_hasError) setState(() => _hasError = false);
  }

  @override
  void dispose() {
    if (widget.clearErrorOnChange) {
      widget.controller.removeListener(_handleControllerChanged);
    }
    _shakeController.dispose();
    super.dispose();
  }

  void clearError() {
    if (_hasError) setState(() => _hasError = false);
  }

  Future<void> triggerInvalid({bool? haptics}) async {
    if ((haptics ?? widget.hapticsOnError)) {
      HapticFeedback.heavyImpact();
    }
    if (!_hasError) setState(() => _hasError = true);
    await _shakeController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final effectiveTextStyle =
        widget.textStyle ??
        textTheme.displaySmall?.copyWith(
          fontSize: 24,
          height: 1.0,
          fontWeight: FontWeight.w800,
        );

    final effectiveHintStyle =
        widget.hintStyle ??
        textTheme.displaySmall?.copyWith(
          fontSize: 18,
          height: 1.0,
          fontWeight: FontWeight.w800,
          color: const Color(0xFFB9C0C8),
        );

    final formatters = <TextInputFormatter>[
      FilteringTextInputFormatter.allow(RegExp(widget.allowPattern)),
      if (widget.uppercase) UpperCaseTextFormatter(),
      LengthLimitingTextInputFormatter(widget.maxLength),
    ];

    return AnimatedBuilder(
      animation: _shakeController,
      builder: (context, child) =>
          Transform.translate(offset: Offset(_shakeX.value, 0), child: child),
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,

        keyboardType: TextInputType.text,
        textCapitalization: TextCapitalization.characters,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.done,
        onSubmitted: widget.onSubmitted,

        inputFormatters: formatters,

        textAlign: TextAlign.center,
        textAlignVertical: TextAlignVertical.center,

        style: effectiveTextStyle,
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: effectiveHintStyle,

          errorText: _hasError ? ' ' : null,
          errorStyle: const TextStyle(fontSize: 0, height: 0),

          prefixIcon: SizedBox(width: widget.sideSpacerWidth),
          prefixIconConstraints: BoxConstraints(
            minWidth: widget.sideSpacerWidth,
          ),
          suffixIcon: SizedBox(width: widget.sideSpacerWidth),
          suffixIconConstraints: BoxConstraints(
            minWidth: widget.sideSpacerWidth,
          ),

          isDense: false,
          contentPadding: widget.contentPadding,
          counterText: '',
        ),
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final upper = newValue.text.toUpperCase();
    return newValue.copyWith(
      text: upper,
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}
