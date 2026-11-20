import 'package:receipt_bot/models/models.dart';
import 'package:receipt_bot/services/firestore_service.dart';
import 'package:receipt_bot/utils/country_utils.dart';

/// Sales broken down by team member, for the owner's stats and the
/// "Your Team" screen.
class TeamSales {
  TeamSales(this.firestoreService);

  final FirestoreService firestoreService;

  /// How a member is shown: their own name if they set one that isn't just
  /// the business name, otherwise the last four digits of their number.
  static String nameFor(BusinessProfile member, BusinessProfile owner) {
    final name = member.businessName?.trim() ?? '';
    final orgName = owner.businessName?.trim() ?? '';
    if (name.isNotEmpty && name.toLowerCase() != orgName.toLowerCase()) {
      return name;
    }
    return _shortPhone(member.phoneNumber);
  }

  static String _shortPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return digits.length <= 4 ? phone : '…${digits.substring(digits.length - 4)}';
  }

  /// One line per person who sold something in [data], best seller first:
  /// "• Tunde: ₦240,000 (12 receipts)". Empty when only the owner sold.
  Future<List<String>> lines(
    BusinessProfile owner,
    SalesLedgerStats data,
  ) async {
    final sellers = data.memberRevenue.keys.where((k) => k.isNotEmpty);
    if (sellers.isEmpty || sellers.every((k) => k == owner.phoneNumber)) {
      return [];
    }

    final members = await firestoreService.getTeamMembers(owner.orgId!);
    final names = {
      for (final m in members)
        m.phoneNumber:
            m.phoneNumber == owner.phoneNumber ? 'You' : nameFor(m, owner),
    };

    final entries = data.memberRevenue.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return [
      for (final e in entries)
        _line(
          e.key.isEmpty
              ? 'Earlier sales'
              : names[e.key] ?? _shortPhone(e.key),
          e.value,
          data.memberReceipts[e.key] ?? 0,
          owner.currencySymbol,
        ),
    ];
  }

  /// Every member (owner included) with their sales this month, so members
  /// who haven't sold anything yet still show up.
  Future<List<String>> roster(
    BusinessProfile owner,
    List<BusinessProfile> members,
  ) async {
    final now = DateTime.now().toUtc();
    final start = DateTime.utc(now.year, now.month);
    final stats =
        await firestoreService.getSalesStats(owner.orgId!, start, now);
    final data = stats[owner.currencyCode] ??
        (stats.isNotEmpty ? stats.values.first : SalesLedgerStats());

    final rows = [
      for (final m in members)
        (
          m.phoneNumber == owner.phoneNumber ? 'You (owner)' : nameFor(m, owner),
          data.memberRevenue[m.phoneNumber] ?? 0.0,
          data.memberReceipts[m.phoneNumber] ?? 0,
        ),
    ]..sort((a, b) => b.$2.compareTo(a.$2));

    return [
      for (final (name, amount, count) in rows)
        _line(name, amount, count, owner.currencySymbol),
    ];
  }

  static String _line(String name, double amount, int count, String symbol) {
    final receipts = count == 1 ? '1 receipt' : '$count receipts';
    return '• $name: ${formatCurrency(amount, symbol)} ($receipts)';
  }
}
