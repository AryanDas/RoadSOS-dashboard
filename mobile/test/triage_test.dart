import 'package:flutter_test/flutter_test.dart';
import 'package:roadsos/triage_engine.dart';

void main() {
  group('TriageEngine Physiological and Kinetic Tests', () {
    test('RED Severity physiological triggers', () {
      final res = TriageEngine.performTriage(
        gForce: 4.5,
        hasAirbagDeployed: false,
        isRollover: false,
        gcs: 12, // Physiological threshold (GCS < 14) -> RED
        isoCountryCode: 'IN',
      );
      
      expect(res.level, TriageLevel.red);
      expect(res.destinationRecommendation, contains('Level 1'));
      expect(res.primarySOSNumber, '102'); // Ambulance
    });

    test('RED Severity extremely high G-force kinetic trigger', () {
      final res = TriageEngine.performTriage(
        gForce: 18.2, // Decel kinetic threshold (>15G) -> RED
        hasAirbagDeployed: false,
        isRollover: false,
        gcs: 15,
        isoCountryCode: 'US',
      );
      
      expect(res.level, TriageLevel.red);
      expect(res.primarySOSNumber, '911'); // US Ambulance
    });

    test('YELLOW Severity rollover kinematic trigger', () {
      final res = TriageEngine.performTriage(
        gForce: 2.1,
        hasAirbagDeployed: false,
        isRollover: true, // Rollover -> YELLOW
        gcs: 15,
        isoCountryCode: 'GB',
      );
      
      expect(res.level, TriageLevel.yellow);
      expect(res.destinationRecommendation, contains('Trauma Center'));
      expect(res.primarySOSNumber, '999'); // UK Ambulance
    });

    test('YELLOW Severity comorbidity trigger (anticoagulant therapy)', () {
      final res = TriageEngine.performTriage(
        gForce: 1.0,
        hasAirbagDeployed: false,
        isRollover: false,
        gcs: 15,
        isAnticoagulant: true, // bleed risk comorbidity -> YELLOW
        isoCountryCode: 'IN',
      );
      
      expect(res.level, TriageLevel.yellow);
      expect(res.primarySOSNumber, '102');
    });

    test('GREEN Severity default fallback', () {
      final res = TriageEngine.performTriage(
        gForce: 0.5,
        hasAirbagDeployed: false,
        isRollover: false,
        gcs: 15,
        isoCountryCode: 'EU',
      );
      
      expect(res.level, TriageLevel.green);
      expect(res.destinationRecommendation, contains('Standard Emergency'));
      expect(res.primarySOSNumber, '112'); // EU General emergency dial
    });
  });
}
