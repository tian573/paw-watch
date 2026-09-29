import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../../services/ai_service.dart';
import '../../services/location_service.dart';
import '../../services/firebase_service.dart';
import '../../services/text_moderation_service.dart';
import '../../utils/double_tap_guard.dart';
import '../../models/sighting.dart';
import '../widgets/shelter_picker_view.dart';

class ReportFormScreen extends StatefulWidget {
  const ReportFormScreen({super.key});

  @override
  State<ReportFormScreen> createState() => _ReportFormScreenState();
}

class _ReportFormScreenState extends State<ReportFormScreen> {
  static const Color _navy = Color(0xFF1B2A4A);
  static const Color _lavender = Color(0xFF9B8EC4);
  static const Color _bgWhite = Color(0xFFFAF9F7);
  static const Color _urgent = Color(0xFFE53935);
  static const Color _needsHelp = Color(0xFFFF7043);
  static const Color _resolved = Color(0xFF43A047);
  static const Color _cardBg = Color(0xFFFFFFFF);

  final ImagePicker _picker = ImagePicker();
  final AiValidationService _aiService = AiValidationService();
  final LocationService _locationService = LocationService();
  final MapController _mapController = MapController();

  final List<File> _photos = [];
  bool _isScanningPhoto = false;

  String _reportType = 'needsHelp'; // 'needsHelp' or 'resolved'
  String? _selectedCategory; // null = completely neutral start
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _routineHoursController = TextEditingController();
  final ScrollController _categoryScrollController = ScrollController();
  bool _isSearchingLocation = false;

  ll.LatLng _selectedLocation = const ll.LatLng(-6.2615, 106.8106);
  String _locationText = 'Detecting current location...';
  bool _isLocationLoading = false;
  bool _isGpsAutoFilled = false;
  bool _hasAttemptedSubmit = false;
  String? _formValidationError;
  String _resolvedPlacement = 'adopted'; // 'adopted' or 'shelter'
  String? _selectedShelterName;
  String? _selectedShelterAddress;
  bool _isRegisterTabActive = false;

  @override
  void initState() {
    super.initState();
    _fetchCurrentLocation();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _searchController.dispose();
    _routineHoursController.dispose();
    _categoryScrollController.dispose();
    super.dispose();
  }

  int get _totalSteps => _reportType == 'resolved' ? 4 : 5;

  int get _currentStepCount {
    int steps = 0;
    if (_titleController.text.trim().isNotEmpty) steps++;
    if (_photos.isNotEmpty) steps++;
    if (_reportType == 'needsHelp' &&
        _selectedCategory != null &&
        _selectedCategory!.isNotEmpty) {
      steps++;
    }
    if (!_isLocationLoading && _locationText.isNotEmpty) steps++;
    if (_descController.text.trim().isNotEmpty) steps++;
    return steps == 0 ? 1 : steps;
  }

  bool get _canSubmit {
    final titleValid = TextModerationService.validateReportTitle(_titleController.text) == null;
    final descValid = TextModerationService.validateDescription(_descController.text) == null;
    if (_reportType == 'resolved') {
      final shelterValid = _resolvedPlacement != 'shelter' || _selectedShelterName != null;
      return _photos.isNotEmpty && titleValid && descValid && shelterValid;
    }
    return _photos.isNotEmpty &&
        _selectedCategory != null &&
        _selectedCategory!.isNotEmpty &&
        titleValid &&
        descValid;
  }

  Future<void> _fetchCurrentLocation() async {
    setState(() => _isLocationLoading = true);
    final result = await _locationService.getCurrentUserLocation();
    if (!mounted) return;
    setState(() {
      _selectedLocation = ll.LatLng(result.latitude, result.longitude);
      _locationText = result.formattedAddress;
      _isGpsAutoFilled = result.isGpsAutoFilled;
      _isLocationLoading = false;
    });

    try {
      _mapController.move(_selectedLocation, 16.0);
    } catch (_) {}

    if (result.isGpsAutoFilled) {
      _showSnackBar('📍 Location auto-detected!');
    } else if (result.errorMessage != null) {
      _showSnackBar('⚠️ Location: ${result.errorMessage}');
    }
  }

  void _onMapTapped(ll.LatLng latLng) async {
    setState(() {
      _selectedLocation = latLng;
      _isLocationLoading = true;
      _isGpsAutoFilled = false;
    });

    final address = await _locationService.getAddressFromCoordinates(
      latLng.latitude,
      latLng.longitude,
    );

    if (!mounted) return;
    setState(() {
      _locationText = address;
      _isLocationLoading = false;
    });
  }

  void _handleSearchLocation(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() => _isSearchingLocation = true);

    final result = await _locationService.searchLocation(cleanQuery);

    if (!mounted) return;
    setState(() => _isSearchingLocation = false);

    if (result != null) {
      setState(() {
        _selectedLocation = ll.LatLng(result.latitude, result.longitude);
        _locationText = result.formattedAddress;
        _isGpsAutoFilled = false;
      });

      try {
        _mapController.move(_selectedLocation, 16.0);
      } catch (_) {}

      _showSnackBar('📍 Found location: $cleanQuery');
    } else {
      _showSnackBar('Could not find "$cleanQuery". Try adding a city name.');
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    return Scaffold(
      backgroundColor: _bgWhite,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoBanner(),
                    const SizedBox(height: 14),
                    _buildReportTypeSelector(),
                    const SizedBox(height: 14),
                    _buildTitleSection(),
                    const SizedBox(height: 14),
                    _buildPhotoSection(),
                    const SizedBox(height: 14),
                    if (_reportType == 'needsHelp') ...[
                      _buildCategorySection(),
                      const SizedBox(height: 14),
                    ],
                    if (_reportType == 'resolved') ...[
                      _buildResolvedShelterSection(),
                      const SizedBox(height: 14),
                    ],
                    _buildLocationSection(),
                    const SizedBox(height: 14),
                    _buildDescriptionSection(),
                    const SizedBox(height: 24),
                    _buildSubmitButton(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Container(
      color: _bgWhite,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: _navy, size: 22),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Text(
              'Report Sighting',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _navy,
              ),
            ),
          ),
          _buildStepIndicator(),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    final step = _currentStepCount;
    final total = _totalSteps;
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              value: step / total,
              strokeWidth: 3.5,
              backgroundColor: _lavender.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation<Color>(_lavender),
            ),
          ),
          Center(
            child: Text(
              '$step/$total',
              style: GoogleFonts.nunito(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: _navy,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _lavender.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _lavender.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _lavender.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.camera_alt_outlined, color: _lavender, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your report helps rescuers take action faster.',
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: _navy,
                    height: 1.3,
                  ),
                ),
                Text(
                  'AI validates every photo to ensure it contains a cat!',
                  style: GoogleFonts.nunito(
                    fontSize: 11,
                    color: _navy.withValues(alpha: 0.55),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Image.asset(
            'assets/images/LogoReportPage.png',
            width: 60,
            height: 60,
            fit: BoxFit.contain,
          ),
        ],
      ),
    );
  }

  Widget _buildReportTypeSelector() {
    final isHelp = _reportType == 'needsHelp';
    final isResolved = _reportType == 'resolved';

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: _navy.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _navy.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _reportType = 'needsHelp'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isHelp ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isHelp
                      ? [
                          BoxShadow(
                            color: _navy.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 20,
                      color: isHelp ? _needsHelp : _navy.withValues(alpha: 0.4),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Needs Help',
                          style: GoogleFonts.nunito(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: isHelp ? _navy : _navy.withValues(alpha: 0.5),
                          ),
                        ),
                        Text(
                          'Rescue / Care Needed',
                          style: GoogleFonts.nunito(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isHelp ? _needsHelp : _navy.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _reportType = 'resolved'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isResolved ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isResolved
                      ? [
                          BoxShadow(
                            color: _navy.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 20,
                      color: isResolved ? _resolved : _navy.withValues(alpha: 0.4),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Resolved / Safe',
                          style: GoogleFonts.nunito(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: isResolved ? _navy : _navy.withValues(alpha: 0.5),
                          ),
                        ),
                        Text(
                          'Cat is Safe or Adopted',
                          style: GoogleFonts.nunito(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isResolved ? _resolved : _navy.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleSection() {
    final titleError = _titleController.text.isNotEmpty
        ? TextModerationService.validateReportTitle(_titleController.text)
        : (_hasAttemptedSubmit ? 'Title is required (min 4 characters).' : null);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Icons.title_rounded,
            title: '1. Title (Required)',
            subtitle: 'Only letters, min 4 characters. No numbers or emojis.',
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: _bgWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: titleError != null
                    ? _urgent.withValues(alpha: 0.6)
                    : _navy.withValues(alpha: 0.1),
                width: titleError != null ? 1.5 : 1,
              ),
            ),
            child: TextField(
              controller: _titleController,
              maxLength: 70,
              onChanged: (_) => setState(() {}),
              style: GoogleFonts.nunito(
                fontSize: 13.5,
                color: _navy,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                hintText: "E.g. Injured calico cat behind minimarket",
                hintStyle: GoogleFonts.nunito(
                  fontSize: 13,
                  color: _navy.withValues(alpha: 0.35),
                  fontWeight: FontWeight.w500,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: InputBorder.none,
                counterStyle: GoogleFonts.nunito(
                  fontSize: 11,
                  color: _navy.withValues(alpha: 0.4),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (titleError != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.error_outline, size: 13, color: _urgent),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    titleError,
                    style: GoogleFonts.nunito(
                      fontSize: 11.5,
                      color: _urgent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPhotoSection() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Icons.camera_alt_outlined,
            title: '2. Add Photo',
            subtitle: 'Minimum 1 cat photo required (max 5). All verified by AI.',
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: List.generate(5, (index) {
                return Padding(
                  padding: EdgeInsets.only(right: index < 4 ? 8.0 : 0.0),
                  child: _buildPhotoSlot(index),
                );
              }),
            ),
          ),
          if (_hasAttemptedSubmit && _photos.isEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.error_outline, size: 14, color: _urgent),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '⚠️ At least 1 verified cat photo is required.',
                    style: GoogleFonts.nunito(
                      fontSize: 11.5,
                      color: _urgent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPhotoSlot(int index) {
    if (_isScanningPhoto && index == _photos.length) {
      return Container(
        width: index == 0 ? 125 : 78,
        height: 115,
        decoration: BoxDecoration(
          color: _lavender.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _lavender, width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: _lavender,
                strokeWidth: 2.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Scanning...',
              style: GoogleFonts.nunito(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: _lavender,
              ),
            ),
          ],
        ),
      );
    }

    if (index < _photos.length) {
      final photo = _photos[index];
      final isPrimary = index == 0;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: isPrimary ? 125 : 78,
              height: 115,
              decoration: BoxDecoration(
                border: Border.all(color: _resolved, width: 2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Image.file(
                photo,
                fit: BoxFit.cover,
              ),
            ),
          ),
          Positioned(
            top: 5,
            left: 5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: _resolved,
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 3,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, size: 9, color: Colors.white),
                  if (isPrimary) ...[
                    const SizedBox(width: 2),
                    Text(
                      'AI Verified',
                      style: GoogleFonts.nunito(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            top: 5,
            right: 5,
            child: GestureDetector(
              onTap: () => setState(() => _photos.removeAt(index)),
              child: Container(
                padding: const EdgeInsets.all(3.5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 12, color: Colors.white),
              ),
            ),
          ),
        ],
      );
    }

    final isNextSlot = index == _photos.length;

    if (index == 0) {
      return GestureDetector(
        onTap: _pickAndValidatePhoto,
        child: Container(
          width: 125,
          height: 115,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: (_hasAttemptedSubmit && _photos.isEmpty) ? _urgent : _lavender,
              width: (_hasAttemptedSubmit && _photos.isEmpty) ? 2.0 : 1.5,
              style: BorderStyle.solid,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.camera_alt_outlined, color: _lavender, size: 28),
              const SizedBox(height: 4),
              Text(
                'Tap to take photo',
                textAlign: TextAlign.center,
                style: GoogleFonts.nunito(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: _lavender,
                ),
              ),
              Text(
                'AI Cat Scan ★',
                textAlign: TextAlign.center,
                style: GoogleFonts.nunito(
                  fontSize: 10,
                  color: _navy.withValues(alpha: 0.5),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                decoration: BoxDecoration(
                  color: _lavender.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Required (1/5)',
                  style: GoogleFonts.nunito(
                    fontSize: 9,
                    color: _lavender,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: isNextSlot ? _pickAndValidatePhoto : null,
      child: Container(
        width: 78,
        height: 115,
        decoration: BoxDecoration(
          color: _bgWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isNextSlot
                ? _lavender.withValues(alpha: 0.4)
                : _navy.withValues(alpha: 0.08),
          ),
        ),
        child: Center(
          child: Icon(
            isNextSlot ? Icons.add_photo_alternate_outlined : Icons.image_outlined,
            size: 24,
            color: isNextSlot
                ? _lavender.withValues(alpha: 0.7)
                : _navy.withValues(alpha: 0.2),
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndValidatePhoto() async {
    if (_photos.length >= 5) {
      _showSnackBar('Maximum 5 photos reached.');
      return;
    }

    final source = await _showPhotoSourceBottomSheet();
    if (source == null) return;

    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );

      if (picked == null) return;

      final file = File(picked.path);
      setState(() => _isScanningPhoto = true);

      final result = await _aiService.validateCatImage(file);

      if (!mounted) return;
      setState(() => _isScanningPhoto = false);

      if (result.isCat) {
        setState(() {
          _photos.add(file);
        });
        _showSnackBar('✨ Cat verified! ${result.primaryLabel} (${(result.confidence * 100).toStringAsFixed(0)}%)');
      } else {
        _showAiRejectionDialog(file, result);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isScanningPhoto = false);
        _showSnackBar('Photo error: $e');
      }
    }
  }

  Future<ImageSource?> _showPhotoSourceBottomSheet() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, 28 + MediaQuery.paddingOf(ctx).bottom),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: _navy.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Add Cat Photo (AI Checked)',
              style: GoogleFonts.nunito(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: _navy,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(ctx, ImageSource.camera),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: _lavender.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _lavender.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.camera_alt_rounded, color: _lavender, size: 28),
                          const SizedBox(height: 6),
                          Text(
                            'Camera',
                            style: GoogleFonts.nunito(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: _navy,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: _lavender.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _lavender.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.photo_library_rounded, color: _lavender, size: 28),
                          const SizedBox(height: 6),
                          Text(
                            'Gallery',
                            style: GoogleFonts.nunito(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: _navy,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAiRejectionDialog(File rejectedFile, CatValidationResult result) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _urgent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning_amber_rounded, color: _urgent, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No Cat Detected',
                style: GoogleFonts.nunito(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _navy,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 120,
                width: double.infinity,
                child: Image.file(rejectedFile, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              result.message,
              style: GoogleFonts.nunito(
                fontSize: 13,
                color: _navy.withValues(alpha: 0.7),
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.nunito(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _navy.withValues(alpha: 0.6),
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _lavender,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _pickAndValidatePhoto();
            },
            child: Text(
              'Try Another Photo',
              style: GoogleFonts.nunito(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBoxItem(Map<String, dynamic> cat) {
    final key = cat['key'] as String;
    final isSelected = _selectedCategory == key;
    final col = cat['color'] as Color;

    return GestureDetector(
      onTap: () => setState(() {
        _selectedCategory = key;
      }),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. Title on top
          Text(
            cat['label'] as String,
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: isSelected ? col : _navy,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          // 2. Big box with custom icon in the center
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              color: isSelected
                  ? col.withValues(alpha: 0.12)
                  : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? col : _navy.withValues(alpha: 0.14),
                width: isSelected ? 2.5 : 1.2,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: col.withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Center(
                  child: Image.asset(
                    cat['asset'] as String,
                    width: 66,
                    height: 66,
                    fit: BoxFit.contain,
                  ),
                ),
                if (isSelected)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: col,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          // 3. Short description at the bottom
          Text(
            cat['sublabel'] as String,
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              color: isSelected ? col : _navy.withValues(alpha: 0.6),
              height: 1.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySection() {
    final categories = [
      {
        'key': 'Kitten',
        'label': 'Vulnerable',
        'sublabel': 'Kitten or high-risk cat',
        'asset': 'assets/images/vulnerable.png',
        'color': const Color(0xFFE91E63),
      },
      {
        'key': 'Injured',
        'label': 'Injured/Sick',
        'sublabel': 'Needs medical / vet care',
        'asset': 'assets/images/injuredsick.png',
        'color': _urgent,
      },
      {
        'key': 'Urgent Rescue',
        'label': 'Trapped',
        'sublabel': 'Immediate extraction',
        'asset': 'assets/images/trapped.png',
        'color': const Color(0xFFFF5722),
      },
      {
        'key': 'Needs Foster',
        'label': 'Needs Home',
        'sublabel': 'Seeking foster or adoption',
        'asset': 'assets/images/needshome.png',
        'color': const Color(0xFF9C27B0),
      },
      {
        'key': 'Stray',
        'label': 'Stray Community Care',
        'sublabel': 'Daily feeding & community care',
        'asset': 'assets/images/straycare.png',
        'color': _lavender,
      },
    ];

    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Icons.category_outlined,
            title: '3. Cat Situation & Goal',
            subtitle: 'Scroll to choose category to set permitted rescue actions.',
          ),
          const SizedBox(height: 14),
          Container(
            height: 380,
            decoration: BoxDecoration(
              color: const Color(0xFFF9F9FB),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: (_hasAttemptedSubmit && (_selectedCategory == null || _selectedCategory!.isEmpty))
                    ? _urgent
                    : _navy.withValues(alpha: 0.08),
                width: (_hasAttemptedSubmit && (_selectedCategory == null || _selectedCategory!.isEmpty)) ? 1.5 : 1.2,
              ),
            ),
            child: RawScrollbar(
              thumbVisibility: true,
              trackVisibility: true,
              thickness: 6,
              radius: const Radius.circular(8),
              thumbColor: _navy.withValues(alpha: 0.3),
              trackColor: _navy.withValues(alpha: 0.06),
              trackRadius: const Radius.circular(8),
              controller: _categoryScrollController,
              child: ListView.separated(
                controller: _categoryScrollController,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                itemCount: categories.length,
                separatorBuilder: (context, index) => const SizedBox(height: 20),
                itemBuilder: (context, index) {
                  return _buildCategoryBoxItem(categories[index]);
                },
              ),
            ),
          ),
          if (_hasAttemptedSubmit && (_selectedCategory == null || _selectedCategory!.isEmpty)) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.error_outline, size: 14, color: _urgent),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '⚠️ Please select a cat situation & rescue goal.',
                    style: GoogleFonts.nunito(
                      fontSize: 11.5,
                      color: _urgent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResolvedShelterSection() {
    final isShelter = _resolvedPlacement == 'shelter';
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Icons.home_work_outlined,
            title: 'Rescue Resolution & Safe Placement',
            subtitle: 'Choose where the cat was safely placed or surrendered.',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _resolvedPlacement = 'adopted'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: !isShelter ? _resolved.withValues(alpha: 0.12) : const Color(0xFFF0F1F5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: !isShelter ? _resolved : Colors.transparent,
                        width: !isShelter ? 1.6 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        const Text('🏡', style: TextStyle(fontSize: 18)),
                        const SizedBox(height: 2),
                        Text(
                          'Adopted / Home',
                          style: GoogleFonts.nunito(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: !isShelter ? _resolved : _navy.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _resolvedPlacement = 'shelter'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isShelter ? const Color(0xFF00897B).withValues(alpha: 0.12) : const Color(0xFFF0F1F5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isShelter ? const Color(0xFF00897B) : Colors.transparent,
                        width: isShelter ? 1.6 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        const Text('🏛️', style: TextStyle(fontSize: 18)),
                        const SizedBox(height: 2),
                        Text(
                          'Animal Shelter',
                          style: GoogleFonts.nunito(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: isShelter ? const Color(0xFF00897B) : _navy.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (isShelter) ...[
            const SizedBox(height: 14),
            ShelterPickerView(
              referenceLat: _selectedLocation.latitude,
              referenceLng: _selectedLocation.longitude,
              initialShelterName: _selectedShelterName,
              initialShelterAddress: _selectedShelterAddress,
              themeColor: const Color(0xFF00897B),
              onShelterSelected: (shelter) {
                setState(() {
                  _selectedShelterName = shelter.name;
                  _selectedShelterAddress = shelter.address;
                  _selectedLocation = ll.LatLng(shelter.latitude, shelter.longitude);
                  _locationText = shelter.address;
                });
                try {
                  _mapController.move(_selectedLocation, 16.0);
                } catch (_) {}
              },
              onClearSelection: () {
                setState(() {
                  _selectedShelterName = null;
                  _selectedShelterAddress = null;
                });
              },
              onRegisterTabActiveChanged: (isActive) {
                setState(() {
                  _isRegisterTabActive = isActive;
                });
              },
            ),
            if (_hasAttemptedSubmit && _selectedShelterName == null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, size: 14, color: Color(0xFFE53935)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Please choose a nearby shelter or register a new one above.',
                        style: GoogleFonts.nunito(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFE53935),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildLocationSection() {
    final isResolved = _reportType == 'resolved';

    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildSectionHeader(
                  icon: Icons.location_on_outlined,
                  title: isResolved ? '3. Location (City-Level Area)' : '4. Location',
                  subtitle: isResolved
                      ? 'Select the general city/area where the cat was rescued.'
                      : 'Pin the exact location where you saw the cat.',
                ),
              ),
              GestureDetector(
                onTap: _fetchCurrentLocation,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: _isGpsAutoFilled ? _lavender.withValues(alpha: 0.12) : Colors.white,
                    border: Border.all(color: _lavender.withValues(alpha: 0.45)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isLocationLoading)
                        const SizedBox(
                          width: 11,
                          height: 11,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            color: _lavender,
                          ),
                        )
                      else
                        const Icon(Icons.near_me_outlined, size: 12, color: _lavender),
                      const SizedBox(width: 4),
                      Text(
                        'Locate Me',
                        style: GoogleFonts.nunito(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: _lavender,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_reportType == 'resolved') ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _resolved.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _resolved.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined,
                      color: _resolved, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '🔒 Adopter Privacy: For resolved or rehomed cats, exact map coordinates are not published publicly to protect the adopter\'s private home.',
                      style: GoogleFonts.nunito(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: _navy.withValues(alpha: 0.8),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            height: 42,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: _bgWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _navy.withValues(alpha: 0.12)),
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(Icons.search_rounded, size: 18, color: _navy.withValues(alpha: 0.45)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: _handleSearchLocation,
                    style: GoogleFonts.nunito(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _navy,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search street, landmark, or city...',
                      hintStyle: GoogleFonts.nunito(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _navy.withValues(alpha: 0.4),
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                if (_isSearchingLocation)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _lavender),
                    ),
                  )
                else if (_searchController.text.isNotEmpty)
                  GestureDetector(
                    onTap: () => setState(() => _searchController.clear()),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Icon(Icons.close_rounded, size: 16, color: _navy.withValues(alpha: 0.4)),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: () => _handleSearchLocation(_searchController.text),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _lavender.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Search',
                        style: GoogleFonts.nunito(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: _lavender,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _buildInteractiveMap(),
          const SizedBox(height: 10),
          _buildLocationAddress(),
        ],
      ),
    );
  }

  Widget _buildInteractiveMap() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 190,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFE8EAF0),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _navy.withValues(alpha: 0.1)),
        ),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _selectedLocation,
                initialZoom: 16.0,
                onTap: (tapPosition, point) => _onMapTapped(point),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.pawwatch.app',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selectedLocation,
                      width: 46,
                      height: 46,
                      child: _buildMapPinMarker(),
                    ),
                  ],
                ),
              ],
            ),
            Positioned(
              right: 10,
              top: 10,
              child: Column(
                children: [
                  _buildMapButton(
                    Icons.my_location,
                    onTap: _fetchCurrentLocation,
                  ),
                  const SizedBox(height: 6),
                  _buildMapButton(
                    Icons.add,
                    onTap: () {
                      try {
                        final zoom = _mapController.camera.zoom + 1;
                        _mapController.move(_selectedLocation, zoom);
                      } catch (_) {}
                    },
                  ),
                  const SizedBox(height: 4),
                  _buildMapButton(
                    Icons.remove,
                    onTap: () {
                      try {
                        final zoom = _mapController.camera.zoom - 1;
                        _mapController.move(_selectedLocation, zoom);
                      } catch (_) {}
                    },
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.touch_app_outlined, size: 12, color: _lavender),
                    const SizedBox(width: 4),
                    Text(
                      'Tap map to drop pin',
                      style: GoogleFonts.nunito(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _navy,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapPinMarker() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _lavender,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: _lavender.withValues(alpha: 0.5),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(Icons.pets, color: Colors.white, size: 18),
        ),
        Container(
          width: 8,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(50),
          ),
        ),
      ],
    );
  }

  Widget _buildMapButton(IconData icon, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: _navy.withValues(alpha: 0.1),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 18, color: _navy),
      ),
    );
  }

  Widget _buildLocationAddress() {
    final isResolved = _reportType == 'resolved';
    final displayText = isResolved
        ? Sighting.extractCityOnly(_locationText)
        : _locationText;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
            isResolved ? Icons.shield_outlined : Icons.location_on,
            size: 16,
            color: isResolved ? _resolved : _lavender),
        const SizedBox(width: 8),
        Expanded(
          child: _isLocationLoading
              ? Text(
                  'Fetching real-time location...',
                  style: GoogleFonts.nunito(
                    fontSize: 12,
                    color: _navy.withValues(alpha: 0.5),
                    fontStyle: FontStyle.italic,
                  ),
                )
              : Text(
                  displayText,
                  style: GoogleFonts.nunito(
                    fontSize: 12,
                    color: _navy.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
        ),
        const SizedBox(width: 8),
        if (isResolved)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.shield_outlined, size: 13, color: _resolved),
              const SizedBox(width: 3),
              Text(
                'City Level Only',
                style: GoogleFonts.nunito(
                  fontSize: 11,
                  color: _resolved,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          )
        else if (_isGpsAutoFilled)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, size: 13, color: _resolved),
              const SizedBox(width: 3),
              Text(
                'GPS Auto-filled',
                style: GoogleFonts.nunito(
                  fontSize: 11,
                  color: _resolved,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          )
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.pin_drop_outlined, size: 13, color: _lavender),
              const SizedBox(width: 3),
              Text(
                'Pinned',
                style: GoogleFonts.nunito(
                  fontSize: 11,
                  color: _lavender,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildDescriptionSection() {
    final isResolved = _reportType == 'resolved';
    final descError = _descController.text.isNotEmpty
        ? TextModerationService.validateDescription(
            _descController.text,
            fieldName: isResolved ? 'Story' : 'Description',
          )
        : (_hasAttemptedSubmit
            ? (isResolved ? 'Story is required (min 8 characters).' : 'Description is required (min 8 characters).')
            : null);

    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Icons.edit_outlined,
            title: isResolved ? '4. Description & Story (Required)' : '5. Description (Required)',
            subtitle: 'Mandatory, min 8 characters. Must be meaningful words.',
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: _bgWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: descError != null
                    ? _urgent.withValues(alpha: 0.6)
                    : _navy.withValues(alpha: 0.1),
                width: descError != null ? 1.5 : 1,
              ),
            ),
            child: TextField(
              controller: _descController,
              maxLines: 5,
              maxLength: 500,
              onChanged: (_) => setState(() {}),
              style: GoogleFonts.nunito(
                fontSize: 13,
                color: _navy,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: isResolved
                    ? "E.g. Rescued from the street and happily adopted by my friend!"
                    : "E.g. color, size, behavior, what's around the cat, etc.",
                hintStyle: GoogleFonts.nunito(
                  fontSize: 13,
                  color: _navy.withValues(alpha: 0.35),
                  fontWeight: FontWeight.w500,
                ),
                contentPadding: const EdgeInsets.all(14),
                border: InputBorder.none,
                counterStyle: GoogleFonts.nunito(
                  fontSize: 11,
                  color: _navy.withValues(alpha: 0.4),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (descError != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.error_outline, size: 13, color: _urgent),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    descError,
                    style: GoogleFonts.nunito(
                      fontSize: 11.5,
                      color: _urgent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (!isResolved &&
              (_selectedCategory == 'Stray' ||
                  _selectedCategory == 'Feeding Spot' ||
                  _selectedCategory == 'Needs Foster' ||
                  _selectedCategory == 'Spotted')) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _lavender.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _lavender.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.schedule, size: 14, color: _lavender),
                      const SizedBox(width: 6),
                      Text(
                        'Usual Active Hours (Optional)',
                        style: GoogleFonts.nunito(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: _navy,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _routineHoursController,
                    maxLength: 80,
                    style: GoogleFonts.nunito(
                      fontSize: 12.5,
                      color: _navy,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          'e.g. Usually spotted around 5 PM - 8 PM near food stall',
                      hintStyle: GoogleFonts.nunito(
                        fontSize: 12,
                        color: _navy.withValues(alpha: 0.4),
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      counterStyle: GoogleFonts.nunito(
                        fontSize: 10,
                        color: _navy.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    final canSubmit = _canSubmit;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_formValidationError != null) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _urgent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _urgent.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 18, color: _urgent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _formValidationError!,
                    style: GoogleFonts.nunito(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFB71C1C),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        GestureDetector(
          onTap: () {
            final titleErr = TextModerationService.validateReportTitle(_titleController.text);
            final descErr = TextModerationService.validateDescription(
              _descController.text,
              fieldName: _reportType == 'resolved' ? 'Story' : 'Description',
            );
            if (_photos.isEmpty) {
              setState(() {
                _hasAttemptedSubmit = true;
                _formValidationError = 'Please add at least 1 verified cat photo.';
              });
              _showSnackBar('⚠️ Please add at least 1 verified cat photo.');
              return;
            }
            if (_reportType == 'needsHelp' &&
                (_selectedCategory == null || _selectedCategory!.isEmpty)) {
              setState(() {
                _hasAttemptedSubmit = true;
                _formValidationError = 'Please select a cat situation & rescue goal.';
              });
              _showSnackBar('⚠️ Please select a cat situation & rescue goal.');
              return;
            }
            if (_reportType == 'resolved' &&
                _resolvedPlacement == 'shelter') {
              if (_isRegisterTabActive && _selectedShelterName == null) {
                setState(() {
                  _hasAttemptedSubmit = true;
                  _formValidationError =
                      'Please tap "Register Shelter" to submit your suggested shelter first, or choose an available shelter.';
                });
                _showSnackBar(
                    '⚠️ Please tap "Register Shelter" to submit your suggested shelter first.');
                return;
              }
              if (_selectedShelterName == null) {
                setState(() {
                  _hasAttemptedSubmit = true;
                  _formValidationError =
                      'Please choose a nearby shelter or register a new one.';
                });
                _showSnackBar('⚠️ Please choose a nearby shelter or register a new one.');
                return;
              }
            }
            if (titleErr != null) {
              setState(() {
                _hasAttemptedSubmit = true;
                _formValidationError = titleErr;
              });
              _showSnackBar('⚠️ $titleErr');
              return;
            }
            if (descErr != null) {
              setState(() {
                _hasAttemptedSubmit = true;
                _formValidationError = descErr;
              });
              _showSnackBar('⚠️ $descErr');
              return;
            }
            setState(() => _formValidationError = null);
            _handleSubmit();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 17),
            decoration: BoxDecoration(
              gradient: canSubmit
                  ? const LinearGradient(
                      colors: [_lavender, Color(0xFF7B6DB5)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    )
                  : null,
              color: canSubmit ? null : _navy.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(18),
              boxShadow: canSubmit
                  ? [
                      BoxShadow(
                        color: _lavender.withValues(alpha: 0.4),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ]
                  : [],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.send_rounded,
                  size: 18,
                  color: canSubmit ? Colors.white : _navy.withValues(alpha: 0.3),
                ),
                const SizedBox(width: 8),
                Text(
                  'Submit Report',
                  style: GoogleFonts.nunito(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: canSubmit ? Colors.white : _navy.withValues(alpha: 0.3),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.055),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _lavender.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 17, color: _lavender),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.nunito(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _navy,
                ),
              ),
              Text(
                subtitle,
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  color: _navy.withValues(alpha: 0.5),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool _isSubmitting = false;
  Future<void> _handleSubmit() async {
    if (_isSubmitting || !DoubleTapGuard.allow('submit_report')) return;

    if (_photos.isEmpty) {
      DoubleTapGuard.reset('submit_report');
      setState(() {
        _hasAttemptedSubmit = true;
        _formValidationError = 'Please add at least 1 verified cat photo.';
      });
      _showSnackBar('⚠️ Please add at least 1 verified cat photo.');
      return;
    }
    if (_reportType == 'needsHelp' &&
        (_selectedCategory == null || _selectedCategory!.isEmpty)) {
      DoubleTapGuard.reset('submit_report');
      setState(() {
        _hasAttemptedSubmit = true;
        _formValidationError = 'Please select a cat situation & rescue goal.';
      });
      _showSnackBar('⚠️ Please select a cat situation & rescue goal.');
      return;
    }
    if (_reportType == 'resolved' &&
        _resolvedPlacement == 'shelter') {
      if (_isRegisterTabActive && _selectedShelterName == null) {
        DoubleTapGuard.reset('submit_report');
        setState(() {
          _hasAttemptedSubmit = true;
          _formValidationError =
              'Please tap "Register Shelter" to submit your suggested shelter first, or choose an available shelter.';
        });
        _showSnackBar(
            '⚠️ Please tap "Register Shelter" to submit your suggested shelter first.');
        return;
      }
      if (_selectedShelterName == null) {
        DoubleTapGuard.reset('submit_report');
        setState(() {
          _hasAttemptedSubmit = true;
          _formValidationError =
              'Please choose a nearby shelter or register a new one.';
        });
        _showSnackBar('⚠️ Please choose a nearby shelter or register a new one.');
        return;
      }
    }
    final titleErr = TextModerationService.validateReportTitle(_titleController.text);
    if (titleErr != null) {
      DoubleTapGuard.reset('submit_report');
      setState(() {
        _hasAttemptedSubmit = true;
        _formValidationError = titleErr;
      });
      _showSnackBar('⚠️ $titleErr');
      return;
    }
    final descErr = TextModerationService.validateDescription(
      _descController.text,
      fieldName: _reportType == 'resolved' ? 'Story' : 'Description',
    );
    if (descErr != null) {
      DoubleTapGuard.reset('submit_report');
      setState(() {
        _hasAttemptedSubmit = true;
        _formValidationError = descErr;
      });
      _showSnackBar('⚠️ $descErr');
      return;
    }

    setState(() => _isSubmitting = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: _lavender.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: _lavender,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Publishing Report...',
                  style: GoogleFonts.nunito(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Alerting local rescuers and colony feeders...',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.nunito(
                    fontSize: 12.5,
                    color: _navy.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final isResolved = _reportType == 'resolved';
    final finalAddress = isResolved
        ? Sighting.extractCityOnly(_locationText)
        : _locationText;

    final String finalUrgency;
    final String finalCategory;

    if (isResolved) {
      finalUrgency = 'resolved';
      finalCategory = 'Resolved';
    } else {
      finalCategory = _selectedCategory ?? 'Stray';
      finalUrgency = (_selectedCategory == 'Injured' ||
              _selectedCategory == 'Urgent Rescue' ||
              _selectedCategory == 'Kitten')
          ? 'urgent'
          : 'needsHelp';
    }

    final String finalDesc = (_reportType == 'resolved' &&
            _resolvedPlacement == 'shelter' &&
            _selectedShelterName != null)
        ? '${_descController.text.trim()}\n\nSafe Placement: Admitted to $_selectedShelterName${_selectedShelterAddress != null ? " ($_selectedShelterAddress)" : ""}.'
        : _descController.text.trim();

    try {
      await FirebaseService.instance.createSighting(
        title: _titleController.text.trim(),
        photos: _photos,
        latitude: _selectedLocation.latitude,
        longitude: _selectedLocation.longitude,
        locationAddress: finalAddress,
        description: finalDesc,
        urgency: finalUrgency,
        category: finalCategory,
        routineHours: _routineHoursController.text.trim(),
        temperament: null,
      );

      if (mounted) {
        Navigator.pop(context); // Dismiss loading dialog
        _showSnackBar('🎉 Sighting published live! +50 XP Earned 🐾');
        Navigator.pop(context, true); // Return to home feed
      }
    } catch (e) {
      DoubleTapGuard.reset('submit_report');
      if (mounted) {
        Navigator.pop(context); // Dismiss loading dialog
        setState(() => _isSubmitting = false);
        _showSnackBar('Failed to submit report: $e');
      }
    }
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.nunito(fontWeight: FontWeight.w600),
        ),
        backgroundColor: _navy,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}
