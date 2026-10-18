import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../ui/k_toast.dart';
import '../services/account_deletion_service.dart';
import 'auth_gate.dart';

/// Settings → Delete account. Explains what goes, asks the user to type
/// DELETE, then deletes the account on the server, then (only on success)
/// this account's data on the phone, then signs out to the sign-in screen.
class AccountDeletionScreen extends StatefulWidget {
  const AccountDeletionScreen({super.key, this.service, this.onDeleted});

  /// Defaults to [AccountDeletionService.instance].
  final AccountDeletionService? service;

  /// Called after a successful deletion instead of the default (back to
  /// sign-in with a confirmation).
  final VoidCallback? onDeleted;

  static const deletedMessage = 'Your account and data are deleted.';

  @override
  State<AccountDeletionScreen> createState() => _AccountDeletionScreenState();
}

class _AccountDeletionScreenState extends State<AccountDeletionScreen> {
  final _confirmCtrl = TextEditingController();
  bool _deleting = false;
  String? _error;

  bool get _confirmed => AccountDeletionService.isConfirmed(_confirmCtrl.text);

  @override
  void initState() {
    super.initState();
    _confirmCtrl.addListener(_onTyped);
  }

  void _onTyped() {
    if (_error != null) _error = null;
    setState(() {});
  }

  @override
  void dispose() {
    _confirmCtrl.removeListener(_onTyped);
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (!_confirmed || _deleting) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _deleting = true;
      _error = null;
    });
    // Captured before the await: this screen is gone once we navigate.
    final toaster = KToaster.of(context);
    final navigator = Navigator.of(context);
    try {
      await (widget.service ?? AccountDeletionService.instance).deleteAccount();
    } on AccountDeletionException catch (e) {
      if (!mounted) return;
      KHaptics.reject();
      setState(() {
        _deleting = false;
        _error = e.message;
      });
      return;
    } catch (_) {
      if (!mounted) return;
      KHaptics.reject();
      setState(() {
        _deleting = false;
        _error = AccountDeletionService.failureMessage;
      });
      return;
    }

    final onDeleted = widget.onDeleted;
    if (onDeleted != null) {
      onDeleted();
      return;
    }
    navigator.pushAndRemoveUntil(
      kFadeThroughRoute(builder: (_) => const AuthGate()),
      (route) => false,
    );
    toaster.show(
      AccountDeletionScreen.deletedMessage,
      kind: KToastKind.success,
      duration: const Duration(seconds: 6),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // No leaving mid-deletion: the result must land somewhere.
      canPop: !_deleting,
      child: KPage(
        tone: KTone.neutral,
        intensity: 0.5,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          leading: _deleting
              ? null
              : IconButton(
                  tooltip: 'Back',
                  icon: Icon(Icons.arrow_back_rounded, color: KColor.textPrimary),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
          title: Text('Delete account', style: KText.h3.copyWith(fontSize: 16)),
          centerTitle: false,
        ),
        body: SafeArea(
          top: false,
          child: AnimatedSwitcher(
            duration: KMotion.of(context, KMotion.standard),
            switchInCurve: KMotion.decelerate,
            switchOutCurve: KMotion.accelerate,
            child: _deleting
                ? const KLoaderPanel(
                    key: ValueKey('deleting'),
                    semanticsLabel: 'Deleting your account',
                    messages: ['Deleting your account…'],
                  )
                : _buildForm(),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      key: const ValueKey('form'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(KSpacing.xl, KSpacing.md, KSpacing.xl, KSpacing.xxxl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text('Delete your account', style: KText.display.copyWith(fontSize: 30)),
              ),
              const SizedBox(height: KSpacing.sm),
              Text(
                'This deletes everything, from this phone and from our servers:',
                style: KText.body.copyWith(color: KColor.textSecondary, fontSize: 15, height: 1.5),
              ),
              const SizedBox(height: KSpacing.lg),
              // What goes, as a ruled list between a heavy and a light rule.
              Container(
                padding: const EdgeInsets.symmetric(vertical: KSpacing.md),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: KColor.textPrimary, width: 1.5),
                    bottom: BorderSide(color: KColor.fg.withValues(alpha: 0.1)),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    _Gone(icon: Icons.restaurant_rounded, text: 'Every meal you logged, with its calories and macros'),
                    _Gone(icon: Icons.fitness_center_rounded, text: 'Your workouts, sets and progress'),
                    _Gone(icon: Icons.person_outline_rounded, text: 'Your profile, targets and settings'),
                    _Gone(icon: Icons.link_off_rounded, text: 'Your ChatGPT link'),
                    _Gone(
                      icon: Icons.delete_sweep_outlined,
                      text: 'Saved meals, food memories, insights and everything else',
                      last: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: KSpacing.lg),
              _Warning(),
              const SizedBox(height: KSpacing.xl),
              Text(
                'Type DELETE to confirm',
                style: KText.bodyMedium.copyWith(color: KColor.textPrimary, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: KSpacing.sm),
              TextField(
                key: const ValueKey('delete-confirm-field'),
                controller: _confirmCtrl,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _delete(),
                style: KText.bodyMedium.copyWith(fontSize: 16, letterSpacing: 1.0),
                decoration: InputDecoration(
                  hintText: 'DELETE',
                  hintStyle: KText.bodyMedium.copyWith(color: KColor.textMuted, fontSize: 16),
                  filled: true,
                  fillColor: KColor.fg.withValues(alpha: KColor.isDark ? 0.05 : 0.04),
                  contentPadding: const EdgeInsets.symmetric(horizontal: KSpacing.lg, vertical: 16),
                  border: OutlineInputBorder(
                    borderRadius: KRadius.sm,
                    borderSide: BorderSide(color: KColor.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: KRadius.sm,
                    borderSide: BorderSide(color: KColor.fg.withValues(alpha: KColor.isDark ? 0.12 : 0.14)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: KRadius.sm,
                    borderSide: BorderSide(color: KColor.danger, width: 1.4),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: KSpacing.md),
                Semantics(
                  liveRegion: true,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline_rounded, color: KColor.danger, size: 18),
                      const SizedBox(width: KSpacing.sm),
                      Expanded(
                        child: Text(
                          _error!,
                          style: KText.body.copyWith(color: KColor.danger, fontSize: 13.5, height: 1.45),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: KSpacing.xl),
              KButton(
                label: 'Delete my account',
                icon: Icons.delete_forever_rounded,
                color: KColor.danger,
                width: double.infinity,
                onTap: _confirmed ? _delete : null,
              ),
              const SizedBox(height: KSpacing.md),
              KButton(
                label: 'Keep my account',
                outlined: true,
                width: double.infinity,
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Gone extends StatelessWidget {
  const _Gone({required this.icon, required this.text, this.last = false});
  final IconData icon;
  final String text;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : KSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Icon(icon, size: 18, color: KColor.textSecondary)),
          const SizedBox(width: KSpacing.md),
          Expanded(
            child: Text(
              text,
              style: KText.body.copyWith(color: KColor.textPrimary, fontSize: 14, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final dark = KColor.isDark;
    return Container(
      padding: const EdgeInsets.all(KSpacing.lg),
      decoration: BoxDecoration(
        color: KColor.danger.withValues(alpha: dark ? 0.10 : 0.06),
        borderRadius: KRadius.md,
        border: Border.all(color: KColor.danger.withValues(alpha: dark ? 0.35 : 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Icon(Icons.warning_amber_rounded, color: KColor.danger, size: 20)),
          const SizedBox(width: KSpacing.md),
          Expanded(
            child: Text(
              "This can't be undone. Once it's deleted, we can't bring any of it back.",
              style: KText.bodyMedium.copyWith(color: KColor.textPrimary, fontSize: 14, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
