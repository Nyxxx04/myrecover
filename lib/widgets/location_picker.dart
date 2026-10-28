import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../services/geocoding_service.dart';
import '../theme.dart';
import 'animations.dart';

/// Address field + OpenStreetMap preview. Search an address, tap the map to
/// move the pin, or use the device's current location.
class LocationPicker extends StatefulWidget {
  const LocationPicker({super.key, required this.addressController, required this.onPointChanged, this.point});

  final TextEditingController addressController;
  final ValueChanged<LatLng?> onPointChanged;
  final LatLng? point;

  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  static const _defaultCenter = LatLng(6.4456470, 100.2750710);

  final _map = MapController();
  bool _busy = false;

  LatLng? get _point => widget.point;

  void _setPoint(LatLng point, {String? address}) {
    widget.onPointChanged(point);
    _map.move(point, 15);
    if (address != null) widget.addressController.text = address;
  }

  Future<void> _search() async {
    final query = widget.addressController.text.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final results = await GeocodingService.search(query);
      if (!mounted) return;
      if (results.isEmpty) {
        _toast('Unable to find that location. Try another search.');
        return;
      }
      final place = results.length == 1
          ? results.first
          : await showModalBottomSheet<Place>(
              context: context,
              builder: (context) => SafeArea(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final p in results)
                      ListTile(
                        leading: const Icon(Icons.place_outlined),
                        title: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                        onTap: () => Navigator.pop(context, p),
                      ),
                  ],
                ),
              ),
            );
      if (place != null) _setPoint(place.point, address: place.name);
    } catch (_) {
      _toast('Address search failed. Check your internet connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _busy = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _toast('Location services are turned off.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _toast('Unable to retrieve your current location.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      final point = LatLng(pos.latitude, pos.longitude);
      _setPoint(point);
      await _reverse(point);
    } catch (_) {
      _toast('Unable to retrieve your current location.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reverse(LatLng point) async {
    try {
      final address = await GeocodingService.reverse(point);
      if (address != null && mounted) widget.addressController.text = address;
    } catch (_) {
      // Keep whatever the user typed.
    }
  }

  void _toast(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: widget.addressController,
          textInputAction: TextInputAction.search,
          onFieldSubmitted: (_) => _search(),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'The location field is required.' : null,
          decoration: InputDecoration(
            labelText: 'Location',
            hintText: 'Where was it lost/found?',
            suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _busy ? null : _search),
          ),
        ),
        const SizedBox(height: 8),
        PressScale(
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _useCurrentLocation,
            icon: _busy
                ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location),
            label: const Text('Use My Current Location'),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Search an address, or tap the map to place the marker.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 240,
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: _point ?? _defaultCenter,
                initialZoom: _point != null ? 15 : 13,
                onTap: (_, point) {
                  widget.onPointChanged(point);
                  _reverse(point);
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.myrecover.myrecover',
                ),
                if (_point != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _point!,
                        width: 40,
                        height: 40,
                        alignment: Alignment.topCenter,
                        child: const Icon(Icons.location_pin, color: brandGreen, size: 40),
                      ),
                    ],
                  ),
                const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
