import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class Place {
  Place(this.name, this.point);
  final String name;
  final LatLng point;
}

/// Address search and reverse lookup using OpenStreetMap's Nominatim
/// (free, no API key; keep usage light per their usage policy).
class GeocodingService {
  static const _host = 'nominatim.openstreetmap.org';
  static const _headers = {'User-Agent': 'MyRecover/1.0 (com.myrecover.myrecover)'};

  static Future<List<Place>> search(String query) async {
    final uri = Uri.https(_host, '/search', {'q': query, 'format': 'json', 'limit': '5'});
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) return [];
    final list = jsonDecode(res.body) as List;
    return [
      for (final p in list)
        Place(p['display_name'] as String, LatLng(double.parse(p['lat'] as String), double.parse(p['lon'] as String))),
    ];
  }

  static Future<String?> reverse(LatLng point) async {
    final uri = Uri.https(_host, '/reverse', {
      'lat': point.latitude.toString(),
      'lon': point.longitude.toString(),
      'format': 'json',
    });
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) return null;
    return (jsonDecode(res.body) as Map)['display_name'] as String?;
  }
}
