import codecs

path = 'lib/screens/profile_screen.dart'
try:
    with codecs.open(path, 'r', 'utf-8') as f:
        text = f.read()

    # 1. Variables
    text = text.replace('bool _aiIsPolling = false;\n', '')
    text = text.replace('String? _aiUserCode;\n', '')
    text = text.replace('String? _aiDeviceCode;\n', '')
    text = text.replace('Timer? _aiPollTimer;\n', '')
    text = text.replace('  String? _pairingCode;\n  String? _verificationUrl;\n', '')
    text = text.replace('  bool _isConnectingOpenAi = false;\n  String? _openAiError;\n', '')

    # 2. Add deep linking init
    text = text.replace('    _probeEdgeFunctionOnStartup();\n  }', '    _probeEdgeFunctionOnStartup();\n    _initDeepLinks();\n  }')

    # 3. Dispose and _initDeepLinks
    old_dispose = """  @override
  void dispose() {
    _aiPollTimer?.cancel();
    super.dispose();
  }"""
    new_dispose = """  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  void _initDeepLinks() {
    _linkSub = _appLinks.uriLinkStream.listen((uri) {
      if (uri.scheme == 'kynetix' && uri.host == 'openai-auth' && uri.path == '/callback') {
        _finishOpenAiAuth(uri);
      }
    });
  }"""
    text = text.replace(old_dispose, new_dispose)

    # 4. _connectAi and related functions
    start_idx = text.find('  Future<void> _connectAi() async {')
    end_idx = text.find('  Future<void> _disconnectAi() async {')
    if start_idx != -1 and end_idx != -1:
        before = text[:start_idx]
        after = text[end_idx:]
        
        new_connect = """  Future<void> _connectAi() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      setState(() => _aiErrorMessage = 'Session expired. Please sign out and sign in again.');
      return;
    }
    setState(() { _aiIsLoading = true; _aiErrorMessage = null; });
    try {
      final res = await Supabase.instance.client.functions.invoke('openai-link-start');
      final data = res.data;
      if (!mounted) return;
      if (data == null || data['authUrl'] == null) {
        setState(() { _aiIsLoading = false; _aiErrorMessage = 'Server returned invalid response'; });
        return;
      }
      final String authUrl = data['authUrl'].toString();
      setState(() { _aiIsLoading = false; });
      
      final uri = Uri.tryParse(authUrl);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
         setState(() { _aiErrorMessage = 'Failed to parse auth URL.'; });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _aiIsLoading = false; _aiErrorMessage = 'Failed to start auth flow'; });
    }
  }

  Future<void> _finishOpenAiAuth(Uri uri) async {
    final code = uri.queryParameters['code'];
    final state = uri.queryParameters['state'];
    if (code == null || state == null) {
      if (mounted) setState(() => _aiErrorMessage = 'Invalid callback from OpenAI.');
      return;
    }

    setState(() { _aiIsLoading = true; _aiErrorMessage = null; });
    try {
      await Supabase.instance.client.functions.invoke(
        'openai-link-finish',
        body: {'code': code, 'state': state},
      );
      if (!mounted) return;
      setState(() { _aiIsConnected = true; _aiIsLoading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _aiIsLoading = false; _aiErrorMessage = 'Failed to complete authentication'; });
    }
  }

"""
        text = before + new_connect + after

    # 5. Fix UI Code
    start_ui = text.find('  // ── AI Integration')
    end_ui = text.find('  // ── About')
    if start_ui != -1 and end_ui != -1:
        ui_before = text[:start_ui]
        ui_after = text[end_ui:]
        
        new_ui = """  // ── AI Integration ──────────────────────────────────────────────────────────

  Widget _buildAiIntegrationCard() {
    Widget content;

    if (_aiIsLoading) {
      content = const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 24, height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF52B788)),
          ),
        ),
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _aiIsConnected ? Icons.auto_awesome_rounded : Icons.auto_awesome_outlined,
                size: 16,
                color: _aiIsConnected ? const Color(0xFF52B788) : const Color(0xFF6B7280),
              ),
              const SizedBox(width: 8),
              Text(
                _aiIsConnected ? 'Connected to OpenAI' : 'Not Connected',
                style: TextStyle(
                  color: _aiIsConnected ? const Color(0xFF52B788) : const Color(0xFF6B7280),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (_aiIsConnected)
                GestureDetector(
                  onTap: _disconnectAi,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B35).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFFF6B35).withValues(alpha: 0.4)),
                    ),
                    child: const Text('Disconnect', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFFF6B35))),
                  ),
                )
              else
                GestureDetector(
                  onTap: _connectAi,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF52B788).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF52B788).withValues(alpha: 0.4)),
                    ),
                    child: const Text('Connect OpenAI', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF52B788))),
                  ),
                ),
            ],
          ),

          if (_aiErrorMessage != null) ...[
            const SizedBox(height: 8),
            Text(_aiErrorMessage!, style: const TextStyle(fontSize: 12, color: Color(0xFFFF6B35))),
          ],
        ],
      );
    }

    return _Section(
      title: 'AI Integration',
      child: content,
    );
  }

"""
        text = ui_before + new_ui + ui_after

    with codecs.open(path, 'w', 'utf-8') as f:
        f.write(text)
    print("Updated profile_screen.dart")
except Exception as e:
    print("Error:", e)
