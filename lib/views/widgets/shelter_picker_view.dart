import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/shelter_clinic.dart';
import '../../services/location_service.dart';
import '../../services/firebase_service.dart';
import '../../services/text_moderation_service.dart';

/// Reusable Shelter Directory & Registration component.
/// Provides:
/// 1. Closest/nearby shelters sorted by distance to the cat sighting/user.
/// 2. Search tab/bar to filter shelters by name, area, or services.
/// 3. Option to register/suggest a new shelter consistent with the map page.
/// 4. Auto-fills selected shelter details and coordinates.
class ShelterPickerView extends StatefulWidget {
  final double referenceLat;
  final double referenceLng;
  final String? initialShelterName;
  final String? initialShelterAddress;
  final ValueChanged<ShelterClinic> onShelterSelected;
  final VoidCallback? onClearSelection;
  /// Fires with `true` when the user switches to the Register New tab,
  /// and `false` when they switch back to Nearby Shelters.
  final ValueChanged<bool>? onRegisterTabActiveChanged;
  final Color themeColor;

  const ShelterPickerView({
    super.key,
    required this.referenceLat,
    required this.referenceLng,
    this.initialShelterName,
    this.initialShelterAddress,
    required this.onShelterSelected,
    this.onClearSelection,
    this.onRegisterTabActiveChanged,
    this.themeColor = const Color(0xFF00897B),
  });

  @override
  State<ShelterPickerView> createState() => _ShelterPickerViewState();
}

class _ShelterPickerViewState extends State<ShelterPickerView> {
  static const Color _navy = Color(0xFF1B2A4A);
  static const Color _urgent = Color(0xFFE53935);
  static const Color _lavLight = Color(0xFFF3F1F8);

  // Tab mode: 0 = Choose Nearby Shelter, 1 = Register New Shelter
  int _activeTab = 0;

  // Search
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // Shelters list
  List<ShelterClinic> _allShelters = [];
  bool _isLoadingShelters = true;
  ShelterClinic? _selectedShelter;
  bool _isPickerExpanded = false;

  // New shelter registration controllers
  final TextEditingController _regNameCtrl = TextEditingController();
  final TextEditingController _regPhoneCtrl = TextEditingController();
  final TextEditingController _regAddressCtrl = TextEditingController();
  final TextEditingController _regHoursCtrl = TextEditingController();
  final TextEditingController _regNotesCtrl = TextEditingController();
  final TextEditingController _regSearchCtrl = TextEditingController();
  final MapController _regMapCtrl = MapController();

  double _regLat = -6.2615;
  double _regLng = 106.8106;
  bool _isLocatingAddress = false;
  bool _isSearchingLocation = false;
  bool _reg24Hours = false;
  final Set<String> _regServices = <String>{};
  bool _isSubmittingNew = false;
  bool _hasAttemptedRegSubmit = false;
  String? _regValidationError;

  static const List<String> _availableShelterServices = [
    'Open Adoption',
    'Foster Care Intake',
    'TNR Recovery Spot',
    'Quarantine Facility',
    'Donation Drop-off',
  ];

  @override
  void initState() {
    super.initState();
    _regLat = widget.referenceLat;
    _regLng = widget.referenceLng;
    _loadShelters();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _regNameCtrl.dispose();
    _regPhoneCtrl.dispose();
    _regAddressCtrl.dispose();
    _regHoursCtrl.dispose();
    _regNotesCtrl.dispose();
    _regSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadShelters() async {
    setState(() => _isLoadingShelters = true);

    final List<ShelterClinic> list = [];
    // 1. Load static partner shelters
    list.addAll(ShelterClinic.partnerDirectory.where((s) => s.isShelter));

    // 2. Load approved/submitted shelter suggestions from Firestore
    try {
      final snap = await FirebaseFirestore.instance
          .collection('clinic_suggestions')
          .where('type', isEqualTo: 'shelter')
          .get();

      for (final doc in snap.docs) {
        final d = doc.data();
        // Shelters entered must be verified by admin before appearing in available list
        if (d['status'] != 'verified') continue;
        final id = doc.id;
        final name = d['name']?.toString() ?? '';
        if (name.isEmpty) continue;
        // Avoid duplicates if same name exists
        if (list.any((s) => s.name.toLowerCase() == name.toLowerCase())) {
          continue;
        }

        final lat = (d['latitude'] as num?)?.toDouble() ?? -6.2615;
        final lng = (d['longitude'] as num?)?.toDouble() ?? 106.8106;
        final addr = d['address']?.toString() ?? '';
        final phone = d['phone']?.toString() ?? '';
        final hours = d['operatingHours']?.toString() ?? 'Daily';
        final servList = (d['services'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [];
        final is24 = d['is24Hours'] == true;

        list.add(ShelterClinic(
          id: id,
          name: name,
          type: 'shelter',
          latitude: lat,
          longitude: lng,
          address: addr,
          phone: phone,
          operatingHours: hours,
          services: servList,
          is24Hours: is24,
          isVerified: d['status'] == 'verified',
        ));
      }
    } catch (_) {}

    // Sort by proximity to reference coordinates (closest first!)
    list.sort((a, b) {
      final distA = _calculateDistKm(a.latitude, a.longitude);
      final distB = _calculateDistKm(b.latitude, b.longitude);
      return distA.compareTo(distB);
    });

    ShelterClinic? matched;
    if (widget.initialShelterName != null &&
        widget.initialShelterName!.trim().isNotEmpty) {
      final name = widget.initialShelterName!.trim().toLowerCase();
      try {
        matched = list.firstWhere(
          (s) => s.name.toLowerCase().contains(name) || name.contains(s.name.toLowerCase()),
        );
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _allShelters = list;
        _isLoadingShelters = false;
        _selectedShelter = matched;
        _isPickerExpanded = _selectedShelter == null;
      });
    }
  }

  double _calculateDistKm(double lat, double lng) {
    const dist = ll.Distance();
    return dist.as(
      ll.LengthUnit.Kilometer,
      ll.LatLng(widget.referenceLat, widget.referenceLng),
      ll.LatLng(lat, lng),
    );
  }

  String _formatDist(double distKm) {
    if (distKm < 1.0) {
      final meters = (distKm * 1000).round();
      return '$meters m away';
    }
    return '${distKm.toStringAsFixed(1)} km away';
  }

  List<ShelterClinic> get _filteredShelters {
    if (_searchQuery.trim().isEmpty) return _allShelters;
    final q = _searchQuery.toLowerCase().trim();
    return _allShelters.where((s) {
      final nameMatch = s.name.toLowerCase().contains(q);
      final addrMatch = s.address.toLowerCase().contains(q);
      final servMatch = s.services.any((serv) => serv.toLowerCase().contains(q));
      return nameMatch || addrMatch || servMatch;
    }).toList();
  }

  void _selectShelter(ShelterClinic shelter) {
    setState(() {
      _selectedShelter = shelter;
      _isPickerExpanded = false;
    });
    widget.onShelterSelected(shelter);
  }

  Future<void> _handleRegisterNewShelter() async {
    final nameErr = TextModerationService.validateFacilityName(
      _regNameCtrl.text,
      label: 'Shelter organization',
    );
    if (nameErr != null || _regNameCtrl.text.trim().isEmpty) {
      setState(() {
        _hasAttemptedRegSubmit = true;
        _regValidationError = nameErr ?? 'Shelter / organization name is required.';
      });
      return;
    }

    final phoneErr = TextModerationService.validatePhoneNumber(
      _regPhoneCtrl.text,
      label: 'Emergency contact phone',
    );
    if (phoneErr != null || _regPhoneCtrl.text.trim().isEmpty) {
      setState(() {
        _hasAttemptedRegSubmit = true;
        _regValidationError = phoneErr ?? 'Contact phone number is required.';
      });
      return;
    }

    final addrErr = TextModerationService.validateAddress(
      _regAddressCtrl.text,
      label: 'Shelter address',
    );
    if (addrErr != null || _regAddressCtrl.text.trim().isEmpty) {
      setState(() {
        _hasAttemptedRegSubmit = true;
        _regValidationError = addrErr ?? 'Shelter address is required.';
      });
      return;
    }

    if (_regNotesCtrl.text.trim().isNotEmpty) {
      final notesErr = TextModerationService.validateDescription(
        _regNotesCtrl.text,
        fieldName: 'Notes',
      );
      if (notesErr != null) {
        setState(() {
          _hasAttemptedRegSubmit = true;
          _regValidationError = notesErr;
        });
        return;
      }
    }

    setState(() {
      _isSubmittingNew = true;
      _regValidationError = null;
    });

    try {
      await FirebaseService.instance.submitClinicSuggestion(
        name: _regNameCtrl.text.trim(),
        type: 'shelter',
        address: _regAddressCtrl.text.trim(),
        latitude: _regLat,
        longitude: _regLng,
        phone: _regPhoneCtrl.text.trim(),
        operatingHours: _reg24Hours
            ? '24 Hours Emergency Intake'
            : (_regHoursCtrl.text.trim().isEmpty ? 'Open Daily' : _regHoursCtrl.text.trim()),
        is24Hours: _reg24Hours,
        services: _regServices.toList(),
        notes: _regNotesCtrl.text.trim(),
      );
      final submittedName = _regNameCtrl.text.trim();
      setState(() {
        _isPickerExpanded = true;
        _activeTab = 0;
        _isSubmittingNew = false;
        _selectedShelter = null;
        _regNameCtrl.clear();
        _regAddressCtrl.clear();
        _regPhoneCtrl.clear();
        _regNotesCtrl.clear();
        _regHoursCtrl.clear();
      });

      widget.onRegisterTabActiveChanged?.call(false);
      widget.onClearSelection?.call();

      if (mounted) {
        showDialog(
          context: context,
          builder: (dCtx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.verified_user_rounded, color: Color(0xFF00897B)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Shelter Submitted for Review',
                    style: GoogleFonts.nunito(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ),
              ],
            ),
            content: Text(
              'Thank you! "$submittedName" has been submitted for admin verification on the Community Map.\n\nTo safeguard rescued cats from unauthorized or unsafe facilities, newly suggested shelters must be verified by administrators before cats can be transferred to them. Please select an existing verified partner shelter from the list below.',
              style: GoogleFonts.nunito(fontSize: 13, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dCtx),
                child: Text('Understood', style: GoogleFonts.nunito(fontWeight: FontWeight.w800, color: const Color(0xFF00897B))),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmittingNew = false;
          _regValidationError = 'Failed to suggest shelter: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: widget.themeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Image.asset(
                'assets/images/shelter.png',
                width: 22,
                height: 22,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Shelter / Organization Partner *',
                    style: GoogleFonts.nunito(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: _navy,
                    ),
                  ),
                  Text(
                    'Select verified nearby shelter or register a new one',
                    style: GoogleFonts.nunito(
                      fontSize: 11,
                      color: _navy.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // If a shelter is selected and picker is not expanded, show selected card
        if (_selectedShelter != null && !_isPickerExpanded) ...[
          _buildSelectedShelterCard(),
        ] else ...[
          // Segmented Tabs: [ Nearby Shelters ] | [ Register New Shelter ]
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F1F5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _activeTab = 0);
                      widget.onRegisterTabActiveChanged?.call(false);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _activeTab == 0 ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: _activeTab == 0
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.verified_rounded,
                            size: 15,
                            color: _activeTab == 0 ? widget.themeColor : _navy.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Verified Shelters (${_allShelters.length})',
                            style: GoogleFonts.nunito(
                              fontSize: 12,
                              fontWeight: _activeTab == 0 ? FontWeight.w800 : FontWeight.w600,
                              color: _activeTab == 0 ? widget.themeColor : _navy.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _activeTab = 1;
                        _selectedShelter = null;
                        _isPickerExpanded = true;
                      });
                      widget.onClearSelection?.call();
                      widget.onRegisterTabActiveChanged?.call(true);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _activeTab == 1 ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: _activeTab == 1
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_location_alt_rounded,
                            size: 15,
                            color: _activeTab == 1 ? widget.themeColor : _navy.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Suggest to Map',
                            style: GoogleFonts.nunito(
                              fontSize: 12,
                              fontWeight: _activeTab == 1 ? FontWeight.w800 : FontWeight.w600,
                              color: _activeTab == 1 ? widget.themeColor : _navy.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Tab content
          if (_activeTab == 0) _buildNearbySheltersTab() else _buildRegisterNewShelterTab(),

          if (_selectedShelter != null) ...[
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () => setState(() => _isPickerExpanded = false),
                icon: const Icon(Icons.close_rounded, size: 16),
                label: Text(
                  'Keep Currently Selected Shelter',
                  style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: _navy.withValues(alpha: 0.7),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildSelectedShelterCard() {
    final s = _selectedShelter!;
    final distKm = _calculateDistKm(s.latitude, s.longitude);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: widget.themeColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.themeColor.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: widget.themeColor.withValues(alpha: 0.15),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/images/shelter.png',
                  width: 24,
                  height: 24,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            s.name,
                            style: GoogleFonts.nunito(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w900,
                              color: _navy,
                            ),
                          ),
                        ),
                        if (s.isVerified) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.verified_rounded, size: 15, color: Color(0xFF2E7D32)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: widget.themeColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.near_me_rounded, size: 10, color: widget.themeColor),
                              const SizedBox(width: 3),
                              Text(
                                _formatDist(distKm),
                                style: GoogleFonts.nunito(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: widget.themeColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (s.is24Hours)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E88E5).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '24h Intake',
                              style: GoogleFonts.nunito(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF1E88E5),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: () => setState(() => _isPickerExpanded = true),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: widget.themeColor.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Change',
                  style: GoogleFonts.nunito(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: widget.themeColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            s.address,
            style: GoogleFonts.nunito(
              fontSize: 12,
              color: _navy.withValues(alpha: 0.75),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (s.phone.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.phone_outlined, size: 12, color: widget.themeColor),
                const SizedBox(width: 4),
                Text(
                  s.phone,
                  style: GoogleFonts.nunito(
                    fontSize: 11.5,
                    color: widget.themeColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.access_time_rounded, size: 12, color: _navy.withValues(alpha: 0.5)),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    s.operatingHours,
                    style: GoogleFonts.nunito(
                      fontSize: 11,
                      color: _navy.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNearbySheltersTab() {
    if (_isLoadingShelters) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(color: widget.themeColor, strokeWidth: 2.5),
            ),
            const SizedBox(height: 8),
            Text(
              'Finding closest partner shelters...',
              style: GoogleFonts.nunito(fontSize: 12, color: _navy.withValues(alpha: 0.6)),
            ),
          ],
        ),
      );
    }

    final filtered = _filteredShelters;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search bar
        Container(
          decoration: BoxDecoration(
            color: _lavLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _navy.withValues(alpha: 0.1)),
          ),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (val) => setState(() => _searchQuery = val),
            style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600, color: _navy),
            decoration: InputDecoration(
              hintText: 'Search nearby shelters by name or address...',
              hintStyle: GoogleFonts.nunito(fontSize: 12.5, color: _navy.withValues(alpha: 0.4)),
              prefixIcon: Icon(Icons.search_rounded, size: 18, color: widget.themeColor),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Count / Distance Note
        Row(
          children: [
            Icon(Icons.sort_rounded, size: 13, color: _navy.withValues(alpha: 0.5)),
            const SizedBox(width: 4),
            Text(
              'Sorted by proximity to cat sighting',
              style: GoogleFonts.nunito(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _navy.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Shelters List
        if (filtered.isEmpty) ...[
          Container(
            padding: const EdgeInsets.all(16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _navy.withValues(alpha: 0.1)),
            ),
            child: Column(
              children: [
                Icon(Icons.search_off_rounded, size: 32, color: _navy.withValues(alpha: 0.3)),
                const SizedBox(height: 6),
                Text(
                  'No shelter found matching "${_searchQuery.trim()}"',
                  style: GoogleFonts.nunito(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: _navy.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    _regNameCtrl.text = _searchQuery.trim();
                    setState(() {
                      _activeTab = 1;
                      _selectedShelter = null;
                      _isPickerExpanded = true;
                    });
                    widget.onClearSelection?.call();
                    widget.onRegisterTabActiveChanged?.call(true);
                  },
                  icon: const Icon(Icons.add_location_alt_rounded, size: 15),
                  label: Text('Suggest "$_searchQuery" on Map for Verification'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.themeColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    textStyle: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtered.length,
            separatorBuilder: (ctx, i) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              final shelter = filtered[i];
              final isSelected = _selectedShelter?.id == shelter.id ||
                  (_selectedShelter != null &&
                      _selectedShelter!.name.toLowerCase() == shelter.name.toLowerCase());
              final distKm = _calculateDistKm(shelter.latitude, shelter.longitude);

              return GestureDetector(
                onTap: () => _selectShelter(shelter),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected ? widget.themeColor.withValues(alpha: 0.08) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected
                          ? widget.themeColor
                          : _navy.withValues(alpha: 0.12),
                      width: isSelected ? 2.0 : 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Radio check
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected ? widget.themeColor : Colors.white,
                          border: Border.all(
                            color: isSelected ? widget.themeColor : _navy.withValues(alpha: 0.3),
                            width: 2,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, size: 14, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(width: 10),

                      // Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    shelter.name,
                                    style: GoogleFonts.nunito(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                      color: isSelected ? widget.themeColor : _navy,
                                    ),
                                  ),
                                ),
                                if (shelter.isVerified) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.verified_rounded, size: 14, color: Color(0xFF2E7D32)),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: widget.themeColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    _formatDist(distKm),
                                    style: GoogleFonts.nunito(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: widget.themeColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                if (shelter.is24Hours)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E88E5).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      '24h Emergency',
                                      style: GoogleFonts.nunito(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFF1E88E5),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              shelter.address,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.nunito(
                                fontSize: 11,
                                color: _navy.withValues(alpha: 0.7),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (shelter.services.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: shelter.services.take(3).map((serv) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _lavLight,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      serv,
                                      style: GoogleFonts.nunito(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        color: _navy.withValues(alpha: 0.75),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

        ],
      ],
    );
  }

  Widget _buildRegisterNewShelterTab() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FBFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.themeColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Registration Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: widget.themeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Image.asset(
                  'assets/images/shelter.png',
                  width: 24,
                  height: 24,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Suggest Shelter for Map Verification',
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: _navy,
                      ),
                    ),
                    Text(
                      'Requires admin verification on Community Map before cat transfers',
                      style: GoogleFonts.nunito(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: _navy.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF00897B).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFF00897B).withValues(alpha: 0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.shield_outlined,
                    color: Color(0xFF00897B), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'To protect rescued cats, newly suggested shelters must be verified by admins on the Community Map before cat transfers can be completed here.',
                    style: GoogleFonts.nunito(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF004D40),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 18),

          // Shelter Name
          Text(
            'Shelter / Organization Name *',
            style: GoogleFonts.nunito(fontSize: 12.5, fontWeight: FontWeight.w800, color: _navy),
          ),
          const SizedBox(height: 5),
          TextField(
            controller: _regNameCtrl,
            onChanged: (_) {
              if (_hasAttemptedRegSubmit) setState(() {});
            },
            style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600, color: _navy),
            decoration: InputDecoration(
              hintText: 'e.g. Sahabat Satwa Rescue Shelter',
              hintStyle: GoogleFonts.nunito(fontSize: 12.5, color: _navy.withValues(alpha: 0.4)),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: (_hasAttemptedRegSubmit && _regNameCtrl.text.trim().isEmpty)
                      ? _urgent
                      : _navy.withValues(alpha: 0.12),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: (_hasAttemptedRegSubmit && _regNameCtrl.text.trim().isEmpty)
                      ? _urgent
                      : _navy.withValues(alpha: 0.12),
                ),
              ),
            ),
          ),
          if (_hasAttemptedRegSubmit && _regNameCtrl.text.trim().isEmpty) ...[
            const SizedBox(height: 3),
            Text(
              '⚠️ Shelter organization name is required.',
              style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w700, color: _urgent),
            ),
          ],
          const SizedBox(height: 10),

          // Emergency Phone
          Text(
            'Emergency Contact Phone *',
            style: GoogleFonts.nunito(fontSize: 12.5, fontWeight: FontWeight.w800, color: _navy),
          ),
          const SizedBox(height: 5),
          TextField(
            controller: _regPhoneCtrl,
            keyboardType: TextInputType.phone,
            onChanged: (_) {
              if (_hasAttemptedRegSubmit) setState(() {});
            },
            style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600, color: _navy),
            decoration: InputDecoration(
              hintText: 'e.g. +62 812 3456 7890',
              hintStyle: GoogleFonts.nunito(fontSize: 12.5, color: _navy.withValues(alpha: 0.4)),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: (_hasAttemptedRegSubmit && _regPhoneCtrl.text.trim().isEmpty)
                      ? _urgent
                      : _navy.withValues(alpha: 0.12),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: (_hasAttemptedRegSubmit && _regPhoneCtrl.text.trim().isEmpty)
                      ? _urgent
                      : _navy.withValues(alpha: 0.12),
                ),
              ),
            ),
          ),
          if (_hasAttemptedRegSubmit && _regPhoneCtrl.text.trim().isEmpty) ...[
            const SizedBox(height: 3),
            Text(
              '⚠️ Emergency contact phone number is required.',
              style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w700, color: _urgent),
            ),
          ],
          const SizedBox(height: 10),

          // Address
          Text(
            'Facility Address *',
            style: GoogleFonts.nunito(fontSize: 12.5, fontWeight: FontWeight.w800, color: _navy),
          ),
          const SizedBox(height: 5),
          // Search address input
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _regSearchCtrl,
                  style: GoogleFonts.nunito(fontSize: 12.5, fontWeight: FontWeight.w600, color: _navy),
                  decoration: InputDecoration(
                    hintText: 'Search address or landmark...',
                    hintStyle: GoogleFonts.nunito(fontSize: 12, color: _navy.withValues(alpha: 0.4)),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: _navy.withValues(alpha: 0.12)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: _navy.withValues(alpha: 0.12)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: widget.themeColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: _isSearchingLocation
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.search, size: 16),
                onPressed: () async {
                  final q = _regSearchCtrl.text.trim();
                  if (q.isEmpty) return;
                  setState(() => _isSearchingLocation = true);
                  final res = await LocationService().searchLocation(q);
                  if (res != null && mounted) {
                    setState(() {
                      _regLat = res.latitude;
                      _regLng = res.longitude;
                      _regAddressCtrl.text = res.formattedAddress;
                      _isSearchingLocation = false;
                    });
                    try {
                      _regMapCtrl.move(ll.LatLng(_regLat, _regLng), 16.0);
                    } catch (_) {}
                  } else if (mounted) {
                    setState(() => _isSearchingLocation = false);
                  }
                },
              ),
              const SizedBox(width: 4),
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: _lavLight,
                  foregroundColor: _navy,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: _isLocatingAddress
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            color: _navy, strokeWidth: 2))
                    : const Icon(Icons.my_location, size: 16),
                onPressed: () async {
                  setState(() => _isLocatingAddress = true);
                  final res = await LocationService().getCurrentUserLocation();
                  if (mounted) {
                    setState(() {
                      _regLat = res.latitude;
                      _regLng = res.longitude;
                      _regAddressCtrl.text = res.formattedAddress;
                      _isLocatingAddress = false;
                    });
                    try {
                      _regMapCtrl.move(ll.LatLng(_regLat, _regLng), 16.0);
                    } catch (_) {}
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Mini Map for Pinning Shelter
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 130,
              width: double.infinity,
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _regMapCtrl,
                    options: MapOptions(
                      initialCenter: ll.LatLng(_regLat, _regLng),
                      initialZoom: 15.0,
                      onTap: (tapPos, point) async {
                        setState(() {
                          _regLat = point.latitude;
                          _regLng = point.longitude;
                          _isLocatingAddress = true;
                        });
                        final addr = await LocationService()
                            .getAddressFromCoordinates(point.latitude, point.longitude);
                        if (mounted) {
                          setState(() {
                            _regAddressCtrl.text = addr;
                            _isLocatingAddress = false;
                          });
                        }
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
                            point: ll.LatLng(_regLat, _regLng),
                            width: 36,
                            height: 36,
                            child: const Icon(
                              Icons.location_on,
                              color: Color(0xFF00897B),
                              size: 34,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Positioned(
                    bottom: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Tap map to set shelter pin',
                        style: GoogleFonts.nunito(fontSize: 9.5, fontWeight: FontWeight.w700, color: _navy),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),

          // Address field display
          TextField(
            controller: _regAddressCtrl,
            maxLines: 2,
            style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w600, color: _navy),
            decoration: InputDecoration(
              hintText: 'Full shelter address will appear here...',
              hintStyle: GoogleFonts.nunito(fontSize: 12, color: _navy.withValues(alpha: 0.4)),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.all(10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: (_hasAttemptedRegSubmit && _regAddressCtrl.text.trim().isEmpty)
                      ? _urgent
                      : _navy.withValues(alpha: 0.12),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: (_hasAttemptedRegSubmit && _regAddressCtrl.text.trim().isEmpty)
                      ? _urgent
                      : _navy.withValues(alpha: 0.12),
                ),
              ),
            ),
          ),
          if (_hasAttemptedRegSubmit && _regAddressCtrl.text.trim().isEmpty) ...[
            const SizedBox(height: 3),
            Text(
              '⚠️ Shelter address is required.',
              style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w700, color: _urgent),
            ),
          ],
          const SizedBox(height: 10),

          // 24h & Operating hours
          Row(
            children: [
              Expanded(
                child: Text(
                  '24 Hours Emergency Intake',
                  style: GoogleFonts.nunito(fontSize: 12.5, fontWeight: FontWeight.w700, color: _navy),
                ),
              ),
              Switch(
                value: _reg24Hours,
                activeThumbColor: widget.themeColor,
                activeTrackColor: widget.themeColor.withValues(alpha: 0.4),
                onChanged: (val) => setState(() => _reg24Hours = val),
              ),
            ],
          ),
          if (!_reg24Hours) ...[
            TextField(
              controller: _regHoursCtrl,
              style: GoogleFonts.nunito(fontSize: 12.5, fontWeight: FontWeight.w600, color: _navy),
              decoration: InputDecoration(
                hintText: 'e.g. 09:00 - 18:00 (Daily)',
                hintStyle: GoogleFonts.nunito(fontSize: 12, color: _navy.withValues(alpha: 0.4)),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: _navy.withValues(alpha: 0.12)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: _navy.withValues(alpha: 0.12)),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Services chips
          Text(
            'Shelter Services Offered',
            style: GoogleFonts.nunito(fontSize: 12.5, fontWeight: FontWeight.w800, color: _navy),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _availableShelterServices.map((service) {
              final isSelected = _regServices.contains(service);
              return FilterChip(
                label: Text(service),
                selected: isSelected,
                selectedColor: widget.themeColor.withValues(alpha: 0.15),
                checkmarkColor: widget.themeColor,
                labelStyle: GoogleFonts.nunito(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? widget.themeColor : _navy,
                ),
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: isSelected ? widget.themeColor : _navy.withValues(alpha: 0.15),
                  ),
                ),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _regServices.add(service);
                    } else {
                      _regServices.remove(service);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 10),

          // Volunteer Notes (Optional)
          Text(
            'Volunteer Notes / Intake Guidelines (Optional)',
            style: GoogleFonts.nunito(fontSize: 12.5, fontWeight: FontWeight.w800, color: _navy),
          ),
          const SizedBox(height: 5),
          TextField(
            controller: _regNotesCtrl,
            maxLines: 2,
            style: GoogleFonts.nunito(fontSize: 12.5, fontWeight: FontWeight.w600, color: _navy),
            decoration: InputDecoration(
              hintText: 'e.g. Call before arrival; quarantine cages available in back.',
              hintStyle: GoogleFonts.nunito(fontSize: 12, color: _navy.withValues(alpha: 0.4)),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.all(10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: _navy.withValues(alpha: 0.12)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: _navy.withValues(alpha: 0.12)),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Error banner if any
          if (_regValidationError != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _urgent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _urgent.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 16, color: _urgent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _regValidationError!,
                      style: GoogleFonts.nunito(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFB71C1C),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Submit & Select Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSubmittingNew ? null : _handleRegisterNewShelter,
              icon: _isSubmittingNew
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.check_circle_rounded, size: 18),
              label: Text(
                _isSubmittingNew ? 'Submitting Suggestion...' : 'Submit Shelter for Map Verification',
                style: GoogleFonts.nunito(fontSize: 13.5, fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.themeColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
