import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../theme.dart';

/// Checks the latest GitHub release. To ship a fix: bump `version:` in
/// pubspec.yaml, build the APK, and publish it as a release tagged `vX.Y.Z`.
class UpdateService {
  UpdateService._();

  static const _latestRelease =
      'https://api.github.com/repos/Nyxxx04/myrecover/releases/latest';
  static bool _checked = false;

  /// Shows the update dialog once per app launch when a newer release exists.
  static Future<void> checkAndPrompt(BuildContext context) async {
    if (_checked || !Platform.isAndroid) return;
    _checked = true;
    final update = await _findUpdate();
    if (update == null || !context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Theme.of(context).cardTheme.color,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        reverseDuration: Duration(milliseconds: 300),
      ),
      builder: (_) => _UpdateDialog(update: update),
    );
  }

  static Future<_Update?> _findUpdate() async {
    try {
      final res = await http
          .get(Uri.parse(_latestRelease))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final latest = (data['tag_name'] as String? ?? '').replaceFirst(
        RegExp('^v'),
        '',
      );
      final current = (await PackageInfo.fromPlatform()).version;
      if (!_isNewer(latest, current)) return null;

      final apks = [
        for (final a in data['assets'] as List? ?? const [])
          if ((a['name'] as String).toLowerCase().endsWith('.apk'))
            a as Map<String, dynamic>,
      ];
      if (apks.isEmpty) return null;
      final apk = apks.firstWhere(
        (a) => (a['name'] as String).contains('arm64'),
        orElse: () => apks.first,
      );
      return _Update(
        latest,
        apk['browser_download_url'] as String,
        (data['body'] as String? ?? '').trim(),
      );
    } catch (_) {
      return null; // offline or GitHub unreachable: just skip this time
    }
  }

  static bool _isNewer(String remote, String current) {
    List<int> parts(String v) =>
        v.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final r = parts(remote), c = parts(current);
    for (var i = 0; i < 3; i++) {
      final rv = i < r.length ? r[i] : 0, cv = i < c.length ? c[i] : 0;
      if (rv != cv) return rv > cv;
    }
    return false;
  }
}

class _Update {
  _Update(this.version, this.apkUrl, this.notes);
  final String version;
  final String apkUrl;
  final String notes;
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.update});
  final _Update update;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress; // null = not downloading
  bool _handedOff = false; // Android's installer was opened at least once
  String? _error;

  void _start() {
    setState(() {
      _progress = 0;
      _error = null;
    });
    OtaUpdate()
        .execute(
          widget.update.apkUrl,
          destinationFilename: 'MyRecover-${widget.update.version}.apk',
        )
        .listen(
          (event) {
            if (!mounted) return;
            switch (event.status) {
              case OtaStatus.DOWNLOADING:
                setState(
                  () => _progress =
                      (double.tryParse(event.value ?? '') ?? 0) / 100,
                );
              // Android's installer takes over. The dialog stays open: the first
              // time, Android asks for permission and drops the install, so the
              // user can tap Install again.
              case OtaStatus.INSTALLING:
              case OtaStatus.INSTALLATION_DONE:
                setState(() {
                  _progress = null;
                  _handedOff = true;
                });
              case OtaStatus.CANCELED:
                setState(() => _progress = null);
              default:
                setState(() {
                  _progress = null;
                  _error =
                      'Update failed (${event.status.name.toLowerCase().replaceAll('_', ' ')}). Try again.';
                });
            }
          },
          onError: (_) {
            if (mounted) {
              setState(() {
                _progress = null;
                _error = 'Download failed. Check your internet connection.';
              });
            }
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    final downloading = _progress != null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Icon(
              Icons.system_update_rounded,
              size: 44,
              color: context.brandText,
            ),
            const SizedBox(height: 12),
            const Text(
              'Update available',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'MyRecover ${widget.update.version} is ready with the latest fixes.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.mutedText),
            ),
            if (widget.update.notes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                widget.update.notes,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
            if (downloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _progress == 0 ? null : _progress,
                color: context.brandText,
              ),
              const SizedBox(height: 6),
              Text(
                'Downloading… ${(_progress! * 100).round()}%',
                style: const TextStyle(fontSize: 12),
              ),
            ],
            if (_handedOff && !downloading && _error == null) ...[
              const SizedBox(height: 12),
              const Text(
                'Tap Install on Android\'s prompt. If you just allowed MyRecover to install apps, tap Install again.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: downloading
                      ? null
                      : () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(130, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Later'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: downloading ? null : _start,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(130, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(_handedOff ? 'Install' : 'Update'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
