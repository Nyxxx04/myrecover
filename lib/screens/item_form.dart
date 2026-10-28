import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../models/app_user.dart';
import '../models/item.dart';
import '../services/ai_service.dart';
import '../services/claim_service.dart';
import '../services/item_service.dart';
import '../widgets/ai_widgets.dart';
import '../widgets/animations.dart';
import '../theme.dart';
import '../widgets/location_picker.dart';

/// Photos are stored inside the Firestore document (1 MiB limit), so they
/// are resized and compressed when picked.
const _maxImageBase64Length = 900 * 1024;

/// "Report an Item" form, used by users (as a tab) and admins (as a page).
/// Adding a photo lets AI fill in the details and check it for private data.
class ItemForm extends StatefulWidget {
  const ItemForm({super.key, required this.user, required this.onSaved, this.submitLabel = 'Submit Report'});

  final AppUser user;
  final VoidCallback onSaved;
  final String submitLabel;

  @override
  State<ItemForm> createState() => _ItemFormState();
}

class _ItemFormState extends State<ItemForm> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _location = TextEditingController();
  final _secret = TextEditingController();
  String _type = 'lost';
  String _category = itemCategories.first;
  bool _categoryTouched = false;
  DateTime? _date;
  LatLng? _point;
  Uint8List? _image;
  bool _saving = false;
  bool _aiBusy = false;
  bool _aiFilled = false;

  @override
  void dispose() {
    for (final c in [_title, _description, _location, _secret]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 800, maxHeight: 800, imageQuality: 70);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (base64Encode(bytes).length > _maxImageBase64Length) {
      _toast('That photo is too large. Please choose a smaller one.');
      return;
    }
    setState(() => _image = bytes);
    _analyzePhoto(bytes);
  }

  /// Fills empty fields from the photo (or all of them when [overwrite]) and
  /// warns when the photo shows ID/bank card details.
  Future<void> _analyzePhoto(Uint8List bytes, {bool overwrite = false}) async {
    setState(() {
      _aiBusy = true;
      _aiFilled = false;
    });
    try {
      final d = await AiService.instance.describe(bytes);
      if (!mounted || !identical(_image, bytes)) return; // photo changed meanwhile
      setState(() {
        if (overwrite || _title.text.trim().isEmpty) _title.text = d.title;
        if (overwrite || _description.text.trim().isEmpty) _description.text = d.description;
        if ((overwrite || !_categoryTouched) && itemCategories.contains(d.category)) _category = d.category;
        _aiFilled = true;
      });
      if (d.sensitive) await _privacyPrompt(d.sensitiveReason, bytes);
    } on AiException catch (e) {
      if (mounted) _toast('AI could not read the photo: ${e.message}');
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _privacyPrompt(String reason, Uint8List bytes) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.privacy_tip_outlined, color: Colors.red, size: 36),
        title: const Text('Private details in photo'),
        content: Text(
          '${reason.isEmpty ? 'This photo may show an ID or card number.' : reason}\n\n'
          'Everyone using the app can see this photo. We recommend blurring it.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'remove'), child: const Text('Remove photo')),
          TextButton(onPressed: () => Navigator.pop(context, 'keep'), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(context, 'blur'), child: const Text('Blur photo')),
        ],
      ),
    );
    if (!mounted || !identical(_image, bytes)) return;
    if (choice == 'blur') {
      final blurred = await blurSensitivePhoto(bytes);
      if (mounted) setState(() => _image = blurred);
    } else if (choice == 'remove') {
      setState(() {
        _image = null;
        _aiFilled = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_date == null) {
      _toast('The date field is required.');
      return;
    }
    setState(() => _saving = true);
    try {
      // For found items with a secret detail, AI writes the questions claimants
      // must answer; the secret itself is stored where only the finder can read it.
      final secret = _type == 'found' ? _secret.text.trim() : '';
      var questions = <String>[];
      if (secret.isNotEmpty) {
        try {
          questions = await AiService.instance.claimQuestions(_title.text.trim(), secret);
        } on AiException catch (e) {
          _toast('Saving without claim protection: ${e.message}');
        }
      }

      final id = await ItemService.instance.create(
        ItemDraft(
          claimQuestions: questions,
          type: _type,
          title: _title.text.trim(),
          category: _category,
          description: _description.text.trim(),
          location: _location.text.trim(),
          latitude: _point?.latitude,
          longitude: _point?.longitude,
          date: _date!,
          // Not shown publicly; revealed only through a claim (see ClaimSheet).
          contact: widget.user.email,
          imageBase64: _image == null ? null : base64Encode(_image!),
        ),
        widget.user,
      );

      if (questions.isNotEmpty) await ClaimService.instance.saveSecret(id, widget.user.uid, secret);
      final wasFound = _type == 'found';

      if (!mounted) return;
      _form.currentState!.reset();
      for (final c in [_title, _description, _location, _secret]) {
        c.clear();
      }
      setState(() {
        _type = 'lost';
        _category = itemCategories.first;
        _categoryTouched = false;
        _date = null;
        _point = null;
        _image = null;
        _aiFilled = false;
      });
      if (wasFound && !widget.user.isAdmin) await _showHandover();
      widget.onSaved();
    } catch (e) {
      _toast('Could not save the item: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Finders hand the item to the office; owners collect it there after the
  /// admin verifies them, so the two never deal with each other directly.
  Future<void> _showHandover() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.volunteer_activism, color: foundColor, size: 36),
      title: const Text('Thank you! One more step'),
      content: const SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Please hand the item in so the admin can return it safely to its owner. You stay anonymous.'),
            SizedBox(height: 12),
            HandoverCard(),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          child: const Text('Got it'),
        ),
      ],
    ),
  );

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  String? _required(String? v, String field) =>
      (v == null || v.trim().isEmpty) ? 'The $field field is required.' : null;

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 14);
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'lost', label: Text('I lost something'), icon: Icon(Icons.search)),
              ButtonSegment(value: 'found', label: Text('I found something'), icon: Icon(Icons.check_circle_outline)),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          gap,
          _photoSection(),
          gap,
          TextFormField(
            controller: _title,
            maxLength: 255,
            decoration: const InputDecoration(labelText: 'Item Name', hintText: 'e.g. Blue backpack', counterText: ''),
            validator: (v) => _required(v, 'item name'),
          ),
          gap,
          DropdownButtonFormField<String>(
            // Rebuilt when AI picks a category.
            key: ValueKey('category-$_category'),
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [for (final c in itemCategories) DropdownMenuItem(value: c, child: Text('${categoryEmoji(c)}  $c'))],
            onChanged: (v) => setState(() {
              _category = v!;
              _categoryTouched = true;
            }),
          ),
          gap,
          TextFormField(
            controller: _description,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(labelText: 'Description', hintText: 'Describe the item...'),
            validator: (v) => _required(v, 'description'),
          ),
          gap,
          LocationPicker(
            addressController: _location,
            point: _point,
            onPointChanged: (p) => setState(() => _point = p),
          ),
          gap,
          InkWell(
            onTap: _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Date', suffixIcon: Icon(Icons.calendar_today)),
              child: Text(_date == null ? 'Select date' : DateFormat('d MMM y').format(_date!)),
            ),
          ),
          AnimatedSize(
            duration: motionMedium,
            curve: Curves.easeOutCubic,
            child: _type != 'found'
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: TextFormField(
                      controller: _secret,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        labelText: '🛡 Secret detail (optional)',
                        hintText: 'e.g. Doraemon sticker inside the cover',
                        helperText: "Something only the real owner would know. It's hidden — AI uses it to check people who claim the item.",
                        helperMaxLines: 3,
                        counterText: '',
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 24),
          PressScale(
            child: FilledButton(
              onPressed: _saving ? null : _submit,
              child: ButtonLabel(widget.submitLabel, loading: _saving),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _photoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Photo', style: TextStyle(fontWeight: FontWeight.w500)),
        const Text(
          '✨ Add a photo and AI fills in the details for you.',
          style: TextStyle(color: aiColor, fontSize: 13),
        ),
        const SizedBox(height: 8),
        AnimatedSize(
          duration: motionMedium,
          curve: Curves.easeOutCubic,
          child: _image == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          _image!,
                          height: 200,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: IconButton.filled(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                            _image = null;
                            _aiFilled = false;
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        AnimatedSwitcher(
          duration: motionMedium,
          child: _aiBusy
              ? const Padding(
                  key: ValueKey('busy'),
                  padding: EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: aiColor)),
                      SizedBox(width: 10),
                      Text('✨ AI is reading your photo…', style: TextStyle(color: aiColor)),
                    ],
                  ),
                )
              : _aiFilled && _image != null
              ? Row(
                  key: const ValueKey('filled'),
                  children: [
                    const Icon(Icons.auto_awesome, color: aiColor, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Details filled in by AI — please check them.', style: TextStyle(color: aiColor)),
                    ),
                    TextButton(onPressed: () => _analyzePhoto(_image!, overwrite: true), child: const Text('Redo')),
                  ],
                )
              : const SizedBox(key: ValueKey('none'), width: double.infinity),
        ),
        Row(
          children: [
            Expanded(
              child: PressScale(
                child: OutlinedButton.icon(
                  onPressed: _aiBusy ? null : () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Camera'),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: PressScale(
                child: OutlinedButton.icon(
                  onPressed: _aiBusy ? null : () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Gallery'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
