import 'package:flutter/material.dart';

import '../models/item.dart';
import '../services/item_service.dart';
import '../widgets/animations.dart';

class AdminEditScreen extends StatefulWidget {
  const AdminEditScreen({super.key, required this.item, this.markReturned = false});
  final Item item;

  /// Opens with the status already set to Returned (after a handover scan).
  final bool markReturned;

  @override
  State<AdminEditScreen> createState() => _AdminEditScreenState();
}

class _AdminEditScreenState extends State<AdminEditScreen> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.item.title);
  late final _description = TextEditingController(text: widget.item.description);
  late String _status = widget.markReturned ? 'returned' : widget.item.status;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      Item? partner;
      if (_status == 'returned') {
        final candidates = await ItemService.instance.likelyPartners(widget.item);
        if (!mounted) return;
        final choice = await _confirmReturn(candidates);
        if (choice == null) return; // cancelled
        partner = choice.partner;
      }
      final deleted = await ItemService.instance.adminUpdate(
        widget.item.id,
        title: _title.text.trim(),
        description: _description.text.trim(),
        status: _status,
        partnerId: partner?.id,
      );
      if (!mounted) return;
      final message = !deleted
          ? 'Item updated.'
          : partner == null
          ? 'Item marked as returned and removed.'
          : 'Returned! Both reports ("${widget.item.title}" and "${partner.title}") were closed.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Asks to confirm the return, offering to close the matching report on the
  /// other side too. Returns null when cancelled.
  Future<({Item? partner})?> _confirmReturn(List<Item> candidates) {
    final otherSide = widget.item.isLost ? 'found' : 'lost';
    Item? selected = candidates.firstOrNull;
    return showDialog<({Item? partner})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Mark as returned?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  candidates.isEmpty
                      ? 'This will remove the report. No matching $otherSide report was found.'
                      : 'Also close the matching $otherSide report? Both are removed and counted as one return.',
                ),
                if (candidates.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  RadioGroup<Item?>(
                    groupValue: selected,
                    onChanged: (v) => setDialog(() => selected = v),
                    child: Column(
                      children: [
                        for (final c in candidates)
                          RadioListTile<Item?>(
                            value: c,
                            contentPadding: EdgeInsets.zero,
                            title: Text(c.title),
                            subtitle: Text(
                              '${c.reporter} · ${c.location}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        const RadioListTile<Item?>(
                          value: null,
                          contentPadding: EdgeInsets.zero,
                          title: Text('Only this report'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(context, (partner: selected)),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              child: const Text('Mark returned'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Item')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _title,
              maxLength: 255,
              decoration: const InputDecoration(labelText: 'Title', counterText: ''),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'The title field is required.' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _description,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Description'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'The description field is required.' : null,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: 'pending', child: Text('Pending')),
                DropdownMenuItem(value: 'returned', child: Text('Returned')),
              ],
              onChanged: (v) => setState(() => _status = v!),
            ),
            const SizedBox(height: 24),
            PressScale(
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: ButtonLabel('Update Item', loading: _saving),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
