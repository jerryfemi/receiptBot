import 'dart:async';
import 'dart:convert';
import 'package:receipt_bot/country_utils.dart';
import 'package:receipt_bot/models/models.dart';
import 'package:receipt_bot/services/firestore_service.dart';
import 'package:receipt_bot/services/gemini_service.dart';
import 'package:receipt_bot/services/whatsapp_service.dart';
import 'package:receipt_bot/utils/constants.dart';

class StatsHandler {
  final FirestoreService firestoreService;
  final WhatsAppService whatsappService;
  final GeminiService geminiService;

  StatsHandler(this.firestoreService, this.whatsappService, this.geminiService);

  Future<void> showStatsMenu(String from) async {
    final buttons = [
      {'id': ButtonIds.statsWeekly, 'title': 'Weekly Report'},
      {'id': ButtonIds.statsMonthly, 'title': 'Monthly Summary'},
      {'id': ButtonIds.statsYearly, 'title': 'Yearly Overview'},
    ];

    await whatsappService.sendInteractiveButtons(
      from,
      '📊 *Business Intelligence*\n\nSelect a timeframe to view your sales stats:',
      buttons,
    );
  }

  Future<void> processStatsRequest(
      String from, String timeframe, BusinessProfile profile) async {
    // 1. Send loading message
    await whatsappService.sendMessage(
        from, '📊 Retreiving  your sales data... ⏳');

    // 2. Calculate dates
    final now = DateTime.now().toUtc();
    final isWestAfrica = CountryUtils.isPaystackRegion(profile.phoneNumber);
    final localTime = now.add(Duration(hours: isWestAfrica ? 1 : 0));

    DateTime start;
    DateTime end = localTime;
    String timeframeLabel = '';

    if (timeframe == 'weekly') {
      // Dart weekday: 1=Monday, 7=Sunday
      start = localTime.subtract(Duration(days: localTime.weekday - 1));
      start = DateTime(start.year, start.month, start.day);
      timeframeLabel = 'This Week';
    } else if (timeframe == 'monthly') {
      start = DateTime(localTime.year, localTime.month, 1);
      timeframeLabel = 'This Month';
    } else {
      // Yearly
      start = DateTime(localTime.year, 1, 1);
      timeframeLabel = 'This Year';
    }

    // Convert local start/end back to UTC for Firestore query
    final queryStart = start.subtract(Duration(hours: isWestAfrica ? 1 : 0));
    final queryEnd = end.subtract(Duration(hours: isWestAfrica ? 1 : 0));

    try {
      // 3. Query ledger
      final orgId = profile.orgId ?? profile.phoneNumber;
      final currencyData =
          await firestoreService.getSalesStats(orgId, queryStart, queryEnd);

      if (currencyData.isEmpty) {
        await whatsappService.sendMessage(from,
            "You don't have any receipts yet for this timeframe! Generate your first one to see your stats grow. 📈");
        return;
      }

      // Pick primary currency (the one they use by default)
      final primaryCurrency = profile.currencyCode;

      var data = currencyData[primaryCurrency];

      // If no data for primary, fallback to first available
      if (data == null && currencyData.isNotEmpty) {
        data = currencyData.values.first;
      }

      final usedCurrency = currencyData.keys.firstWhere(
          (k) => currencyData[k] == data,
          orElse: () => primaryCurrency);

      final totalRevenue = data!.totalRevenue;
      final receiptCount = data.receiptCount;
      final customerSpending = data.customerSpending;
      final dailyTotals = data.dailyTotals;

      // Find top customer
      String topCustomer = 'N/A';
      double topAmount = 0.0;
      customerSpending.forEach((k, v) {
        if (v > topAmount) {
          topAmount = v;
          topCustomer = k;
        }
      });

      // 4. Formatter & Strings
      final formatter = profile.currencySymbol;

      // 5. Gemini Insight
      final statsSummary = '''
Timeframe: $timeframeLabel
Total Revenue: $formatter${formatCurrency(totalRevenue, '')} $usedCurrency
Total Receipts: $receiptCount
Top Customer: $topCustomer ($formatter${formatCurrency(topAmount, '')} $usedCurrency)
      ''';

      final insight = await geminiService.generateBusinessInsight(statsSummary);

      // 6. Build QuickChart URL
      final List<String> labels = [];
      final List<double> dataPoints = [];

      final sortedDays = dailyTotals.keys.toList()..sort();
      for (var day in sortedDays) {
        // e.g. "2026-03-01" -> "Mar 01"
        final parts = day.split('-');
        if (parts.length == 3) {
          final y = parts[0];
          final m = int.tryParse(parts[1]) ?? 1;
          final d = parts[2];
          const months = [
            'Jan',
            'Feb',
            'Mar',
            'Apr',
            'May',
            'Jun',
            'Jul',
            'Aug',
            'Sep',
            'Oct',
            'Nov',
            'Dec'
          ];

          if (timeframe == 'yearly') {
            labels.add('${months[m - 1]} $y');
          } else {
            labels.add('${months[m - 1]} $d');
          }
        } else {
          labels.add(day);
        }
        dataPoints.add(dailyTotals[day]!);
      }

      String chartType = 'line';
      if (labels.length <= 1) chartType = 'bar'; // Line needs at least 2 points

      final chartConfigJson = {
        'type': chartType,
        'data': {
          'labels': labels,
          'datasets': [
            {
              'label': 'Revenue',
              'data': dataPoints,
              'backgroundColor': 'rgba(54, 162, 235, 0.5)',
              'borderColor': 'rgb(54, 162, 235)',
              'borderWidth': 2,
              'fill': true,
            }
          ]
        }
      };

      final encodedChart = Uri.encodeComponent(jsonEncode(chartConfigJson));
      final chartUrl = 'https://quickchart.io/chart?c=$encodedChart';

      // 7. Build text report
      String reportText = '''
📊 *Sales Summary: $timeframeLabel*
💰 Total Revenue: $formatter${formatCurrency(totalRevenue, '')}
📄 Receipts Issued: $receiptCount
🏆 Top Customer: $topCustomer

💡 *Insight:* $insight
''';

      // Add multi-currency footnote if applicable
      if (currencyData.keys.length > 1) {
        reportText += '\n_P.S. You also had sales in ';
        final otherKeys =
            currencyData.keys.where((k) => k != usedCurrency).toList();
        final List<String> footnoteParts = [];
        for (var k in otherKeys) {
          footnoteParts
              .add('$k (${formatCurrency(currencyData[k]!.totalRevenue, '')})');
        }
        reportText += '${footnoteParts.join(', ')} this $timeframe._';
      }


      // 8. Send image message
      await whatsappService.sendImage(
        from,
        chartUrl,
        caption: reportText,
      );
    } catch (e) {
      print('DEBUG: Error generating stats: $e');
      await whatsappService.sendMessage(from,
          'An error occurred while retrieving your stats. Please try again later.');
    }
  }
}
