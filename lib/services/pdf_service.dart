import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:receipt_bot/layouts/corporate_layout.dart';
import 'package:receipt_bot/layouts/default_layout.dart';
import 'package:receipt_bot/layouts/signature_layout.dart';
import 'package:receipt_bot/layouts/simple_layout.dart';

import 'package:receipt_bot/models/models.dart';

class PdfService {
  // Static Caches for Fonts and Logos
  static Uint8List? _regularFontData;
  static Uint8List? _boldFontData;
  static Uint8List? _scriptFontData;
  static Uint8List? _serifFontData;
  static Uint8List? _notoFontData;
  static final Map<String, Uint8List> _logoCache = {};

  Future<Uint8List> generateReceipt(
    BusinessProfile profile,
    Transaction transaction, {
    int themeIndex = 0, // 0: B&W, 1: Beige, 2: Blue
    int layoutIndex = 0, // 0: Classic, 1: Modern, 2: Minimal
    Organization? org,
  }) async {
    // Load Fonts (with Caching)
    _regularFontData ??=
        await File('public/fonts/Roboto-Regular.ttf').readAsBytes();
    final regularFont = pw.Font.ttf(_regularFontData!.buffer.asByteData());

    _boldFontData ??= await File('public/fonts/Roboto-Bold.ttf').readAsBytes();
    final boldFont = pw.Font.ttf(_boldFontData!.buffer.asByteData());

    _notoFontData ??=
        await File('public/fonts/NotoSans-Regular.ttf').readAsBytes();
    final notoFont = pw.Font.ttf(_notoFontData!.buffer.asByteData());

    pw.Font? scriptFont;
    try {
      _scriptFontData ??=
          await File('public/fonts/DancingScript-Bold.ttf').readAsBytes();
      scriptFont = pw.Font.ttf(_scriptFontData!.buffer.asByteData());
    } catch (e) {
      print('Warning: Could not load script font: $e');
    }

    pw.Font? serifFont;
    try {
      _serifFontData ??=
          await File('public/fonts/PlayfairDisplay-SemiBold.ttf').readAsBytes();
      serifFont = pw.Font.ttf(_serifFontData!.buffer.asByteData());
    } catch (e) {
      print('Warning: Could not load serif font: $e');
    }

    final pdf = pw.Document();

    // Determine values correctly from org or fallback
    final usedLogoUrl = org?.logoUrl ?? profile.logoUrl;
    final usedBusinessName = org?.businessName ?? profile.businessName;
    final usedBusinessAddress = org?.businessAddress ?? profile.businessAddress;
    final usedDisplayPhoneNumber =
        org?.displayPhoneNumber ?? profile.displayPhoneNumber;
    final usedBankName = org?.bankName ?? profile.bankName;
    final usedAccountNumber = org?.accountNumber ?? profile.accountNumber;
    final usedAccountName = org?.accountName ?? profile.accountName;

    // 1. Load Logo (with Caching)
    pw.MemoryImage? logoImage;
    if (usedLogoUrl != null && usedLogoUrl.isNotEmpty) {
      if (_logoCache.containsKey(usedLogoUrl)) {
        logoImage = pw.MemoryImage(_logoCache[usedLogoUrl]!);
      } else {
        try {
          if (usedLogoUrl.startsWith('http')) {
            final response = await http
                .get(Uri.parse(usedLogoUrl))
                .timeout(const Duration(seconds: 15));
            if (response.statusCode == 200) {
              _logoCache[usedLogoUrl] = response.bodyBytes;
              logoImage = pw.MemoryImage(response.bodyBytes);
            }
          } else {
            // Local file fallback
            final bytes = await File(usedLogoUrl).readAsBytes();
            _logoCache[usedLogoUrl] = bytes;
            logoImage = pw.MemoryImage(bytes);
          }
        } catch (e) {
          print('Error loading logo: $e');
        }
      }
    }

    // Define Theme Colors
    PdfColor bg;
    PdfColor primary;
    const textColor = PdfColors.black;

    switch (themeIndex) {
      case 1: // Beige
        bg = PdfColor.fromHex('#EFE9DB');
        primary = PdfColor.fromHex('#D73138');
        break;
      case 0: // B&W (Default)
      default:
        bg = layoutIndex == 1 ? PdfColor.fromHex('#FAF7F2') : PdfColors.white;
        primary = PdfColors.black;
        break;
    }

    pdf.addPage(pw.MultiPage(
      pageTheme: pw.PageTheme(
        theme: pw.ThemeData.withFont(
          base: regularFont,
          bold: boldFont,
          fontFallback: [notoFont],
        ),
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(20),
        buildBackground: (context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Container(color: bg),
        ),
      ),
      build: (context) {
        if (transaction.type == TransactionType.invoice) {
          return _generateInvoiceLayout(
              context,
              transaction,
              logoImage,
              primary,
              textColor,
              regularFont,
              boldFont,
              scriptFont,
              serifFont,
              usedBusinessName,
              usedBusinessAddress,
              usedDisplayPhoneNumber,
              usedBankName,
              usedAccountNumber,
              usedAccountName,
              org?.currencySymbol ?? profile.currencySymbol,
              layoutIndex);
        } else {
          return _generateReceiptLayout(
              context,
              transaction,
              logoImage,
              primary,
              textColor,
              regularFont,
              boldFont,
              scriptFont,
              serifFont,
              usedBusinessName,
              usedBusinessAddress,
              usedDisplayPhoneNumber,
              org?.currencySymbol ?? profile.currencySymbol,
              layoutIndex);
        }
      },
    ));

    return pdf.save();
  }

  // --- INVOICE ROUTER ---
  List<pw.Widget> _generateInvoiceLayout(
      pw.Context context,
      Transaction transaction,
      pw.MemoryImage? logoImage,
      PdfColor primary,
      PdfColor textColor,
      pw.Font regularFont,
      pw.Font boldFont,
      pw.Font? scriptFont,
      pw.Font? serifFont, // Added serifFont
      String? businessName,
      String? businessAddress,
      String? displayPhoneNumber,
      String? bankName,
      String? accountNumber,
      String? accountName,
      String currencySymbol,
      int layoutIndex) {
    // 0: Classic, 1: Modern Left, 2: Minimal Grid, 3: Standard
    switch (layoutIndex) {
      case 3:
        return corporateInvoice(
            context,
            transaction,
            logoImage,
            primary,
            textColor,
            regularFont,
            boldFont,
            serifFont,
            businessName,
            businessAddress,
            displayPhoneNumber,
            bankName,
            accountNumber,
            accountName,
            currencySymbol);
      case 1:
        return signatureInvoice(
            context,
            transaction,
            logoImage,
            primary,
            textColor,
            regularFont,
            boldFont,
            scriptFont,
            serifFont,
            businessName,
            businessAddress,
            displayPhoneNumber,
            bankName,
            accountNumber,
            accountName,
            currencySymbol);
      case 2:
        return simpleInvoice(
            context,
            transaction,
            logoImage,
            primary,
            textColor,
            regularFont,
            boldFont,
            serifFont,
            businessName,
            businessAddress,
            displayPhoneNumber,
            bankName,
            accountNumber,
            accountName,
            currencySymbol);
      case 0:
      default:
        return defaultInvoiceLayout(
            context,
            transaction,
            logoImage,
            primary,
            textColor,
            regularFont,
            boldFont,
            serifFont,
            businessName,
            businessAddress,
            displayPhoneNumber,
            bankName,
            accountNumber,
            accountName,
            currencySymbol);
    }
  }

// RECEIPT ROUTER
  List<pw.Widget> _generateReceiptLayout(
      pw.Context context,
      Transaction transaction,
      pw.MemoryImage? logoImage,
      PdfColor primary,
      PdfColor textColor,
      pw.Font regularFont,
      pw.Font boldFont,
      pw.Font? scriptFont,
      pw.Font? serifFont,
      String? businessName,
      String? businessAddress,
      String? displayPhoneNumber,
      String currencySymbol,
      int layoutIndex) {
    // 0: Classic, 1: Modern Left, 2: Minimal Grid, 3: Standard
    switch (layoutIndex) {
      case 3:
        return corporateReceipt(
            context,
            transaction,
            logoImage,
            primary,
            textColor,
            regularFont,
            boldFont,
            serifFont,
            businessName,
            businessAddress,
            displayPhoneNumber,
            currencySymbol);
      case 1:
        return signatureReceipt(
            context,
            transaction,
            logoImage,
            primary,
            textColor,
            regularFont,
            boldFont,
            scriptFont,
            serifFont,
            businessName,
            businessAddress,
            displayPhoneNumber,
            currencySymbol);
      case 2:
        return simpleReceipt(
            context,
            transaction,
            logoImage,
            primary,
            textColor,
            regularFont,
            boldFont,
            serifFont,
            businessName,
            businessAddress,
            displayPhoneNumber,
            currencySymbol);
      case 0:
      default:
        return defaultReceiptLayout(
            context,
            transaction,
            logoImage,
            primary,
            textColor,
            regularFont,
            boldFont,
            serifFont,
            businessName,
            businessAddress,
            displayPhoneNumber,
            currencySymbol);
    }
  }
}
