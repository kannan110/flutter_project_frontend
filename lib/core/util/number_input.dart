import 'package:flutter/services.dart';

/// Allows only digits and at most one decimal point ("45", "45.5", "45.250").
/// Any edit that would add a letter, a sign, a comma or a second "." is
/// ignored, so the field keeps its previous text.
class DecimalNumberFormatter extends TextInputFormatter {
  const DecimalNumberFormatter();

  static final RegExp _valid = RegExp(r'^\d*\.?\d*$');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      _valid.hasMatch(newValue.text) ? newValue : oldValue;
}

/// Allows only digits, one decimal point and at most 2 digits after it
/// ("1250", "1250.5", "1250.75"). Any other edit is ignored.
class MoneyFormatter extends TextInputFormatter {
  const MoneyFormatter();

  static final RegExp _valid = RegExp(r'^\d*\.?\d{0,2}$');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      _valid.hasMatch(newValue.text) ? newValue : oldValue;
}

/// inputFormatters for Amount / Rate fields (₹): up to 2 decimal places.
const List<TextInputFormatter> moneyInputFormatters = [MoneyFormatter()];

/// inputFormatters for weight / Kg (and other decimal-number) fields.
const List<TextInputFormatter> kgInputFormatters = [DecimalNumberFormatter()];

/// inputFormatters for Birds / No. of birds (and other whole-number) fields:
/// digits only — no letters, signs, spaces or decimal point.
final List<TextInputFormatter> birdsInputFormatters = [FilteringTextInputFormatter.digitsOnly];
