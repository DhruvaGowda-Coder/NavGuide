import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Premium, minimal, Google Maps-inspired real-time location and trip progress sharing sheet.
class LocationShareSheet extends StatefulWidget {
  final double latitude;
  final double longitude;
  final String? placeName;
  final double? accuracyMeters;

  // Optional Live Turn-by-Turn navigation context
  final String? destinationName;
  final String? tripEta;
  final String? remainingDistance;

  // Optional Train tracking context
  final String? trainNumber;
  final String? trainName;
  final String? nextStation;
  final int? speedKmh;

  const LocationShareSheet({
    super.key,
    required this.latitude,
    required this.longitude,
    this.placeName,
    this.accuracyMeters,
    this.destinationName,
    this.tripEta,
    this.remainingDistance,
    this.trainNumber,
    this.trainName,
    this.nextStation,
    this.speedKmh,
  });

  /// Directly opens the native system share dialog (WhatsApp, Messages, Telegram, Gmail, etc.)
  /// with a NavGuide custom redirect link.
  static Future<void> shareDirectly({
    required double latitude,
    required double longitude,
    String? placeName,
    double? accuracyMeters,
    String? destinationName,
    String? tripEta,
    String? remainingDistance,
    String? trainNumber,
    String? trainName,
    String? nextStation,
    int? speedKmh,
  }) async {
    HapticFeedback.mediumImpact();
    final link =
        'https://navguide.app/live?lat=${latitude.toStringAsFixed(6)}&lon=${longitude.toStringAsFixed(6)}';
    final buffer = StringBuffer();

    if (trainNumber != null && trainName != null) {
      buffer.writeln('🚆 Live Train Tracking on NavGuide');
      buffer.writeln('Train: $trainNumber - $trainName');
      if (nextStation != null) {
        buffer.writeln('Approaching: $nextStation');
      }
      if (speedKmh != null && speedKmh > 0) {
        buffer.writeln('Speed: $speedKmh km/h');
      }
      buffer.writeln('Live Tracking Link: $link');
      buffer.writeln('(Open in NavGuide App)');
    } else if (destinationName != null) {
      buffer.writeln('🚗 Live Trip Progress on NavGuide');
      buffer.writeln('Heading to: $destinationName');
      if (tripEta != null) {
        buffer.writeln('ETA: $tripEta');
      }
      if (remainingDistance != null) {
        buffer.writeln('Remaining: $remainingDistance');
      }
      buffer.writeln('Live Tracking Link: $link');
      buffer.writeln('(Open in NavGuide App)');
    } else {
      final name = placeName ?? 'Current Location';
      buffer.writeln('📍 My Live Location via NavGuide');
      buffer.writeln('I am here: $name');
      if (accuracyMeters != null) {
        buffer.writeln('GPS Accuracy: ±${accuracyMeters.toStringAsFixed(0)}m');
      }
      buffer.writeln('Track my live location:');
      buffer.writeln(link);
      buffer.writeln('(Open in NavGuide App)');
    }

    final message = buffer.toString().trim();
    await SharePlus.instance.share(
      ShareParams(
        text: message,
        subject: 'My Live Location on NavGuide',
      ),
    );
  }

  /// Displays the location sharing sheet as a modern bottom modal.
  static Future<void> show(
    BuildContext context, {
    required double latitude,
    required double longitude,
    String? placeName,
    double? accuracyMeters,
    String? destinationName,
    String? tripEta,
    String? remainingDistance,
    String? trainNumber,
    String? trainName,
    String? nextStation,
    int? speedKmh,
  }) {
    HapticFeedback.mediumImpact();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LocationShareSheet(
        latitude: latitude,
        longitude: longitude,
        placeName: placeName,
        accuracyMeters: accuracyMeters,
        destinationName: destinationName,
        tripEta: tripEta,
        remainingDistance: remainingDistance,
        trainNumber: trainNumber,
        trainName: trainName,
        nextStation: nextStation,
        speedKmh: speedKmh,
      ),
    );
  }

  @override
  State<LocationShareSheet> createState() => _LocationShareSheetState();
}

class _LocationShareSheetState extends State<LocationShareSheet>
    with SingleTickerProviderStateMixin {
  static const Color _primaryEmerald = Color(0xff23695a);
  static const Color _cardBg = Colors.white;
  static const Color _textDark = Color(0xff1e293b);
  static const Color _textMuted = Color(0xff64748b);

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Sharing duration chips
  int _selectedDurationIndex = 0; // 0: 1 Hour, 1: 8 Hours, 2: Until I arrive, 3: Current spot
  final List<String> _durationLabels = [
    'For 1 hour',
    'For 8 hours',
    'Until I arrive',
    'Current spot only',
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // If on active trip or train, default to "Until I arrive"
    if (widget.destinationName != null || widget.trainNumber != null) {
      _selectedDurationIndex = 2; // "Until I arrive"
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String get _navGuideLiveUrl =>
      'https://navguide.app/live?lat=${widget.latitude.toStringAsFixed(6)}&lon=${widget.longitude.toStringAsFixed(6)}';

  String _buildShareMessage() {
    final durationStr = _durationLabels[_selectedDurationIndex];

    final buffer = StringBuffer();

    if (widget.trainNumber != null && widget.trainName != null) {
      buffer.writeln('🚆 Live Train Status via NavGuide');
      buffer.writeln('Train: ${widget.trainNumber} - ${widget.trainName}');
      if (widget.nextStation != null) {
        buffer.writeln('Approaching: ${widget.nextStation}');
      }
      if (widget.speedKmh != null && widget.speedKmh! > 0) {
        buffer.writeln('Speed: ${widget.speedKmh} km/h');
      }
      buffer.writeln('Live Tracking: $_navGuideLiveUrl');
      buffer.writeln('($durationStr)');
    } else if (widget.destinationName != null) {
      buffer.writeln('🚗 Live Trip Progress via NavGuide');
      buffer.writeln('Heading to: ${widget.destinationName}');
      if (widget.tripEta != null) {
        buffer.writeln('ETA: ${widget.tripEta}');
      }
      if (widget.remainingDistance != null) {
        buffer.writeln('Distance Remaining: ${widget.remainingDistance}');
      }
      buffer.writeln('Live Tracking: $_navGuideLiveUrl');
      buffer.writeln('($durationStr)');
    } else {
      final name = widget.placeName ?? 'Current Location';
      buffer.writeln('📍 Live Location via NavGuide');
      buffer.writeln('I am here: $name');
      buffer.writeln('Track Live on NavGuide: $_navGuideLiveUrl');
      if (widget.accuracyMeters != null) {
        buffer.writeln('Accuracy: ±${widget.accuracyMeters!.toStringAsFixed(0)}m');
      }
      buffer.writeln('Shared $durationStr');
    }

    return buffer.toString().trim();
  }

  Future<void> _shareViaWhatsApp() async {
    HapticFeedback.selectionClick();
    final text = Uri.encodeComponent(_buildShareMessage());
    final waUrl = Uri.parse('whatsapp://send?text=$text');
    final waWebUrl = Uri.parse('https://api.whatsapp.com/send?text=$text');

    try {
      if (await canLaunchUrl(waUrl)) {
        await launchUrl(waUrl, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(waWebUrl)) {
        await launchUrl(waWebUrl, mode: LaunchMode.externalApplication);
      } else {
        _shareViaSystem();
      }
    } catch (_) {
      _shareViaSystem();
    }
  }

  Future<void> _shareViaSms() async {
    HapticFeedback.selectionClick();
    final text = Uri.encodeComponent(_buildShareMessage());
    final smsUri = Uri.parse('sms:?body=$text');

    try {
      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri, mode: LaunchMode.externalApplication);
      } else {
        _shareViaSystem();
      }
    } catch (_) {
      _shareViaSystem();
    }
  }

  void _copyToClipboard() {
    HapticFeedback.mediumImpact();
    Clipboard.setData(ClipboardData(text: _buildShareMessage()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xff1e293b),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Color(0xff10b981), size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Location link copied to clipboard!',
                style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );
    Navigator.of(context).pop();
  }

  void _shareViaSystem() {
    HapticFeedback.selectionClick();
    final message = _buildShareMessage();
    SharePlus.instance.share(
      ShareParams(
        text: message,
        subject: 'My Real-Time Location via NavGuide',
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final isNavigating = widget.destinationName != null;
    final isTrain = widget.trainNumber != null;

    return Container(
      decoration: const BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          // ─── 1. Minimal Pull Handle ──────────────────────────────────────────
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ─── 2. Header with Glowing Pulse Dot ────────────────────────────────
          Row(
            children: [
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: const Color(0xff10b981),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xff10b981).withValues(alpha: 0.6),
                          blurRadius: 6 * _pulseAnimation.value,
                          spreadRadius: 2 * _pulseAnimation.value,
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isTrain
                          ? 'Share Train Journey'
                          : (isNavigating ? 'Share Trip Progress' : 'Share Real-Time Location'),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: _textDark,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      isTrain
                          ? 'Share live speed & upcoming halts'
                          : (isNavigating
                              ? 'Friends can track your live ETA & route'
                              : 'Send your live GPS pin to family & friends'),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: _textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, color: _textMuted, size: 20),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Close',
              ),
            ],
          ),

          const SizedBox(height: 14),

          // ─── 3. Location / Trip Highlight Card (Google Maps Styled) ──────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xfff8fafc),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _primaryEmerald.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isTrain
                        ? Icons.train_rounded
                        : (isNavigating
                            ? Icons.navigation_rounded
                            : Icons.my_location_rounded),
                    color: _primaryEmerald,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isTrain
                            ? '${widget.trainNumber} · ${widget.trainName}'
                            : (isNavigating
                                ? widget.destinationName!
                                : (widget.placeName ??
                                    '${widget.latitude.toStringAsFixed(4)}°, ${widget.longitude.toStringAsFixed(4)}°')),
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: _textDark,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isTrain
                            ? (widget.nextStation != null
                                ? 'Approaching ${widget.nextStation} · ${widget.speedKmh ?? 0} km/h'
                                : 'Live on Indian Railways track')
                            : (isNavigating
                                ? '${widget.tripEta ?? "En route"} · ${widget.remainingDistance ?? "Live GPS"}'
                                : 'Accuracy: ±${widget.accuracyMeters?.toStringAsFixed(0) ?? "5"}m · Real-time Fused GPS'),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isNavigating
                              ? const Color(0xff1b873f)
                              : _textMuted,
                          fontWeight:
                              isNavigating ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ─── 4. Duration Selector Chips ──────────────────────────────────────
          Row(
            children: List.generate(_durationLabels.length, (index) {
              final isSelected = _selectedDurationIndex == index;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: index < _durationLabels.length - 1 ? 6 : 0,
                  ),
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedDurationIndex = index);
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? _primaryEmerald
                            : const Color(0xfff1f5f9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? _primaryEmerald
                              : Colors.transparent,
                        ),
                      ),
                      child: Text(
                        _durationLabels[index],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.w600,
                          color: isSelected ? Colors.white : _textDark,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),

          const SizedBox(height: 16),

          // ─── 5. Sleek Action Buttons Row (WhatsApp, SMS, Copy Link, More) ────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildShareActionButton(
                icon: Icons.chat_rounded,
                label: 'WhatsApp',
                bgColor: const Color(0xffe8f5e9),
                iconColor: const Color(0xff2e7d32),
                onTap: _shareViaWhatsApp,
              ),
              _buildShareActionButton(
                icon: Icons.sms_rounded,
                label: 'Message',
                bgColor: const Color(0xffe0f2fe),
                iconColor: const Color(0xff0284c7),
                onTap: _shareViaSms,
              ),
              _buildShareActionButton(
                icon: Icons.link_rounded,
                label: 'Copy Link',
                bgColor: const Color(0xfffef3c7),
                iconColor: const Color(0xffd97706),
                onTap: _copyToClipboard,
              ),
              _buildShareActionButton(
                icon: Icons.ios_share_rounded,
                label: 'More',
                bgColor: const Color(0xfff1f5f9),
                iconColor: const Color(0xff475569),
                onTap: _shareViaSystem,
              ),
            ],
          ),

          const SizedBox(height: 14),

          // ─── 6. Privacy & Security Assurance Note ────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xfff8fafc),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: const [
                Icon(Icons.shield_outlined, size: 14, color: _primaryEmerald),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Direct NavGuide live link. Only people you send this to can view your spot.',
                    style: TextStyle(fontSize: 10.5, color: _textMuted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  ),
);
  }

  Widget _buildShareActionButton({
    required IconData icon,
    required String label,
    required Color bgColor,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
                border: Border.all(color: iconColor.withValues(alpha: 0.15)),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: _textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
