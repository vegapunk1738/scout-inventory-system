import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scout_stock/presentation/widgets/attention_text_field_widget.dart';
import 'package:scout_stock/presentation/widgets/dotted_background.dart';
import 'package:scout_stock/presentation/widgets/glowing_action_button.dart';
import 'package:scout_stock/state/providers/auth_providers.dart';
import 'package:scout_stock/theme/app_theme.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();

  final _identifierKey = GlobalKey<AttentionTextFieldState>();
  final _passwordKey = GlobalKey<AttentionTextFieldState>();

  final _identifierFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  bool _obscurePassword = true;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    _identifierFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final identifier = _identifierController.text.trim();
    final password = _passwordController.text;

    final idValid = _isValidScoutIdOrFullName(identifier);
    final pwValid = password.trim().isNotEmpty;

    if (!idValid) {
      _identifierFocusNode.requestFocus();
      await _identifierKey.currentState?.triggerInvalid();
      return;
    }

    if (!pwValid) {
      _passwordFocusNode.requestFocus();
      await _passwordKey.currentState?.triggerInvalid();
      return;
    }

    FocusScope.of(context).unfocus();

    final ok = await ref
        .read(authControllerProvider.notifier)
        .login(identifier: identifier, password: password);

    if (!mounted) return;

    if (!ok) {
      _passwordFocusNode.requestFocus();
      await _passwordKey.currentState?.triggerInvalid();

      final auth = ref.read(authControllerProvider);
      final message = auth.hasError ? auth.error.toString() : 'Login failed.';

      // ScaffoldMessenger.of(
      //   context,
      // ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  bool _isValidScoutIdOrFullName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;

    final scoutId = RegExp(r'^\d+$');
    final fullName = RegExp(
      r"^[A-Za-z]+(?:-[A-Za-z]+)? [A-Za-z]+(?:-[A-Za-z]+)?$",
    );

    return scoutId.hasMatch(trimmed) || fullName.hasMatch(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final loading = auth.isLoading;
    final textTheme = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<AppTokens>()!;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          const Positioned.fill(child: DottedBackground()),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 150),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),

                      Center(
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: const Color(0xFFD9E1E8),
                              width: 1.5,
                            ),
                            boxShadow: tokens.cardShadow,
                          ),
                          alignment: Alignment.center,
                          child: Image.asset(
                            'assets/images/scout_stock_logo.png',
                            width: 80,
                            height: 80,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),

                      const SizedBox(height: 22),

                      Center(
                        child: Text(
                          'Scout Stock',
                          style: textTheme.displaySmall?.copyWith(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            height: 1.0,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),

                      const SizedBox(height: 10),

                      Center(
                        child: Text(
                          'Bucket-based Scout inventory system',
                          style: textTheme.titleMedium?.copyWith(
                            color: AppColors.muted,
                            fontWeight: FontWeight.w700,
                            height: 1.15,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),

                      const SizedBox(height: 34),

                      _FieldLabel('SCOUT ID OR FULL NAME'),
                      const SizedBox(height: 12),

                      AttentionTextField(
                        key: _identifierKey,
                        controller: _identifierController,
                        focusNode: _identifierFocusNode,
                        hintText: 'Enter ID or full name',
                        centeredLayout: false,
                        uppercase: false,
                        maxLength: 40,
                        allowPattern: r"[A-Za-z0-9 -]",
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.words,
                        textAlign: TextAlign.left,
                        onSubmitted: (_) => _passwordFocusNode.requestFocus(),
                        suffixIcon: const Padding(
                          padding: EdgeInsets.only(right: 16),
                          child: Icon(
                            Icons.person_rounded,
                            color: Color(0xFFA0A8B8),
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      _FieldLabel('PASSWORD'),
                      const SizedBox(height: 12),

                      AttentionTextField(
                        key: _passwordKey,
                        controller: _passwordController,
                        focusNode: _passwordFocusNode,
                        hintText: 'Enter password',
                        centeredLayout: false,
                        uppercase: false,
                        allowPattern: r"[ -~]",
                        maxLength: 64,
                        keyboardType: TextInputType.visiblePassword,
                        textInputAction: TextInputAction.done,
                        textCapitalization: TextCapitalization.none,
                        textAlign: TextAlign.left,
                        obscureText: _obscurePassword,
                        onSubmitted: (_) => _submit(),
                        suffixIcon: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: IconButton(
                            splashRadius: 22,
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.lock_rounded
                                  : Icons.visibility_rounded,
                              color: const Color(0xFFA0A8B8),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: RichText(
                          text: TextSpan(
                            style: textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              height: 1.2,
                              color: AppColors.muted,
                            ),
                            children: const [
                              TextSpan(
                                text: 'Forget Password?',
                                style: TextStyle(color: AppColors.primary),
                              ),
                              TextSpan(
                                text: ' Ask an admin to reset password.',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlowingActionButton(
            label: 'Login',
            icon: const Icon(Icons.arrow_forward_rounded),
            loading: loading,
            onPressed: loading ? null : _submit,
            respectKeyboardInset: false,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 2, 24, 20),
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: textTheme.bodyLarge?.copyWith(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  fontSize: 14,
                ),
                children: const [
                  TextSpan(
                    text: 'New account?',
                    style: TextStyle(color: AppColors.primary),
                  ),
                  TextSpan(text: ' Ask an admin to set you up.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.labelMedium?.copyWith(color: AppColors.ink),
    );
  }
}
