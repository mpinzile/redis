import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/services/location_service.dart';

/// Premium in-app directions screen using OSRM + flutter_map (no Google Maps).
class DirectionsScreen extends StatefulWidget {
  final double destinationLat;
  final double destinationLng;
  final String? venueName;
  final String? address;

  const DirectionsScreen({
    super.key,
    required this.destinationLat,
    required this.destinationLng,
    this.venueName,
    this.address,
  });

  @override
  State<DirectionsScreen> createState() => _DirectionsScreenState();
}

class _DirectionsScreenState extends State<DirectionsScreen> {
  final MapController _mapCtrl = MapController();
  LatLng? _userLocation;
  List<LatLng> _routePoints = [];
  String? _distance;
  String? _duration;
  bool _loading = true;
  String? _error;

  LatLngBounds? _routeBounds;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final pos = await LocationService.getCurrentPosition();
      if (pos != null && mounted) {
        setState(() => _userLocation = LatLng(pos.latitude, pos.longitude));
        await _fetchRoute();
      } else if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not get your location. Please enable location access.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not get your location.';
        });
      }
    }
  }

  Future<void> _fetchRoute() async {
    if (_userLocation == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${_userLocation!.longitude},${_userLocation!.latitude};'
        '${widget.destinationLng},${widget.destinationLat}'
        '?overview=full&geometries=geojson',
      );
      final res = await http.get(url);
      final data = jsonDecode(res.body);

      if (data['code'] != 'Ok' || (data['routes'] as List).isEmpty) {
        if (mounted) setState(() { _loading = false; _error = 'Could not calculate route'; });
        return;
      }

      final route = data['routes'][0];
      final coords = (route['geometry']['coordinates'] as List)
          .map((c) => LatLng((c as List)[1].toDouble(), c[0].toDouble()))
          .toList();

      final distKm = (route['distance'] / 1000).toStringAsFixed(1);
      final durMin = (route['duration'] / 60).round();
      final durStr = durMin >= 60
          ? '${durMin ~/ 60}h ${durMin % 60}m'
          : '$durMin min';

      if (mounted) {
        setState(() {
          _routePoints = coords;
          _distance = '$distKm km';
          _duration = durStr;
          _routeBounds = LatLngBounds.fromPoints([
            _userLocation!,
            LatLng(widget.destinationLat, widget.destinationLng),
            ...coords,
          ]);
          _loading = false;
        });
        // Fit bounds
        try {
          _mapCtrl.fitCamera(CameraFit.bounds(bounds: _routeBounds!, padding: const EdgeInsets.all(60)));
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Failed to fetch directions'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dest = LatLng(widget.destinationLat, widget.destinationLng);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: dest,
              initialZoom: 14,
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
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 5,
                      color: const Color(0xFF1A73E8),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  // Destination marker
                  Marker(
                    point: dest,
                    width: 48,
                    height: 48,
                    alignment: Alignment.topCenter,
                    child: const _VenuePin(),
                  ),
                  // User location marker
                  if (_userLocation != null)
                    Marker(
                      point: _userLocation!,
                      width: 22,
                      height: 22,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF1A73E8),
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                left: 12,
                right: 12,
                bottom: 12,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withOpacity(0.95),
                    Colors.white.withOpacity(0.0),
                  ],
                ),
              ),
              child: Row(
                children: [
                  _circleButton(
                    icon: Icons.chevron_left_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: AppColors.softShadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.venueName ?? 'Venue',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (widget.address != null && widget.address!.isNotEmpty)
                            Text(
                              widget.address!,
                              style: appText(size: 11, color: AppColors.textTertiary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Route info card at bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).padding.bottom + 16,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                          strokeWidth: 2.5,
                        ),
                      ),
                    )
                  : _error != null
                      ? _errorCard()
                      : _routeInfoCard(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _routeInfoCard() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Handle bar
        Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: AppColors.borderLight,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Row(
          children: [
            // Duration badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1A73E8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _duration ?? '--',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _distance ?? '--',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    'Driving route',
                    style: appText(size: 11, color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
            // Re-center button
            GestureDetector(
              onTap: () {
                if (_userLocation != null) {
                  try {
                    final bounds = _routeBounds ?? LatLngBounds.fromPoints([
                      _userLocation!,
                      LatLng(widget.destinationLat, widget.destinationLng),
                    ]);
                    _mapCtrl.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(60)));
                  } catch (_) {}
                }
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: const Center(
                  child: Icon(Icons.my_location_rounded, size: 20, color: AppColors.textSecondary),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // Route endpoints
        Row(
          children: [
            Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF1A73E8),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)],
                  ),
                ),
                Container(width: 1.5, height: 24, color: AppColors.borderLight),
                const Icon(Icons.location_on_rounded, size: 16, color: Color(0xFFEA4335)),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your location',
                    style: appText(size: 12, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    widget.venueName ?? 'Destination',
                    style: appText(size: 12, weight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _errorCard() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: AppColors.borderLight,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.errorSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Icon(Icons.error_outline_rounded, size: 20, color: AppColors.error),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _error!,
                style: appText(size: 13, color: AppColors.error),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _init,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                'Retry',
                style: appText(size: 13, weight: FontWeight.w700, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _circleButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: AppColors.softShadow,
        ),
        child: Center(child: Icon(icon, size: 20, color: AppColors.textPrimary)),
      ),
    );
  }
}

class _VenuePin extends StatelessWidget {
  const _VenuePin();

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
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
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
              shadows: [Shadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
            ),
          ),
          Positioned(
            bottom: 17,
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            ),
          ),
        ],
      ),
    );
  }
}
