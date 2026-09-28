import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/sighting.dart';
import '../../models/user_profile.dart';
import '../../models/shelter_clinic.dart';
import '../../services/firebase_service.dart';
import '../../services/location_service.dart';
import '../../services/text_moderation_service.dart';
import '../widgets/paw_image.dart';
import 'sighting_detail.dart';

class MapScreen extends StatefulWidget {
  final VoidCallback? onNotificationTap;
  final VoidCallback? onProfileTap;
  final Sighting? initialFocusedSighting;

  const MapScreen({
    super.key,
    this.onNotificationTap,
    this.onProfileTap,
    this.initialFocusedSighting,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with SingleTickerProviderStateMixin {
  static const Color _navy = Color(0xFF1B2A4A);
  static const Color _lavender = Color(0xFF9B8EC4);
  static const Color _lavLight = Color(0xFFEDE9F7);
  static const Color _bgWhite = Color(0xFFFAF9F7);
  static const Color _urgent = Color(0xFFE53935);
  static const Color _needsHelp = Color(0xFFFF7043);
  static const Color _needsHome = Color(0xFF8E24AA);
  static const Color _resolved = Color(0xFF2E7D32);
  static const Color _coral = Color(0xFFFF5252);
  static const Color _accentBlue = Color(0xFF2196F3);
  static const Color _green = Color(0xFF4CAF50);

  final MapController _mapController = MapController();
  final TextEditingController _searchCtrl = TextEditingController();
  final LocationService _locationService = LocationService();

  ll.LatLng _centerLocation = const ll.LatLng(-6.2615, 106.8106); // Default South Jakarta
  ll.LatLng? _userLocation;
  bool _isLoadingGps = true;
  double _currentZoom = 14.0;

  String _activeFilter = 'All'; // 'All', 'Needs Help', 'Nearby', 'Resolved', 'Shelters & Vets'
  double _radiusFilterKm = 5.0;
  bool _includeShelters = true;

  Sighting? _selectedSighting;
  ShelterClinic? _selectedShelter;
  bool _isSearching = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late final Stream<List<Sighting>> _sightingsStream;
  late final Stream<UserProfile> _userProfileStream;

  @override
  void initState() {
    super.initState();
    _sightingsStream = FirebaseService.instance.streamSightings();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
    _userProfileStream = FirebaseService.instance.streamUserProfile(uid);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.initialFocusedSighting != null) {
      final s = widget.initialFocusedSighting!;
      final sLat = s.updatedLatitude ?? s.latitude;
      final sLng = s.updatedLongitude ?? s.longitude;
      _centerLocation = ll.LatLng(sLat, sLng);
      _selectedSighting = s;
      _currentZoom = 16.0;
    }

    _initUserLocation();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _initUserLocation() async {
    try {
      final loc = await _locationService.getCurrentUserLocation();
      if (!mounted) return;
      setState(() {
        _userLocation = ll.LatLng(loc.latitude, loc.longitude);
        _isLoadingGps = false;
        if (widget.initialFocusedSighting == null) {
          _centerLocation = _userLocation!;
          _mapController.move(_centerLocation, _currentZoom);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingGps = false;
      });
    }
  }

  void _recenterToUser() {
    if (_userLocation != null) {
      _mapController.move(_userLocation!, 16.0);
      setState(() {
        _currentZoom = 16.0;
      });
    } else {
      _initUserLocation();
    }
  }

  Future<void> _handleSearchSubmit(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;

    setState(() => _isSearching = true);
    FocusScope.of(context).unfocus();

    try {
      final res = await _locationService.searchLocation(clean);
      if (!mounted) return;
      if (res != null) {
        final target = ll.LatLng(res.latitude, res.longitude);
        _mapController.move(target, 15.5);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Moved map to ${res.formattedAddress.split(',').first}',
              style: GoogleFonts.nunito(fontWeight: FontWeight.w700),
            ),
            backgroundColor: _navy,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No location found for "$clean"',
              style: GoogleFonts.nunito(fontWeight: FontWeight.w700),
            ),
            backgroundColor: _urgent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Search error: $e'),
            backgroundColor: _urgent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  String _formatDistance(double targetLat, double targetLng) {
    final refLat = _userLocation?.latitude ?? _centerLocation.latitude;
    final refLng = _userLocation?.longitude ?? _centerLocation.longitude;
    final meters = Geolocator.distanceBetween(refLat, refLng, targetLat, targetLng);

    if (meters < 1000) {
      return '${meters.round()} m away';
    } else {
      return '${(meters / 1000).toStringAsFixed(1)} km away';
    }
  }

  double _getDistanceKm(double targetLat, double targetLng) {
    final refLat = _userLocation?.latitude ?? _centerLocation.latitude;
    final refLng = _userLocation?.longitude ?? _centerLocation.longitude;
    return Geolocator.distanceBetween(refLat, refLng, targetLat, targetLng) / 1000.0;
  }

  void _checkSelectedWithinRadius(double radius) {
    if (_selectedSighting != null) {
      final lat = _selectedSighting!.updatedLatitude ?? _selectedSighting!.latitude;
      final lng = _selectedSighting!.updatedLongitude ?? _selectedSighting!.longitude;
      if (_getDistanceKm(lat, lng) > radius) {
        _selectedSighting = null;
      }
    }
  }

  List<Sighting> _filterSightings(List<Sighting> sightings) {
    return sightings.where((s) {
      final lat = s.updatedLatitude ?? s.latitude;
      final lng = s.updatedLongitude ?? s.longitude;
      final distKm = _getDistanceKm(lat, lng);

      // Distance / Search Radius filter applies specifically to Cat Reports
      if (distKm > _radiusFilterKm) {
        return false;
      }

      switch (_activeFilter) {
        case 'Needs Home':
          return s.isNeedsHome;
        case 'Needs Help':
          return (s.urgency == 'urgent' || s.urgency == 'needsHelp') && !s.isNeedsHome;
        case 'Nearby':
          return distKm <= min(_radiusFilterKm, 3.0) && s.urgency != 'resolved';
        case 'Resolved':
          return s.urgency == 'resolved';
        case 'Shelters & Vets':
          return false; // Show only shelters & clinics in this mode
        case 'All':
        default:
          return true;
      }
    }).toList();
  }

  List<ShelterClinic> _filterShelters() {
    if (_activeFilter == 'Resolved') return [];
    if (_activeFilter == 'Needs Help') return [];
    if (_activeFilter == 'Needs Home') return [];
    if (!_includeShelters && _activeFilter != 'Shelters & Vets') return [];

    // Shelters & clinics remain visible as landmarks, controlled by their toggle switch
    return ShelterClinic.partnerDirectory;
  }

  @override
  Widget build(BuildContext context) {
    final isSelectedSightingVisible = _selectedSighting != null &&
        _getDistanceKm(
              _selectedSighting!.updatedLatitude ?? _selectedSighting!.latitude,
              _selectedSighting!.updatedLongitude ?? _selectedSighting!.longitude,
            ) <=
            _radiusFilterKm;
    final isSelectedShelterVisible = _selectedShelter != null &&
        (_includeShelters || _activeFilter == 'Shelters & Vets');

    return Scaffold(
      backgroundColor: _bgWhite,
      body: SafeArea(
        child: Stack(
          children: [
            // Map Layer
            _buildMapLayer(),

            // Top Header & Floating Search Bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopOverlay(),
            ),

            // Floating Map Controls (Recenter, Zoom)
            Positioned(
              right: 16,
              bottom: isSelectedSightingVisible || isSelectedShelterVisible ? 220 : 100,
              child: _buildMapActionButtons(),
            ),

            // Callout Preview Card
            if (isSelectedSightingVisible)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: _buildSightingCalloutCard(_selectedSighting!),
              )
            else if (isSelectedShelterVisible)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: _buildShelterCalloutCard(_selectedShelter!),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Top Branded Header & Search Bar
  // ---------------------------------------------------------------------------
  Widget _buildTopOverlay() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.95),
            Colors.white.withValues(alpha: 0.85),
            Colors.white.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.75, 1.0],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // PawWatch Top App Bar (Branded)
          _buildBrandedHeader(),
          const SizedBox(height: 6),

          // Floating Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildSearchBar(),
          ),
          const SizedBox(height: 8),

          // Horizontal Filter Chips
          _buildFilterPills(),
          if (_activeFilter == 'Shelters & Vets') ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildSuggestClinicBanner(),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildSuggestClinicBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _navy.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0xFF00897B).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.add_location_alt_rounded,
              color: Color(0xFF00897B),
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Know a partner vet or shelter?',
                  style: GoogleFonts.nunito(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
                Text(
                  'Suggest it for community verification',
                  style: GoogleFonts.nunito(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _navy.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: _showSuggestClinicModal,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _navy,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_rounded, size: 14, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    'Suggest',
                    style: GoogleFonts.nunito(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
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

  Widget _buildBrandedHeader() {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? user?.email ?? 'PawWatcher';
    final initials = displayName.isNotEmpty
        ? displayName.trim().split(' ').map((p) => p.isNotEmpty ? p[0] : '').take(2).join().toUpperCase()
        : 'PW';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Notification Bell
          GestureDetector(
            onTap: widget.onNotificationTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _navy.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.notifications_outlined, color: _navy, size: 22),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: _coral,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Branded Center Title & Logo
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/AppLogo.png',
                height: 34,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 2),
              RichText(
                text: TextSpan(
                  style: GoogleFonts.nunito(fontSize: 10.5, fontWeight: FontWeight.w800),
                  children: const [
                    TextSpan(text: 'Rescue.', style: TextStyle(color: _navy)),
                    TextSpan(text: ' '),
                    TextSpan(text: 'Report.', style: TextStyle(color: _lavender)),
                    TextSpan(text: ' '),
                    TextSpan(text: 'Earn.', style: TextStyle(color: _green)),
                  ],
                ),
              ),
            ],
          ),

          // User Level / XP Avatar
          GestureDetector(
            onTap: widget.onProfileTap,
            behavior: HitTestBehavior.opaque,
            child: StreamBuilder<UserProfile>(
              stream: _userProfileStream,
              builder: (context, snapshot) {
                final level = snapshot.data?.level ?? 1;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: _navy.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _lavLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Lv.$level',
                          style: GoogleFonts.nunito(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: _navy,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      CircleAvatar(
                        radius: 13,
                        backgroundColor: _lavender,
                        child: Text(
                          initials,
                          style: GoogleFonts.nunito(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.1),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _searchCtrl,
        textInputAction: TextInputAction.search,
        onSubmitted: _handleSearchSubmit,
        style: GoogleFonts.nunito(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: _navy,
        ),
        decoration: InputDecoration(
          hintText: 'Search location, street, area...',
          hintStyle: GoogleFonts.nunito(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            color: _navy.withValues(alpha: 0.45),
          ),
          prefixIcon: _isSearching
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _lavender),
                  ),
                )
              : const Icon(Icons.search_rounded, color: _navy, size: 22),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_searchCtrl.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18, color: Colors.grey),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() {});
                  },
                ),
              IconButton(
                icon: Icon(
                  Icons.tune_rounded,
                  color: (_radiusFilterKm != 5.0 || !_includeShelters)
                      ? _coral
                      : _lavender,
                  size: 22,
                ),
                tooltip: 'Filters',
                onPressed: _showAdvancedFilterModal,
              ),
              const SizedBox(width: 4),
            ],
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildFilterPills() {
    final filters = [
      {'label': 'All', 'icon': Icons.layers_outlined},
      {'label': 'Needs Help', 'icon': Icons.warning_amber_rounded},
      {'label': 'Needs Home', 'icon': Icons.home_outlined},
      {'label': 'Nearby', 'icon': Icons.near_me_outlined},
      {'label': 'Resolved', 'icon': Icons.check_circle_outline_rounded},
      {'label': 'Shelters & Vets', 'icon': Icons.health_and_safety_outlined},
    ];

    return SizedBox(
      height: 38,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: filters.length + 1,
        separatorBuilder: (_, index) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          if (i == filters.length) {
            // Standalone action pill to suggest a clinic/shelter outside filters
            return GestureDetector(
              onTap: _showSuggestClinicModal,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF00897B).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00897B).withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                  border: Border.all(
                    color: const Color(0xFF00897B).withValues(alpha: 0.35),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.add_business_rounded,
                      size: 16,
                      color: Color(0xFF00897B),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Suggest Facility',
                      style: GoogleFonts.nunito(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF00897B),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final item = filters[i];
          final label = item['label'] as String;
          final icon = item['icon'] as IconData;
          final isSelected = _activeFilter == label;

          return GestureDetector(
            onTap: () {
              setState(() {
                _activeFilter = label;
                _selectedSighting = null;
                _selectedShelter = null;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? _navy : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: isSelected
                        ? _navy.withValues(alpha: 0.25)
                        : _navy.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
                border: Border.all(
                  color: isSelected ? _navy : _lavender.withValues(alpha: 0.2),
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: isSelected ? Colors.white : _navy,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: GoogleFonts.nunito(
                      fontSize: 12.5,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected ? Colors.white : _navy,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // FlutterMap Layer
  // ---------------------------------------------------------------------------
  Widget _buildMapLayer() {
    return StreamBuilder<List<Sighting>>(
      stream: _sightingsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('⚠️ Firestore map streamSightings error: ${snapshot.error}');
        }
        final sightings = snapshot.data ?? [];
        final filteredSightings = _filterSightings(sightings);
        final filteredShelters = _filterShelters();

        final markers = <Marker>[];

        // 1. User Location Marker
        if (_userLocation != null) {
          markers.add(
            Marker(
              point: _userLocation!,
              width: 50,
              height: 50,
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 44 * _pulseAnimation.value,
                        height: 44 * _pulseAnimation.value,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _accentBlue.withValues(alpha: 0.25),
                        ),
                      ),
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _accentBlue,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: _accentBlue.withValues(alpha: 0.5),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        }

        // 2. Sighting Markers (Sorted by Z-Index priority and dispersed if overlapping)
        // Resolved reports are painted underneath, Urgent and Needs Help are on TOP.
        final sortedSightings = List<Sighting>.from(filteredSightings);
        sortedSightings.sort((a, b) {
          if (a.id == _selectedSighting?.id) return 1;
          if (b.id == _selectedSighting?.id) return -1;

          int rank(Sighting s) {
            if (s.urgency == 'resolved') return 0; // painted bottom
            if (s.urgency == 'urgent') return 3;   // painted on top of active cases
            return 1;                              // Active cases: Needs Help & Needs Home (equal layer)
          }

          return rank(a).compareTo(rank(b));
        });

        // Detect coordinate collisions within ~15m and disperse slightly in a neat spiral/circle
        final clusterMap = <String, List<Sighting>>{};
        for (final s in sortedSightings) {
          final lat = s.updatedLatitude ?? s.latitude;
          final lng = s.updatedLongitude ?? s.longitude;
          final key = '${(lat * 8000).round()}_${(lng * 8000).round()}';
          clusterMap.putIfAbsent(key, () => []).add(s);
        }

        final pointMap = <String, ll.LatLng>{};
        for (final entry in clusterMap.entries) {
          final list = entry.value;
          if (list.length == 1) {
            final s = list.first;
            pointMap[s.id] = ll.LatLng(
              s.updatedLatitude ?? s.latitude,
              s.updatedLongitude ?? s.longitude,
            );
          } else {
            final count = list.length;
            for (int i = 0; i < count; i++) {
              final s = list[i];
              final baseLat = s.updatedLatitude ?? s.latitude;
              final baseLng = s.updatedLongitude ?? s.longitude;
              final angle = (2 * pi * i) / count;
              const spread = 0.00018; // ~18-20m visible separation on map
              pointMap[s.id] = ll.LatLng(
                baseLat + spread * sin(angle),
                baseLng + spread * cos(angle),
              );
            }
          }
        }

        // 3. Proximity-Based Fading Hierarchy (3-Tier Model):
        // Tier 3 (Top):    🚨 Urgent (NEVER faded, always 100% opacity)
        // Tier 2 (Active):  ⚠️ Needs Help & 🏠 Needs Home (Equal peers! Never fade each other)
        // Tier 1 (Bottom):  ✓ Resolved (Faded when touching active cases)
        //
        // Only when a higher-tier pin actually touches/overlaps a lower-tier pin (within ~22m),
        // does the lower-tier pin fade and become semi-transparent.
        final opacityMap = <String, double>{};
        final scaleMap = <String, double>{};
        const double touchingThresholdMeters = 22.0;

        int getTier(Sighting s) {
          if (s.urgency == 'urgent') return 3; // Top: Urgent
          if (s.urgency == 'resolved') return 1; // Bottom: Resolved
          return 2; // Equal peers: Needs Help (orange) & Needs Home (purple)
        }

        for (final s in sortedSightings) {
          final myTier = getTier(s);

          // Urgent pins and selected pin are ALWAYS 100% full opacity and never faded
          if (s.id == _selectedSighting?.id || myTier == 3) {
            opacityMap[s.id] = 1.0;
            scaleMap[s.id] = 1.0;
            continue;
          }

          final sLat = s.updatedLatitude ?? s.latitude;
          final sLng = s.updatedLongitude ?? s.longitude;

          // Tracks if any higher-tier pin is physically touching this pin
          int higherNearbyTier = 0;

          for (final other in sortedSightings) {
            if (other.id == s.id) continue;
            final otherTier = getTier(other);
            if (otherTier <= myTier) continue; // Equal tiers (Needs Help & Needs Home) NEVER fade each other!

            final oLat = other.updatedLatitude ?? other.latitude;
            final oLng = other.updatedLongitude ?? other.longitude;

            // Fast bounding box check (~30m)
            if ((sLat - oLat).abs() > 0.0003 || (sLng - oLng).abs() > 0.0003) continue;

            final dist = Geolocator.distanceBetween(sLat, sLng, oLat, oLng);
            if (dist <= touchingThresholdMeters) {
              if (otherTier > higherNearbyTier) {
                higherNearbyTier = otherTier;
              }
            }
          }

          if (higherNearbyTier == 3) {
            // Touches an Urgent pin: fade lower tier so Urgent stands out
            opacityMap[s.id] = 0.42;
            scaleMap[s.id] = 0.88;
          } else if (higherNearbyTier == 2) {
            // Touches an active case (Needs Help or Needs Home): fade resolved
            opacityMap[s.id] = 0.55;
            scaleMap[s.id] = 0.92;
          } else {
            // Not touching any higher-tier pin: FULL 100% OPACITY!
            opacityMap[s.id] = 1.0;
            scaleMap[s.id] = 1.0;
          }
        }

        for (final s in sortedSightings) {
          final point = pointMap[s.id] ??
              ll.LatLng(s.updatedLatitude ?? s.latitude, s.updatedLongitude ?? s.longitude);
          final isSelected = _selectedSighting?.id == s.id;

          final isUrgent = s.urgency == 'urgent';
          final mWidth = isUrgent ? 112.0 : 96.0;
          final mHeight = isUrgent ? 108.0 : 92.0;

          markers.add(
            Marker(
              point: point,
              width: mWidth,
              height: mHeight,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedSighting = s;
                    _selectedShelter = null;
                  });
                  _mapController.move(point, max(_currentZoom, 15.5));
                },
                child: Center(
                  child: _buildSightingPin(
                    s,
                    isSelected,
                    opacity: opacityMap[s.id] ?? 1.0,
                    scale: scaleMap[s.id] ?? 1.0,
                  ),
                ),
              ),
            ),
          );
        }

        // 3. Partner Shelter / Clinic Markers
        for (final sc in filteredShelters) {
          final isSelected = _selectedShelter?.id == sc.id;

          markers.add(
            Marker(
              point: ll.LatLng(sc.latitude, sc.longitude),
              width: 64,
              height: 74,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedShelter = sc;
                    _selectedSighting = null;
                  });
                  _mapController.move(ll.LatLng(sc.latitude, sc.longitude), max(_currentZoom, 15.0));
                },
                child: _buildShelterPin(sc, isSelected),
              ),
            ),
          );
        }

        return FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _centerLocation,
            initialZoom: _currentZoom,
            onPositionChanged: (pos, hasGesture) {
              _currentZoom = pos.zoom;
              if (_userLocation == null) {
                _centerLocation = pos.center;
              }
            },
            onTap: (tapPosition, point) {
              if (_selectedSighting != null || _selectedShelter != null) {
                setState(() {
                  _selectedSighting = null;
                  _selectedShelter = null;
                });
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.pawwatch.app',
            ),
            MarkerLayer(markers: markers),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Custom Map Markers (matching MapPage.png)
  // ---------------------------------------------------------------------------
  Widget _buildSightingPin(
    Sighting s,
    bool isSelected, {
    double opacity = 1.0,
    double scale = 1.0,
  }) {
    final isUrgent = s.urgency == 'urgent';
    final isResolved = s.urgency == 'resolved';
    final isNeedsHome = s.isNeedsHome;

    Color badgeColor;
    String badgeText;
    IconData badgeIcon;
    double avatarSize;
    double borderWidth;
    double elevationAlpha;

    if (isUrgent) {
      // 1. URGENT: Most standout (single exclamation icon, glowing radar ripple, largest avatar)
      badgeColor = _urgent;
      badgeText = 'Urgent';
      badgeIcon = Icons.priority_high_rounded;
      avatarSize = isSelected ? 50.0 : 45.0;
      borderWidth = 3.2;
      elevationAlpha = 0.55;
    } else if (isResolved) {
      // 4. RESOLVED: Least standout (kept modest, flat, smaller footprint)
      badgeColor = _resolved;
      badgeText = 'Resolved';
      badgeIcon = Icons.check_rounded;
      avatarSize = isSelected ? 42.0 : 36.0;
      borderWidth = 1.8;
      elevationAlpha = 0.18;
    } else if (isNeedsHome) {
      // 3. NEEDS HOME: Less standout than Needs Help and Urgent (soft purple, medium-compact)
      badgeColor = _needsHome;
      badgeText = 'Needs Home';
      badgeIcon = Icons.home_rounded;
      avatarSize = isSelected ? 44.0 : 38.0;
      borderWidth = 2.0;
      elevationAlpha = 0.22;
    } else {
      // 2. NEEDS HELP (Stray feeding community & strays needing help): More standout than Needs Home, less than Urgent
      badgeColor = _needsHelp;
      badgeText = 'Needs Help';
      badgeIcon = Icons.warning_amber_rounded;
      avatarSize = isSelected ? 46.0 : 42.0;
      borderWidth = 2.6;
      elevationAlpha = 0.38;
    }

    final photoUrl = s.photoUrls.isNotEmpty ? s.photoUrls.first : '';

    final pinBody = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Status Pill Badge (Top)
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: isUrgent ? 8 : (isResolved ? 5 : 6),
            vertical: isUrgent ? 2.5 : 2,
          ),
          decoration: BoxDecoration(
            color: badgeColor,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: badgeColor.withValues(alpha: elevationAlpha),
                blurRadius: isUrgent ? 8 : 4,
                spreadRadius: isUrgent ? 1 : 0,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(color: Colors.white, width: isUrgent ? 1.4 : 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(badgeIcon, size: isUrgent ? 11 : 9.5, color: Colors.white),
              const SizedBox(width: 2.5),
              Text(
                badgeText,
                style: GoogleFonts.nunito(
                  fontSize: isUrgent ? 9.5 : 8.5,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: isUrgent ? 0.2 : 0,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),

        // Avatar Thumbnail with Standout Outer Border / Radar
        // Fixed SizedBox ensures radar expansion NEVER causes vertical layout overflows
        SizedBox(
          width: avatarSize + 16,
          height: avatarSize + 16,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // If Urgent: Animated Pulsing Halo / Radar ripple (contained via OverflowBox)
              if (isUrgent)
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, _) {
                    final rippleSize = (avatarSize + 14) * _pulseAnimation.value;
                    return OverflowBox(
                      maxWidth: 110,
                      maxHeight: 110,
                      child: Container(
                        width: rippleSize,
                        height: rippleSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _urgent.withValues(alpha: 0.20 * (1.35 - _pulseAnimation.value)),
                          border: Border.all(
                            color: _urgent.withValues(alpha: 0.45 * (1.35 - _pulseAnimation.value)),
                            width: 1.5,
                          ),
                        ),
                      ),
                    );
                  },
                ),

              // Photo Circle
              Container(
                width: avatarSize,
                height: avatarSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(
                    color: isSelected ? _coral : badgeColor,
                    width: borderWidth,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isUrgent
                          ? _urgent.withValues(alpha: 0.5)
                          : _navy.withValues(alpha: elevationAlpha),
                      blurRadius: isUrgent ? 12 : 8,
                      spreadRadius: isUrgent ? 1.5 : 0,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: photoUrl.isNotEmpty
                      ? PawImage(
                          url: photoUrl,
                          fit: BoxFit.cover,
                          errorWidget: Container(
                            color: _lavLight,
                            child: Icon(Icons.pets, color: badgeColor, size: avatarSize * 0.45),
                          ),
                        )
                      : Container(
                          color: _lavLight,
                          child: Icon(Icons.pets, color: badgeColor, size: avatarSize * 0.45),
                        ),
                ),
              ),
            ],
          ),
        ),

        // Pointer triangle
        CustomPaint(
          size: Size(isUrgent ? 11 : 9, isUrgent ? 6.5 : 5),
          painter: _TrianglePainter(color: isSelected ? _coral : badgeColor),
        ),
      ],
    );

    if (opacity < 1.0 || scale < 1.0) {
      return Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          alignment: Alignment.bottomCenter,
          child: pinBody,
        ),
      );
    }

    return pinBody;
  }

  Widget _buildShelterPin(ShelterClinic sc, bool isSelected) {
    final isShelter = sc.isShelter;
    final pinColor = isShelter ? const Color(0xFF00897B) : const Color(0xFF1E88E5);
    final icon = isShelter ? Icons.home_work_rounded : Icons.local_hospital_rounded;
    final label = isShelter ? 'Shelter' : 'Vet Clinic';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Pill Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: pinColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white, width: 1),
            boxShadow: [
              BoxShadow(
                color: pinColor.withValues(alpha: 0.35),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            label,
            style: GoogleFonts.nunito(
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Shield/Circular Pin
        Container(
          width: isSelected ? 44 : 38,
          height: isSelected ? 44 : 38,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? _navy : pinColor,
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _navy.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Center(
            child: Icon(icon, color: pinColor, size: isSelected ? 22 : 19),
          ),
        ),

        // Pointer
        CustomPaint(
          size: const Size(8, 5),
          painter: _TrianglePainter(color: isSelected ? _navy : pinColor),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Floating Map Controls (Right Side)
  // ---------------------------------------------------------------------------
  Widget _buildMapActionButtons() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Suggest Clinic / Shelter Button (standalone on map)
        _buildCircleButton(
          icon: const Icon(
            Icons.add_business_rounded,
            color: Color(0xFF00897B),
            size: 22,
          ),
          tooltip: 'Suggest Vet or Shelter',
          onTap: _showSuggestClinicModal,
        ),
        const SizedBox(height: 10),

        // GPS Recenter Button
        _buildCircleButton(
          icon: _isLoadingGps
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _navy),
                )
              : const Icon(Icons.my_location_rounded, color: _navy, size: 22),
          tooltip: 'My Location',
          onTap: _recenterToUser,
        ),
        const SizedBox(height: 10),

        // Zoom In
        _buildCircleButton(
          icon: const Icon(Icons.add_rounded, color: _navy, size: 22),
          tooltip: 'Zoom In',
          onTap: () {
            setState(() {
              _currentZoom = (_currentZoom + 1.0).clamp(3.0, 19.0);
              _mapController.move(_mapController.camera.center, _currentZoom);
            });
          },
        ),
        const SizedBox(height: 10),

        // Zoom Out
        _buildCircleButton(
          icon: const Icon(Icons.remove_rounded, color: _navy, size: 22),
          tooltip: 'Zoom Out',
          onTap: () {
            setState(() {
              _currentZoom = (_currentZoom - 1.0).clamp(3.0, 19.0);
              _mapController.move(_mapController.camera.center, _currentZoom);
            });
          },
        ),
      ],
    );
  }

  Widget _buildCircleButton({
    required Widget icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _navy.withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(color: _lavender.withValues(alpha: 0.2), width: 1),
          ),
          child: Center(child: icon),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Floating Callout Preview Cards (matching MapPage.png)
  // ---------------------------------------------------------------------------
  Widget _buildSightingCalloutCard(Sighting s) {
    final photoUrl = s.photoUrls.isNotEmpty ? s.photoUrls.first : '';
    final lat = s.updatedLatitude ?? s.latitude;
    final lng = s.updatedLongitude ?? s.longitude;
    final distStr = _formatDistance(lat, lng);

    Color badgeColor;
    String badgeLabel;
    if (s.urgency == 'urgent') {
      badgeColor = _urgent;
      badgeLabel = '! Urgent';
    } else if (s.urgency == 'resolved') {
      badgeColor = _resolved;
      badgeLabel = '✓ Resolved';
    } else if (s.isNeedsHome) {
      badgeColor = _needsHome;
      badgeLabel = '🏠 Needs Home';
    } else {
      badgeColor = _needsHelp;
      badgeLabel = '! Needs Help';
    }

    final displayTitle = s.title.isNotEmpty
        ? s.title
        : (s.category.isNotEmpty ? '${s.category} cat spotted' : 'Cat sighting spotted');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.16),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo with Urgency Badge Overlay
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      width: 90,
                      height: 90,
                      child: photoUrl.isNotEmpty
                          ? PawImage(url: photoUrl, fit: BoxFit.cover)
                          : Container(
                              color: _lavLight,
                              child: const Icon(Icons.pets, color: _lavender, size: 36),
                            ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Text(
                        badgeLabel,
                        style: GoogleFonts.nunito(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),

              // Sighting Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title & Close Button
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.nunito(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: _navy,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _selectedSighting = null),
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: _lavLight.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close_rounded, size: 16, color: _navy),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Time Ago & Distance
                    Row(
                      children: [
                        Icon(Icons.access_time_rounded, size: 13, color: _navy.withValues(alpha: 0.5)),
                        const SizedBox(width: 4),
                        Text(
                          '${s.timeAgo}  •  $distStr',
                          style: GoogleFonts.nunito(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _navy.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),

                    // Description snippet
                    Text(
                      s.description.isNotEmpty ? s.description : s.locationAddress,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _navy.withValues(alpha: 0.75),
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // View Details Action Button (Coral/Red Accent)
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _coral,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SightingDetailScreen(sighting: s),
                  ),
                );
              },
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: Text(
                'View Details',
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShelterCalloutCard(ShelterClinic sc) {
    final distStr = _formatDistance(sc.latitude, sc.longitude);
    final isShelter = sc.isShelter;
    final color = isShelter ? const Color(0xFF00897B) : const Color(0xFF1E88E5);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.16),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Icon, Name, Close
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Icon(
                    isShelter ? Icons.home_work_rounded : Icons.local_hospital_rounded,
                    color: color,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            sc.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.nunito(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: _navy,
                            ),
                          ),
                        ),
                        if (sc.isVerified)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _green.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.verified_rounded, size: 12, color: _green),
                                const SizedBox(width: 2),
                                Text(
                                  'Verified',
                                  style: GoogleFonts.nunito(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: _green,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${sc.typeLabel}  •  $distStr',
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _navy.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() => _selectedShelter = null),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: _lavLight.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded, size: 16, color: _navy),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Operating Hours & Address
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _bgWhite,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule_rounded, size: 14, color: _navy.withValues(alpha: 0.6)),
                const SizedBox(width: 6),
                Text(
                  sc.operatingHours,
                  style: GoogleFonts.nunito(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _navy,
                  ),
                ),
                if (sc.is24Hours) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: _urgent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '24/7 Service',
                      style: GoogleFonts.nunito(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: _urgent,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),

          Text(
            sc.address,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.nunito(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _navy.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 12),

          // Action Buttons: Call & Directions
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: color,
                    side: BorderSide(color: color, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: () => launchUrl(Uri.parse('tel:${sc.phone}')),
                  icon: const Icon(Icons.phone_rounded, size: 16),
                  label: Text(
                    'Call',
                    style: GoogleFonts.nunito(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: () {
                    final url =
                        'https://www.google.com/maps/search/?api=1&query=${sc.latitude},${sc.longitude}';
                    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                  },
                  icon: const Icon(Icons.directions_rounded, size: 16),
                  label: Text(
                    'Directions',
                    style: GoogleFonts.nunito(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Advanced Filter Modal Bottom Sheet
  // ---------------------------------------------------------------------------
  void _showAdvancedFilterModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final systemBottomNav = MediaQuery.paddingOf(ctx).bottom;
            final keyboardInset = MediaQuery.viewInsetsOf(ctx).bottom;
            final effectiveBottomPadding = keyboardInset > 0
                ? keyboardInset + 16
                : (systemBottomNav > 0 ? systemBottomNav + 24 : 36.0);

            return Container(
              padding: EdgeInsets.fromLTRB(20, 16, 20, effectiveBottomPadding),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _lavender.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Map Filters',
                          style: GoogleFonts.nunito(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: _navy,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setModalState(() {
                              _radiusFilterKm = 5.0;
                              _includeShelters = true;
                            });
                            setState(() {
                              _radiusFilterKm = 5.0;
                              _includeShelters = true;
                              _checkSelectedWithinRadius(5.0);
                            });
                          },
                          child: Text(
                            'Reset',
                            style: GoogleFonts.nunito(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _coral,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 10),

                    // Radius Slider
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Cat Report Radius: ${_radiusFilterKm.round()} km',
                          style: GoogleFonts.nunito(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _navy,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: _lavLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '≤ ${_radiusFilterKm.round()} km',
                            style: GoogleFonts.nunito(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: _navy,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: _radiusFilterKm,
                      min: 1.0,
                      max: 20.0,
                      divisions: 19,
                      activeColor: _navy,
                      inactiveColor: _lavLight,
                      onChanged: (v) {
                        setModalState(() => _radiusFilterKm = v);
                        setState(() {
                          _radiusFilterKm = v;
                          _checkSelectedWithinRadius(v);
                        });
                      },
                    ),
                    const SizedBox(height: 10),

                    // Toggle Partner Shelters & Clinics
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Show Partner Shelters & Vet Clinics',
                        style: GoogleFonts.nunito(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _navy,
                        ),
                      ),
                      subtitle: Text(
                        'Display verified rescue shelters, clinic drop-offs, and TNR points',
                        style: GoogleFonts.nunito(
                          fontSize: 12,
                          color: _navy.withValues(alpha: 0.6),
                        ),
                      ),
                      activeThumbColor: _accentBlue,
                      value: _includeShelters,
                      onChanged: (val) {
                        setModalState(() => _includeShelters = val);
                        setState(() => _includeShelters = val);
                      },
                    ),
                    const SizedBox(height: 20),

                    // Apply Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _navy,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () {
                          setState(() {
                            _checkSelectedWithinRadius(_radiusFilterKm);
                          });
                          Navigator.pop(ctx);
                        },
                        child: Text(
                          'Apply Filters',
                          style: GoogleFonts.nunito(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Suggest Vet Clinic or Shelter Modal Bottom Sheet (User Use Case)
  // ---------------------------------------------------------------------------
  void _showSuggestClinicModal() {
    String type = 'clinic'; // 'clinic' or 'shelter'
    final nameCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final hoursCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final miniMapCtrl = MapController();

    bool is24Hours = false;
    double selectedLat = _userLocation?.latitude ?? _centerLocation.latitude;
    double selectedLng = _userLocation?.longitude ?? _centerLocation.longitude;
    bool isFetchingGps = false;
    bool isLocatingAddress = false;
    bool isSubmitting = false;
    bool hasAttemptedSubmit = false;
    String? formValidationError;
    final selectedServices = <String>{};

    const clinicServices = [
      'TNR Discount',
      'Stray Friendly',
      'Emergency 24h',
      'Vaccination/Spay',
      'Quarantine Facility',
      'Pet Hotel/Foster',
    ];

    const shelterServices = [
      'Open Adoption',
      'Foster Care Intake',
      'TNR Recovery Spot',
      'Quarantine Facility',
      'Donation Drop-off',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final systemBottomNav = MediaQuery.paddingOf(ctx).bottom;
            final keyboardInset = MediaQuery.viewInsetsOf(ctx).bottom;
            final effectiveBottomPadding = keyboardInset > 0
                ? keyboardInset + 16
                : (systemBottomNav > 0 ? systemBottomNav + 24 : 36.0);

            final currentServices = type == 'clinic' ? clinicServices : shelterServices;
            final themeColor = type == 'clinic' ? const Color(0xFF1E88E5) : const Color(0xFF00897B);
            final activeAsset = type == 'clinic' ? 'assets/images/guardianangel.png' : 'assets/images/shelter.png';

            final nameErr = TextModerationService.validateFacilityName(
              nameCtrl.text,
              label: type == 'clinic' ? 'Vet Clinic' : 'Animal Shelter',
            );
            final phoneErr = TextModerationService.validatePhoneNumber(
              phoneCtrl.text,
              label: 'Emergency contact phone',
            );
            final addressErr = TextModerationService.validateAddress(
              addressCtrl.text,
              label: 'Facility address',
            );
            final notesErr = notesCtrl.text.trim().isNotEmpty
                ? TextModerationService.validateDescription(notesCtrl.text, fieldName: 'Notes')
                : null;

            return Container(
              padding: EdgeInsets.fromLTRB(20, 16, 20, effectiveBottomPadding),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _lavender.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: themeColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Image.asset(
                            activeAsset,
                            width: 28,
                            height: 28,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Suggest ${type == 'clinic' ? 'Vet Clinic' : 'Animal Shelter'}',
                                style: GoogleFonts.nunito(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: _navy,
                                ),
                              ),
                              Text(
                                'Community recommendations reviewed by Admins',
                                style: GoogleFonts.nunito(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: _navy.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20, color: _navy),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const Divider(height: 24),

                    // Facility Type Selector: 2 cards matching report outcome/action design
                    Text(
                      'Facility Category *',
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        // Vet Clinic Card (matching report action box design)
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setModalState(() {
                                type = 'clinic';
                                selectedServices.clear();
                              });
                            },
                            behavior: HitTestBehavior.opaque,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // 1. Title on top
                                SizedBox(
                                  height: 28,
                                  child: Center(
                                    child: Text(
                                      'Vet Clinic',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.nunito(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w800,
                                        color: type == 'clinic'
                                            ? const Color(0xFF1E88E5)
                                            : _navy,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                // 2. Center box with custom logo
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: double.infinity,
                                  height: 86,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: type == 'clinic'
                                          ? const Color(0xFF1E88E5)
                                          : _navy.withValues(alpha: 0.12),
                                      width: type == 'clinic' ? 2.2 : 1.2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: (type == 'clinic'
                                                ? const Color(0xFF1E88E5)
                                                : _navy)
                                            .withValues(alpha: type == 'clinic' ? 0.22 : 0.08),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Image.asset(
                                      'assets/images/guardianangel.png',
                                      width: 52,
                                      height: 52,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                // 3. Subtitle / description pill at bottom
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: (type == 'clinic'
                                            ? const Color(0xFF1E88E5)
                                            : _navy)
                                        .withValues(alpha: type == 'clinic' ? 0.12 : 0.06),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Medical Care & TNR',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.nunito(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: type == 'clinic'
                                          ? const Color(0xFF1E88E5)
                                          : _navy.withValues(alpha: 0.7),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),

                        // Rescue Shelter Card (matching report action box design)
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setModalState(() {
                                type = 'shelter';
                                selectedServices.clear();
                              });
                            },
                            behavior: HitTestBehavior.opaque,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // 1. Title on top
                                SizedBox(
                                  height: 28,
                                  child: Center(
                                    child: Text(
                                      'Rescue Shelter',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.nunito(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w800,
                                        color: type == 'shelter'
                                            ? const Color(0xFF00897B)
                                            : _navy,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                // 2. Center box with custom logo
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: double.infinity,
                                  height: 86,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: type == 'shelter'
                                          ? const Color(0xFF00897B)
                                          : _navy.withValues(alpha: 0.12),
                                      width: type == 'shelter' ? 2.2 : 1.2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: (type == 'shelter'
                                                ? const Color(0xFF00897B)
                                                : _navy)
                                            .withValues(alpha: type == 'shelter' ? 0.22 : 0.08),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Image.asset(
                                      'assets/images/shelter.png',
                                      width: 52,
                                      height: 52,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                // 3. Subtitle / description pill at bottom
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: (type == 'shelter'
                                            ? const Color(0xFF00897B)
                                            : _navy)
                                        .withValues(alpha: type == 'shelter' ? 0.12 : 0.06),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Intake & Adoption',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.nunito(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: type == 'shelter'
                                          ? const Color(0xFF00897B)
                                          : _navy.withValues(alpha: 0.7),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Name Field
                    Text(
                      type == 'clinic' ? 'Vet Clinic / Hospital Name *' : 'Shelter / Rescue Center Name *',
                      style: GoogleFonts.nunito(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameCtrl,
                      onChanged: (_) => setModalState(() {}),
                      style: GoogleFonts.nunito(fontSize: 13, color: _navy, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        hintText: type == 'clinic'
                            ? 'e.g. Sahabat Satwa Pet Clinic, Pejaten Vet'
                            : 'e.g. Pejaten Animal Shelter, ASPERA Sanctuary',
                        hintStyle: GoogleFonts.nunito(fontSize: 12, color: _navy.withValues(alpha: 0.4)),
                        prefixIcon: Icon(Icons.home_work_outlined, size: 18, color: themeColor),
                        filled: true,
                        fillColor: _bgWhite,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: (hasAttemptedSubmit && nameErr != null)
                                ? const Color(0xFFE53935)
                                : _navy.withValues(alpha: 0.15),
                            width: (hasAttemptedSubmit && nameErr != null) ? 1.5 : 1,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: (hasAttemptedSubmit && nameErr != null)
                                ? const Color(0xFFE53935)
                                : _navy.withValues(alpha: 0.15),
                            width: (hasAttemptedSubmit && nameErr != null) ? 1.5 : 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: (hasAttemptedSubmit && nameErr != null)
                                ? const Color(0xFFE53935)
                                : themeColor,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    if (hasAttemptedSubmit && nameErr != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '⚠️ $nameErr',
                        style: GoogleFonts.nunito(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFE53935),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),

                    // Phone Field
                    Text(
                      'Emergency Contact / WhatsApp Phone *',
                      style: GoogleFonts.nunito(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: phoneCtrl,
                      onChanged: (_) => setModalState(() {}),
                      keyboardType: TextInputType.phone,
                      style: GoogleFonts.nunito(fontSize: 13, color: _navy, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        hintText: 'e.g. +62 812-3456-7890 or (021) 7890-1234',
                        hintStyle: GoogleFonts.nunito(fontSize: 12, color: _navy.withValues(alpha: 0.4)),
                        prefixIcon: Icon(Icons.phone_outlined, size: 18, color: themeColor),
                        filled: true,
                        fillColor: _bgWhite,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: (hasAttemptedSubmit && phoneErr != null)
                                ? const Color(0xFFE53935)
                                : _navy.withValues(alpha: 0.15),
                            width: (hasAttemptedSubmit && phoneErr != null) ? 1.5 : 1,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: (hasAttemptedSubmit && phoneErr != null)
                                ? const Color(0xFFE53935)
                                : _navy.withValues(alpha: 0.15),
                            width: (hasAttemptedSubmit && phoneErr != null) ? 1.5 : 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: (hasAttemptedSubmit && phoneErr != null)
                                ? const Color(0xFFE53935)
                                : themeColor,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    if (hasAttemptedSubmit && phoneErr != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '⚠️ $phoneErr',
                        style: GoogleFonts.nunito(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFE53935),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),

                    // Address Field with GPS Auto-fill
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Facility Location & Address *',
                          style: GoogleFonts.nunito(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: _navy,
                          ),
                        ),
                        InkWell(
                          onTap: (isFetchingGps || isLocatingAddress)
                              ? null
                              : () async {
                                  setModalState(() => isFetchingGps = true);
                                  try {
                                    final loc = await _locationService.getCurrentUserLocation();
                                    addressCtrl.text = loc.formattedAddress;
                                    selectedLat = loc.latitude;
                                    selectedLng = loc.longitude;
                                    try {
                                      miniMapCtrl.move(ll.LatLng(selectedLat, selectedLng), 16.0);
                                    } catch (_) {}
                                  } catch (_) {}
                                  setModalState(() => isFetchingGps = false);
                                },
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isFetchingGps)
                                  SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(strokeWidth: 1.5, color: themeColor),
                                  )
                                else
                                  Icon(Icons.my_location_rounded, size: 14, color: themeColor),
                                const SizedBox(width: 4),
                                Text(
                                  'Use Current GPS',
                                  style: GoogleFonts.nunito(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: themeColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: addressCtrl,
                      onChanged: (_) => setModalState(() {}),
                      maxLines: 2,
                      style: GoogleFonts.nunito(fontSize: 13, color: _navy, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        hintText: 'e.g. Jl. Cipete Raya No. 12, Cilandak, Jakarta Selatan',
                        hintStyle: GoogleFonts.nunito(fontSize: 12, color: _navy.withValues(alpha: 0.4)),
                        prefixIcon: Icon(Icons.location_on_outlined, size: 18, color: themeColor),
                        filled: true,
                        fillColor: _bgWhite,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: (hasAttemptedSubmit && addressErr != null)
                                ? const Color(0xFFE53935)
                                : _navy.withValues(alpha: 0.15),
                            width: (hasAttemptedSubmit && addressErr != null) ? 1.5 : 1,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: (hasAttemptedSubmit && addressErr != null)
                                ? const Color(0xFFE53935)
                                : _navy.withValues(alpha: 0.15),
                            width: (hasAttemptedSubmit && addressErr != null) ? 1.5 : 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: (hasAttemptedSubmit && addressErr != null)
                                ? const Color(0xFFE53935)
                                : themeColor,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    if (hasAttemptedSubmit && addressErr != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '⚠️ $addressErr',
                        style: GoogleFonts.nunito(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFE53935),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),

                    // Interactive Mini-Map (Matching Sighting Detail Outcome Form)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        height: 150,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8EAF0),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _navy.withValues(alpha: 0.1)),
                        ),
                        child: Stack(
                          children: [
                            FlutterMap(
                              mapController: miniMapCtrl,
                              options: MapOptions(
                                initialCenter: ll.LatLng(selectedLat, selectedLng),
                                initialZoom: 15.5,
                                onTap: (tapPos, point) async {
                                  selectedLat = point.latitude;
                                  selectedLng = point.longitude;
                                  setModalState(() => isLocatingAddress = true);
                                  try {
                                    final addr = await _locationService.getAddressFromCoordinates(
                                      point.latitude,
                                      point.longitude,
                                    );
                                    addressCtrl.text = addr;
                                  } catch (_) {}
                                  setModalState(() => isLocatingAddress = false);
                                },
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName: 'com.pawwatch.app',
                                ),
                                MarkerLayer(
                                  markers: [
                                    Marker(
                                      point: ll.LatLng(selectedLat, selectedLng),
                                      width: 44,
                                      height: 44,
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: themeColor,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: Colors.white, width: 2.5),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(alpha: 0.25),
                                                blurRadius: 6,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: Image.asset(
                                            activeAsset,
                                            width: 20,
                                            height: 20,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Tap map to drop pin',
                                  style: GoogleFonts.nunito(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            if (isLocatingAddress)
                              const Positioned(
                                bottom: 8,
                                left: 8,
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 24-Hours Switch
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Open 24 Hours Emergency?',
                        style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w800, color: _navy),
                      ),
                      value: is24Hours,
                      activeThumbColor: themeColor,
                      onChanged: (val) => setModalState(() => is24Hours = val),
                    ),

                    if (!is24Hours) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Operating Hours',
                        style: GoogleFonts.nunito(fontSize: 12.5, fontWeight: FontWeight.w800, color: _navy),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: hoursCtrl,
                        style: GoogleFonts.nunito(fontSize: 13, color: _navy, fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          hintText: 'e.g. 09:00 - 21:00 (Mon - Sat)',
                          hintStyle: GoogleFonts.nunito(fontSize: 12, color: _navy.withValues(alpha: 0.4)),
                          prefixIcon: Icon(Icons.access_time_rounded, size: 18, color: themeColor),
                          filled: true,
                          fillColor: _bgWhite,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: _navy.withValues(alpha: 0.15)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: _navy.withValues(alpha: 0.15)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: themeColor, width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Services / Tags
                    Text(
                      'Services & Facilities (Optional)',
                      style: GoogleFonts.nunito(fontSize: 12.5, fontWeight: FontWeight.w800, color: _navy),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: currentServices.map((service) {
                        final isSelected = selectedServices.contains(service);
                        return FilterChip(
                          label: Text(service),
                          selected: isSelected,
                          onSelected: (val) {
                            setModalState(() {
                              if (val) {
                                selectedServices.add(service);
                              } else {
                                selectedServices.remove(service);
                              }
                            });
                          },
                          labelStyle: GoogleFonts.nunito(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isSelected ? Colors.white : _navy,
                          ),
                          backgroundColor: _lavLight.withValues(alpha: 0.4),
                          selectedColor: themeColor,
                          checkmarkColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),

                    // Additional Notes
                    Text(
                      'Notes or Description (Optional)',
                      style: GoogleFonts.nunito(fontSize: 12.5, fontWeight: FontWeight.w800, color: _navy),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: notesCtrl,
                      onChanged: (_) => setModalState(() {}),
                      maxLines: 2,
                      style: GoogleFonts.nunito(fontSize: 13, color: _navy),
                      decoration: InputDecoration(
                        hintText: 'e.g. Offers stray discounts, Dr. Budi is very gentle with rescue kittens.',
                        hintStyle: GoogleFonts.nunito(fontSize: 12, color: _navy.withValues(alpha: 0.4)),
                        prefixIcon: Icon(Icons.notes_rounded, size: 18, color: themeColor),
                        filled: true,
                        fillColor: _bgWhite,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: (hasAttemptedSubmit && notesErr != null)
                                ? const Color(0xFFE53935)
                                : _navy.withValues(alpha: 0.15),
                            width: (hasAttemptedSubmit && notesErr != null) ? 1.5 : 1,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: (hasAttemptedSubmit && notesErr != null)
                                ? const Color(0xFFE53935)
                                : _navy.withValues(alpha: 0.15),
                            width: (hasAttemptedSubmit && notesErr != null) ? 1.5 : 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: (hasAttemptedSubmit && notesErr != null)
                                ? const Color(0xFFE53935)
                                : themeColor,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    if (hasAttemptedSubmit && notesErr != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '⚠️ $notesErr',
                        style: GoogleFonts.nunito(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFE53935),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),

                    // Warning Banner
                    if (formValidationError != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFEF5350)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFD32F2F)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                formValidationError!,
                                style: GoogleFonts.nunito(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFFB71C1C),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: themeColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 1,
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                final currentNameErr = TextModerationService.validateFacilityName(
                                  nameCtrl.text,
                                  label: type == 'clinic' ? 'Vet Clinic' : 'Animal Shelter',
                                );
                                if (currentNameErr != null) {
                                  setModalState(() {
                                    hasAttemptedSubmit = true;
                                    formValidationError = '⚠️ $currentNameErr';
                                  });
                                  return;
                                }

                                final currentPhoneErr = TextModerationService.validatePhoneNumber(
                                  phoneCtrl.text,
                                  label: 'Emergency contact phone',
                                );
                                if (currentPhoneErr != null) {
                                  setModalState(() {
                                    hasAttemptedSubmit = true;
                                    formValidationError = '⚠️ $currentPhoneErr';
                                  });
                                  return;
                                }

                                final currentAddressErr = TextModerationService.validateAddress(
                                  addressCtrl.text,
                                  label: 'Facility address',
                                );
                                if (currentAddressErr != null) {
                                  setModalState(() {
                                    hasAttemptedSubmit = true;
                                    formValidationError = '⚠️ $currentAddressErr';
                                  });
                                  return;
                                }

                                if (notesCtrl.text.trim().isNotEmpty) {
                                  final currentNotesErr = TextModerationService.validateDescription(
                                    notesCtrl.text,
                                    fieldName: 'Notes',
                                  );
                                  if (currentNotesErr != null) {
                                    setModalState(() {
                                      hasAttemptedSubmit = true;
                                      formValidationError = '⚠️ $currentNotesErr';
                                    });
                                    return;
                                  }
                                }

                                setModalState(() {
                                  isSubmitting = true;
                                  formValidationError = null;
                                });
                                final messenger = ScaffoldMessenger.of(context);
                                final nav = Navigator.of(ctx);

                                try {
                                  await FirebaseService.instance.submitClinicSuggestion(
                                    name: nameCtrl.text.trim(),
                                    type: type,
                                    address: addressCtrl.text.trim(),
                                    latitude: selectedLat,
                                    longitude: selectedLng,
                                    phone: phoneCtrl.text.trim(),
                                    operatingHours: is24Hours ? '24 Hours Emergency' : hoursCtrl.text.trim(),
                                    is24Hours: is24Hours,
                                    services: selectedServices.toList(),
                                    notes: notesCtrl.text.trim(),
                                  );

                                  if (!mounted) return;
                                  nav.pop();
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Row(
                                        children: [
                                          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Suggestion submitted! Our team will verify and add it to the map directory. 🐾',
                                              style: GoogleFonts.nunito(fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                        ],
                                      ),
                                      backgroundColor: _resolved,
                                      behavior: SnackBarBehavior.floating,
                                      duration: const Duration(seconds: 4),
                                    ),
                                  );
                                } catch (e) {
                                  if (!mounted) return;
                                  setModalState(() {
                                    isSubmitting = false;
                                    formValidationError = 'Failed to submit: $e';
                                  });
                                }
                              },
                        child: isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Image.asset(
                                    activeAsset,
                                    width: 20,
                                    height: 20,
                                    fit: BoxFit.contain,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Submit for Admin Review',
                                    style: GoogleFonts.nunito(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Small Triangle Painter for Map Pins
// -----------------------------------------------------------------------------
class _TrianglePainter extends CustomPainter {
  final Color color;
  const _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TrianglePainter oldDelegate) => oldDelegate.color != color;
}
