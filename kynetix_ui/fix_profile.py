import sys

path = r'c:\Users\Dhruv\Desktop\Kynetix\kynetix_ui\lib\screens\profile_screen.dart'

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

print('File chars:', len(content))
print('_connectAi present:', '_connectAi' in content)
print('_startPolling present:', '_startPolling' in content)
print('_disconnectAi present:', '_disconnectAi' in content)

# Find the exact marker to insert after
marker = '  Future<void> _doSync()'
idx = content.find(marker)
print('_doSync index:', idx)
if idx == -1:
    print('ERROR: cannot find _doSync')
    sys.exit(1)

print('Context before marker:')
print(repr(content[idx-60:idx]))

insert = '''  Future<void> _connectAi() async {
    final session = Supabase.instance.client.auth.currentSession;
    final user = Supabase.instance.client.auth.currentUser;
    debugPrint('[_connectAi] session null: ${session == null} | user: ${user?.id ?? "NULL"}');
    if (session == null) {
      setState(() => _aiErrorMessage = 'Session expired. Please sign out and sign in again.');
      return;
    }
    setState(() { _aiIsLoading = true; _aiErrorMessage = null; });
    try {
      final res = await Supabase.instance.client.functions.invoke(\'openai-link-start\');
      debugPrint(\'=== OPENAI START RESPONSE ===\");
      debugPrint(\'status: ${res.status}\');
      debugPrint(\'data: ${res.data}\');
      debugPrint(\'error: ${res.error}\');
      debugPrint(\'=============================\");
      final data = res.data;
      if (!mounted) return;
      if (data == null) {
        setState(() { _aiIsLoading = false; _aiErrorMessage = \'Server returned empty response\'; });
        return;
      }
      debugPrint(\'[_connectAi] interval type: ${data["interval"].runtimeType}\');
      final String? userCode = data[\'userCode\']?.toString();
      final String? deviceCode = data[\'deviceCode\']?.toString();
      final String? verificationUrl = data[\'verificationUrl\']?.toString();
      final int interval = data[\'interval\'] != null ? (data[\'interval\'] as num).toInt() : 5;
      setState(() {
        _aiUserCode = userCode;
        _aiDeviceCode = deviceCode;
        _aiVerificationUrl = verificationUrl;
        _aiIsLoading = false;
        _aiIsPolling = true;
      });
      debugPrint(\'[_connectAi] SUCCESS userCode: $userCode interval: $interval\');
      if (verificationUrl != null && verificationUrl.isNotEmpty) {
        final uri = Uri.tryParse(verificationUrl);
        if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      _startPolling(interval);
    } catch (e, st) {
      debugPrint(\'[_connectAi] EXCEPTION ${e.runtimeType}: $e\');
      debugPrint(st.toString());
      if (!mounted) return;
      setState(() { _aiIsLoading = false; _aiErrorMessage = \'Failed to start pairing\'; });
    }
  }

  void _startPolling(int intervalSeconds) {
    _aiPollTimer?.cancel();
    _aiPollTimer = Timer.periodic(Duration(seconds: intervalSeconds), (timer) async {
      try {
        final res = await Supabase.instance.client.functions.invoke(
          \'openai-link-poll\',
          body: {\'device_code\': _aiDeviceCode},
        );
        final status = res.data[\'status\'];
        if (status == \'connected\') {
          timer.cancel();
          if (!mounted) return;
          setState(() { _aiIsConnected = true; _aiIsPolling = false; _aiUserCode = null; _aiDeviceCode = null; _aiVerificationUrl = null; });
        } else if (status == \'expired\') {
          timer.cancel();
          if (!mounted) return;
          setState(() { _aiIsPolling = false; _aiErrorMessage = \'Code expired. Please try again.\'; _aiUserCode = null; _aiDeviceCode = null; _aiVerificationUrl = null; });
        }
      } catch (e) {}
    });
  }

  Future<void> _disconnectAi() async {
    setState(() { _aiIsLoading = true; });
    try {
      await Supabase.instance.client.functions.invoke(\'openai-link-disconnect\');
      if (!mounted) return;
      setState(() { _aiIsConnected = false; _aiIsLoading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _aiIsLoading = false; _aiErrorMessage = \'Failed to disconnect\'; });
    }
  }

'''

new_content = content[:idx] + insert + content[idx:]

with open(path, 'w', encoding='utf-8') as f:
    f.write(new_content)

print('Written. New length:', len(new_content))
for m in ['_connectAi', '_startPolling', '_disconnectAi']:
    print(m, 'present:', m in new_content)
