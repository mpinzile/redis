import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/services/location_service.dart';
import '../../widgets/app_search_field.dart';

class MapPickerScreen extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;
  const MapPickerScreen({super.key, this.initialLatitude, this.initialLongitude});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final _searchCtrl = TextEditingController();
  final _mapCtrl = MapController();
  final _searchFocus = FocusNode();

  List<_SearchResult> _searchResults = [];
  bool _searching = false;
  bool _showSearchResults = false;
  bool _loadingAddress = false;
  bool _locatingUser = false;

  LatLng? _selectedPoint;
  String? _selectedAddress;
  String? _selectedShortName;

  static const _defaultCenter = LatLng(-6.7924, 39.2083);
  static const _defaultZoom = 13.0;

  @override
  void initState() {
    super.initState();
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _selectedPoint = LatLng(widget.initialLatitude!, widget.initialLongitude!);
      _reverseGeocode(_selectedPoint!);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _mapCtrl.dispose();
    super.dispose();
  }

  LatLng get _initialCenter => _selectedPoint ?? _defaultCenter;

  static String _formatReadableAddress(Map<String, dynamic>? address, String? displayName) {
    if (address == null) return displayName ?? '';
    final parts = <String>[];

    final placeName = address['amenity'] ?? address['building'] ?? address['tourism'] ?? address['shop'];
    if (placeName != null) parts.add(placeName.toString());

    final road = address['road'] ?? address['street'];
    if (road != null) parts.add(road.toString());

    final neighbourhood = address['neighbourhood'] ?? address['suburb'] ?? address['quarter'];
    if (neighbourhood != null && parts.length < 3) parts.add(neighbourhood.toString());

    final city = address['city'] ?? address['town'] ?? address['village'] ?? address['municipality'];
    if (city != null) parts.add(city.toString());

    final state = address['state'] ?? address['region'];
    if (state != null && parts.length < 4) parts.add(state.toString());

    if (parts.isEmpty) return displayName ?? '';
    return parts.join(', ');
  }

  static String _extractShortName(Map<String, dynamic>? address, String? displayName) {
    if (address == null) return displayName?.split(',').first.trim() ?? '';
    final name = address['amenity'] ?? address['building'] ?? address['tourism'] ??
        address['shop'] ?? address['road'] ?? address['neighbourhood'] ??
        address['suburb'];
    if (name != null) return name.toString();
    return displayName?.split(',').first.trim() ?? '';
  }

  Future<void> _search(String query) async {
    if (query.trim().length < 3) return;
    setState(() { _searching = true; _showSearchResults = true; });
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(query)}&format=json&limit=6&addressdetails=1',
      );
      final res = await http.get(uri, headers: {'User-Agent': 'com.nuru.app'});
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as List;
        setState(() => _searchResults = data
            .map((e) => _SearchResult.fromJson(e as Map<String, dynamic>))
            .toList());
      }
    } catch (_) {}
    setState(() => _searching = false);
  }

  Future<void> _reverseGeocode(LatLng point) async {
    setState(() => _loadingAddress = true);
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=${point.latitude}&lon=${point.longitude}&format=json&addressdetails=1',
      );
      final res = await http.get(uri, headers: {'User-Agent': 'com.nuru.app'});
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final address = data['address'] as Map<String, dynamic>?;
        setState(() {
          _selectedAddress = _formatReadableAddress(address, data['display_name']?.toString());
          _selectedShortName = _extractShortName(address, data['display_name']?.toString());
        });
      }
    } catch (_) {}
    setState(() => _loadingAddress = false);
  }

  void _onMapTap(TapPosition tapPos, LatLng point) {
    setState(() {
      _selectedPoint = point;
      _showSearchResults = false;
      _searchFocus.unfocus();
    });
    _reverseGeocode(point);
  }

  void _selectSearchResult(_SearchResult r) {
    final point = LatLng(r.lat, r.lng);
    setState(() {
      _selectedPoint = point;
      _selectedAddress = r.readableAddress;
      _selectedShortName = r.name;
      _searchResults = [];
      _showSearchResults = false;
      _searchCtrl.text = '';
      _searchFocus.unfocus();
    });
    _mapCtrl.move(point, 16.0);
  }

  Future<void> _goToMyLocation() async {
    setState(() => _locatingUser = true);
    final pos = await LocationService.getCurrentPosition();
    if (pos != null && mounted) {
      final point = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _selectedPoint = point;
        _locatingUser = false;
      });
      _mapCtrl.move(point, 16.0);
      _reverseGeocode(point);
    } else {
      if (mounted) setState(() => _locatingUser = false);
    }
  }

  void _confirmSelection() {
    if (_selectedPoint == null) return;
    Navigator.pop(context, {
      'latitude': _selectedPoint!.latitude,
      'longitude': _selectedPoint!.longitude,
      'address': _selectedAddress,
    });
  }

  @override
  Widget build(BuildContext context) {
    final safePadding = MediaQuery.of(context).padding;
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: _selectedPoint != null ? 15.0 : _defaultZoom,
              onTap: _onMapTap,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.nuru.app',
                maxZoom: 19,
                tileSize: 512,
                zoomOffset: -1,
                retinaMode: RetinaMode.isHighDensity(context),
              ),
              if (_selectedPoint != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selectedPoint!,
                      width: 48,
                      height: 48,
                      alignment: Alignment.topCenter,
                      child: const _GoogleMapPin(),
                    ),
                  ],
                ),
            ],
          ),
          _buildSearchBar(safePadding),
          if (_showSearchResults && _searchResults.isNotEmpty) _buildSearchOverlay(safePadding),
          _buildMyLocationButton(safePadding),
          if (_selectedPoint != null) _buildBottomCard(safePadding),
        ],
      ),
    );
  }

  Widget _buildSearchBar(EdgeInsets safePadding) {
    return Positioned(
      top: safePadding.top + 12,
      left: 16,
      right: 16,
      child: Row(
        children: [
          _floatingButton(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.chevron_left_rounded, color: Color(0xFF202124), size: 24),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 16, offset: const Offset(0, 4)),
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 1)),
                ],
              ),
              child: AppSearchField(
                controller: _searchCtrl,
                hint: 'Search places...',
                loading: _searching,
                onClear: () {
                  _searchCtrl.clear();
                  setState(() { _searchResults = []; _showSearchResults = false; });
                },
                onChanged: (v) {
                  if (v.length >= 3) _search(v);
                  if (v.isEmpty) setState(() { _searchResults = []; _showSearchResults = false; });
                },
                onSubmitted: _search,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchOverlay(EdgeInsets safePadding) {
    return Positioned(
      top: safePadding.top + 70,
      left: 16,
      right: 16,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 320),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 6)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            shrinkWrap: true,
            itemCount: _searchResults.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100, indent: 60),
            itemBuilder: (_, i) {
              final r = _searchResults[i];
              return ListTile(
                leading: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.location_on_rounded, color: Color(0xFFEA4335), size: 22),
                ),
                title: Text(r.name,
                  style: appText(size: 14, weight: FontWeight.w600, color: const Color(0xFF202124)),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(r.readableAddress,
                  style: appText(size: 12, color: const Color(0xFF5F6368)),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                onTap: () => _selectSearchResult(r),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMyLocationButton(EdgeInsets safePadding) {
    return Positioned(
      right: 16,
      bottom: _selectedPoint != null ? 210 : safePadding.bottom + 24,
      child: _floatingButton(
        onTap: _locatingUser ? null : _goToMyLocation,
        child: _locatingUser
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1A73E8)))
            : const Icon(Icons.my_location_rounded, color: Color(0xFF1A73E8), size: 24),
      ),
    );
  }

  Widget _buildBottomCard(EdgeInsets safePadding) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: safePadding.bottom + 16,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 24, offset: const Offset(0, -4)),
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, -1)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.location_on_rounded, color: Color(0xFFEA4335), size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  _selectedShortName ?? 'Selected Location',
                  style: appText(size: 16, weight: FontWeight.w700, color: const Color(0xFF202124)),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                if (_loadingAddress)
                  Row(children: [
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF9AA0A6))),
                    const SizedBox(width: 8),
                    Text('Fetching address...', style: appText(size: 13, color: const Color(0xFF9AA0A6))),
                  ])
                else
                  Text(
                    _selectedAddress ?? '${_selectedPoint!.latitude.toStringAsFixed(5)}, ${_selectedPoint!.longitude.toStringAsFixed(5)}',
                    style: appText(size: 13, color: const Color(0xFF5F6368)),
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                  ),
              ])),
            ]),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _confirmSelection,
                icon: const Icon(Icons.check_rounded, size: 20),
                label: Text('Confirm Location', style: appText(size: 15, weight: FontWeight.w700, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A73E8),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _floatingButton({required Widget child, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50, height: 50,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 16, offset: const Offset(0, 4)),
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 1)),
          ],
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _SearchResult {
  final String readableAddress;
  final String name;
  final double lat;
  final double lng;

  _SearchResult({required this.readableAddress, required this.name, required this.lat, required this.lng});

  factory _SearchResult.fromJson(Map<String, dynamic> json) {
    final address = json['address'] as Map<String, dynamic>?;
    final name = _MapPickerScreenState._extractShortName(address, json['display_name']?.toString());
    final readable = _MapPickerScreenState._formatReadableAddress(address, json['display_name']?.toString());
    return _SearchResult(
      readableAddress: readable,
      name: name,
      lat: double.tryParse(json['lat']?.toString() ?? '') ?? 0,
      lng: double.tryParse(json['lon']?.toString() ?? '') ?? 0,
    );
  }
}

class _GoogleMapPin extends StatelessWidget {
  const _GoogleMapPin();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            bottom: 0,
            child: Container(
              width: 10,
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, spreadRadius: 1),
                ],
              ),
            ),
          ),
          const Positioned(
            bottom: 2,
            child: Icon(
              Icons.location_on,
              color: Color(0xFFEA4335),
              size: 40,
              shadows: [
                Shadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
