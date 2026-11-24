import 'package:intl/intl.dart';

final _money = NumberFormat.currency(locale: 'fr_FR', symbol: 'FCFA', decimalDigits: 0);

/// "12 500 FCFA" — same output as formatCurrency() in the Tauri app (XAF, no decimals).
String formatCurrency(num? value) => _money.format(value ?? 0);

/// Payment method keys as the server stores them → label shown to staff (same names as the till).
String paymentMethodLabel(String key) => switch (key) {
      'cash' => 'Espèces',
      'momo' => 'MoMo',
      'om' => 'OM',
      'card' => 'Carte Bancaire',
      'room_charge' => 'Chambre',
      _ => key,
    };
