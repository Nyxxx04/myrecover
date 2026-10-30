import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/claim_service.dart';
import '../services/item_service.dart';
import 'admin_edit_screen.dart';

/// Admin: scan the claimant's QR code (or type the code under it) to confirm
/// the right person is collecting the item, then mark it returned.
class HandoverScanScreen extends StatefulWidget {
  const HandoverScanScreen({super.key});

  @override
  State<HandoverScanScreen> createState() => _HandoverScanScreenState();
}

class _HandoverScanScreenState extends State<HandoverScanScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _lastScanned; // the camera reports the same code many times a second

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    final value = capture.barcodes.firstOrNull?.rawValue;
    if (value == null || value == _lastScanned) return;
    _lastScanned = value;
    _check(value);
  }

  Future<void> _check(String raw) async {
    if (_busy) return;
    final code = raw.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final claim = await ClaimService.instance.claimForCode(code);
      if (claim == null || !claim.isApproved) {
        setState(() => _error = 'This code is not valid.');
        return;
      }
      final item = await ItemService.instance.itemById(claim.itemId);
      if (item == null) {
        setState(() => _error = 'This item was already handed over.');
        return;
      }
      if (!mounted || !await _confirm(claim)) return;
      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => AdminEditScreen(item: item, markReturned: true)),
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not check the code. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(Claim claim) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Code is valid'),
          content: Text(
            'Hand over "${claim.itemTitle}" to ${claim.claimantName} (${claim.claimantContact})?\n\n'
            'Check their student ID first.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              child: const Text('Continue'),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan handover QR')),
    body: Column(
      children: [
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              MobileScanner(
                onDetect: _onDetect,
                errorBuilder: (context, error) => const ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: Text(
                      'Camera not available.\nType the code below instead.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              if (_busy) const CircularProgressIndicator(color: Colors.white),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                TextField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.done,
                  onSubmitted: _check,
                  decoration: InputDecoration(
                    labelText: 'Or type the code',
                    suffixIcon: IconButton(
                      tooltip: 'Check code',
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: _busy ? null : () => _check(_code.text),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
