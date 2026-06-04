import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/chatgpt_link_service.dart';

// ─── Connect ChatGPT Screen — Device-Code Auth Flow ───────────────────────────
//
// Flow:
//   Step 1: User taps "Connect" → calls openai-link-start
//   Step 2: Shows user_code + opens chatgpt.com/device
//   Step 3: Auto-polls every interval_seconds for auth completion
//   Step 4: On connected → calls openai-link-verify (model discovery)
//   Step 5: Shows discovery results + success state

class ConnectChatGptScreen extends StatefulWidget {
  const ConnectChatGptScreen({super.key});

  @override
  State<ConnectChatGptScreen> createState() => _ConnectChatGptScreenState();
}

enum _FlowStep { idle, starting, waitingAndPolling, verifying, success, error }

class _ConnectChatGptScreenState extends State<ConnectChatGptScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  _FlowStep _step = _FlowStep.idle;
  DeviceCodeSession? _session;
  ModelVerificationResult? _verifyResult;
  String? _errorMessage;
  Timer? _pollTimer;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[ConnectChatGpt] App resumed. Triggering immediate poll...');
      if (_step == _FlowStep.waitingAndPolling) {
        _doPoll();
        _startPolling();
      }
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      debugPrint('[ConnectChatGpt] App backgrounded. Pausing poll timer.');
      _pollTimer?.cancel();
    }
  }

  // ── Step 1: Start the flow ───────────────────────────────────────────────────

  Future<void> _startFlow() async {
    setState(() { _step = _FlowStep.starting; _errorMessage = null; });

    try {
      final session = await ChatGptLinkService.startLink();
      if (!mounted) return;
      setState(() { _session = session; _step = _FlowStep.waitingAndPolling; });

      // Automatically open the verification URL in the browser.
      // The correct URL is auth.openai.com/codex/device (returned by OpenAI API).
      await _openVerificationUrl();

      // Automatically start background polling
      _startPolling();
    } on DeviceCodeDisabledException catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _FlowStep.error;
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _FlowStep.error;
        _errorMessage = 'Failed to start: ${e.toString().replaceFirst('Exception: ', '')}';
      });
    }
  }

  // ── Open verification URL in browser ────────────────────────────────────────

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

  // ── Step 2: Start background polling ───────────────────────────────────────

  void _startPolling() {
    if (_session == null) return;
    final interval = Duration(seconds: _session!.intervalSeconds.clamp(3, 10));
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(interval, (_) => _doPoll());
    // Poll immediately on first call
    _doPoll();
  }

  Future<void> _doPoll() async {
    if (_session == null || !mounted) return;

    // Timeout after ~15 minutes (the session TTL)
    if (DateTime.now().isAfter(_session!.expiresAt)) {
      _pollTimer?.cancel();
      if (mounted) {
        setState(() {
          _step = _FlowStep.error;
          _errorMessage = 'Authorization timed out. Please try again.';
        });
      }
      return;
    }

    try {
      final result = await ChatGptLinkService.pollLink(_session!.sessionId);
      if (!mounted) return;

      switch (result.status) {
        case LinkPollStatus.connected:
          _pollTimer?.cancel();
          await _runVerification();
        case LinkPollStatus.expired:
          _pollTimer?.cancel();
          setState(() {
            _step = _FlowStep.error;
            _errorMessage = 'Session expired. Please try again.';
          });
        case LinkPollStatus.error:
          _pollTimer?.cancel();
          setState(() {
            _step = _FlowStep.error;
            _errorMessage = result.message ?? 'Polling failed. Please try again.';
          });
        case LinkPollStatus.pending:
          break; // still waiting, continue polling
      }
    } catch (e) {
      // Don't stop polling on transient network errors
      debugPrint('[ConnectChatGpt] Poll error (transient): $e');
    }
  }

  // ── Step 3: Run model verification after connection ────────────────────────

  Future<void> _runVerification() async {
    if (!mounted) return;
    setState(() => _step = _FlowStep.verifying);

    try {
      final result = await ChatGptLinkService.verifyAndSelectModel();
      if (!mounted) return;
      setState(() {
        _verifyResult = result;
        _step = result.success ? _FlowStep.success : _FlowStep.error;
        if (!result.success) {
          _errorMessage = result.error == 'no_chat_models'
              ? 'No chat-capable models found on this account. API access may not be enabled.'
              : result.error == 'generation_failed'
                  ? 'Account authenticated but verification failed. Falling back to Kynetix shared servers.'
                  : result.error ?? 'Verification failed.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _FlowStep.error;
        _errorMessage = 'Verification error: $e';
      });
    }
  }

  // ── Copy user_code to clipboard ────────────────────────────────────────────

  void _copyCode() {
    if (_session?.userCode == null) return;
    Clipboard.setData(ClipboardData(text: _session!.userCode));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Code copied to clipboard'),
        duration: Duration(seconds: 2),
        backgroundColor: Color(0xFF52B788),
      ),
    );
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF13131F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF13131F),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Connect ChatGPT',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return switch (_step) {
      _FlowStep.idle       => _buildIdleView(),
      _FlowStep.starting   => _buildLoadingView('Starting authentication…'),
      _FlowStep.waitingAndPolling => _buildWaitingAndPollingView(),
      _FlowStep.verifying  => _buildLoadingView('Setting up analysis service…'),
      _FlowStep.success    => _buildSuccessView(),
      _FlowStep.error      => _buildErrorView(),
    };
  }

  // ── Idle ──────────────────────────────────────────────────────────────────

  Widget _buildIdleView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _buildHeaderIcon(Icons.account_circle_rounded, const Color(0xFF52B788)),
        const SizedBox(height: 24),
        const Text(
          'Connect Your ChatGPT Account',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Use your own OpenAI/ChatGPT account for AI coaching. '
          'Your credits, your custom settings, your data.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 14,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 28),
        _buildBenefitRow(Icons.model_training_rounded, 'Optimal analysis engine selected automatically'),
        const SizedBox(height: 10),
        _buildBenefitRow(Icons.lock_rounded, 'Your credentials stay server-side only'),
        const SizedBox(height: 10),
        _buildBenefitRow(Icons.credit_card_rounded, 'Your ChatGPT credits, not Kynetix\'s'),
        const SizedBox(height: 10),
        _buildBenefitRow(Icons.swap_horiz_rounded, 'Falls back to backup Kynetix server if needed'),
        const SizedBox(height: 36),
        _buildWarningBox(
          icon: Icons.settings_rounded,
          text: 'Before connecting: open chatgpt.com → Settings → Security → '
              'enable "Device code authorization". This is required once.',
        ),
        const Spacer(),
        _buildPrimaryButton(
          label: 'Connect ChatGPT Account',
          icon: Icons.arrow_forward_rounded,
          onTap: _startFlow,
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  // ── Waiting and Polling combined view ──────────────────────────────────────

  Widget _buildWaitingAndPollingView() {
    final code    = _session?.userCode ?? '';
    final urlStr  = _session?.verificationUrl ?? 'https://auth.openai.com/codex/device';
    final interval = _session?.intervalSeconds ?? 5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _buildHeaderIcon(Icons.devices_rounded, const Color(0xFF60A5FA)),
        const SizedBox(height: 24),
        const Text(
          'Authorize on ChatGPT',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'A browser tab has been opened for you. '
          'Sign in to ChatGPT and enter the code below:',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 14,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 28),

        // User code display
        GestureDetector(
          onTap: _copyCode,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2C),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xFF60A5FA).withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
            child: Column(
              children: [
                Text(
                  code,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 8,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.copy_rounded, size: 13, color: Color(0xFF60A5FA)),
                    const SizedBox(width: 4),
                    Text(
                      'Tap to copy',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Re-open browser button (in case user dismissed the tab)
        GestureDetector(
          onTap: _openVerificationUrl,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2C),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF60A5FA).withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.open_in_browser_rounded, size: 14, color: Color(0xFF60A5FA)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    urlStr,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF60A5FA),
                      decoration: TextDecoration.underline,
                      decorationColor: Color(0xFF60A5FA),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),
        _buildWarningBox(
          icon: Icons.info_outline_rounded,
          text: 'Enter the code at the page that opened in your browser. '
              'Once authorized, Kynetix will automatically detect completion.',
        ),
        const Spacer(),

        // Dynamic background polling status indicator
        Center(
          child: Column(
            children: [
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, child) => Opacity(
                  opacity: _pulseAnim.value,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF52B788),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Checking status every $interval seconds...',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  _pollTimer?.cancel();
                  setState(() => _step = _FlowStep.idle);
                },
                child: Text(
                  'Cancel & Start Over',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  // ── Loading ───────────────────────────────────────────────────────────────

  Widget _buildLoadingView(String label) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Color(0xFF52B788),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  // ── Success ───────────────────────────────────────────────────────────────

  Widget _buildSuccessView() {
    final r = _verifyResult;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _buildHeaderIcon(Icons.check_circle_rounded, const Color(0xFF52B788)),
        const SizedBox(height: 24),
        const Text(
          'Connected & Verified',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Your ChatGPT account is connected. Generation has been verified.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 14,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 24),

        // Model discovery report card
        if (r != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2C),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _reportRow('Selected AI Engine', r.selectedModel ?? '—', highlight: true),
                const Divider(color: Color(0xFF2E2E3E), height: 20),
                _reportRow('Optimization Reason', r.selectionReason ?? '—'),
                const Divider(color: Color(0xFF2E2E3E), height: 20),
                _reportRow(
                  'Supported AI Engines',
                  '${r.chatModelsFound.length} engine${r.chatModelsFound.length == 1 ? '' : 's'}',
                ),
                if (r.chatModelsFound.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...r.chatModelsFound.map(
                    (m) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(
                            m == r.selectedModel
                                ? Icons.star_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 12,
                            color: m == r.selectedModel
                                ? const Color(0xFF52B788)
                                : Colors.white.withValues(alpha: 0.3),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            m,
                            style: TextStyle(
                              fontSize: 12,
                              color: m == r.selectedModel
                                  ? const Color(0xFF52B788)
                                  : Colors.white.withValues(alpha: 0.55),
                              fontWeight: m == r.selectedModel
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (r.testSnippet != null) ...[
                  const Divider(color: Color(0xFF2E2E3E), height: 20),
                  Text(
                    'Test Generation',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '"${r.testSnippet}"',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF52B788),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],

        const Spacer(),
        _buildPrimaryButton(
          label: 'Done',
          icon: Icons.check_rounded,
          onTap: () => Navigator.of(context).pop(),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  // ── Error ─────────────────────────────────────────────────────────────────

  Widget _buildErrorView() {
    final isDisabledError = _errorMessage?.toLowerCase().contains('device code') == true ||
        _errorMessage?.toLowerCase().contains('enable') == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _buildHeaderIcon(Icons.error_outline_rounded, const Color(0xFFFF6B6B)),
        const SizedBox(height: 24),
        const Text(
          'Connection Failed',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFF6B6B).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFFF6B6B).withValues(alpha: 0.25),
            ),
          ),
          child: Text(
            _errorMessage ?? 'An unexpected error occurred.',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFFFFAAAA),
              height: 1.5,
            ),
          ),
        ),
        if (isDisabledError) ...[
          const SizedBox(height: 16),
          _buildWarningBox(
            icon: Icons.settings_rounded,
            text: 'Go to chatgpt.com/settings → Security → '
                'enable "Device code authorization", then try again.',
          ),
        ],
        const Spacer(),
        _buildPrimaryButton(
          label: 'Try Again',
          icon: Icons.refresh_rounded,
          onTap: () => setState(() { _step = _FlowStep.idle; _errorMessage = null; }),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 13,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Shared UI components ──────────────────────────────────────────────────

  Widget _buildHeaderIcon(IconData icon, Color color) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Icon(icon, color: color, size: 28),
    );
  }

  Widget _buildBenefitRow(IconData icon, String text) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: const Color(0xFF52B788).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: const Color(0xFF52B788)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWarningBox({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFB347).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFFB347).withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: const Color(0xFFFFB347)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFFFB347),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    Color color = const Color(0xFF52B788),
  }) {
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Icon(icon, size: 16, color: color),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reportRow(String label, String value, {bool highlight = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.45),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
              color: highlight ? const Color(0xFF52B788) : Colors.white,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
