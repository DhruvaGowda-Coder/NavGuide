import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../domain/union_models.dart';
import '../../device/unions/union_service.dart';

class EditConvoySheet extends StatefulWidget {
  final TravelUnionGroup convoy;
  final UnionService service;

  const EditConvoySheet({
    super.key,
    required this.convoy,
    required this.service,
  });

  @override
  State<EditConvoySheet> createState() => _EditConvoySheetState();
}

class _EditConvoySheetState extends State<EditConvoySheet> {
  static const _emerald = Color(0xff0e382d);
  static const _textDark = Color(0xff1e293b);
  static const _textMuted = Color(0xff64748b);

  late final TextEditingController _titleCtrl;
  late final TextEditingController _fromCtrl;
  late final TextEditingController _toCtrl;
  late final TextEditingController _highwayCtrl;
  late final TextEditingController _dateCtrl;
  late final TextEditingController _descCtrl;
  late VehicleCategory _cat;
  late String _selectedBanner;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final u = widget.convoy;
    _titleCtrl = TextEditingController(text: u.title);
    _fromCtrl = TextEditingController(text: u.fromLocation);
    _toCtrl = TextEditingController(text: u.toLocation);
    _highwayCtrl = TextEditingController(text: u.viaHighway);
    _dateCtrl = TextEditingController(text: u.departureDateStr);
    _descCtrl = TextEditingController(text: u.description);
    _cat = u.category;
    _selectedBanner = u.imageUrl.isNotEmpty
        ? u.imageUrl
        : UnionService.getRandomScenicBanner(u.id.hashCode);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _highwayCtrl.dispose();
    _dateCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _emerald),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 6, minute: 0),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _emerald),
        ),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;

    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final ampm = time.hour < 12 ? 'AM' : 'PM';
    final hour = time.hour == 0 ? 12 : (time.hour > 12 ? time.hour - 12 : time.hour);
    final min = time.minute.toString().padLeft(2, '0');
    setState(() {
      _dateCtrl.text = '${date.day} ${months[date.month - 1]} ${date.year} • ${hour.toString().padLeft(2, '0')}:$min $ampm';
    });
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty ||
        _fromCtrl.text.trim().isEmpty ||
        _toCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill title, start, and destination.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await widget.service.updateUnion(
        unionId: widget.convoy.id,
        title: _titleCtrl.text.trim(),
        fromLocation: _fromCtrl.text.trim(),
        toLocation: _toCtrl.text.trim(),
        viaHighway: _highwayCtrl.text.trim(),
        departureDateStr: _dateCtrl.text.trim().isEmpty ? 'TBD' : _dateCtrl.text.trim(),
        category: _cat,
        hostName: widget.convoy.hostName,
        hostMobile: widget.convoy.hostMobile,
        hostEmail: widget.convoy.hostEmail,
        hostVehicle: _cat.shortLabel,
        description: _descCtrl.text.trim(),
        imageUrl: _selectedBanner,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: _emerald,
            content: Text('Convoy updated successfully!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update convoy: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final navPad = math.max(48.0, math.max(media.padding.bottom, media.viewPadding.bottom));
    final bottomPad = media.viewInsets.bottom > 20
        ? (16.0 + media.viewInsets.bottom)
        : (24.0 + navPad);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPad),
      child: SafeArea(
        top: false,
        bottom: true,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Title Row
              Row(
                children: [
                  const Icon(Icons.edit_note_rounded, color: _emerald, size: 24),
                  const SizedBox(width: 8),
                  const Text(
                    'Edit Convoy',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _textDark,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20, color: _textMuted),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Live Banner Preview
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  children: [
                    SizedBox(
                      height: 100,
                      width: double.infinity,
                      child: _selectedBanner.startsWith('assets/')
                          ? Image.asset(_selectedBanner, fit: BoxFit.cover, cacheWidth: 700)
                          : Image.network(
                              _selectedBanner,
                              fit: BoxFit.cover,
                              cacheWidth: 700,
                              errorBuilder: (_, __, ___) => Image.asset(
                                UnionService.defaultScenicBanners[0],
                                fit: BoxFit.cover,
                                cacheWidth: 700,
                              ),
                            ),
                    ),
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.65),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ),
                    const Positioned(
                      bottom: 8,
                      left: 10,
                      child: Text(
                        'Selected Cover Banner',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Scenic Banner Selector
              const Text(
                'Change Cover Banner',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _textDark,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 64,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: UnionService.defaultScenicBanners.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final bPath = UnionService.defaultScenicBanners[i];
                    final isSel = bPath == _selectedBanner;
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedBanner = bPath);
                      },
                      child: Container(
                        width: 90,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSel ? _emerald : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.asset(bPath, fit: BoxFit.cover, cacheWidth: 200),
                              if (isSel)
                                Container(
                                  color: _emerald.withValues(alpha: 0.35),
                                  child: const Center(
                                    child: Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Form fields
              _f(_titleCtrl, 'Convoy Title', Icons.flag_rounded),
              const SizedBox(height: 10),
              _f(_fromCtrl, 'From (City / Location)', Icons.trip_origin_rounded),
              const SizedBox(height: 10),
              _f(_toCtrl, 'To (City / Location)', Icons.location_on_rounded),
              const SizedBox(height: 10),
              _f(_highwayCtrl, 'Via Highway (optional, e.g. NH 48)', Icons.alt_route_rounded),
              const SizedBox(height: 10),
              _f(
                _dateCtrl,
                'Departure Date & Time',
                Icons.calendar_today_rounded,
                readOnly: true,
                onTap: _pickDateTime,
              ),
              const SizedBox(height: 10),
              _f(_descCtrl, 'Description / Plan', Icons.description_rounded, maxLines: 2),
              const SizedBox(height: 10),

              // Category selector
              DropdownButtonFormField<VehicleCategory>(
                initialValue: _cat,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xfff1f5f3),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
                  prefixIcon: const Icon(Icons.directions_car_rounded, color: _emerald, size: 18),
                ),
                items: VehicleCategory.values
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(c.shortLabel, style: const TextStyle(fontSize: 13)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _cat = v ?? _cat),
              ),
              const SizedBox(height: 18),

              // Save Button
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _emerald,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded, size: 18),
                  label: Text(
                    _isSubmitting ? 'Saving...' : 'Save Convoy Details',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: _isSubmitting ? null : _save,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _f(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    int maxLines = 1,
    bool readOnly = false,
    VoidCallback? onTap,
  }) =>
      TextField(
        controller: ctrl,
        maxLines: maxLines,
        readOnly: readOnly,
        onTap: onTap,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: _textMuted, fontSize: 13),
          prefixIcon: Icon(icon, color: _emerald, size: 18),
          filled: true,
          fillColor: const Color(0xfff1f5f3),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
        ),
      );
}
