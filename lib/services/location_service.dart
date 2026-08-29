import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class LocationResult {
  final double latitude;
  final double longitude;
  final String formattedAddress;
  final bool isGpsAutoFilled;
  final String? errorMessage;

  const LocationResult({
    required this.latitude,
    required this.longitude,
    required this.formattedAddress,
    this.isGpsAutoFilled = true,
    this.errorMessage,
  });

  // Default fallback (Jakarta, Indonesia)
  static const LocationResult defaultJakarta = LocationResult(
    latitude: -6.2615,
    longitude: 106.8106,
    formattedAddress:
        'Jl. Kemang Raya No. 45, Bangka, Mampang Prapatan,\nJakarta Selatan 12730, Indonesia',
    isGpsAutoFilled: false,
  );
}

class LocationService {
  Future<LocationResult> getCurrentUserLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return const LocationResult(
          latitude: -6.2615,
          longitude: 106.8106,
          formattedAddress:
              'Jl. Kemang Raya No. 45, Bangka, Mampang Prapatan,\nJakarta Selatan 12730, Indonesia',
          isGpsAutoFilled: false,
          errorMessage: 'Location services are disabled on device.',
        );
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return const LocationResult(
            latitude: -6.2615,
            longitude: 106.8106,
            formattedAddress:
                'Jl. Kemang Raya No. 45, Bangka, Mampang Prapatan,\nJakarta Selatan 12730, Indonesia',
            isGpsAutoFilled: false,
            errorMessage: 'Location permission was denied.',
          );
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return const LocationResult(
          latitude: -6.2615,
          longitude: 106.8106,
          formattedAddress:
              'Jl. Kemang Raya No. 45, Bangka, Mampang Prapatan,\nJakarta Selatan 12730, Indonesia',
          isGpsAutoFilled: false,
          errorMessage:
              'Location permissions are permanently denied, please enable in settings.',
        );
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            timeLimit: Duration(seconds: 8),
          ),
        );
      } catch (_) {
        position = await Geolocator.getLastKnownPosition();
      }

      position ??= await Geolocator.getLastKnownPosition();

      if (position == null) {
        return const LocationResult(
          latitude: -6.2615,
          longitude: 106.8106,
          formattedAddress:
              'Jl. Kemang Raya No. 45, Bangka, Mampang Prapatan,\nJakarta Selatan 12730, Indonesia',
          isGpsAutoFilled: false,
          errorMessage: 'Could not obtain GPS lock.',
        );
      }

      final address = await getAddressFromCoordinates(
        position.latitude,
        position.longitude,
      );

      return LocationResult(
        latitude: position.latitude,
        longitude: position.longitude,
        formattedAddress: address,
        isGpsAutoFilled: true,
      );
    } catch (e) {
      return LocationResult(
        latitude: -6.2615,
        longitude: 106.8106,
        formattedAddress:
            'Jl. Kemang Raya No. 45, Bangka, Mampang Prapatan,\nJakarta Selatan 12730, Indonesia',
        isGpsAutoFilled: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<String> getAddressFromCoordinates(double lat, double lng) async {
    try {
      final List<Placemark> placemarks =
          await placemarkFromCoordinates(lat, lng);

      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = <String>[];

        final name = (p.name ?? '').trim();
        final street = (p.street ?? '').trim();
        final subLocality = (p.subLocality ?? '').trim();
        final locality = (p.locality ?? '').trim();
        final subAdminArea = (p.subAdministrativeArea ?? '').trim();
        final postalCode = (p.postalCode ?? '').trim();
        final country = (p.country ?? '').trim();

        if (street.isNotEmpty) {
          parts.add(street);
        } else if (name.isNotEmpty) {
          parts.add(name);
        }

        if (subLocality.isNotEmpty && !parts.contains(subLocality)) {
          parts.add(subLocality);
        }
        if (locality.isNotEmpty && !parts.contains(locality)) {
          parts.add(locality);
        } else if (subAdminArea.isNotEmpty && !parts.contains(subAdminArea)) {
          parts.add(subAdminArea);
        }

        if (postalCode.isNotEmpty) parts.add(postalCode);
        if (country.isNotEmpty) parts.add(country);

        if (parts.isNotEmpty) {
          if (parts.length >= 2) {
            return '${parts.take(2).join(', ')},\n${parts.skip(2).join(', ')}';
          }
          return parts.join(', ');
        }
      }
      return 'Lat: ${lat.toStringAsFixed(4)}, Lng: ${lng.toStringAsFixed(4)}';
    } catch (_) {
      return 'Lat: ${lat.toStringAsFixed(4)}, Lng: ${lng.toStringAsFixed(4)}';
    }
  }

  Future<LocationResult?> searchLocation(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return null;

    try {
      final List<Location> locations = await locationFromAddress(cleanQuery);
      if (locations.isNotEmpty) {
        final loc = locations.first;
        final address =
            await getAddressFromCoordinates(loc.latitude, loc.longitude);
        return LocationResult(
          latitude: loc.latitude,
          longitude: loc.longitude,
          formattedAddress: address,
          isGpsAutoFilled: false,
        );
      }
    } catch (_) {}
    return null;
  }
}
