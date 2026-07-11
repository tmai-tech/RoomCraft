enum UnitSystem { feet, meters }

extension UnitSystemX on UnitSystem {
  String get label => this == UnitSystem.feet ? 'ft' : 'm';
  String get longLabel => this == UnitSystem.feet ? 'Feet' : 'Meters';
}

/// Converts and formats lengths. Internal model stays in feet.
class LengthFormat {
  static const double feetToMeters = 0.3048;

  static double feetToDisplay(double feet, UnitSystem unit) {
    return unit == UnitSystem.feet ? feet : feet * feetToMeters;
  }

  static double displayToFeet(double value, UnitSystem unit) {
    return unit == UnitSystem.feet ? value : value / feetToMeters;
  }

  static String formatFeet(double feet, UnitSystem unit, {int decimals = 1}) {
    final v = feetToDisplay(feet, unit);
    return '${v.toStringAsFixed(decimals)} ${unit.label}';
  }

  static String formatAreaSqFt(double sqFt, UnitSystem unit, {int decimals = 1}) {
    if (unit == UnitSystem.feet) {
      return '${sqFt.toStringAsFixed(decimals)} sq ft';
    }
    final sqM = sqFt * feetToMeters * feetToMeters;
    return '${sqM.toStringAsFixed(decimals)} m²';
  }
}
