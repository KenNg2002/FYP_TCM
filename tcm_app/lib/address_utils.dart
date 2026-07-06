// Builds a display-friendly multi-line address string from the structured
// shippingaddress fields (addressLine1, addressLine2, city, postcode, state).
String formatAddress(Map<String, dynamic> addr) {
  final line1 = (addr['addressLine1'] ?? '').toString().trim();
  final line2 = (addr['addressLine2'] ?? '').toString().trim();
  final city = (addr['city'] ?? '').toString().trim();
  final postcode = (addr['postcode'] ?? '').toString().trim();
  final state = (addr['state'] ?? '').toString().trim();

  final lines = <String>[
    line1,
    if (line2.isNotEmpty) line2,
    [postcode, city].where((s) => s.isNotEmpty).join(' '),
    state,
  ].where((s) => s.isNotEmpty).toList();

  return lines.join('\n');
}
