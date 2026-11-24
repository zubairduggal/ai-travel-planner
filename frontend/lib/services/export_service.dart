import 'dart:typed_data';
import 'dart:ui';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../core/utils/formatters.dart';
import '../models/expense_model.dart';
import '../models/packing_item_model.dart';
import '../models/trip_model.dart';

/// Generates offline PDF documents and formatted WhatsApp/text summaries (MFR-12).
class ExportService {
  const ExportService();

  /// Produces a filesystem-safe filename like `hunza_valley_itinerary.pdf`.
  String safePdfFilename(TripModel trip) {
    final slug = trip.destination
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return '${slug.isEmpty ? "trip" : slug}_itinerary.pdf';
  }

  /// Formats a human-readable summary suitable for WhatsApp, Messages, or Email.
  String formatTextSummary(
    TripModel trip, {
    List<ExpenseModel> expenses = const [],
    List<PackingItemModel> packingList = const [],
  }) {
    final buf = StringBuffer();
    buf.writeln('AI Travel Planner — ${trip.destination}');
    if (trip.startDate != null && trip.endDate != null) {
      buf.writeln(
        'Dates: ${AppFormatters.toDateRange(trip.startDate!, trip.endDate!)} '
        '(${trip.durationDays} ${trip.durationDays == 1 ? "day" : "days"})',
      );
    } else {
      buf.writeln(
        'Duration: ${trip.durationDays} '
        '${trip.durationDays == 1 ? "day" : "days"}',
      );
    }
    buf.writeln(
      'Style: ${trip.travelStyle} | Est. Cost: '
      '${AppFormatters.formatCurrency(trip.totalEstimatedCost, trip.currency)}'
      '${trip.targetBudget != null ? " / Budget ${AppFormatters.formatCurrency(trip.targetBudget!, trip.currency)}" : ""}',
    );
    buf.writeln('');

    for (final day in trip.days) {
      final dist = day.totalDistanceKm != null
          ? ' (${AppFormatters.formatDistance(day.totalDistanceKm)})'
          : '';
      buf.writeln('Day ${day.dayNumber}: ${day.title}$dist');
      for (final act in day.activities) {
        final cost = AppFormatters.formatCurrency(
          act.estimatedCost,
          trip.currency,
        );
        buf.writeln(
          '  • [${act.timeSlot}] ${act.title} (${act.category}) — $cost',
        );
        if (act.hasCoordinates) {
          buf.writeln(
            '    GPS: ${act.latitude!.toStringAsFixed(4)}, '
            '${act.longitude!.toStringAsFixed(4)}',
          );
        }
        if (act.notes != null && act.notes!.trim().isNotEmpty) {
          buf.writeln('    Note: ${act.notes}');
        }
      }
      buf.writeln('');
    }

    if (expenses.isNotEmpty) {
      buf.writeln('Logged Expenses (${expenses.length}):');
      for (final exp in expenses) {
        buf.writeln(
          '  • ${exp.title} (${exp.category}): '
          '${AppFormatters.formatCurrency(exp.amount, exp.currency)}',
        );
      }
      buf.writeln('');
    }

    if (packingList.isNotEmpty) {
      final packed = packingList.where((i) => i.isPacked).length;
      buf.writeln('Packing Checklist ($packed/${packingList.length} packed):');
      for (final item in packingList) {
        buf.writeln('  ${item.isPacked ? "[x]" : "[ ]"} ${item.title}');
      }
    }

    return buf.toString().trimRight();
  }

  /// Attempts to load Unicode Noto Sans fonts (online/cached); returns null offline.
  Future<({pw.Font regular, pw.Font bold})?> tryLoadUnicodeFonts() async {
    try {
      final regular = await PdfGoogleFonts.notoSansRegular();
      final bold = await PdfGoogleFonts.notoSansBold();
      return (regular: regular, bold: bold);
    } catch (_) {
      return null;
    }
  }

  /// Generates a clean, multi-page offline PDF itinerary as raw bytes.
  ///
  /// When [baseFont] / [boldFont] are omitted (such as offline or in unit tests),
  /// falls back to built-in Helvetica with ASCII-safe currency codes so offline
  /// PDF generation never fails or prints garbled glyph boxes.
  Future<Uint8List> buildItineraryPdfBytes(
    TripModel trip, {
    List<ExpenseModel> expenses = const [],
    List<PackingItemModel> packingList = const [],
    pw.Font? baseFont,
    pw.Font? boldFont,
  }) async {
    final usesUnicodeFont = baseFont != null && boldFont != null;
    final regular = baseFont ?? pw.Font.helvetica();
    final bold = boldFont ?? pw.Font.helveticaBold();

    String pdfText(String input) {
      if (usesUnicodeFont) return input;
      // Built-in PDF Helvetica uses WinAnsi encoding; replace non-Latin-1 runes
      // cleanly so offline PDF generation never throws or renders boxes.
      return input
          .replaceAll('—', '-')
          .replaceAll('–', '-')
          .replaceAll('•', '*')
          .replaceAll('₨', 'PKR ')
          .replaceAll('€', 'EUR ')
          .replaceAll('£', 'GBP ')
          .replaceAll(RegExp(r'[^\x20-\x7E\xA0-\xFF\n]'), '');
    }

    String pdfCurrency(double amount, String currency) {
      if (usesUnicodeFont) {
        return AppFormatters.formatCurrency(amount, currency);
      }
      final formatted = amount.toStringAsFixed(
        amount.truncateToDouble() == amount ? 0 : 2,
      );
      return '${currency.toUpperCase()} $formatted';
    }

    final doc = pw.Document(
      title: '${trip.destination} Itinerary',
      author: 'AI Travel Planner',
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    final primary = PdfColor.fromHex('#006B6B');
    final subtle = PdfColor.fromHex('#F3F7F7');
    final muted = PdfColor.fromHex('#52606D');

    final dateRange = (trip.startDate != null && trip.endDate != null)
        ? AppFormatters.toDateRange(trip.startDate!, trip.endDate!)
        : '${trip.durationDays} ${trip.durationDays == 1 ? "day" : "days"}';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 12),
          child: pw.Text(
            pdfText(
              'AI Travel Planner  |  ${trip.destination}  |  '
              'Page ${context.pageNumber} of ${context.pagesCount}',
            ),
            style: pw.TextStyle(fontSize: 9, color: muted),
          ),
        ),
        build: (context) => [
          // Header banner
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: primary,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  pdfText(trip.destination),
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: 22,
                    color: PdfColors.white,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  pdfText(
                    '$dateRange  |  ${trip.travelStyle}  |  '
                    'Est. ${pdfCurrency(trip.totalEstimatedCost, trip.currency)}'
                    '${trip.targetBudget != null ? " / Budget ${pdfCurrency(trip.targetBudget!, trip.currency)}" : ""}',
                  ),
                  style: const pw.TextStyle(
                    fontSize: 11,
                    color: PdfColors.white,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 18),

          // Day-by-day schedule
          for (final day in trip.days) ...[
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: pw.BoxDecoration(
                color: subtle,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      pdfText('Day ${day.dayNumber}: ${day.title}'),
                      style: pw.TextStyle(
                        font: bold,
                        fontSize: 13,
                        color: primary,
                      ),
                    ),
                  ),
                  if (day.totalDistanceKm != null)
                    pw.Text(
                      pdfText(AppFormatters.formatDistance(day.totalDistanceKm)),
                      style: pw.TextStyle(fontSize: 10, color: muted),
                    ),
                ],
              ),
            ),
            pw.SizedBox(height: 8),
            for (final act in day.activities)
              pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 8),
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Expanded(
                          child: pw.Text(
                            pdfText('[${act.timeSlot}] ${act.title}'),
                            style: pw.TextStyle(font: bold, fontSize: 11),
                          ),
                        ),
                        pw.Text(
                          pdfCurrency(act.estimatedCost, trip.currency),
                          style: pw.TextStyle(
                            font: bold,
                            fontSize: 11,
                            color: primary,
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      pdfText(act.description),
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                    if (act.hasCoordinates)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 3),
                        child: pw.Text(
                          pdfText(
                            'Category: ${act.category}  |  '
                            'GPS: ${act.latitude!.toStringAsFixed(4)}, '
                            '${act.longitude!.toStringAsFixed(4)}',
                          ),
                          style: pw.TextStyle(fontSize: 9, color: muted),
                        ),
                      ),
                    if (act.notes != null && act.notes!.trim().isNotEmpty)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 3),
                        child: pw.Text(
                          pdfText('Personal Note: ${act.notes}'),
                          style: pw.TextStyle(
                            font: bold,
                            fontSize: 9,
                            color: primary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            pw.SizedBox(height: 10),
          ],

          // Optional Expenses section
          if (expenses.isNotEmpty) ...[
            pw.Divider(color: PdfColors.grey400),
            pw.SizedBox(height: 6),
            pw.Text(
              pdfText('Logged Expenses (${expenses.length})'),
              style: pw.TextStyle(font: bold, fontSize: 13, color: primary),
            ),
            pw.SizedBox(height: 6),
            for (final exp in expenses)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        pdfText('${exp.title} (${exp.category})'),
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ),
                    pw.Text(
                      pdfCurrency(exp.amount, exp.currency),
                      style: pw.TextStyle(font: bold, fontSize: 10),
                    ),
                  ],
                ),
              ),
          ],

          // Optional Packing Checklist section
          if (packingList.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Divider(color: PdfColors.grey400),
            pw.SizedBox(height: 6),
            pw.Text(
              pdfText('Packing Checklist'),
              style: pw.TextStyle(font: bold, fontSize: 13, color: primary),
            ),
            pw.SizedBox(height: 6),
            pw.Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final item in packingList)
                  pw.Text(
                    pdfText('${item.isPacked ? "[x]" : "[ ]"} ${item.title}'),
                    style: const pw.TextStyle(fontSize: 10),
                  ),
              ],
            ),
          ],
        ],
      ),
    );

    return doc.save();
  }

  /// Shares the formatted itinerary summary via the native OS share sheet
  /// (WhatsApp, Messages, Email, etc.). Always passes [sharePositionOrigin]
  /// to prevent iOS popover crashes.
  Future<ShareResult> shareTextSummary(
    TripModel trip, {
    required Rect sharePositionOrigin,
    List<ExpenseModel> expenses = const [],
    List<PackingItemModel> packingList = const [],
  }) {
    final text = formatTextSummary(
      trip,
      expenses: expenses,
      packingList: packingList,
    );
    return SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: 'Trip to ${trip.destination}',
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  /// Generates an offline PDF and opens the native share sheet for the file.
  Future<bool> sharePdfItinerary(
    TripModel trip, {
    required Rect sharePositionOrigin,
    List<ExpenseModel> expenses = const [],
    List<PackingItemModel> packingList = const [],
  }) async {
    final fonts = await tryLoadUnicodeFonts();
    final bytes = await buildItineraryPdfBytes(
      trip,
      expenses: expenses,
      packingList: packingList,
      baseFont: fonts?.regular,
      boldFont: fonts?.bold,
    );
    return Printing.sharePdf(
      bytes: bytes,
      filename: safePdfFilename(trip),
      bounds: sharePositionOrigin,
      subject: '${trip.destination} Travel Itinerary',
    );
  }

  /// Opens the native PDF print/save dialog.
  Future<bool> printPdfItinerary(
    TripModel trip, {
    List<ExpenseModel> expenses = const [],
    List<PackingItemModel> packingList = const [],
  }) async {
    final fonts = await tryLoadUnicodeFonts();
    return Printing.layoutPdf(
      name: safePdfFilename(trip),
      onLayout: (_) => buildItineraryPdfBytes(
        trip,
        expenses: expenses,
        packingList: packingList,
        baseFont: fonts?.regular,
        boldFont: fonts?.bold,
      ),
    );
  }
}
