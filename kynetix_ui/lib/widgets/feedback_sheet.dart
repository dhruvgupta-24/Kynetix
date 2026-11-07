import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../config/app_theme.dart';
import '../services/feedback_service.dart';
import '../ui/k_segmented.dart';
import '../ui/k_toast.dart';
import '../services/analytics_service.dart';

// ─── Feedback sheet ───────────────────────────────────────────────────────────
// "Talk to us": pick a kind, say it, add up to three screenshots or photos
// if it helps, send. On success the sheet closes with a
// toast and a success haptic. On failure it stays open, keeps the text, and
// says what happened under the field.

/// Opens the feedback sheet over [context].
Future<void> showFeedbackSheet(BuildContext context) {
  KHaptics.select();
  return showKSheet<void>(
    context: context,
    builder: (_) => FeedbackSheet(email: FeedbackService.instance.accountEmail),
  );
}

class FeedbackSheet extends StatefulWidget {
  const FeedbackSheet({super.key, this.email, this.send, this.pickPhotos});

  /// The account's email, offered as the reply address. No email, no offer.
  final String? email;

  /// Sends the feedback. Defaults to [FeedbackService.submit]; tests swap it.
  final Future<void> Function({
    required FeedbackKind kind,
    required String message,
    String? replyTo,
    List<Uint8List> photos,
  })? send;

  /// Picks photos, at most [limit]. Defaults to the camera or gallery via
  /// image_picker; tests swap it.
  final Future<List<Uint8List>> Function(BuildContext context, int limit)? pickPhotos;

  @override
  State<FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<FeedbackSheet> {
  final _text = TextEditingController();
  FeedbackKind _kind = FeedbackKind.idea;
  bool _replyOk = true;
  final List<Uint8List> _photos = [];
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _addPhotos() async {
    if (_sending) return;
    final remaining = FeedbackService.maxPhotos - _photos.length;
    if (remaining <= 0) return;
    KHaptics.select();
    final toaster = KToaster.of(context);
    final pick = widget.pickPhotos ?? _pickWithImagePicker;
    List<Uint8List> picked;
    try {
      picked = await pick(context, remaining);
    } catch (e) {
      debugPrint('[FEEDBACK] photo pick failed: $e');
      toaster.show("Couldn't open that photo. Try another one.", kind: KToastKind.error);
      return;
    }
    if (!mounted || picked.isEmpty) return;
    var skipped = 0;
    final ok = <Uint8List>[];
    for (final b in picked) {
      if (ok.length >= remaining) break;
      if (FeedbackService.imageType(b) == null || b.length > FeedbackService.maxPhotoBytes) {
        skipped++;
      } else {
        ok.add(b);
      }
    }
    setState(() => _photos.addAll(ok));
    if (skipped > 0) {
      toaster.show(
        skipped == 1 ? 'One photo was too big or not a JPG or PNG.' : '$skipped photos were too big or not a JPG or PNG.',
        kind: KToastKind.error,
      );
    }
  }

  static Future<List<Uint8List>> _pickWithImagePicker(BuildContext context, int limit) async {
    final source = await showKSheet<ImageSource>(
      context: context,
      builder: (ctx) {
        Widget option(IconData icon, String label, ImageSource src) => ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: KSpacing.p),
              leading: Icon(icon, color: KColor.textPrimary),
              title: Text(label, style: KText.bodyMedium.copyWith(fontSize: 15)),
              onTap: () => Navigator.of(ctx).pop(src),
            );
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: KSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const KSheetHeader('Add a photo', subtitle: 'A screenshot of the problem helps most'),
                option(Icons.photo_library_rounded, 'Choose from gallery', ImageSource.gallery),
                option(Icons.camera_alt_rounded, 'Take photo', ImageSource.camera),
              ],
            ),
          ),
        );
      },
    );
    if (source == null) return const [];
    final picker = ImagePicker();
    final List<XFile> files;
    if (source == ImageSource.camera || limit == 1) {
      final f = await picker.pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 80);
      files = f == null ? const [] : [f];
    } else {
      files = await picker.pickMultiImage(maxWidth: 1600, maxHeight: 1600, imageQuality: 80, limit: limit);
    }
    return [for (final f in files.take(limit)) await f.readAsBytes()];
  }

  void _removePhoto(int i) {
    if (_sending) return;
    KHaptics.select();
    setState(() => _photos.removeAt(i));
  }

  Future<void> _submit() async {
    if (_sending) return;
    if (_text.text.trim().isEmpty) {
      KHaptics.reject();
      setState(() => _error = 'Say something first. Even one line.');
      return;
    }
    final toaster = KToaster.of(context);
    final navigator = Navigator.of(context);
    final send = widget.send ?? FeedbackService.instance.submit;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await send(
        kind: _kind,
        message: _text.text,
        replyTo: _replyOk ? widget.email : null,
        photos: List.unmodifiable(_photos),
      );
      AnalyticsService.instance.track('feedback_sent', {'kind': _kind.code, 'photos': _photos.length});
      KHaptics.success();
      if (navigator.mounted) navigator.pop();
      toaster.show('Got it. Straight to the team.', kind: KToastKind.success);
    } catch (e) {
      debugPrint('[FEEDBACK] send failed: $e');
      if (!mounted) return;
      final signedOut = e.toString().contains('not authenticated');
      setState(() {
        _sending = false;
        _error = signedOut
            ? 'Sign in again, then send it.'
            : "Didn't go through. Check your connection and try again.";
      });
    }
  }

  OutlineInputBorder _border(Color c) =>
      OutlineInputBorder(borderRadius: KRadius.md, borderSide: BorderSide(color: c));

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final email = widget.email;
    final edge = KColor.isDark ? KColor.fg.withValues(alpha: 0.08) : KColor.border;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: KSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const KSheetHeader(
                'Say it straight',
                subtitle: 'Ideas, bugs, love letters. We read every one.',
              ),
              const SizedBox(height: KSpacing.md),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: KSpacing.p),
                child: KSegmented<FeedbackKind>(
                  dense: true,
                  segments: [for (final k in FeedbackKind.values) KSegment(k, k.label)],
                  value: _kind,
                  onChanged: (k) {
                    if (_sending) return;
                    setState(() => _kind = k);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.md, KSpacing.p, 0),
                child: TextField(
                  controller: _text,
                  enabled: !_sending,
                  maxLength: FeedbackService.maxMessageLength,
                  minLines: 4,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                  style: KText.body.copyWith(fontSize: 15, height: 1.4),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  decoration: InputDecoration(
                    hintText: _kind.hint,
                    hintStyle: KText.body.copyWith(color: KColor.textMuted),
                    filled: true,
                    fillColor: KShade.field,
                    contentPadding: const EdgeInsets.all(KSpacing.md),
                    border: _border(edge),
                    enabledBorder: _border(edge),
                    focusedBorder: _border(KColor.textSecondary),
                    disabledBorder: _border(edge),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.xs, KSpacing.p, KSpacing.xs),
                child: _PhotoStrip(
                  photos: _photos,
                  enabled: !_sending,
                  onAdd: _addPhotos,
                  onRemove: _removePhoto,
                ),
              ),
              if (email != null)
                MergeSemantics(
                  child: InkWell(
                    onTap: _sending
                        ? null
                        : () {
                            KHaptics.select();
                            setState(() => _replyOk = !_replyOk);
                          },
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.xs, KSpacing.md, KSpacing.xs),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                text: 'You can reply to me at ',
                                children: [
                                  TextSpan(text: email, style: TextStyle(color: KColor.textPrimary, fontWeight: FontWeight.w600)),
                                ],
                              ),
                              style: KText.caption.copyWith(fontSize: 13, color: KColor.textSecondary),
                            ),
                          ),
                          const SizedBox(width: KSpacing.sm),
                          Switch(
                            value: _replyOk,
                            activeThumbColor: KColor.onInk,
                            activeTrackColor: KColor.ink,
                            inactiveThumbColor: KColor.textMuted,
                            inactiveTrackColor: KColor.fg.withValues(alpha: KColor.isDark ? 0.08 : 0.07),
                            trackOutlineColor: WidgetStatePropertyAll(KColor.fg.withValues(alpha: KColor.isDark ? 0.09 : 0.1)),
                            onChanged: _sending
                                ? null
                                : (v) {
                                    KHaptics.select();
                                    setState(() => _replyOk = v);
                                  },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              AnimatedSize(
                duration: KMotion.of(context, KMotion.quick),
                alignment: Alignment.topCenter,
                child: _error == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.xs, KSpacing.p, 0),
                        child: Semantics(
                          liveRegion: true,
                          child: Row(
                            children: [
                              Icon(Icons.info_outline_rounded, size: 16, color: KColor.danger),
                              const SizedBox(width: KSpacing.sm),
                              Expanded(
                                child: Text(_error!, style: KText.caption.copyWith(fontSize: 13, color: KColor.danger)),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: KSpacing.md),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: KSpacing.p),
                child: KButton(
                  label: 'Send',
                  icon: Icons.arrow_upward_rounded,
                  loading: _sending,
                  onTap: _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The attached photos as small rounded tiles, each with a remove button,
/// then an add tile while there is room. Sunken like the text field above
/// it, so it reads as part of the same form.
class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({required this.photos, required this.enabled, required this.onAdd, required this.onRemove});

  final List<Uint8List> photos;
  final bool enabled;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  static const double _tile = 64;

  @override
  Widget build(BuildContext context) {
    final edge = KColor.isDark ? KColor.fg.withValues(alpha: 0.08) : KColor.border;
    final room = photos.length < FeedbackService.maxPhotos;
    return Row(
      children: [
        for (final (i, bytes) in photos.indexed) ...[
          Semantics(
            label: 'Photo ${i + 1} of ${photos.length}',
            image: true,
            child: SizedBox(
              width: _tile,
              height: _tile,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: KRadius.sm,
                        border: Border.all(color: edge),
                        boxShadow: KShadow.lifted,
                      ),
                      child: ClipRRect(
                        borderRadius: KRadius.sm,
                        child: Image.memory(bytes, fit: BoxFit.cover, cacheWidth: 192, gaplessPlayback: true),
                      ),
                    ),
                  ),
                  Positioned(
                    top: -10,
                    right: -10,
                    child: Semantics(
                      button: true,
                      label: 'Remove photo ${i + 1}',
                      excludeSemantics: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: enabled ? () => onRemove(i) : null,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: KColor.surface,
                              border: Border.all(color: edge),
                              boxShadow: KShadow.lifted,
                            ),
                            child: Icon(Icons.close_rounded, size: 14, color: KColor.textPrimary),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: KSpacing.sm + 2),
        ],
        if (room)
          Expanded(
            child: Semantics(
              button: true,
              label: photos.isEmpty ? 'Add a photo or screenshot' : 'Add another photo',
              excludeSemantics: true,
              child: InkWell(
                onTap: enabled ? onAdd : null,
                borderRadius: KRadius.sm,
                child: Container(
                  height: _tile,
                  padding: const EdgeInsets.symmetric(horizontal: KSpacing.md),
                  decoration: BoxDecoration(
                    color: KShade.field,
                    borderRadius: KRadius.sm,
                    border: Border.all(color: edge),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.add_photo_alternate_outlined, size: 20, color: KColor.textSecondary),
                      const SizedBox(width: KSpacing.sm),
                      Expanded(
                        child: Text(
                          photos.isEmpty ? 'Add a screenshot or photo' : 'Add another',
                          style: KText.bodyMedium.copyWith(fontSize: 14, color: KColor.textSecondary),
                        ),
                      ),
                      if (photos.isEmpty) ...[
                        const SizedBox(width: KSpacing.sm),
                        Text('Up to ${FeedbackService.maxPhotos}', style: KText.caption.copyWith(fontSize: 12, color: KColor.textMuted)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
