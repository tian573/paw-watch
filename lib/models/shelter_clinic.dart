class ShelterClinic {
  final String id;
  final String name;
  final String type;
  final double latitude;
  final double longitude;
  final String address;
  final String phone;
  final String operatingHours;
  final List<String> services;
  final bool is24Hours;
  final bool isVerified;

  const ShelterClinic({
    required this.id,
    required this.name,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.phone,
    required this.operatingHours,
    required this.services,
    this.is24Hours = false,
    this.isVerified = true,
  });

  bool get isShelter => type == 'shelter';
  bool get isClinic => type == 'clinic';

  String get typeLabel => isShelter ? 'Animal Shelter' : 'Veterinary Clinic';

  static List<ShelterClinic> get partnerDirectory => const [
        ShelterClinic(
          id: 'sc_pejaten',
          name: 'Pejaten Animal Shelter',
          type: 'shelter',
          latitude: -6.2840,
          longitude: 106.8280,
          address: 'Jl. Pejaten Barat No. 23, Pasar Minggu, Jakarta Selatan',
          phone: '+62 21 7890 1234',
          operatingHours: '09:00 - 17:00 (Daily)',
          services: [
            '🏛️ Open Adoption',
            '🐾 Foster Care',
            '💉 Quarantine Intake',
            '🌿 TNR Recovery Spot'
          ],
          is24Hours: false,
          isVerified: true,
        ),
        ShelterClinic(
          id: 'sc_jaan',
          name: 'Jakarta Animal Aid Network (JAAN)',
          type: 'shelter',
          latitude: -6.3050,
          longitude: 106.7850,
          address: 'Jl. Cilandak Barat No. 12, Cilandak, Jakarta Selatan',
          phone: '+62 811 999 8888',
          operatingHours: '08:00 - 18:00 (Daily)',
          services: [
            '🚨 Emergency Rescue',
            '🏥 Wildlife & Stray Care',
            '🏡 Adoption Program',
            '🤝 Community Volunteers'
          ],
          is24Hours: false,
          isVerified: true,
        ),
        ShelterClinic(
          id: 'sc_amore_kemang',
          name: 'Amore Animal Clinic Kemang',
          type: 'clinic',
          latitude: -6.2650,
          longitude: 106.8150,
          address: 'Jl. Kemang Selatan No. 14, Bangka, Jakarta Selatan',
          phone: '+62 21 719 5555',
          operatingHours: 'Open 24 Hours',
          services: [
            '🚨 24/7 Emergency',
            '🩺 General Checkup',
            '✂️ Spay & Neuter',
            '🏥 Inpatient ICU'
          ],
          is24Hours: true,
          isVerified: true,
        ),
        ShelterClinic(
          id: 'sc_drh_cucu',
          name: 'PDHB Drh. Cucu Vet Hospital',
          type: 'clinic',
          latitude: -6.2580,
          longitude: 106.8020,
          address: 'Jl. Radio Dalam Raya No. 88, Gandaria, Jakarta Selatan',
          phone: '+62 21 726 4444',
          operatingHours: '08:00 - 21:00 (Daily)',
          services: [
            '🩺 Diagnostic Lab',
            '🔬 Orthopedic Surgery',
            '💉 Cat Vaccines',
            '🩹 Trauma Wound Care'
          ],
          is24Hours: false,
          isVerified: true,
        ),
        ShelterClinic(
          id: 'sc_aspera',
          name: 'ASPERA Kitten Nursery & Shelter',
          type: 'shelter',
          latitude: -6.2720,
          longitude: 106.8180,
          address: 'Jl. Kemang Timur No. 10, Mampang Prapatan, Jakarta Selatan',
          phone: '+62 812 3456 7890',
          operatingHours: '10:00 - 18:00 (Daily)',
          services: [
            '🍼 Kitten Incubator',
            '🐱 Socialization',
            '🏡 Forever Home Matching',
            '🩺 Health Verification'
          ],
          is24Hours: false,
          isVerified: true,
        ),
        ShelterClinic(
          id: 'sc_modern_cipete',
          name: 'Modern Vet Clinic Cipete',
          type: 'clinic',
          latitude: -6.2750,
          longitude: 106.8050,
          address: 'Jl. Cipete Raya No. 15, Cipete Selatan, Jakarta Selatan',
          phone: '+62 21 759 1122',
          operatingHours: '09:00 - 20:00 (Daily)',
          services: [
            '🩺 Vet Triage',
            '✂️ Subsidized TNR',
            '💊 Pet Pharmacy',
            '🔬 Ultrasound & X-Ray'
          ],
          is24Hours: false,
          isVerified: true,
        ),
      ];
}

