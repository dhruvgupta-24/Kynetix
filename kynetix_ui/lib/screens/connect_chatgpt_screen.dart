import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/chatgpt_sign_in_button.dart';
import '../config/app_theme.dart';
import '../services/chatgpt_link_service.dart';
import '../services/chatgpt_siwc_service.dart';

// ─── Connect ChatGPT ──────────────────────────────────────────────────────────
//
// Two ways in, one destination: Kyno runs on the user's own ChatGPT plan.
//
//   Primary  "Continue with ChatGPT": official Sign in with ChatGPT (OAuth +
//            PKCE in the system browser, loopback callback). Tokens go
//            straight to the server via `openai-link-siwc`.
//   Fallback "Use a code instead": the existing device-code flow
//            (openai-link-start → poll → verify), unchanged.
//
// States: idle → waiting for browser → connecting → connected ("You're using
// your ChatGPT plan." + "Got it"), or error. The code flow adds its own
// starting / waiting-for-code / verifying states.
//
// Embedded mode (onboarding): no app bar, no route pushes or pops. The host
// gets `onFinished` after a connection or when the user taps "Skip for now".
//
// Motion: one AnimatedSwitcher cross-fade between states; the waiting pulse
// only loops when ambient motion is allowed. The device-code polling Timer is
// real logic, not animation.

class ConnectChatGptScreen extends StatefulWidget {
  const ConnectChatGptScreen({super.key, this.embedded = false, this.onFinished});

  /// Render inline (e.g. inside onboarding) instead of as a pushed page.
  final bool embedded;

  /// Called after a successful connection, or on "Skip for now" (embedded).
  final VoidCallback? onFinished;

  @override
  State<ConnectChatGptScreen> createState() => _ConnectChatGptScreenState();
}

enum _Step {
  idle,
  browserWaiting,
  connecting,
  connected,
  codeStarting,
  codeWaiting,
  codeVerifying,
  error,
}

enum _Method { browser, code }

class _ErrorInfo {
  const _ErrorInfo({
    required this.title,
    required this.message,
    required this.method,
    this.hint,
    this.showManageUsage = false,
    this.offerCode = false,
  });
  final String title;
  final String message;
  final _Method method;
  final String? hint;
  final bool showManageUsage;
  final bool offerCode;
}

class _ConnectChatGptScreenState extends State<ConnectChatGptScreen>
    with WidgetsBindingObserver {
  _Step _step = _Step.idle;
  _ErrorInfo? _error;

  // Browser (Sign in with ChatGPT)
  ChatGptSiwcFlow? _flow;
  SiwcConnectResult? _siwcResult;

  // Device code
  DeviceCodeSession? _session;
  ModelVerificationResult? _verifyResult;
  Timer? _pollTimer;

  _Method _connectedVia = _Method.browser;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _flow?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_step == _Step.codeWaiting) {
        debugPrint('[ConnectChatGpt] App resumed. Triggering immediate poll...');
        _doPoll();
        _startPolling();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _pollTimer?.cancel();
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Browser sign-in (primary)
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _startBrowserFlow() async {
    _flow?.cancel();
    final flow = ChatGptSiwcFlow();
    _flow = flow;
    setState(() {
      _error = null;
      _step = _Step.browserWaiting;
    });

    try {
      final result = await flow.run(
        onPhase: (phase) {
          if (!mounted || !identical(_flow, flow)) return;
          setState(() {
            _step = phase == SiwcPhase.connecting
                ? _Step.connecting
                : _Step.browserWaiting;
          });
        },
      );
      if (!mounted || !identical(_flow, flow)) return;
      setState(() {
        _siwcResult = result;
        _connectedVia = _Method.browser;
        _step = _Step.connected;
      });
      KHaptics.success();
    } on SiwcException catch (e) {
      if (!mounted || !identical(_flow, flow)) return;
      if (e.failure == SiwcFailure.cancelled) {
        setState(() => _step = _Step.idle);
        return;
      }
      debugPrint('[ConnectChatGpt] browser sign-in failed: $e');
      _fail(_browserError(e.failure));
    } catch (e) {
      if (!mounted || !identical(_flow, flow)) return;
      debugPrint('[ConnectChatGpt] browser sign-in error: ${e.runtimeType}');
      _fail(_browserError(SiwcFailure.server));
    } finally {
      if (identical(_flow, flow)) _flow = null;
    }
  }

  void _cancelBrowserFlow() {
    final flow = _flow;
    _flow = null;
    flow?.cancel();
    setState(() => _step = _Step.idle);
  }

  _ErrorInfo _browserError(SiwcFailure f) {
    const m = _Method.browser;
    return switch (f) {
      SiwcFailure.denied => const _ErrorInfo(
        method: m,
        title: 'Sign-in cancelled',
        message: 'Nothing was connected. Try again whenever you\'re ready.',
      ),
      SiwcFailure.timedOut => const _ErrorInfo(
        method: m,
        title: 'Sign-in timed out',
        message:
            'We didn\'t hear back from ChatGPT within 5 minutes. '
            'Try again and finish signing in in your browser.',
        offerCode: true,
      ),
      SiwcFailure.browserUnavailable => const _ErrorInfo(
        method: m,
        title: 'Couldn\'t open your browser',
        message: 'Try again, or use a code instead.',
        offerCode: true,
      ),
      SiwcFailure.listenerUnavailable => const _ErrorInfo(
        method: m,
        title: 'Couldn\'t start sign-in',
        message:
            'This phone blocked the sign-in handoff. Try again, or use a '
            'code instead.',
        offerCode: true,
      ),
      SiwcFailure.securityCheck => const _ErrorInfo(
        method: m,
        title: 'Sign-in didn\'t check out',
        message:
            'That sign-in didn\'t pass a security check, so nothing was '
            'connected. Try again.',
      ),
      SiwcFailure.registrationIncomplete => const _ErrorInfo(
        method: m,
        title: 'Setup didn\'t finish',
        message: 'ChatGPT didn\'t finish setting up Kynetix. Try again.',
      ),
      SiwcFailure.planNotEnabled => const _ErrorInfo(
        method: m,
        title: 'Plan usage is off',
        message:
            'You signed in, but Kynetix wasn\'t allowed to use your ChatGPT '
            'plan. Try again and allow plan usage when ChatGPT asks.',
      ),
      SiwcFailure.notEligible => const _ErrorInfo(
        method: m,
        title: 'Your plan can\'t be used here yet',
        message:
            'ChatGPT says plan usage isn\'t available for this account, '
            'workspace or region. Kyno keeps working on Kynetix servers.',
        showManageUsage: true,
      ),
      SiwcFailure.exchangeFailed => const _ErrorInfo(
        method: m,
        title: 'Sign-in expired',
        message: 'The sign-in expired before we could finish. Try again.',
      ),
      SiwcFailure.network => const _ErrorInfo(
        method: m,
        title: 'No connection',
        message: 'Couldn\'t reach the server. Check your connection and try again.',
      ),
      SiwcFailure.server || SiwcFailure.cancelled => const _ErrorInfo(
        method: m,
        title: 'That didn\'t go through',
        message: 'Try again in a moment, or use a code instead.',
        offerCode: true,
      ),
    };
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Device code (secondary, unchanged flow)
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _startCodeFlow() async {
    _flow?.cancel();
    _flow = null;
    setState(() {
      _step = _Step.codeStarting;
      _error = null;
      _session = null;
    });

    try {
      final session = await ChatGptLinkService.startLink();
      if (!mounted) return;
      setState(() {
        _session = session;
        _step = _Step.codeWaiting;
      });

      // Open the verification URL (auth.openai.com/codex/device) right away.
      await _openVerificationUrl();
      _startPolling();
    } on DeviceCodeDisabledException catch (_) {
      if (!mounted) return;
      _fail(const _ErrorInfo(
        method: _Method.code,
        title: 'Code sign-in is off',
        message: 'Your ChatGPT account has code sign-in turned off.',
        hint:
            'In ChatGPT, open Settings → Security and turn on "Device code '
            'authorization", then try again.',
      ));
    } catch (e) {
      if (!mounted) return;
      debugPrint('[ConnectChatGpt] code start failed: ${e.runtimeType}');
      _fail(const _ErrorInfo(
        method: _Method.code,
        title: 'Couldn\'t get a code',
        message: 'That didn\'t go through. Try again in a moment.',
      ));
    }
  }

  Future<void> _openVerificationUrl() async {
    final urlStr = _session?.verificationUrl;
    if (urlStr == null || urlStr.isEmpty) return;
    final uri = Uri.tryParse(urlStr);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[ConnectChatGpt] Could not launch browser: $e');
    }
  }

  void _startPolling() {
    if (_session == null) return;
    final interval = Duration(seconds: _session!.intervalSeconds.clamp(3, 10));
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(interval, (_) => _doPoll());
    _doPoll();
  }

  Future<void> _doPoll() async {
    if (_session == null || !mounted || _step != _Step.codeWaiting) return;

    if (DateTime.now().isAfter(_session!.expiresAt)) {
      _pollTimer?.cancel();
      _fail(const _ErrorInfo(
        method: _Method.code,
        title: 'That code expired',
        message: 'Codes last 15 minutes. Try again for a fresh one.',
      ));
      return;
    }

    try {
      final result = await ChatGptLinkService.pollLink(_session!.sessionId);
      if (!mounted || _step != _Step.codeWaiting) return;

      switch (result.status) {
        case LinkPollStatus.connected:
          _pollTimer?.cancel();
          await _runVerification();
        case LinkPollStatus.expired:
          _pollTimer?.cancel();
          _fail(const _ErrorInfo(
            method: _Method.code,
            title: 'That code expired',
            message: 'Try again for a fresh one.',
          ));
        case LinkPollStatus.error:
          _pollTimer?.cancel();
          debugPrint('[ConnectChatGpt] poll error: ${result.message}');
          _fail(const _ErrorInfo(
            method: _Method.code,
            title: 'That didn\'t go through',
            message: 'We couldn\'t finish linking with that code. Try again.',
          ));
        case LinkPollStatus.pending:
          break;
      }
    } catch (e) {
      // Don't stop polling on transient network errors.
      debugPrint('[ConnectChatGpt] Poll error (transient): $e');
    }
  }

  Future<void> _runVerification() async {
    if (!mounted) return;
    setState(() => _step = _Step.codeVerifying);

    try {
      final result = await ChatGptLinkService.verifyAndSelectModel();
      if (!mounted) return;
      if (result.success) {
        setState(() {
          _verifyResult = result;
          _connectedVia = _Method.code;
          _step = _Step.connected;
        });
        KHaptics.success();
      } else {
        debugPrint('[ConnectChatGpt] verify failed: ${result.error}');
        _fail(_ErrorInfo(
          method: _Method.code,
          title: 'Connected, but no reply yet',
          message: result.error == 'no_chat_models'
              ? 'Your account linked, but no chat models showed up for it. '
                    'Kyno keeps working on Kynetix servers.'
              : 'Your account linked, but Kyno couldn\'t get a reply from '
                    'ChatGPT. Kyno keeps working on Kynetix servers. Try again '
                    'in a moment.',
        ));
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('[ConnectChatGpt] verify error: ${e.runtimeType}');
      _fail(const _ErrorInfo(
        method: _Method.code,
        title: 'That didn\'t go through',
        message: 'Try again in a moment.',
      ));
    }
  }

  void _cancelCodeFlow() {
    _pollTimer?.cancel();
    setState(() => _step = _Step.idle);
  }

  void _copyCode() {
    if (_session?.userCode == null) return;
    Clipboard.setData(ClipboardData(text: _session!.userCode));
    KHaptics.select();
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.clearSnackBars();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          'Code copied.',
          style: KText.bodyMedium.copyWith(color: KColor.onInk),
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: KColor.ink,
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Shared
  // ══════════════════════════════════════════════════════════════════════════

  void _fail(_ErrorInfo info) {
    if (!mounted) return;
    KHaptics.reject();
    setState(() {
      _error = info;
      _step = _Step.error;
    });
  }

  Future<void> _openManageUsage() async {
    try {
      await launchUrl(
        Uri.parse(ChatGptLinkService.manageUsageUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('[ConnectChatGpt] Could not open usage settings: $e');
    }
  }

  void _finish() {
    widget.onFinished?.call();
    if (!widget.embedded && mounted) Navigator.of(context).maybePop();
  }

  void _skip() => widget.onFinished?.call();

  void _leave() {
    if (widget.embedded) {
      setState(() => _step = _Step.idle);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // UI
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final switchDuration = KMotion.of(context, KMotion.standard);
    final body = AnimatedSwitcher(
      duration: switchDuration,
      reverseDuration: switchDuration,
      switchInCurve: KMotion.decelerate,
      switchOutCurve: KMotion.accelerate,
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.03),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(_step), child: _buildBody()),
    );

    if (widget.embedded) {
      return Material(type: MaterialType.transparency, child: body);
    }

    return KPage(
      tone: KTone.kyno,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: Icon(Icons.arrow_back_rounded, color: KColor.textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text('ChatGPT', style: KText.h2),
      ),
      body: SafeArea(top: false, child: body),
    );
  }

  Widget _buildBody() {
    return switch (_step) {
      _Step.idle => _buildIdleView(),
      _Step.browserWaiting => _buildBrowserWaitingView(),
      _Step.connecting => _buildLoadingView('Checking your plan…', forCode: false),
      _Step.connected => _buildConnectedView(),
      _Step.codeStarting => _buildLoadingView('Getting your code…', forCode: true),
      _Step.codeWaiting => _buildCodeWaitingView(),
      _Step.codeVerifying => _buildLoadingView('Checking your account…', forCode: false),
      _Step.error => _buildErrorView(),
    };
  }

  /// Full-height scroll column: a [Spacer] can pin actions to the bottom on
  /// tall screens, and content scrolls instead of overflowing on large text.
  Widget _scrollShell(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: KSpacing.p,
          vertical: KSpacing.lg,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (box.maxHeight - KSpacing.lg * 2).clamp(
              0.0,
              double.infinity,
            ),
          ),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
  }

  // ── Idle ──────────────────────────────────────────────────────────────────

  Widget _buildIdleView() {
    return _scrollShell([
      const SizedBox(height: KSpacing.sm),
      const Align(
        alignment: AlignmentDirectional.centerStart,
        child: _LinkMark(),
      ),
      const SizedBox(height: KSpacing.xl),
      Text(
        'Run Kyno on your ChatGPT plan',
        style: KText.display.copyWith(fontSize: 30, height: 1.1),
      ),
      const SizedBox(height: KSpacing.sm),
      Text(
        'Connect ChatGPT and Kyno\'s coaching, meal estimates and insights '
        'run on your own plan.',
        style: KText.body.copyWith(color: KColor.textSecondary, fontSize: 15, height: 1.5),
      ),
      const SizedBox(height: KSpacing.xl),
      // Three plain facts between rules: no card.
      Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: KColor.textPrimary, width: 1.5),
            bottom: BorderSide(color: KColor.fg.withValues(alpha: 0.1)),
          ),
        ),
        child: Column(
          children: [
            _infoRow(
              Icons.data_usage_rounded,
              'Your plan, your limits',
              'Kyno\'s AI requests count toward your ChatGPT usage, not a '
                  'Kynetix bill.',
            ),
            const _Hairline(indent: 36),
            _infoRow(
              Icons.swap_horiz_rounded,
              'Never stuck',
              'Hit a limit and Kyno switches to Kynetix servers until your '
                  'plan is back.',
            ),
            const _Hairline(indent: 36),
            _infoRow(
              Icons.lock_outline_rounded,
              'Private and reversible',
              'Your ChatGPT sign-in is kept on Kynetix\'s server, never on '
                  'this phone. Disconnect any time in Settings.',
            ),
          ],
        ),
      ),
      const Spacer(),
      const SizedBox(height: KSpacing.xxl),
      ContinueWithChatGptButton(onTap: _startBrowserFlow),
      const SizedBox(height: KSpacing.sm),
      _quietButton('Use a code instead', _startCodeFlow),
      if (widget.embedded) ...[
        _quietButton('Skip for now', _skip),
        Text(
          'You can do this later in Settings.',
          textAlign: TextAlign.center,
          style: KText.caption.copyWith(color: KColor.textMuted),
        ),
      ],
      const SizedBox(height: KSpacing.sm),
    ]);
  }

  // ── Waiting for the browser ───────────────────────────────────────────────

  Widget _buildBrowserWaitingView() {
    return _scrollShell([
      const SizedBox(height: KSpacing.sm),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: _headerIcon(Icons.open_in_browser_rounded, KColor.textPrimary),
      ),
      const SizedBox(height: KSpacing.xl),
      Text('Finish in your browser', style: KText.h1),
      const SizedBox(height: KSpacing.sm),
      Text(
        'Sign in to ChatGPT and allow Kynetix to use your plan. When the page '
        'says you\'re done, come back here.',
        style: KText.body.copyWith(color: KColor.textSecondary),
      ),
      const SizedBox(height: KSpacing.xl),
      _noteBox(
        icon: Icons.info_outline_rounded,
        text:
            'Kynetix never sees your ChatGPT password. You can pick which '
            'account to use on the ChatGPT page.',
      ),
      const Spacer(),
      const SizedBox(height: KSpacing.xl),
      Semantics(
        liveRegion: true,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const _PulseDot(),
            const SizedBox(width: KSpacing.md),
            Flexible(
              child: Text(
                'Waiting for ChatGPT…',
                textAlign: TextAlign.center,
                style: KText.caption.copyWith(color: KColor.textSecondary),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: KSpacing.sm),
      _quietButton('Cancel', _cancelBrowserFlow),
      const SizedBox(height: KSpacing.sm),
    ]);
  }

  // ── Device code: waiting ──────────────────────────────────────────────────

  Widget _buildCodeWaitingView() {
    final code = _session?.userCode ?? '';
    final urlStr =
        _session?.verificationUrl ?? 'https://auth.openai.com/codex/device';
    final interval = _session?.intervalSeconds ?? 5;

    return _scrollShell([
      const SizedBox(height: KSpacing.sm),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: _headerIcon(Icons.devices_rounded, KColor.textPrimary),
      ),
      const SizedBox(height: KSpacing.xl),
      Text('Enter this code in ChatGPT', style: KText.h1),
      const SizedBox(height: KSpacing.sm),
      Text(
        'We opened the ChatGPT page in your browser. Sign in and type the '
        'code below.',
        style: KText.body.copyWith(color: KColor.textSecondary),
      ),
      const SizedBox(height: KSpacing.xl),

      // The code: this view's one hero.
      Pressable(
        onTap: _copyCode,
        scale: 0.98,
        borderRadius: KRadius.xl,
        semanticLabel: 'Code $code. Tap to copy',
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: KSpacing.xxl,
            horizontal: KSpacing.xl,
          ),
          decoration: BoxDecoration(
            borderRadius: KRadius.xl,
            color: KColor.card,
            border: Border.all(
              color: KColor.fg.withValues(alpha: KColor.isDark ? 0.12 : 0.1),
            ),
            boxShadow: KShadow.card,
          ),
          child: Column(
            children: [
              Text('Your code', style: KText.label),
              const SizedBox(height: KSpacing.md),
              Text(
                code,
                textAlign: TextAlign.center,
                style: KText.numDisplay.copyWith(
                  fontSize: 32,
                  letterSpacing: 1.0,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: KSpacing.lg),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: KSpacing.md,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: KColor.ink,
                  borderRadius: KRadius.pill,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.copy_rounded, size: 14, color: KColor.onInk),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Tap to copy',
                        style: KText.caption.copyWith(
                          color: KColor.onInk,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),

      const SizedBox(height: KSpacing.md),

      // Reopen the page in case the tab got closed.
      Pressable(
        onTap: _openVerificationUrl,
        borderRadius: KRadius.md,
        semanticLabel: 'Open $urlStr in browser',
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(
            vertical: KSpacing.md,
            horizontal: KSpacing.lg,
          ),
          decoration: BoxDecoration(
            color: KColor.card,
            borderRadius: KRadius.md,
            border: Border.all(color: KColor.fg.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.open_in_browser_rounded,
                size: 18,
                color: KColor.textSecondary,
              ),
              const SizedBox(width: KSpacing.md),
              Expanded(
                child: Text(
                  urlStr,
                  style: KText.caption.copyWith(
                    color: KColor.textPrimary,
                    decoration: TextDecoration.underline,
                    decorationColor: KColor.fg.withValues(alpha: 0.35),
                  ),
                ),
              ),
              const SizedBox(width: KSpacing.sm),
              Icon(Icons.north_east_rounded, size: 14, color: KColor.textMuted),
            ],
          ),
        ),
      ),

      const SizedBox(height: KSpacing.lg),
      _noteBox(
        icon: Icons.settings_rounded,
        text:
            'Code sign-in needs "Device code authorization" turned on in '
            'ChatGPT → Settings → Security.',
      ),
      const Spacer(),
      const SizedBox(height: KSpacing.xl),
      Semantics(
        liveRegion: true,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const _PulseDot(),
            const SizedBox(width: KSpacing.md),
            Flexible(
              child: Text(
                'Checking every $interval seconds…',
                textAlign: TextAlign.center,
                style: KText.caption.copyWith(
                  color: KColor.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: KSpacing.sm),
      _quietButton('Cancel', _cancelCodeFlow),
      const SizedBox(height: KSpacing.sm),
    ]);
  }

  // ── Loading ───────────────────────────────────────────────────────────────
  // Skeletons shaped like what's coming.

  Widget _buildLoadingView(String label, {required bool forCode}) {
    return _scrollShell([
      const SizedBox(height: KSpacing.sm),
      const Align(
        alignment: AlignmentDirectional.centerStart,
        child: KShimmerBox(width: 60, height: 60, borderRadius: KRadius.lg),
      ),
      const SizedBox(height: KSpacing.xl),
      Semantics(
        liveRegion: true,
        child: Text(label, style: KText.h2.copyWith(color: KColor.textSecondary)),
      ),
      const SizedBox(height: KSpacing.md),
      const KShimmerBox(
        width: double.infinity,
        height: 14,
        borderRadius: KRadius.sm,
      ),
      const SizedBox(height: KSpacing.sm),
      const FractionallySizedBox(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: 0.6,
        child: KShimmerBox(
          width: double.infinity,
          height: 14,
          borderRadius: KRadius.sm,
        ),
      ),
      const SizedBox(height: KSpacing.xl),
      if (forCode)
        const KShimmerBox(
          width: double.infinity,
          height: 150,
          borderRadius: KRadius.xl,
        )
      else
        const KCardShimmer(height: 120),
      const Spacer(),
    ]);
  }

  // ── Connected ─────────────────────────────────────────────────────────────

  Widget _buildConnectedView() {
    final viaPlan = _connectedVia == _Method.browser;
    final siwc = _siwcResult;
    final firstTime = viaPlan && (siwc?.firstTimePlanUse ?? false);
    final limited = viaPlan && (siwc?.usageLimited ?? false);
    final model = viaPlan ? siwc?.model : _verifyResult?.selectedModel;

    final title = viaPlan
        ? (firstTime ? 'You\'re using your ChatGPT plan.' : 'ChatGPT connected.')
        : 'ChatGPT connected.';
    final message = viaPlan
        ? 'Kyno\'s AI requests now run on your ChatGPT plan. You can check '
              'and manage usage in ChatGPT settings any time.'
        : 'Kyno now runs on your ChatGPT account. Disconnect any time in '
              'Settings.';

    return _scrollShell([
      const SizedBox(height: KSpacing.sm),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: _headerIcon(Icons.check_circle_rounded, KColor.green),
      ),
      const SizedBox(height: KSpacing.xl),
      Semantics(
        liveRegion: true,
        header: true,
        child: Text(title, style: KText.h1),
      ),
      const SizedBox(height: KSpacing.sm),
      Text(message, style: KText.body.copyWith(color: KColor.textSecondary)),
      const SizedBox(height: KSpacing.xl),
      KCard(
        padding: const EdgeInsets.all(KSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow('Status', viaPlan ? 'Using ChatGPT plan' : 'Connected'),
            if (model != null && model.isNotEmpty) ...[
              const _Hairline(vertical: KSpacing.md),
              _detailRow('Model', model),
            ],
          ],
        ),
      ),
      if (limited) ...[
        const SizedBox(height: KSpacing.md),
        _noteBox(
          icon: Icons.hourglass_bottom_rounded,
          text:
              'You\'re at your ChatGPT usage limit right now. Kyno uses '
              'Kynetix servers until your plan has room again.',
        ),
      ],
      if (viaPlan) ...[
        const SizedBox(height: KSpacing.sm),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: _manageUsageLink(),
        ),
      ],
      const Spacer(),
      const SizedBox(height: KSpacing.xxl),
      KButton(
        label: 'Got it',
        icon: Icons.check_rounded,
        onTap: _finish,
        width: double.infinity,
      ),
      const SizedBox(height: KSpacing.md),
    ]);
  }

  // ── Error ─────────────────────────────────────────────────────────────────

  Widget _buildErrorView() {
    final e = _error ??
        const _ErrorInfo(
          method: _Method.browser,
          title: 'That didn\'t go through',
          message: 'Try again in a moment.',
        );
    final retry = e.method == _Method.code ? _startCodeFlow : _startBrowserFlow;

    return _scrollShell([
      const SizedBox(height: KSpacing.sm),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: _headerIcon(Icons.error_outline_rounded, KColor.danger),
      ),
      const SizedBox(height: KSpacing.xl),
      Text('Not connected', style: KText.h1),
      const SizedBox(height: KSpacing.md),
      Semantics(
        liveRegion: true,
        child: KErrorCard(title: e.title, message: e.message),
      ),
      if (e.hint != null) ...[
        const SizedBox(height: KSpacing.md),
        _noteBox(icon: Icons.settings_rounded, text: e.hint!),
      ],
      if (e.showManageUsage) ...[
        const SizedBox(height: KSpacing.sm),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: _manageUsageLink(),
        ),
      ],
      const Spacer(),
      const SizedBox(height: KSpacing.xxl),
      KButton(
        label: 'Try again',
        icon: Icons.refresh_rounded,
        onTap: retry,
        width: double.infinity,
      ),
      const SizedBox(height: KSpacing.sm),
      if (e.offerCode) _quietButton('Use a code instead', _startCodeFlow),
      if (e.method == _Method.code)
        _quietButton('Continue with ChatGPT instead', _startBrowserFlow),
      if (widget.embedded)
        _quietButton('Skip for now', _skip)
      else
        _quietButton('Cancel', _leave),
    ]);
  }

  // ── Pieces ────────────────────────────────────────────────────────────────

  Widget _quietButton(String label, VoidCallback onTap) {
    return Center(
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
        child: Text(
          label,
          style: KText.bodyMedium.copyWith(
            color: KColor.textSecondary,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _manageUsageLink() {
    return TextButton.icon(
      onPressed: _openManageUsage,
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: KSpacing.sm),
      ),
      icon: Icon(Icons.north_east_rounded, size: 16, color: KColor.textPrimary),
      label: Text(
        'Manage usage',
        style: KText.bodyMedium.copyWith(
          color: KColor.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _headerIcon(IconData icon, Color color) {
    final neutral = color == KColor.textPrimary;
    return ExcludeSemantics(
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: neutral
              ? KColor.card
              : color.withValues(alpha: KColor.isDark ? 0.12 : 0.09),
          borderRadius: KRadius.lg,
          border: Border.all(
            color: neutral
                ? KColor.fg.withValues(alpha: KColor.isDark ? 0.1 : 0.08)
                : color.withValues(alpha: 0.3),
          ),
          boxShadow: KShadow.card,
        ),
        child: Icon(icon, color: color, size: 28),
      ),
    );
  }

  Widget _infoRow(IconData icon, String title, String body) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: KSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: KIcon(icon, size: KIcons.md, color: KColor.textPrimary),
          ),
          const SizedBox(width: KSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: KText.bodyMedium.copyWith(
                    color: KColor.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: KText.caption.copyWith(
                    color: KColor.textSecondary,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _noteBox({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.all(KSpacing.md),
      decoration: BoxDecoration(
        color: KColor.fg.withValues(alpha: KColor.isDark ? 0.05 : 0.04),
        borderRadius: KRadius.md,
        border: Border.all(color: KColor.fg.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 16, color: KColor.textSecondary),
          ),
          const SizedBox(width: KSpacing.md),
          Expanded(
            child: Text(
              text,
              style: KText.caption.copyWith(
                color: KColor.textPrimary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: KText.caption.copyWith(color: KColor.textMuted),
          ),
        ),
        const SizedBox(width: KSpacing.md),
        Expanded(
          flex: 2,
          child: Text(
            value,
            style: KText.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: KColor.textPrimary,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

// ─── Link mark ────────────────────────────────────────────────────────────────
// Kyno's monochrome mark joined to ChatGPT (an outlined conversation glyph)
// by a short rule: the idle view's single signature element. Decorative.

class _LinkMark extends StatelessWidget {
  const _LinkMark();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const KynoMark(size: 44),
          Container(
            width: 28,
            height: 1.5,
            margin: const EdgeInsets.symmetric(horizontal: KSpacing.sm),
            color: KColor.fg.withValues(alpha: 0.35),
          ),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: KColor.fg.withValues(alpha: 0.55), width: 1.2),
            ),
            child: Icon(
              Icons.chat_bubble_outline_rounded,
              color: KColor.textPrimary,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Waiting pulse ────────────────────────────────────────────────────────────
// Mounted only while waiting, so its controller lives exactly as long as the
// waiting state. Loops only when ambient motion is allowed (off under reduced
// motion and in tests); otherwise it's a steady dot.

class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: KMotion.celebrate,
    );
    _pulseAnim = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (KMotion.ambientAllowed(context)) {
      if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: 20,
          child: AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, _) {
              final v = _pulseAnim.value;
              return Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 10 + 10 * v,
                    height: 10 + 10 * v,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: KColor.green.withValues(
                        alpha: 0.22 * (1 - v) + 0.04,
                      ),
                    ),
                  ),
                  Opacity(
                    opacity: 0.65 + 0.35 * v,
                    child: KGlowDot(color: KColor.green, size: 8),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─── Hairline ─────────────────────────────────────────────────────────────────

class _Hairline extends StatelessWidget {
  const _Hairline({this.indent = 0, this.vertical = 0});
  final double indent;
  final double vertical;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: indent,
        top: vertical,
        bottom: vertical,
      ),
      child: Container(
        height: 1,
        color: KColor.fg.withValues(alpha: KColor.isDark ? 0.07 : 0.08),
      ),
    );
  }
}
