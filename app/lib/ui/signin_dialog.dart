import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/core_api.dart';
import '../core/core_controller.dart';
import '../core/models.dart';
import '../l10n/app_localizations.dart';
import 'widgets.dart';

/// Adds an account, or signs one in again: the core runs the sign-in and
/// the dialog shows whatever Mozilla asks for (codes, CAPTCHA, a link).
Future<void> showSignInDialog(
  BuildContext context,
  CoreController core, {
  String email = '',
  SignInState? started,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _SignInDialog(core: core, email: email, started: started),
);

class _SignInDialog extends StatefulWidget {
  const _SignInDialog({required this.core, required this.email, this.started});

  final CoreController core;
  final String email;
  final SignInState? started;

  @override
  State<_SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends State<_SignInDialog> {
  late final _email = TextEditingController(text: widget.email);
  final _password = TextEditingController();
  final _answer = TextEditingController();
  final _form = GlobalKey<FormState>();

  SignInState? _state;
  String? _error;
  bool _sending = false;
  bool _showPassword = false;
  Timer? _poll;

  CoreApi? get _api => widget.core.api;

  @override
  void initState() {
    super.initState();
    if (widget.started != null) _follow(widget.started!);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _email.dispose();
    _password.dispose();
    _answer.dispose();
    super.dispose();
  }

  void _follow(SignInState s) {
    _state = s;
    _poll?.cancel();
    if (s.finished) {
      if (s.step == SignInStep.done) widget.core.refresh(accountsToo: true);
      return;
    }
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _read());
  }

  Future<void> _read() async {
    final id = _state?.id;
    final api = _api;
    if (id == null || api == null) return;
    try {
      final next = await api.signInState(id);
      if (!mounted) return;
      // Keep a typed answer while the step stays the same.
      if (next.step != _state?.step) _answer.clear();
      setState(() => _follow(next));
    } on Exception {
      // The next tick retries; the core may be busy.
    }
  }

  Future<void> _send(Future<SignInState> Function(CoreApi api) call) async {
    final api = _api;
    if (api == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final next = await call(api);
      if (!mounted) return;
      setState(() => _follow(next));
    } on CoreApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on CoreUnavailable catch (e) {
      if (mounted) {
        setState(
          () => _error = describeProblem(AppLocalizations.of(context), e),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _start() {
    if (!_form.currentState!.validate()) return;
    final email = _email.text.trim();
    final password = _password.text;
    _send((api) => api.startSignIn(email, password));
    _password.clear();
  }

  void _submitAnswer() {
    final value = _answer.text.trim();
    final id = _state?.id;
    if (value.isEmpty || id == null) return;
    _send((api) => api.answerSignIn(id, value));
  }

  Future<void> _close() async {
    final s = _state;
    if (s != null && !s.finished) {
      try {
        await _api?.cancelSignIn(s.id);
      } on Exception {
        // The core ends abandoned sign-ins itself.
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _restart() => setState(() {
    _poll?.cancel();
    _state = null;
    _error = null;
    _answer.clear();
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = _state;
    final done = s?.step == SignInStep.done;
    final failed =
        s?.step == SignInStep.failed || s?.step == SignInStep.cancelled;
    return AlertDialog(
      title: Text(
        s == null ? l.addAccount : (s.email.isEmpty ? l.signInTitle : s.email),
      ),
      content: SizedBox(
        width: 400,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: s == null ? _credentials() : _progress(s),
        ),
      ),
      actions: [
        if (done)
          FilledButton(onPressed: _close, child: Text(l.done))
        else ...[
          TextButton(
            onPressed: _close,
            child: Text(failed ? l.close : l.cancel),
          ),
          if (failed)
            FilledButton(onPressed: _restart, child: Text(l.tryAgain))
          else if (s == null)
            FilledButton(
              onPressed: _sending ? null : _start,
              child: Text(l.signIn),
            )
          else if (s.needsAnswer)
            FilledButton(
              onPressed: _sending ? null : _submitAnswer,
              child: Text(l.continueLabel),
            ),
        ],
      ],
    );
  }

  Widget _credentials() {
    final l = AppLocalizations.of(context);
    return Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.signInIntro, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          TextFormField(
            controller: _email,
            autofocus: widget.email.isEmpty,
            keyboardType: TextInputType.emailAddress,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: l.email,
              border: const OutlineInputBorder(),
            ),
            validator: (v) => (v ?? '').contains('@') ? null : l.emailInvalid,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _password,
            autofocus: widget.email.isNotEmpty,
            obscureText: !_showPassword,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: l.password,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _showPassword ? l.hide : l.show,
                icon: Icon(
                  _showPassword ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
            validator: (v) => (v ?? '').isEmpty ? l.passwordEmpty : null,
            onFieldSubmitted: (_) => _start(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _ErrorBox(_error!),
          ],
        ],
      ),
    );
  }

  /// The instruction for a step in the app's language; the core's own
  /// message for steps the app does not know.
  String _instruction(AppLocalizations l, SignInState s) => switch (s.step) {
    SignInStep.needEmailCode => l.stepEmailCode(s.email),
    SignInStep.needTotp => l.stepTotp,
    SignInStep.needUnblockCode => l.stepUnblockCode(s.email),
    SignInStep.needCaptcha => l.stepCaptcha,
    SignInStep.needEmailLink => l.stepEmailLink(s.email),
    SignInStep.working => l.signingIn,
    _ => s.message,
  };

  Widget _progress(SignInState s) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final instruction = _instruction(l, s);
    final error = _error ?? (s.error.isEmpty ? null : s.error);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (s.step == SignInStep.done)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.check_circle_rounded,
              color: StatusColors.good,
              size: 32,
            ),
            title: Text(l.accountReady),
            subtitle: Text(l.accountReadyHint),
          )
        else if (s.step == SignInStep.working ||
            s.step == SignInStep.needEmailLink)
          Row(
            children: [
              const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(instruction, style: theme.textTheme.bodyMedium),
              ),
            ],
          )
        else if (instruction.isNotEmpty)
          Text(instruction, style: theme.textTheme.bodyMedium),
        if (s.step == SignInStep.needCaptcha && s.captcha.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Captcha(dataUrl: s.captcha),
        ],
        if (s.needsAnswer) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _answer,
            autofocus: true,
            decoration: InputDecoration(
              labelText: s.step == SignInStep.needCaptcha
                  ? l.captchaLabel
                  : l.codeLabel,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submitAnswer(),
          ),
        ],
        if (error != null && s.step != SignInStep.done) ...[
          const SizedBox(height: 12),
          _ErrorBox(error),
        ],
      ],
    );
  }
}

class _Captcha extends StatelessWidget {
  const _Captcha({required this.dataUrl});

  final String dataUrl;

  @override
  Widget build(BuildContext context) {
    final comma = dataUrl.indexOf(',');
    try {
      final bytes = base64Decode(dataUrl.substring(comma + 1));
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(bytes, height: 120, fit: BoxFit.contain),
      );
    } on FormatException {
      return _ErrorBox(AppLocalizations.of(context).captchaBroken);
    }
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: StatusColors.bad.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      message,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: StatusColors.bad),
    ),
  );
}
