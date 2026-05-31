import 'dart:math';

/// Severity level of the crash / injury.
enum TriageLevel {
  red,    // Step 1 or 2: Immediate transport to Level 1 / highest level trauma center.
  yellow, // Step 3 or 4: Transport to trauma center (can be Level 2/3).
  green,  // Not meeting trauma criteria. Standard emergency department / local facility.
}

/// A structured representation of the triage assessment output.
class TriageAssessment {
  final TriageLevel level;
  final String destinationRecommendation;
  final List<String> triggeredCriteria;
  final String primarySOSNumber;

  TriageAssessment({
    required this.level,
    required this.destinationRecommendation,
    required this.triggeredCriteria,
    required this.primarySOSNumber,
  });

  @override
  String toString() {
    return 'TriageAssessment(Level: ${level.name.toUpperCase()}, '
        'Destination: $destinationRecommendation, '
        'Criteria: ${triggeredCriteria.join(", ")}, '
        'SOS Number: $primarySOSNumber)';
  }
}

/// Country-specific SOS configuration mapping.
class CountrySOSConfig {
  final String countryCode; // ISO 3166-1 alpha-2 (e.g. IN, US)
  final String countryName;
  final String police;
  final String ambulance;
  final String emergencyGeneral;

  const CountrySOSConfig({
    required this.countryCode,
    required this.countryName,
    required this.police,
    required this.ambulance,
    required this.emergencyGeneral,
  });
}

/// The main Global Triage and Emergency SOS Routing Engine.
class TriageEngine {
  // ISO 3166-1 Country Configurations
  static const Map<String, CountrySOSConfig> _countryConfigs = {
    'IN': CountrySOSConfig(
      countryCode: 'IN',
      countryName: 'India',
      police: '100',
      ambulance: '102',
      emergencyGeneral: '112',
    ),
    'US': CountrySOSConfig(
      countryCode: 'US',
      countryName: 'United States',
      police: '911',
      ambulance: '911',
      emergencyGeneral: '911',
    ),
    'GB': CountrySOSConfig(
      countryCode: 'GB',
      countryName: 'United Kingdom',
      police: '999',
      ambulance: '999',
      emergencyGeneral: '112',
    ),
    'EU': CountrySOSConfig(
      countryCode: 'EU',
      countryName: 'European Union Default',
      police: '112',
      ambulance: '112',
      emergencyGeneral: '112',
    ),
    'AU': CountrySOSConfig(
      countryCode: 'AU',
      countryName: 'Australia',
      police: '000',
      ambulance: '000',
      emergencyGeneral: '000',
    ),
    'ZA': CountrySOSConfig(
      countryCode: 'ZA',
      countryName: 'South Africa',
      police: '10111',
      ambulance: '10177',
      emergencyGeneral: '112',
    ),
  };

  /// Resolves the country's SOS configuration using an ISO 3166-1 alpha-2 code.
  /// Falls back to US (911) if the country is not registered or found.
  static CountrySOSConfig getSOSConfig(String isoCountryCode) {
    final cleaned = isoCountryCode.trim().toUpperCase();
    if (_countryConfigs.containsKey(cleaned)) {
      return _countryConfigs[cleaned]!;
    }
    // Generic European backup for common 112 implementations
    if (['FR', 'DE', 'IT', 'ES', 'NL', 'BE', 'SE', 'DK', 'FI'].contains(cleaned)) {
      return _countryConfigs['EU']!;
    }
    return _countryConfigs['US']!; // Global default fallback
  }

  /// Implements the ACS-COT (American College of Surgeons Committee on Trauma)
  /// Field Triage Decision Scheme to prioritize patients and recommend
  /// the appropriate emergency response destination.
  ///
  /// Inputs:
  /// - [gForce]: Max registered decel force.
  /// - [hasAirbagDeployed]: True if airbag deployment event detected.
  /// - [isRollover]: True if vehicular rollover detected.
  /// - [gcs]: Glasgow Coma Scale score (3 to 15).
  /// - [sysBP]: Systolic Blood Pressure (mmHg). Pass null if offline/unknown.
  /// - [respRate]: Respiratory rate (breaths per minute). Pass null if unknown.
  /// - [age]: User's age. Pass null if unknown.
  /// - [isAnticoagulant]: True if patient takes blood thinners/anticoagulants.
  /// - [isoCountryCode]: The ISO country code for SOS number routing.
  static TriageAssessment performTriage({
    required double gForce,
    required bool hasAirbagDeployed,
    required bool isRollover,
    required int gcs,
    int? sysBP,
    int? respRate,
    int? age,
    bool isAnticoagulant = false,
    String isoCountryCode = 'IN',
  }) {
    final List<String> triggered = [];
    final sosConfig = getSOSConfig(isoCountryCode);
    final String defaultSOS = sosConfig.emergencyGeneral;

    // --- STEP 1: Physiological Criteria (High Urgency - RED) ---
    bool step1Triggered = false;

    if (gcs < 14) {
      triggered.add('Altered mental status (GCS < 14)');
      step1Triggered = true;
    }

    if (sysBP != null && sysBP < 90) {
      triggered.add('Hypotension (Systolic BP < 90 mmHg)');
      step1Triggered = true;
    }

    if (respRate != null && (respRate < 10 || respRate > 29)) {
      triggered.add('Respiratory rate out of range (<10 or >29 bpm)');
      step1Triggered = true;
    }

    if (step1Triggered) {
      return TriageAssessment(
        level: TriageLevel.red,
        destinationRecommendation: 'Level 1 Trauma Center (Highest Available)',
        triggeredCriteria: triggered,
        primarySOSNumber: sosConfig.ambulance,
      );
    }

    // --- STEP 2: Anatomical/Crash Kinetic High Impact (RED) ---
    // If the deceleration crash g-force exceeds a critical lethal threshold (e.g. > 15G)
    if (gForce > 15.0) {
      triggered.add('Extremely High Impact G-Force (>15G: ${gForce.toStringAsFixed(1)}G)');
      return TriageAssessment(
        level: TriageLevel.red,
        destinationRecommendation: 'Level 1 Trauma Center (Highest Available)',
        triggeredCriteria: triggered,
        primarySOSNumber: sosConfig.ambulance,
      );
    }

    // --- STEP 3: Mechanism-of-Injury Criteria (YELLOW) ---
    bool step3Triggered = false;

    if (isRollover) {
      triggered.add('Vehicular Rollover (High risk of axial/spine injury)');
      step3Triggered = true;
    }

    // High speed / heavy deceleration trigger (between 8G and 15G)
    if (gForce >= 8.0 && gForce <= 15.0) {
      triggered.add('High Deceleration Forces (${gForce.toStringAsFixed(1)}G)');
      step3Triggered = true;
    }

    if (hasAirbagDeployed) {
      triggered.add('Airbag Deployment Event');
      step3Triggered = true;
    }

    if (step3Triggered) {
      return TriageAssessment(
        level: TriageLevel.yellow,
        destinationRecommendation: 'Trauma Center (Level 2 or 3 acceptable)',
        triggeredCriteria: triggered,
        primarySOSNumber: sosConfig.ambulance,
      );
    }

    // --- STEP 4: Special Considerations & Comorbidities (YELLOW or GREEN) ---
    // Aged adults (>55) or pediatric, or patients taking anticoagulants (bleed risk)
    if (isAnticoagulant) {
      triggered.add('Patient on Anticoagulant Therapy (High intracranial bleed risk)');
      return TriageAssessment(
        level: TriageLevel.yellow,
        destinationRecommendation: 'Trauma Center / Rapid Evaluation Facility',
        triggeredCriteria: triggered,
        primarySOSNumber: sosConfig.ambulance,
      );
    }

    if (age != null && (age > 55 || age < 15)) {
      triggered.add('Special Age Group Vulnerability (Age: $age)');
      return TriageAssessment(
        level: TriageLevel.yellow,
        destinationRecommendation: 'Trauma Evaluation Facility',
        triggeredCriteria: triggered,
        primarySOSNumber: sosConfig.ambulance,
      );
    }

    // --- DEFAULT: GREEN ---
    return TriageAssessment(
      level: TriageLevel.green,
      destinationRecommendation: 'Standard Emergency Department / Local Hospital',
      triggeredCriteria: ['No ACS-COT high-severity physiological or kinetic markers met'],
      primarySOSNumber: defaultSOS,
    );
  }
}
