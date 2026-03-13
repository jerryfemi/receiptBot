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
    final options = [
      {'id': ButtonIds.statsWeekly, 'title': 'Weekly Report', 'description': 'Sales from this week'},
      {'id': ButtonIds.statsMonthly, 'title': 'Monthly Summary', 'description': 'Sales from this month'},
      {'id': ButtonIds.statsYearly, 'title': 'Yearly Overview', 'description': 'Sales from this year'},
      {'id': ButtonIds.statsAllTime, 'title': 'All Time History', 'description': 'All imported and recent sales'},
    ];

    await whatsappService.sendInteractiveList(
      from,
      '📊 *Business Intelligence*\n\nSelect a timeframe to view your sales stats:',
      'View Options',
      'Timeframes',
      options,
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
   final  DateTime end = localTime;
    String timeframeLabel = '';

    if (timeframe == 'weekly') {
      // Dart weekday: 1=Monday, 7=Sunday
      start = localTime.subtract(Duration(days: localTime.weekday - 1));
      start = DateTime(start.year, start.month, start.day);
      timeframeLabel = 'This Week';
    } else if (timeframe == 'monthly') {
      start = DateTime(localTime.year, localTime.month, 1);
      timeframeLabel = 'This Month';
    } else if (timeframe == 'yearly') {
      start = DateTime(localTime.year, 1, 1);
      timeframeLabel = 'This Year';
    } else {
      // All Time
      start = DateTime(2000, 1, 1);
      timeframeLabel = 'All Time';
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
      double topAmount = 0;
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
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

      if (timeframe == 'yearly') {
        final Map<int, double> monthlyTotals = {for (var i = 1; i <= 12; i++) i: 0.0};
        dailyTotals.forEach((day, amount) {
          final parts = day.split('-');
          if (parts.length >= 2) {
             final m = int.tryParse(parts[1]) ?? 1;
             monthlyTotals[m] = (monthlyTotals[m] ?? 0) + amount;
          }
        });
      final  int endMonth = (end.year == start.year) ? end.month : 12;
        for (int i = 1; i <= endMonth; i++) {
          labels.add(months[i - 1]);
          dataPoints.add(monthlyTotals[i]!);
        }
      } else if (timeframe == 'all_time') {
         final Map<int, double> yearlyTotals = {};
         int minYear = end.year;
         dailyTotals.forEach((day, amount) {
            final year = int.tryParse(day.split('-')[0]) ?? end.year;
            if (year < minYear) minYear = year;
            yearlyTotals[year] = (yearlyTotals[year] ?? 0) + amount;
         });
         for (int y = minYear; y <= end.year; y++) {
             labels.add(y.toString());
             dataPoints.add(yearlyTotals[y] ?? 0.0);
         }
      } else {
        // Weekly or Monthly
        DateTime current = start;
        final endDay = DateTime(end.year, end.month, end.day);
        
        while (!current.isAfter(endDay)) {
          final dayKey = "${current.year}-${current.month.toString().padLeft(2, '0')}-${current.day.toString().padLeft(2, '0')}";
          if (timeframe == 'monthly') {
             labels.add('${months[current.month - 1]} ${current.day}');
          } else { 
             const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
             labels.add(weekdays[current.weekday - 1]);
          }
          dataPoints.add(dailyTotals[dayKey] ?? 0.0);
          current = current.add(const Duration(days: 1));
        }
      }

      // Dynamic formatting function for Y-axis (e.g., 40000 -> 40k, 40000000 -> 40M)
      const  yAxisFormatter = 'function(v) { if (v >= 1000000) return (v / 1000000).toFixed(1) + "M"; if (v >= 1000) return (v / 1000).toFixed(1) + "k"; return v.toString(); }';

      final chartConfigJson = {
        'type': 'bar',
        'data': {
          'labels': labels,
          'datasets': [
            {
              'label': 'Revenue',
              'data': dataPoints,
              'backgroundColor': 'rgba(124, 58, 237, 0.85)', // A premium vivid purple
              'borderColor': 'rgb(109, 40, 217)',
              'borderWidth': 1,
              'borderRadius': 4, // Rounded tops for modern look
            }
          ]
        },
        'options': {
          'plugins': {
            'title': {
              'display': true,
              'text': 'Sales Revenue ($usedCurrency)',
              'font': {'size': 20, 'family': 'sans-serif', 'weight': 'bold'},
              'padding': {'bottom': 5}
            },
            'subtitle': {
              'display': topCustomer != 'N/A' && topCustomer.isNotEmpty,
              'text': '🏆 Top Customer: $topCustomer',
              'font': {'size': 14, 'family': 'sans-serif', 'style': 'italic'},
              'padding': {'bottom': 15},
              'color': '#666'
            },
            'legend': {'display': false}, // Hide legend since title is clear
            'datalabels': {
              'display': false // Don't clutter bars with exact numbers
            }
          },
          'scales': {
            'y': {
              'beginAtZero': true,
              'grid': {
                'color': 'rgba(0,0,0,0.05)', // Very subtle grid lines
                'borderDash': [5, 5]
              },
              'ticks': {
                'callback': yAxisFormatter, 
                'color': '#555',
                'font': {'family': 'sans-serif', 'size': 11}
              }
            },
            'x': {
              'grid': {'display': false},
              'ticks': {
                'color': '#555',
                'font': {'family': 'sans-serif', 'size': 11}
              }
            }
          },
          'layout': {
            'padding': {
              'left': 40, // More space for labels
              'right': 20,
              'top': 10,
              'bottom': 10
            }
          }
        }
      };

      // We need to pass the JS function string directly to QuickChart. 
      // jsonEncode turns strings into JSON strings (with quotes). To pass raw JS functions, we encode normally,
      // and then manually strip the quotes around the function body if QuickChart API expects raw JS.
      // QuickChart actually supports JS formatting if you use the Chart.js format perfectly.
      // Easiest is to generate the chart via the URL format string if using JS.
      // Wait, QuickChart's easiest way to inject JS callbacks in the JSON payload is to just pass a string starting with function().
      // It detects this on its backend!
      
      final encodedChart = Uri.encodeComponent(jsonEncode(chartConfigJson));
      // Tell QuickChart to evaluate JS in the config and use Chart.js v3 for plugins support
      final chartUrl = 'https://quickchart.io/chart?v=3&chart=$encodedChart';

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
        for (final k in otherKeys) {
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
