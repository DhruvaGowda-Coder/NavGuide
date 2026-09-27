import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../device/auth/google_auth_service.dart';
import '../../device/unions/union_service.dart';
import '../../domain/union_models.dart';
import 'convoy_details_screen.dart';
import 'group_detail_screen.dart';
import 'widgets/union_google_auth_sheet.dart';

const Color primaryEmerald = Color(0xff23695a);
const Color textDark = Color(0xff1e293b);
const Color textMuted = Color(0xff64748b);
const Color scaffoldBg = Color(0xfff7f9f6);

class UnionsScreen extends StatefulWidget {
  const UnionsScreen({super.key});
  @override
  State<UnionsScreen> createState() => _UnionsScreenState();
}

class _UnionsScreenState extends State<UnionsScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  static const int _pageSize = 8;

  late TabController _mainTabCtrl;
  final UnionService _service = UnionService();
  // Cache the auth service reference — avoid re-creating on every build
  final GoogleAuthService _auth = GoogleAuthService();
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _groupSearchCtrl = TextEditingController();
  String _searchQuery = '';
  String _groupSearch = '';
  String _selectedCategory = 'Travel Unions & Convoys';
  String? _selectedCity;
  int _visibleCount = _pageSize;
  int _groupFilterTab = 0; // 0: All Groups, 1: My Groups

  // Debounce timers — prevent rebuilds on every keystroke
  Timer? _searchDebounce;
  Timer? _groupSearchDebounce;

  @override
  bool get wantKeepAlive => true;

  Timer? _liveSyncTimer;

  @override
  void initState() {
    super.initState();
    _mainTabCtrl = TabController(length: 2, vsync: this);
    _service.initialize();
    _service.addListener(_onServiceUpdate);
    _auth.addListener(_onServiceUpdate);
    _searchCtrl.addListener(_onSearchChanged);
    _groupSearchCtrl.addListener(_onGroupSearchChanged);

    // Live auto-sync: every 4 seconds, pull any newly created groups or convoys
    _liveSyncTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) {
        _service.syncWithFirebase();
      }
    });
  }

  bool _bannersPrecached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_bannersPrecached) {
      _bannersPrecached = true;
      for (final b in UnionService.defaultScenicBanners) {
        precacheImage(AssetImage(b), context);
      }
    }
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      if (mounted) {
        setState(() {
          _searchQuery = _searchCtrl.text.trim().toLowerCase();
          _visibleCount = _pageSize;
        });
      }
    });
  }

  void _onGroupSearchChanged() {
    _groupSearchDebounce?.cancel();
    _groupSearchDebounce = Timer(const Duration(milliseconds: 280), () {
      if (mounted) {
        setState(() => _groupSearch = _groupSearchCtrl.text.trim().toLowerCase());
      }
    });
  }

  @override
  void dispose() {
    _liveSyncTimer?.cancel();
    _searchDebounce?.cancel();
    _groupSearchDebounce?.cancel();
    _mainTabCtrl.dispose();
    _service.removeListener(_onServiceUpdate);
    _auth.removeListener(_onServiceUpdate);
    _searchCtrl.removeListener(_onSearchChanged);
    _groupSearchCtrl.removeListener(_onGroupSearchChanged);
    _searchCtrl.dispose();
    _groupSearchCtrl.dispose();
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _signInWithGoogle() async {
    await _ensureSignedInForSync(showSuccess: true);
  }

  Future<GoogleUserProfile?> _ensureSignedInForSync({
    bool showSuccess = false,
  }) async {
    final auth = GoogleAuthService();
    try {
      await auth.initialize();
      var user = auth.currentUser;
      if (user == null || user.email.trim().isEmpty) {
        user = await auth.signIn();
      }
      if (user == null || user.email.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please sign in with Google to sync this action.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return null;
      }
      await _service.syncWithGoogleUser(user);
      if (showSuccess && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Signed in as ${user.displayName}. Sync is active.'),
            backgroundColor: primaryEmerald,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return user;
    } catch (_) {
      // Keep Google cancel/dismiss quiet. The user can tap Sign In again.
    }
    return null;
  }

  Future<void> _makeCall(String p) async {
    try {
      final clean = p.replaceAll(RegExp(r'\s+'), '');
      await launchUrl(
        Uri.parse('tel:$clean'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
  }

  Future<void> _sendEmail(String e) async {
    try {
      await launchUrl(
        Uri.parse('mailto:$e'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
  }

  bool _isOpeningModal = false;

  Future<void> _openCreate() async {
    if (_isOpeningModal) return;
    _isOpeningModal = true;
    try {
      // Show the sheet IMMEDIATELY — auth check happens on submit, not here
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useRootNavigator: false,
        backgroundColor: Colors.transparent,
        builder: (_) => _CreateUnionSheet(service: _service),
      );
    } finally {
      if (mounted) _isOpeningModal = false;
    }
  }

  void _openEdit(TravelUnionGroup union) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EditUnionSheet(service: _service, union: union),
  );

  void _openRequestJoin(TravelUnionGroup union) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RequestJoinSheet(service: _service, union: union),
  );

  void _openDetails(TravelUnionGroup union) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ConvoyDetailsScreen(unionId: union.id)),
    );
  }

  Future<void> _confirmLeaveGroup(TravelGroup g) async {
    final isPending = _service.isGroupPending(g);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              isPending ? Icons.cancel_schedule_send_rounded : Icons.exit_to_app_rounded,
              color: isPending ? Colors.orange : Colors.redAccent,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(isPending ? 'Cancel Join Request?' : 'Leave Group'),
          ],
        ),
        content: Text(
          isPending
              ? 'Do you want to withdraw your request to join "${g.name}"?'
              : 'Are you sure you want to leave "${g.name}"?\nYou will lose access to member convoys and group chat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: isPending ? Colors.orange.shade700 : Colors.redAccent,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(isPending ? 'Withdraw Request' : 'Leave Group'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _service.leaveGroup(g.id);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isPending
                  ? 'Cancelled request for "${g.name}".'
                  : 'You left "${g.name}".',
            ),
          ),
        );
      }
    }
  }

  void _pickCityDialog() {
    final cities = [
      'All Cities',
      // Karnataka
      'Bangalore',
      'Mysore',
      'Mangalore',
      'Hassan',
      'Chikmagalur',
      'Coorg (Madikeri)',
      'Hampi',
      'Hubli',
      'Dharwad',
      'Belgaum',
      'Udupi',
      'Shimoga',
      'Tumkur',
      'Hospet',
      'Bidar', 'Kolar', 'Davanagere', 'Raichur',
      // Tamil Nadu
      'Chennai',
      'Coimbatore',
      'Madurai',
      'Salem',
      'Tiruchirappalli',
      'Tirunelveli',
      'Vellore',
      'Ooty (Udhagamandalam)',
      'Kodaikanal',
      'Thanjavur',
      'Pondicherry',
      'Kanyakumari',
      // Kerala
      'Kochi',
      'Thiruvananthapuram',
      'Kozhikode',
      'Thrissur',
      'Alappuzha',
      'Munnar',
      'Wayanad', 'Varkala', 'Kollam',
      // Andhra Pradesh & Telangana
      'Hyderabad',
      'Visakhapatnam',
      'Vijayawada',
      'Guntur',
      'Tirupati',
      'Warangal',
      'Karimnagar',
      // Goa
      'Panaji', 'Margao', 'Mapusa', 'Vasco da Gama',
      // Maharashtra
      'Mumbai',
      'Pune',
      'Nashik',
      'Nagpur',
      'Aurangabad',
      'Kolhapur',
      'Solapur',
      'Lonavala',
      'Mahabaleshwar', 'Shirdi', 'Ratnagiri',
      // Gujarat
      'Ahmedabad', 'Surat', 'Vadodara', 'Rajkot', 'Jamnagar', 'Bhavnagar',
      // Rajasthan
      'Jaipur',
      'Jodhpur',
      'Udaipur',
      'Jaisalmer',
      'Ajmer',
      'Pushkar',
      'Bikaner',
      'Kota',
      // Delhi & NCR
      'Delhi', 'Noida', 'Gurgaon', 'Faridabad', 'Ghaziabad',
      // Uttar Pradesh
      'Agra',
      'Lucknow',
      'Varanasi',
      'Prayagraj',
      'Mathura',
      'Vrindavan',
      'Kanpur',
      // Himachal Pradesh
      'Shimla', 'Manali', 'Dharamshala', 'Dalhousie', 'Kasauli', 'Spiti Valley',
      // Uttarakhand
      'Dehradun',
      'Haridwar',
      'Rishikesh',
      'Mussoorie',
      'Nainital',
      'Jim Corbett',
      'Roorkee', 'Auli',
      // Punjab & Haryana
      'Chandigarh', 'Amritsar', 'Ludhiana', 'Jalandhar', 'Ambala',
      // Jammu & Kashmir
      'Srinagar', 'Jammu', 'Leh', 'Kargil', 'Pahalgam', 'Gulmarg',
      // Madhya Pradesh
      'Bhopal',
      'Indore',
      'Gwalior',
      'Ujjain',
      'Jabalpur',
      'Khajuraho',
      'Pachmarhi',
      // Odisha
      'Bhubaneswar', 'Cuttack', 'Puri', 'Rourkela',
      // West Bengal
      'Kolkata', 'Darjeeling', 'Siliguri', 'Durgapur',
      // North East
      'Guwahati',
      'Shillong',
      'Imphal',
      'Aizawl',
      'Agartala',
      'Itanagar',
      'Kohima',
      'Gangtok',
      // Bihar & Jharkhand
      'Patna', 'Gaya', 'Ranchi', 'Jamshedpur',
      // Other
      'Lakshadweep', 'Andaman & Nicobar',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.location_city_rounded, color: primaryEmerald),
                  SizedBox(width: 10),
                  Text(
                    'Filter Convoys by City',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: textDark,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                itemCount: cities.length,
                itemBuilder: (_, i) {
                  final city = cities[i];
                  final isSelected =
                      (city == 'All Cities' && _selectedCity == null) ||
                      (_selectedCity == city);
                  return ListTile(
                    leading: Icon(
                      city == 'All Cities'
                          ? Icons.public_rounded
                          : Icons.location_on_rounded,
                      color: isSelected ? primaryEmerald : textMuted,
                      size: 20,
                    ),
                    title: Text(
                      city,
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected ? primaryEmerald : textDark,
                        fontSize: 14,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_rounded, color: primaryEmerald)
                        : null,
                    dense: true,
                    onTap: () {
                      setState(() {
                        _selectedCity = city == 'All Cities' ? null : city;
                        _visibleCount = _pageSize;
                      });
                      Navigator.of(ctx).pop();
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(TravelUnionGroup union) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.redAccent,
              size: 26,
            ),
            SizedBox(width: 8),
            Text('Delete Convoy?'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${union.title}"?\nThis will remove the convoy for everyone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _service.deleteUnion(union.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${union.title}" was deleted.')),
        );
      }
    }
  }

  Future<void> _confirmDeleteGroup(TravelGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(
              Icons.delete_forever_rounded,
              color: Colors.redAccent,
              size: 24,
            ),
            SizedBox(width: 8),
            Text('Delete Group?'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${group.name}"?\nAll group convoys and chat messages will be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete Group'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _service.deleteGroup(group.id);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Group "${group.name}" was deleted.')),
        );
      }
    }
  }

  Future<void> _confirmLeave(TravelUnionGroup union) async {
    final isPending = _service.myMembershipStatus(union) == UnionMemberStatus.pending;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(
              isPending ? Icons.cancel_schedule_send_rounded : Icons.logout_rounded,
              color: isPending ? Colors.orange : Colors.redAccent,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(isPending ? 'Cancel Request?' : 'Exit Convoy?'),
          ],
        ),
        content: Text(
          isPending
              ? 'Do you want to cancel your pending join request for "${union.title}"?'
              : 'Are you sure you want to leave "${union.title}"?\nYou will no longer be a rider in this group.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Stay', style: TextStyle(color: textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: isPending ? Colors.orange.shade700 : Colors.redAccent,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(isPending ? 'Cancel Request' : 'Leave Convoy'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (isPending) {
        await _service.cancelJoinRequest(union.id);
      } else {
        await _service.leaveUnion(union.id);
      }
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isPending
                  ? 'Cancelled join request for "${union.title}".'
                  : 'You left "${union.title}".',
            ),
          ),
        );
      }
    }
  }

  Future<void> _confirmKickMember(
    TravelUnionGroup union,
    UnionMember member,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(
              Icons.person_remove_rounded,
              color: Colors.redAccent,
              size: 24,
            ),
            SizedBox(width: 8),
            Text('Kick Rider?'),
          ],
        ),
        content: Text('Remove "${member.name}" from "${union.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Kick Rider'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _service.kickMember(unionId: union.id, memberId: member.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${member.name}" was removed from the convoy.'),
          ),
        );
      }
    }
  }

  Widget _filterChip(String title, {int? count}) {
    final isSelected = _selectedCategory == title;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedCategory = title;
          _visibleCount = _pageSize;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? primaryEmerald : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? primaryEmerald : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: primaryEmerald.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : textDark,
              ),
            ),
            if (count != null && count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.25)
                      : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : textDark,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGoogleAuthChip() {
    final isSignedIn = _auth.isSignedIn;
    final user = _auth.currentUser;

    if (isSignedIn && user != null) {
      return InkWell(
        onTap: () => UnionGoogleAuthSheet.show(context),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF34D399), width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 10,
                backgroundColor: const Color(0xFF0F766E),
                backgroundImage: user.photoUrl != null
                    ? NetworkImage(user.photoUrl!)
                    : null,
                child: user.photoUrl == null
                    ? Text(
                        user.displayName.isNotEmpty
                            ? user.displayName[0].toUpperCase()
                            : 'G',
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 5),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 75),
                child: Text(
                  user.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return InkWell(
      onTap: _signInWithGoogle,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white38, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/navguide_icon.png',
              height: 13,
              width: 13,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 5),
            const Text(
              'Sign In',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestsBell(
    int pendingCount,
    List<MapEntry<TravelUnionGroup, UnionMember>> allPending,
    List<MapEntry<TravelGroup, GroupMember>> allGroupPending,
  ) {
    return InkWell(
      onTap: () => _openRequestsCenter(allPending, allGroupPending),
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: pendingCount > 0 ? 0.28 : 0.16),
              shape: BoxShape.circle,
              border: Border.all(
                color: pendingCount > 0 ? Colors.amberAccent : Colors.white24,
                width: pendingCount > 0 ? 1.5 : 1,
              ),
            ),
            child: Icon(
              pendingCount > 0
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
              color: pendingCount > 0 ? Colors.amberAccent : Colors.white,
              size: 18,
            ),
          ),
          if (pendingCount > 0)
            Positioned(
              top: -3,
              right: -3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: Colors.redAccent.shade700,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  pendingCount > 99 ? '99+' : '$pendingCount',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    height: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _openRequestsCenter(
    List<MapEntry<TravelUnionGroup, UnionMember>> allPending,
    List<MapEntry<TravelGroup, GroupMember>> allGroupPending,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RequestsCenterSheet(service: _service),
    );
  }

  Widget _buildPendingSummaryCard(
    List<MapEntry<TravelUnionGroup, UnionMember>> allPending,
    List<MapEntry<TravelGroup, GroupMember>> allGroupPending, {
    bool groupOnly = false,
  }) {
    final effectivePending =
        groupOnly ? <MapEntry<TravelUnionGroup, UnionMember>>[] : allPending;
    final effectiveGroupPending = allGroupPending;
    final totalCount = effectivePending.length + effectiveGroupPending.length;
    if (totalCount == 0) return const SizedBox.shrink();

    String summarySubtitle = '';
    if (effectiveGroupPending.isNotEmpty && effectivePending.isEmpty) {
      final first = effectiveGroupPending.first;
      if (totalCount == 1) {
        summarySubtitle = '${first.value.name} wants to join "${first.key.name}"';
      } else {
        summarySubtitle =
            '${first.value.name} and ${totalCount - 1} other${totalCount > 2 ? 's' : ''} requested to join your groups';
      }
    } else if (effectivePending.isNotEmpty && effectiveGroupPending.isEmpty) {
      final first = effectivePending.first;
      if (totalCount == 1) {
        summarySubtitle = '${first.value.name} wants to join "${first.key.title}"';
      } else {
        summarySubtitle =
            '${first.value.name} and ${totalCount - 1} other${totalCount > 2 ? 's' : ''} requested to join your convoys';
      }
    } else {
      summarySubtitle =
          '$totalCount pending request${totalCount > 1 ? 's' : ''} across your convoys & groups';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xfffffbeb),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade300, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.shade100.withValues(alpha: 0.6),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _openRequestsCenter(allPending, allGroupPending),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.mark_email_unread_rounded,
                      color: Colors.orange.shade900,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              groupOnly
                                  ? 'Pending Group Approvals'
                                  : 'Pending Join Requests',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                                color: textDark,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade800,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$totalCount',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          summarySubtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      backgroundColor: Colors.orange.shade100,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Text(
                      'Review All',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xff9a3412),
                      ),
                    ),
                    label: const Icon(
                      Icons.arrow_forward_rounded,
                      size: 13,
                      color: Color(0xff9a3412),
                    ),
                    onPressed: () =>
                        _openRequestsCenter(allPending, allGroupPending),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: Colors.orange.shade200),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              children: [
                if (effectiveGroupPending.isNotEmpty)
                  for (final entry in effectiveGroupPending.take(2))
                    _buildCompactRequestTile(
                      isGroup: true,
                      title: entry.key.name,
                      name: entry.value.name,
                      subtitle: 'Group · ${entry.key.category}',
                      onAccept: () async {
                        await _service.approveGroupMember(
                          entry.key.id,
                          entry.value.id,
                        );
                        if (mounted) {
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: primaryEmerald,
                              content: Text(
                                'Approved ${entry.value.name} into "${entry.key.name}"!',
                              ),
                            ),
                          );
                        }
                      },
                      onDecline: () async {
                        await _service.rejectGroupMember(
                          entry.key.id,
                          entry.value.id,
                        );
                        if (mounted) {
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Declined request from ${entry.value.name}.',
                              ),
                            ),
                          );
                        }
                      },
                    ),
                if (effectivePending.isNotEmpty)
                  for (final entry in effectivePending.take(
                    effectiveGroupPending.isEmpty ? 2 : 1,
                  ))
                    _buildCompactRequestTile(
                      isGroup: false,
                      title: entry.key.title,
                      name: entry.value.name,
                      subtitle: 'Convoy · ${entry.value.vehicle}',
                      isFull: entry.key.isFull,
                      onAccept: () async {
                        if (entry.key.isFull) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.red.shade700,
                              content: Text(
                                'Cannot accept: "${entry.key.title}" is full (${entry.key.maxMembers}/${entry.key.maxMembers})! Please edit convoy to increase team size.',
                              ),
                            ),
                          );
                          return;
                        }
                        final ok = await _service.respondToJoinRequest(
                          unionId: entry.key.id,
                          memberId: entry.value.id,
                          accept: true,
                        );
                        if (mounted) {
                          setState(() {});
                          if (ok) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: primaryEmerald,
                                content: Text(
                                  'Accepted ${entry.value.name} into "${entry.key.title}"!',
                                ),
                              ),
                            );
                          }
                        }
                      },
                      onDecline: () async {
                        await _service.respondToJoinRequest(
                          unionId: entry.key.id,
                          memberId: entry.value.id,
                          accept: false,
                        );
                        if (mounted) {
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Declined ${entry.value.name}\'s request.',
                              ),
                            ),
                          );
                        }
                      },
                    ),
                if (totalCount > 2)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 2),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xff9a3412),
                          side: BorderSide(color: Colors.orange.shade300),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 7),
                        ),
                        onPressed: () =>
                            _openRequestsCenter(allPending, allGroupPending),
                        child: Text(
                          'View all $totalCount pending requests in Requests Center ➔',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactRequestTile({
    required bool isGroup,
    required String title,
    required String name,
    required String subtitle,
    bool isFull = false,
    required VoidCallback onAccept,
    required VoidCallback onDecline,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.orange.shade100),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: Colors.orange.shade100,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: Colors.orange.shade900,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: textDark,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4.5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: isGroup ? primaryEmerald : const Color(0xff1b5e4a),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isGroup ? 'GROUP' : 'CONVOY',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (isFull) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4.5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.shade700,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'FULL',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  'for "$title"',
                  style: const TextStyle(fontSize: 11, color: textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
            icon: Icon(
              Icons.check_circle_rounded,
              color: isFull ? Colors.grey.shade400 : Colors.green.shade600,
              size: 24,
            ),
            tooltip: isFull ? 'Convoy Full' : 'Accept',
            onPressed: onAccept,
          ),
          IconButton(
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
            icon: Icon(
              Icons.cancel_rounded,
              color: Colors.red.shade400,
              size: 24,
            ),
            tooltip: 'Decline',
            onPressed: onDecline,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin
    final allGroupConvoyIds = _service.groups
        .expand((g) => g.convoyIds)
        .toSet();
    final allUnions = _service.unions.where((u) {
      if (allGroupConvoyIds.contains(u.id)) {
        return u.isPublicFeed;
      }
      return true;
    }).toList();

    final popularCount = allUnions
        .where(
          (u) =>
              u.isPopular ||
              u.hostRating >= 4.5 ||
              u.acceptedMembers.length >= 2,
        )
        .length;
    final myConvoysCount = _service.unions
        .where(
          (u) => _service.isOwner(u) || _service.myMembershipStatus(u) != null,
        )
        .length;

    // Filter by Search, City, and Category
    final sourceList = _selectedCategory == '🚗 My Convoys'
        ? _service.unions
        : allUnions;
    final filtered = sourceList.where((u) {
      if (_searchQuery.isNotEmpty) {
        final matchesSearch =
            u.title.toLowerCase().contains(_searchQuery) ||
            u.fromLocation.toLowerCase().contains(_searchQuery) ||
            u.toLocation.toLowerCase().contains(_searchQuery) ||
            u.hostName.toLowerCase().contains(_searchQuery) ||
            u.tags.any((t) => t.toLowerCase().contains(_searchQuery));
        if (!matchesSearch) return false;
      }
      if (_selectedCity != null && _selectedCity!.isNotEmpty) {
        final matchesCity =
            u.fromLocation.toLowerCase().contains(
              _selectedCity!.toLowerCase(),
            ) ||
            u.toLocation.toLowerCase().contains(_selectedCity!.toLowerCase());
        if (!matchesCity) return false;
      }
      if (_selectedCategory == '⭐ Popular') {
        return u.isPopular ||
            u.hostRating >= 4.5 ||
            u.acceptedMembers.length >= 2;
      } else if (_selectedCategory == '🚗 My Convoys') {
        return _service.isOwner(u) || _service.myMembershipStatus(u) != null;
      } else if (_selectedCategory == 'Nearby') {
        final loc = '${u.fromLocation} ${u.toLocation}'.toLowerCase();
        return loc.contains('bangalore') ||
            loc.contains('bengaluru') ||
            loc.contains('mysore') ||
            loc.contains('hassan') ||
            loc.contains('coorg');
      } else if (_selectedCategory == '🔖 Saved') {
        return _service.isSaved(u.id);
      }
      return true;
    }).toList();

    final visible = filtered.take(_visibleCount).toList();
    final hasMore = filtered.length > _visibleCount;

    // Collect pending approvals for both owned Convoys and administered Groups
    final allPending = <MapEntry<TravelUnionGroup, UnionMember>>[];
    for (final u in allUnions) {
      if (_service.isOwner(u)) {
        for (final p in u.pendingRequests) {
          allPending.add(MapEntry(u, p));
        }
      }
    }

    final allGroupPending = <MapEntry<TravelGroup, GroupMember>>[];
    for (final g in _service.groups) {
      if (_service.isGroupAdmin(g)) {
        for (final m in g.members.where((m) => m.isPending)) {
          allGroupPending.add(MapEntry(g, m));
        }
      }
    }

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        flexibleSpace: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/banners/community_header_banner.jpg',
              fit: BoxFit.cover,
              cacheWidth: 900,
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.35),
                    const Color(0xff0e382d).withValues(alpha: 0.88),
                  ],
                ),
              ),
            ),
          ],
        ),
        title: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.explore_rounded,
                  color: Colors.greenAccent,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'NavGuide Community',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                        color: Colors.black87,
                        blurRadius: 6,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              _buildRequestsBell(
                allPending.length + allGroupPending.length,
                allPending,
                allGroupPending,
              ),
              const SizedBox(width: 6),
              _buildGoogleAuthChip(),
            ],
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              height: 44,
              padding: const EdgeInsets.all(3.5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.16),
                  width: 1,
                ),
              ),
              child: TabBar(
                controller: _mainTabCtrl,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                labelColor: primaryEmerald,
                unselectedLabelColor: Colors.white.withValues(alpha: 0.85),
                labelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                tabs: const [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.groups_rounded, size: 16),
                        SizedBox(width: 6),
                        Text('Groups'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.explore_rounded, size: 16),
                        SizedBox(width: 6),
                        Text('Convoys'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _mainTabCtrl,
        children: [
          // ── Groups Tab ────────────────────────────────────
          _buildGroupsTab(allGroupPending),
          // ── Convoys Tab (existing) ─────────────────────────
          SafeArea(
            child: RefreshIndicator(
              color: primaryEmerald,
              onRefresh: () async {
                await _service.syncWithFirebase();
                if (mounted) setState(() {});
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // Search Bar & City Selector
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              decoration: InputDecoration(
                                hintText: 'Search destination, route, host...',
                                hintStyle: const TextStyle(
                                  fontSize: 13,
                                  color: textMuted,
                                ),
                                prefixIcon: const Icon(
                                  Icons.search_rounded,
                                  color: textMuted,
                                  size: 20,
                                ),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(
                                          Icons.close_rounded,
                                          size: 18,
                                        ),
                                        onPressed: () => _searchCtrl.clear(),
                                      )
                                    : null,
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 16,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade200,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade200,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                    color: primaryEmerald,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: _pickCityDialog,
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: _selectedCity != null
                                    ? primaryEmerald.withValues(alpha: 0.12)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: _selectedCity != null
                                      ? primaryEmerald
                                      : Colors.grey.shade300,
                                  width: _selectedCity != null ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.location_on_rounded,
                                    size: 17,
                                    color: _selectedCity != null
                                        ? primaryEmerald
                                        : textMuted,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _selectedCity ?? 'City',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: _selectedCity != null
                                          ? primaryEmerald
                                          : textDark,
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  Icon(
                                    Icons.arrow_drop_down_rounded,
                                    size: 18,
                                    color: _selectedCity != null
                                        ? primaryEmerald
                                        : textMuted,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Filter Category Chips
                  SliverToBoxAdapter(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
                      child: Row(
                        children: [
                          _filterChip(
                            'Travel Unions & Convoys',
                            count: allUnions.length,
                          ),
                          const SizedBox(width: 8),
                          _filterChip('🚗 My Convoys', count: myConvoysCount),
                          const SizedBox(width: 8),
                          _filterChip('⭐ Popular', count: popularCount),
                          const SizedBox(width: 8),
                          _filterChip('Nearby'),
                          const SizedBox(width: 8),
                          _filterChip('🔖 Saved', count: _service.savedCount),
                        ],
                      ),
                    ),
                  ),

                  // Create Convoy button (matches Create a Group button style)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primaryEmerald,
                            side: const BorderSide(color: primaryEmerald),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text(
                            'Create a Convoy',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          onPressed: _openCreate,
                        ),
                      ),
                    ),
                  ),

                  // Universal Pending Join Requests Summary Card
                  if (allPending.isNotEmpty || allGroupPending.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
                        child: _buildPendingSummaryCard(
                          allPending,
                          allGroupPending,
                        ),
                      ),
                    ),

                  // Section Header
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
                      child: Row(
                        children: [
                          Text(
                            filtered.isEmpty
                                ? 'No Convoys Found'
                                : 'Available Convoys (${filtered.length})',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: textDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Empty State
                  if (filtered.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 32, 18, 32),
                        child: Column(
                          children: [
                            Icon(
                              Icons.group_off_rounded,
                              size: 64,
                              color: Colors.grey.shade300,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? 'No convoys match "$_searchQuery"'
                                  : 'No active convoys in this view.\nBe the first to create one!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Convoy Cards
                  SliverList(
                    delegate: SliverChildBuilderDelegate((ctx, i) {
                      final u = visible[i];
                      final isOwner = _service.isOwner(u);
                      final myStatus = _service.myMembershipStatus(u);
                      final isSaved = _service.isSaved(u.id);

                      return _UnionCard(
                        union: u,
                        isOwner: isOwner,
                        myStatus: myStatus,
                        isSaved: isSaved,
                        myRating: _service.myRatingFor(u.id),
                        onTap: () => _openDetails(u),
                        onCall: _makeCall,
                        onEmail: _sendEmail,
                        onRequestJoin: () => _openRequestJoin(u),
                        onToggleSave: () => _service.toggleSaveUnion(u.id),
                        onEdit: () => _openEdit(u),
                        onDelete: () => _confirmDelete(u),
                        onLeave: () => _confirmLeave(u),
                        onRateUnion: (stars) => _service.rateUnion(u.id, stars),
                        onKickMember: (m) => _confirmKickMember(u, m),
                      );
                    }, childCount: visible.length),
                  ),

                  // Load More
                  if (hasMore)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primaryEmerald,
                            side: const BorderSide(color: primaryEmerald),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () =>
                              setState(() => _visibleCount += _pageSize),
                          child: Text(
                            'Load More (${filtered.length - _visibleCount} remaining)',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),

                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          ), // end Convoys SafeArea
        ], // end TabBarView children
      ), // end TabBarView
    ); // end Scaffold
  }

  // ─── Groups Tab ─────────────────────────────────────────────────────────────

  Widget _buildGroupsTab(List<MapEntry<TravelGroup, GroupMember>> allGroupPending) {
    final allGroups = _service.groups;
    final myGroups = allGroups.where((g) => _service.isGroupMember(g)).toList();
    final currentList = _groupFilterTab == 1 ? myGroups : allGroups;

    final filtered = _groupSearch.isEmpty
        ? currentList
        : currentList
              .where(
                (g) =>
                    g.name.toLowerCase().contains(_groupSearch) ||
                    g.description.toLowerCase().contains(_groupSearch) ||
                    g.category.toLowerCase().contains(_groupSearch),
              )
              .toList();

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _groupSearchCtrl,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Search groups...',
                hintStyle: TextStyle(color: textMuted, fontSize: 13),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: textMuted,
                  size: 18,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 11),
              ),
            ),
          ),
        ),
        // Filter pills: All Groups / My Groups
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: Row(
            children: [
              _groupFilterPill('All Groups', allGroups.length, 0),
              const SizedBox(width: 8),
              _groupFilterPill('👤 My Groups', myGroups.length, 1),
            ],
          ),
        ),
        // Create group button
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: primaryEmerald,
                side: const BorderSide(color: primaryEmerald),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text(
                'Create a Group',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              onPressed: _showCreateGroupSheet,
            ),
          ),
        ),
        // Pending Group Approvals summary banner
        if (allGroupPending.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: _buildPendingSummaryCard(
              const [],
              allGroupPending,
              groupOnly: true,
            ),
          ),
        // Group list
        Expanded(
          child: RefreshIndicator(
            color: primaryEmerald,
            onRefresh: () async {
              await _service.syncWithFirebase();
              if (mounted) setState(() {});
            },
            child: filtered.isEmpty
                ? LayoutBuilder(
                    builder: (ctx, constraints) => SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _groupFilterTab == 1
                                    ? Icons.group_off_rounded
                                    : Icons.group_outlined,
                                size: 48,
                                color: Colors.grey.shade300,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                _groupFilterTab == 1
                                    ? 'You haven\'t joined any groups yet'
                                    : 'No groups found',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: textDark,
                                  fontSize: 14,
                                ),
                              ),
                              if (_groupFilterTab == 1) ...[
                                const SizedBox(height: 4),
                                const Text(
                                  'Join a group from "All Groups" or create your own!',
                                  style: TextStyle(
                                    color: textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: () =>
                                      setState(() => _groupFilterTab = 0),
                                  child: const Text(
                                    'Browse All Groups',
                                    style: TextStyle(
                                      color: primaryEmerald,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final g = filtered[i];
                      final isMember = _service.isGroupMember(g);
                      final isAdmin = _service.isGroupAdmin(g);
                      final isPending = _service.isGroupPending(g);
                      return RepaintBoundary(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    GroupDetailScreen(groupId: g.id),
                              ),
                            );
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ── Scenic Travel Banner Top Header ──
                                SizedBox(
                                  height: 105,
                                  width: double.infinity,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      // Scenic nature/road banner image
                                      Image.asset(
                                        g.imageUrl.isNotEmpty
                                            ? g.imageUrl
                                            : UnionService.getRandomScenicBanner(
                                                g.id.hashCode,
                                              ),
                                        fit: BoxFit.cover,
                                        cacheWidth: 800,
                                        errorBuilder: (_, __, ___) => Container(
                                          decoration: const BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Color(0xFF1E3A2F),
                                                Color(0xFF0D231B),
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Dark atmospheric gradient overlay
                                      Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Colors.black.withValues(
                                                alpha: 0.25,
                                              ),
                                              Colors.transparent,
                                              Colors.black.withValues(
                                                alpha: 0.78,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      // Top row: category chip and privacy / member status
                                      Positioned(
                                        top: 10,
                                        left: 10,
                                        right: 10,
                                        child: Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 3,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(
                                                  alpha: 0.45,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: Colors.white24,
                                                  width: 0.8,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                    Icons.category_rounded,
                                                    size: 11,
                                                    color: Colors.white70,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    g.category,
                                                    style: const TextStyle(
                                                      fontSize: 10.5,
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const Spacer(),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 3,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(
                                                  alpha: 0.45,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: Colors.white24,
                                                  width: 0.8,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    g.isPublic
                                                        ? Icons.public_rounded
                                                        : Icons.lock_rounded,
                                                    size: 11,
                                                    color: Colors.white70,
                                                  ),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    g.isPublic
                                                        ? 'Public'
                                                        : 'Private',
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.white70,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (isAdmin) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: primaryEmerald,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: primaryEmerald
                                                          .withValues(
                                                            alpha: 0.4,
                                                          ),
                                                      blurRadius: 4,
                                                    ),
                                                  ],
                                                ),
                                                child: const Text(
                                                  'Admin',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ] else if (isMember) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.blue.shade600,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors
                                                          .blue
                                                          .shade600
                                                          .withValues(
                                                            alpha: 0.4,
                                                          ),
                                                      blurRadius: 4,
                                                    ),
                                                  ],
                                                ),
                                                child: const Text(
                                                  'Joined',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ] else if (isPending) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.amber.shade700,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors
                                                          .amber
                                                          .shade700
                                                          .withValues(
                                                            alpha: 0.4,
                                                          ),
                                                      blurRadius: 4,
                                                    ),
                                                  ],
                                                ),
                                                child: const Text(
                                                  '⏳ Pending',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      // Bottom row on banner: Emoji badge + Group Name
                                      Positioned(
                                        bottom: 8,
                                        left: 10,
                                        right: 10,
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 34,
                                              height: 34,
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(
                                                  alpha: 0.25,
                                                ),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.6),
                                                  width: 1.2,
                                                ),
                                              ),
                                              child: Text(
                                                g.emoji,
                                                style: const TextStyle(
                                                  fontSize: 18,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                g.name,
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                  shadows: [
                                                    Shadow(
                                                      color: Colors.black87,
                                                      blurRadius: 6,
                                                      offset: Offset(0, 1),
                                                    ),
                                                  ],
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // ── Group Details & Statistics Row ──
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    10,
                                    12,
                                    10,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (g.description.isNotEmpty) ...[
                                        Text(
                                          g.description,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: textMuted,
                                            height: 1.35,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                      ],
                                      Row(
                                        children: [
                                          _groupPill(
                                            Icons.group_rounded,
                                            '${g.approvedMembers.length} members',
                                          ),
                                          const SizedBox(width: 8),
                                          _groupPill(
                                            Icons.add_road_rounded,
                                            '${g.convoyIds.length} convoys',
                                          ),
                                          const SizedBox(width: 8),
                                          _groupPill(
                                            g.isPublic || isMember || isAdmin
                                                ? Icons.chat_rounded
                                                : Icons.lock_rounded,
                                            g.isPublic || isMember || isAdmin
                                                ? '${g.chatMessages.length} msgs'
                                                : 'Private chat',
                                          ),
                                          const Spacer(),
                                          if (isAdmin)
                                            IconButton(
                                              icon: const Icon(
                                                Icons.delete_outline_rounded,
                                                color: Colors.redAccent,
                                                size: 20,
                                              ),
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                minWidth: 32,
                                                minHeight: 32,
                                              ),
                                              tooltip: 'Delete Group',
                                              onPressed: () =>
                                                  _confirmDeleteGroup(g),
                                            )
                                          else if (isMember)
                                            IconButton(
                                              icon: const Icon(
                                                Icons.logout_rounded,
                                                color: Colors.redAccent,
                                                size: 20,
                                              ),
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                minWidth: 32,
                                                minHeight: 32,
                                              ),
                                              tooltip: 'Leave Group',
                                              onPressed: () =>
                                                  _confirmLeaveGroup(g),
                                            )
                                          else if (isPending)
                                            IconButton(
                                              icon: const Icon(
                                                Icons.cancel_schedule_send_rounded,
                                                color: Colors.orange,
                                                size: 20,
                                              ),
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                minWidth: 32,
                                                minHeight: 32,
                                              ),
                                              tooltip: 'Cancel Request',
                                              onPressed: () =>
                                                  _confirmLeaveGroup(g),
                                            ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: primaryEmerald.withValues(
                                                alpha: 0.1,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  'View',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: primaryEmerald,
                                                  ),
                                                ),
                                                SizedBox(width: 2),
                                                Icon(
                                                  Icons
                                                      .arrow_forward_ios_rounded,
                                                  size: 10,
                                                  color: primaryEmerald,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
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
        ),
      ],
    );
  }

  Widget _groupFilterPill(String label, int count, int index) {
    final isSelected = _groupFilterTab == index;
    return GestureDetector(
      onTap: () => setState(() => _groupFilterTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? primaryEmerald : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? primaryEmerald : Colors.grey.shade300,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: primaryEmerald.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? Colors.white : textDark,
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.25)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupPill(IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 11, color: primaryEmerald),
      const SizedBox(width: 3),
      Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          color: textMuted,
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  );

  Future<void> _showCreateGroupSheet() async {
    if (_isOpeningModal) return;
    _isOpeningModal = true;
    try {
      // Show the sheet IMMEDIATELY — auth check happens on submit, not here
      if (!mounted) return;

      final nameCtrl = TextEditingController();
      final descCtrl = TextEditingController();
      final adminNameCtrl = TextEditingController();
      final adminMobCtrl = TextEditingController(
        text: _service.myHostMobile ?? _service.myRiderMobile ?? '',
      );
      bool isPublic = true;
      String emoji = '🚗';
      String category = 'Riders';
      bool isSubmitting = false;
      String selectedBanner = UnionService.getRandomScenicBanner(
        DateTime.now().millisecondsSinceEpoch,
      );

      final categories = [
        'Riders',
        'Car Poolers',
        'Trekkers',
        'Travelers',
        'Adventurers',
        'Commuters',
        'Travel',
        'Bikers Club',
        'Cars & Bikes',
        'Weekend Getaways',
        'Offroad & Trails',
        'Long Tours',
      ];
      if (!categories.contains(category)) {
        categories.insert(0, category);
      }

      Widget buildBannerSelector(StateSetter setModal) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                children: [
                  SizedBox(
                    height: 90,
                    width: double.infinity,
                    child: Image.asset(
                      selectedBanner,
                      fit: BoxFit.cover,
                      cacheWidth: 600,
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
                    bottom: 7,
                    left: 10,
                    child: Text(
                      'Selected Group Banner',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Choose Group Banner',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textDark,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: UnionService.defaultScenicBanners.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final banner = UnionService.defaultScenicBanners[i];
                  final isSelected = banner == selectedBanner;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setModal(() => selectedBanner = banner);
                    },
                    child: Container(
                      width: 80,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? primaryEmerald : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.asset(
                              banner,
                              fit: BoxFit.cover,
                              cacheWidth: 200,
                            ),
                            if (isSelected)
                              Container(
                                color: primaryEmerald.withValues(alpha: 0.35),
                                child: const Center(
                                  child: Icon(
                                    Icons.check_circle_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
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
          ],
        );
      }

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useRootNavigator: false,
        backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.88,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            math.max(
              28.0,
              16.0 +
                  MediaQuery.of(ctx).viewInsets.bottom +
                  MediaQuery.of(ctx).padding.bottom,
            ),
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
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
                const Text(
                  'Create a Group',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: textDark,
                  ),
                ),
                const SizedBox(height: 14),
                buildBannerSelector(setModal),
                const SizedBox(height: 14),
                _sField(nameCtrl, 'Group Name', Icons.group_rounded),
                const SizedBox(height: 10),
                _sField(
                  descCtrl,
                  'Description',
                  Icons.description_rounded,
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                // Category dropdown
                DropdownButtonFormField<String>(
                  initialValue: categories.contains(category)
                      ? category
                      : (categories.isNotEmpty ? categories.first : null),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xfff1f5f3),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 13,
                      horizontal: 14,
                    ),
                    prefixIcon: const Icon(
                      Icons.category_rounded,
                      color: primaryEmerald,
                      size: 18,
                    ),
                  ),
                  items: categories
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(c, style: const TextStyle(fontSize: 13)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setModal(() => category = v ?? category),
                ),
                const SizedBox(height: 10),
                _sField(
                  adminNameCtrl,
                  'Your Name (Admin)',
                  Icons.person_rounded,
                ),
                const SizedBox(height: 10),
                _sField(
                  adminMobCtrl,
                  'Your Mobile',
                  Icons.phone_rounded,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                // Public/Private toggle
                Row(
                  children: [
                    const Text(
                      'Group Type:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textDark,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => setModal(() => isPublic = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isPublic
                              ? primaryEmerald
                              : Colors.grey.shade100,
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(8),
                          ),
                        ),
                        child: Text(
                          'Public 🌐',
                          style: TextStyle(
                            fontSize: 12,
                            color: isPublic ? Colors.white : textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setModal(() => isPublic = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: !isPublic
                              ? primaryEmerald
                              : Colors.grey.shade100,
                          borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(8),
                          ),
                        ),
                        child: Text(
                          'Private 🔒',
                          style: TextStyle(
                            fontSize: 12,
                            color: !isPublic ? Colors.white : textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryEmerald,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.add_rounded, size: 18),
                    label: Text(
                      isSubmitting ? 'Creating Group...' : 'Create Group',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            if (nameCtrl.text.trim().isEmpty ||
                                adminNameCtrl.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Please enter a group name and your name.',
                                  ),
                                ),
                              );
                              return;
                            }
                            setModal(() => isSubmitting = true);
                            try {
                              final googleUser = await _ensureSignedInForSync();
                              if (googleUser == null || !mounted) {
                                setModal(() => isSubmitting = false);
                                return;
                              }
                              final group = await _service.createGroup(
                                name: nameCtrl.text.trim(),
                                description: descCtrl.text.trim(),
                                category: category,
                                isPublic: isPublic,
                                emoji: emoji,
                                adminName: adminNameCtrl.text.trim(),
                                adminMobile: adminMobCtrl.text.trim(),
                                imageUrl: selectedBanner,
                              );
                              if (ctx.mounted) Navigator.of(ctx).pop();
                              if (mounted) {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        GroupDetailScreen(groupId: group.id),
                                  ),
                                );
                              }
                            } catch (_) {
                              if (ctx.mounted) {
                                setModal(() => isSubmitting = false);
                              }
                            }
                          },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  } finally {
    if (mounted) _isOpeningModal = false;
  }
}

  Widget _sField(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    TextInputType? keyboardType,
    int maxLines = 1,
  }) => TextField(
    controller: ctrl,
    keyboardType: keyboardType,
    maxLines: maxLines,
    style: const TextStyle(fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: textMuted, fontSize: 13),
      prefixIcon: Icon(icon, color: primaryEmerald, size: 18),
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

// -- Convoy Card matching Mockup Design --------------------------------------

class _UnionCard extends StatefulWidget {
  final TravelUnionGroup union;
  final bool isOwner;
  final UnionMemberStatus? myStatus;
  final bool isSaved;
  final int? myRating;
  final VoidCallback onTap;
  final void Function(String) onCall;
  final void Function(String) onEmail;
  final VoidCallback onRequestJoin;
  final VoidCallback onToggleSave;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onLeave;
  final void Function(int stars) onRateUnion;
  final void Function(UnionMember) onKickMember;

  const _UnionCard({
    required this.union,
    required this.isOwner,
    required this.myStatus,
    required this.isSaved,
    this.myRating,
    required this.onTap,
    required this.onCall,
    required this.onEmail,
    required this.onRequestJoin,
    required this.onToggleSave,
    required this.onEdit,
    required this.onDelete,
    required this.onLeave,
    required this.onRateUnion,
    required this.onKickMember,
  });

  @override
  State<_UnionCard> createState() => _UnionCardState();
}

class _UnionCardState extends State<_UnionCard> {
  static const Color primaryEmerald = Color(0xff23695a);
  static const Color textDark = Color(0xff1e293b);
  static const Color textMuted = Color(0xff64748b);
  bool _expanded = false;

  IconData _catIcon(VehicleCategory c) => getVehicleCategoryIcon(c);

  @override
  Widget build(BuildContext context) {
    final u = widget.union;
    final accepted = u.members
        .where((m) => m.status == UnionMemberStatus.accepted)
        .toList();
    final full = accepted.length >= u.maxMembers;
    final canContact =
        widget.isOwner || widget.myStatus == UnionMemberStatus.accepted;
    final isLive = u.liveRiders.isNotEmpty ||
        u.statusTag.toLowerCase().contains('live') ||
        u.statusTag.toLowerCase().contains('active') ||
        u.statusTag.toLowerCase().contains('ongoing');

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: widget.isOwner
                      ? primaryEmerald.withValues(alpha: 0.4)
                      : Colors.grey.shade200,
                  width: widget.isOwner ? 1.5 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Scenic Top Banner with Capacity & Status Overlays
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(18),
                    ),
                    child: Stack(
                      children: [
                        Container(
                          height: 110,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xff143d31),
                                const Color(0xff1b5e4a),
                                primaryEmerald,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: _buildBanner(u.imageUrl, u.id.hashCode),
                        ),
                        // Gradient Vignette
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.black.withValues(alpha: 0.5),
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.65),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                        ),
                        // Top Left: Status Tag (Live Radar or Category tag)
                        Positioned(
                          top: 10,
                          left: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isLive
                                  ? const Color(0xff064e3b).withValues(alpha: 0.90)
                                  : Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isLive
                                    ? const Color(0xff34d399)
                                    : Colors.white.withValues(alpha: 0.25),
                                width: isLive ? 1.2 : 1,
                              ),
                              boxShadow: isLive
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xff34d399).withValues(alpha: 0.35),
                                        blurRadius: 8,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isLive ? Icons.radar_rounded : Icons.flash_on_rounded,
                                  color: isLive ? const Color(0xff34d399) : Colors.amberAccent,
                                  size: 12,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isLive
                                      ? (u.liveRiders.isNotEmpty
                                          ? 'LIVE ON ROAD (${u.liveRiders.length})'
                                          : 'LIVE ON ROAD')
                                      : (u.statusTag.isNotEmpty
                                          ? u.statusTag
                                          : 'Weekend Ride'),
                                  style: TextStyle(
                                    color: isLive ? const Color(0xffa7f3d0) : Colors.white,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: isLive ? 0.3 : 0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Top Right: Save Bookmark
                        Positioned(
                          top: 10,
                          right: 10,
                          child: GestureDetector(
                            onTap: widget.onToggleSave,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.25),
                                ),
                              ),
                              child: Icon(
                                widget.isSaved
                                    ? Icons.bookmark_rounded
                                    : Icons.bookmark_border_rounded,
                                color: widget.isSaved
                                    ? Colors.amberAccent
                                    : Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                        // Bottom Left: Capacity Badge (e.g. 10/15 Riders)
                        Positioned(
                          bottom: 10,
                          left: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: full
                                  ? Colors.red.shade900.withValues(alpha: 0.85)
                                  : Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: full
                                    ? Colors.redAccent.withValues(alpha: 0.6)
                                    : Colors.white.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  full
                                      ? Icons.lock_rounded
                                      : Icons.group_rounded,
                                  color: full
                                      ? Colors.redAccent
                                      : Colors.greenAccent,
                                  size: 13,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  full
                                      ? 'Team Full (${u.maxMembers}/${u.maxMembers})'
                                      : '${accepted.length}/${u.maxMembers} Riders',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Bottom Right: Vehicle Category
                        Positioned(
                          bottom: 10,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _catIcon(u.category),
                                  size: 13,
                                  color: primaryEmerald,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  u.category.displayName,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: primaryEmerald,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Card Details
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title + Owner Badge + Options
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    u.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: textDark,
                                    ),
                                  ),
                                  if (u.slogan.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      u.slogan,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: primaryEmerald,
                                        fontWeight: FontWeight.w500,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (widget.isOwner) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: primaryEmerald,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'YOUR CONVOY',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              PopupMenuButton<String>(
                                icon: const Icon(
                                  Icons.more_vert_rounded,
                                  color: textMuted,
                                  size: 20,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onSelected: (val) {
                                  if (val == 'edit') widget.onEdit();
                                  if (val == 'delete') widget.onDelete();
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.edit_rounded,
                                          size: 18,
                                          color: primaryEmerald,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Edit Convoy',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.delete_forever_rounded,
                                          size: 18,
                                          color: Colors.redAccent,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Delete Convoy',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.redAccent,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Route Corridor Visual Timeline Capsule
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xfff8faf9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xffe6ece9),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Origin -> Line with Vehicle -> Destination
                              Row(
                                children: [
                                  // Origin Dot
                                  Container(
                                    width: 9,
                                    height: 9,
                                    decoration: const BoxDecoration(
                                      color: Color(0xff10b981),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  Expanded(
                                    child: Text(
                                      u.fromLocation,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: textDark,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  // Route connector
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 14,
                                          height: 1.5,
                                          color: Colors.grey.shade300,
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                          ),
                                          child: Icon(
                                            _catIcon(u.category),
                                            size: 14,
                                            color: primaryEmerald,
                                          ),
                                        ),
                                        Container(
                                          width: 14,
                                          height: 1.5,
                                          color: Colors.grey.shade300,
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Destination
                                  Expanded(
                                    child: Text(
                                      u.toLocation,
                                      textAlign: TextAlign.end,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: textDark,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.flag_rounded,
                                    size: 14,
                                    color: Color(0xffef4444),
                                  ),
                                ],
                              ),
                              if (u.viaHighway.isNotEmpty &&
                                  u.viaHighway != 'Direct Route') ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: primaryEmerald.withValues(
                                          alpha: 0.08,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.alt_route_rounded,
                                            size: 11,
                                            color: primaryEmerald,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'via ${u.viaHighway}',
                                            style: const TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w600,
                                              color: primaryEmerald,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 8),
                              // Timing & Distance Badges
                              Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today_rounded,
                                    size: 12,
                                    color: textMuted.withValues(alpha: 0.9),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    u.departureDateStr,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                      color: textMuted,
                                    ),
                                  ),
                                  if (u.estimatedDistanceKm > 0) ...[
                                    const Text(
                                      ' · ',
                                      style: TextStyle(color: textMuted),
                                    ),
                                    Icon(
                                      Icons.straighten_rounded,
                                      size: 12,
                                      color: textMuted.withValues(alpha: 0.9),
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      '${u.estimatedDistanceKm} km',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: textDark,
                                      ),
                                    ),
                                  ],
                                  if (u.estimatedDuration.isNotEmpty) ...[
                                    const Text(
                                      ' · ',
                                      style: TextStyle(color: textMuted),
                                    ),
                                    Icon(
                                      Icons.schedule_rounded,
                                      size: 12,
                                      color: textMuted.withValues(alpha: 0.9),
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      u.estimatedDuration,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w500,
                                        color: textMuted,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Host Card with Rating & Direct Contact
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xfff8fafc),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 12,
                                backgroundColor: primaryEmerald.withValues(
                                  alpha: 0.15,
                                ),
                                child: Text(
                                  u.hostName.isNotEmpty
                                      ? u.hostName[0].toUpperCase()
                                      : 'H',
                                  style: const TextStyle(
                                    color: primaryEmerald,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 7),
                              Text(
                                'Host: ${u.hostName}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: textDark,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.verified_rounded,
                                size: 14,
                                color: primaryEmerald,
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.star_rounded,
                                      size: 11,
                                      color: Colors.amber,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      u.hostRating.toStringAsFixed(1),
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.amber.shade900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              if (canContact) ...[
                                GestureDetector(
                                  onTap: () => widget.onCall(u.hostMobile),
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: primaryEmerald.withValues(
                                        alpha: 0.1,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.call_rounded,
                                      size: 14,
                                      color: primaryEmerald,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => widget.onEmail(u.hostEmail),
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: primaryEmerald.withValues(
                                        alpha: 0.1,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.email_rounded,
                                      size: 14,
                                      color: primaryEmerald,
                                    ),
                                  ),
                                ),
                              ] else
                                const Icon(
                                  Icons.privacy_tip_outlined,
                                  size: 18,
                                  color: textMuted,
                                ),
                            ],
                          ),
                        ),

                        // Tags
                        if (u.tags.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: u.tags
                                .take(3)
                                .map(
                                  (tag) => Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xfff1f5f9),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      tag.startsWith('#') ? tag : '#$tag',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: textMuted,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const Divider(height: 1, indent: 14, endIndent: 14),

                  // Members Dropdown preview
                  if (accepted.isNotEmpty)
                    InkWell(
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Text(
                              _expanded
                                  ? 'Hide Members'
                                  : 'View ${accepted.length} Member${accepted.length > 1 ? "s" : ""}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: primaryEmerald,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              _expanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              size: 16,
                              color: primaryEmerald,
                            ),
                          ],
                        ),
                      ),
                    ),

                  if (_expanded && accepted.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                      child: Column(
                        children: accepted
                            .map(
                              (m) => Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xfff8fafc),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.grey.shade200,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 12,
                                      backgroundColor: primaryEmerald
                                          .withValues(alpha: 0.15),
                                      child: Text(
                                        m.name[0].toUpperCase(),
                                        style: const TextStyle(
                                          color: primaryEmerald,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                m.name,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 11.5,
                                                ),
                                              ),
                                              if (m.email == u.hostEmail)
                                                Container(
                                                  margin: const EdgeInsets.only(
                                                    left: 6,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 5,
                                                        vertical: 1,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: primaryEmerald,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                  child: const Text(
                                                    'HOST',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 7.5,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          Text(
                                            m.vehicle,
                                            style: const TextStyle(
                                              fontSize: 9.5,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (canContact) ...[
                                      GestureDetector(
                                        onTap: () => widget.onCall(m.mobile),
                                        child: Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: primaryEmerald.withValues(
                                              alpha: 0.1,
                                            ),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.call_rounded,
                                            size: 14,
                                            color: primaryEmerald,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      GestureDetector(
                                        onTap: () => widget.onEmail(m.email),
                                        child: Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: primaryEmerald.withValues(
                                              alpha: 0.1,
                                            ),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.email_rounded,
                                            size: 14,
                                            color: primaryEmerald,
                                          ),
                                        ),
                                      ),
                                    ] else
                                      const Icon(
                                        Icons.privacy_tip_outlined,
                                        size: 16,
                                        color: textMuted,
                                      ),
                                    if (widget.isOwner &&
                                        m.email != u.hostEmail) ...[
                                      const SizedBox(width: 6),
                                      GestureDetector(
                                        onTap: () => widget.onKickMember(m),
                                        child: Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: Colors.redAccent.withValues(
                                              alpha: 0.1,
                                            ),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.person_remove_rounded,
                                            size: 14,
                                            color: Colors.redAccent,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),

                  // ── Group Rating Row ─────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
                    child: InkWell(
                      onTap: () => _showRatingSheet(context),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber.shade200),
                        ),
                        child: Row(
                          children: [
                            // Stars display
                            Row(
                              children: List.generate(5, (i) {
                                final full = i < u.groupRating.floor();
                                final half = !full && i < u.groupRating;
                                return Icon(
                                  full
                                      ? Icons.star_rounded
                                      : half
                                      ? Icons.star_half_rounded
                                      : Icons.star_outline_rounded,
                                  size: 17,
                                  color: Colors.amber,
                                );
                              }),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              u.groupRating > 0
                                  ? '${u.groupRating.toStringAsFixed(1)} (${u.memberRatingsCount} ${u.memberRatingsCount == 1 ? "rating" : "ratings"})'
                                  : 'No ratings yet',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.amber.shade800,
                              ),
                            ),
                            const Spacer(),
                            // My rating indicator
                            if (widget.myRating != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: primaryEmerald.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: primaryEmerald.withValues(
                                      alpha: 0.3,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.star_rounded,
                                      size: 13,
                                      color: Color(0xFFF59E0B),
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      'You: ${widget.myRating}★',
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        color: primaryEmerald,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: primaryEmerald,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: primaryEmerald.withValues(
                                        alpha: 0.25,
                                      ),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Rate Group',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(width: 4),
                                    Icon(
                                      Icons.star_rounded,
                                      size: 13,
                                      color: Color(0xFFFDE047),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Action Button Area
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: _buildActionButton(context, full),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Shows interactive 5-star rating bottom sheet
  void _showRatingSheet(BuildContext context) {
    int _tempStars = widget.myRating ?? 0;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          top: false,
          child: Container(
            padding: EdgeInsets.fromLTRB(
              24,
              20,
              24,
              math.max(
                28.0,
                MediaQuery.of(ctx).viewInsets.bottom +
                    MediaQuery.of(ctx).padding.bottom +
                    16.0,
              ),
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Rate This Group 🌟',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.union.title,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                // Interactive star row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    final filled = i < _tempStars;
                    return GestureDetector(
                      onTap: () => setSheetState(() => _tempStars = i + 1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(
                          filled
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 44,
                          color: filled ? Colors.amber : Colors.grey.shade300,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 12),
                Text(
                  _tempStars == 0
                      ? 'Tap a star to rate'
                      : _tempStars == 1
                      ? '😕 Needs Improvement'
                      : _tempStars == 2
                      ? '🙂 Below Average'
                      : _tempStars == 3
                      ? '😊 Good Group!'
                      : _tempStars == 4
                      ? '😄 Great Convoy!'
                      : '🤩 Absolutely Loved It!',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _tempStars > 0 ? Colors.amber.shade800 : Colors.grey,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: _tempStars == 0
                            ? null
                            : () {
                                widget.onRateUnion(_tempStars);
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '⭐ You rated this group $_tempStars star${_tempStars > 1 ? "s" : ""}!',
                                    ),
                                    backgroundColor: Colors.amber.shade700,
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.amber.shade600,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          widget.myRating != null
                              ? 'Update Rating'
                              : 'Submit Rating',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBanner(String? url, int seed) {
    final bannerPath = (url != null && url.isNotEmpty)
        ? url
        : UnionService.getRandomScenicBanner(seed);

    if (bannerPath.startsWith('assets/')) {
      return Image.asset(
        bannerPath,
        fit: BoxFit.cover,
        cacheWidth: 800,
        errorBuilder: (_, __, ___) => _buildScenicGraphic(),
      );
    }
    return Image.network(
      bannerPath,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Image.asset(
        UnionService.getRandomScenicBanner(seed),
        fit: BoxFit.cover,
        cacheWidth: 800,
        errorBuilder: (_, __, ___) => _buildScenicGraphic(),
      ),
    );
  }

  Widget _buildScenicGraphic() {
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.terrain_rounded,
            size: 36,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.two_wheeler_rounded,
            size: 32,
            color: Colors.white.withValues(alpha: 0.4),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.alt_route_rounded,
            size: 36,
            color: Colors.white.withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, bool full) {
    // 1. If user is the Host/Owner
    if (widget.isOwner) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primaryEmerald.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: primaryEmerald.withValues(alpha: 0.3)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_rounded, size: 15, color: primaryEmerald),
            SizedBox(width: 6),
            Text(
              'Manage Convoy & Riders (Host)',
              style: TextStyle(
                color: primaryEmerald,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    // 2. If user already joined
    if (widget.myStatus == UnionMemberStatus.accepted) {
      return Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 15,
                    color: Colors.green,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Joined Convoy · View HUD',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: BorderSide(color: Colors.red.shade200),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            icon: const Icon(Icons.logout_rounded, size: 15),
            label: const Text(
              'Exit',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
            ),
            onPressed: widget.onLeave,
          ),
        ],
      );
    }

    // 3. If request is pending approval
    if (widget.myStatus == UnionMemberStatus.pending) {
      return Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade300),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.hourglass_top_rounded,
                    size: 15,
                    color: Colors.orange.shade800,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '⏳ Join Request Pending Host Approval',
                    style: TextStyle(
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: BorderSide(color: Colors.red.shade200),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onPressed: widget.onLeave,
            child: const Text(
              'Cancel',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      );
    }

    // 4. Default: Join Convoy
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: full ? Colors.grey.shade400 : primaryEmerald,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 11),
        ),
        icon: Icon(
          full ? Icons.lock_outline_rounded : Icons.person_add_alt_1_rounded,
          size: 16,
          color: Colors.white,
        ),
        label: Text(
          full
              ? 'Team Full (${widget.union.maxMembers}/${widget.union.maxMembers})'
              : 'Join Convoy',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13.5,
          ),
        ),
        onPressed: full
            ? () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: Colors.red.shade700,
                    content: Text(
                      'Convoy "${widget.union.title}" is full. Max team size limit of ${widget.union.maxMembers} riders has been reached.',
                    ),
                  ),
                );
              }
            : widget.onRequestJoin,
      ),
    );
  }
}

IconData getVehicleCategoryIcon(VehicleCategory c) => switch (c) {
  VehicleCategory.allVehicles => Icons.commute_rounded,
  VehicleCategory.bike => Icons.two_wheeler_rounded,
  VehicleCategory.car => Icons.directions_car_rounded,
  VehicleCategory.bus => Icons.directions_bus_rounded,
  VehicleCategory.truck => Icons.local_shipping_rounded,
  VehicleCategory.bicycle => Icons.pedal_bike_rounded,
  VehicleCategory.soloWalker => Icons.directions_walk_rounded,
  VehicleCategory.other => Icons.alt_route_rounded,
};

// -- Create Union Sheet --------------------------------------------------------

class _CreateUnionSheet extends StatefulWidget {
  final UnionService service;
  const _CreateUnionSheet({required this.service});
  @override
  State<_CreateUnionSheet> createState() => _CreateUnionSheetState();
}

class _CreateUnionSheetState extends State<_CreateUnionSheet> {
  final _titleCtrl = TextEditingController();
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  final _highwayCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  VehicleCategory _cat = VehicleCategory.allVehicles;
  bool _isPublicFeed = true;
  late String _selectedBanner;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _selectedBanner = UnionService.getRandomScenicBanner(
      DateTime.now().millisecondsSinceEpoch,
    );
    final now = DateTime.now().add(const Duration(days: 1));
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
      'Dec',
    ];
    _dateCtrl.text =
        '${now.day} ${months[now.month - 1]} ${now.year} • 06:00 AM';

    final savedMobile =
        widget.service.myHostMobile ?? widget.service.myRiderMobile;
    if (savedMobile != null && savedMobile.isNotEmpty) {
      _mobileCtrl.text = savedMobile;
    }
  }

  @override
  void dispose() {
    for (final c in [
      _titleCtrl,
      _fromCtrl,
      _toCtrl,
      _highwayCtrl,
      _descCtrl,
      _dateCtrl,
      _nameCtrl,
      _mobileCtrl,
    ]) {
      c.dispose();
    }
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
          colorScheme: const ColorScheme.light(primary: primaryEmerald),
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
          colorScheme: const ColorScheme.light(primary: primaryEmerald),
        ),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;

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
      'Dec',
    ];
    final ampm = time.hour < 12 ? 'AM' : 'PM';
    final hour = time.hour == 0
        ? 12
        : (time.hour > 12 ? time.hour - 12 : time.hour);
    final min = time.minute.toString().padLeft(2, '0');
    setState(() {
      _dateCtrl.text =
          '${date.day} ${months[date.month - 1]} ${date.year} • ${hour.toString().padLeft(2, '0')}:$min $ampm';
    });
  }

  Widget _cField(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    TextInputType? keyboardType,
    int maxLines = 1,
    VoidCallback? onTap,
  }) => TextField(
    controller: ctrl,
    keyboardType: keyboardType,
    maxLines: maxLines,
    readOnly: onTap != null,
    onTap: onTap,
    style: const TextStyle(fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: textMuted, fontSize: 13),
      prefixIcon: Icon(icon, color: primaryEmerald, size: 18),
      filled: true,
      fillColor: const Color(0xfff1f5f3),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
    ),
  );

  Widget _buildBannerSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            children: [
              SizedBox(
                height: 90,
                width: double.infinity,
                child: Image.asset(
                  _selectedBanner,
                  fit: BoxFit.cover,
                  cacheWidth: 600,
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
                bottom: 7,
                left: 10,
                child: Text(
                  'Selected Cover Banner',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Choose Cover Banner',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: textDark,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: UnionService.defaultScenicBanners.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final banner = UnionService.defaultScenicBanners[i];
              final isSelected = banner == _selectedBanner;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedBanner = banner);
                },
                child: Container(
                  width: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? primaryEmerald : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(
                          banner,
                          fit: BoxFit.cover,
                          cacheWidth: 200,
                        ),
                        if (isSelected)
                          Container(
                            color: primaryEmerald.withValues(alpha: 0.35),
                            child: const Center(
                              child: Icon(
                                Icons.check_circle_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
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
      ],
    );
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty ||
        _fromCtrl.text.trim().isEmpty ||
        _toCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter Convoy Title, From, and To locations.'),
        ),
      );
      return;
    }
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter your name.')));
      return;
    }

    final auth = GoogleAuthService();
    await auth.initialize();
    var googleUser = auth.currentUser;
    if (googleUser == null || googleUser.email.trim().isEmpty) {
      googleUser = await auth.signIn();
    }
    if (googleUser == null || googleUser.email.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please sign in with Google to create a convoy.'),
          ),
        );
      }
      return;
    }
    await widget.service.syncWithGoogleUser(googleUser);

    setState(() => _loading = true);

    final rawMobile = _mobileCtrl.text.trim();
    final digits = rawMobile.replaceAll(RegExp(r'\D'), '');
    final formattedMobile = digits.length == 10
        ? '+91 $digits'
        : (rawMobile.isNotEmpty ? rawMobile : '+91 99000 00000');
    final hostName = _nameCtrl.text.trim();

    await widget.service.createUnion(
      title: _titleCtrl.text.trim(),
      fromLocation: _fromCtrl.text.trim(),
      toLocation: _toCtrl.text.trim(),
      viaHighway: _highwayCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      departureDateStr: _dateCtrl.text.trim(),
      category: _cat,
      hostName: hostName,
      hostMobile: formattedMobile,
      hostEmail: googleUser.email,
      hostVehicle: _cat.shortLabel,
      maxMembers: 10,
      isPublicFeed: _isPublicFeed,
      imageUrl: _selectedBanner,
    );

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: primaryEmerald,
          content: Text('Convoy created successfully!'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = math.max(
      28.0,
      16.0 +
          MediaQuery.of(context).viewInsets.bottom +
          MediaQuery.of(context).padding.bottom,
    );

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPad),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
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
            Row(
              children: [
                const Icon(
                  Icons.add_road_rounded,
                  color: primaryEmerald,
                  size: 22,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Create a Convoy',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: textDark,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: textMuted,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _cField(
              _titleCtrl,
              'Convoy Title (e.g. Coorg Weekend Ride)',
              Icons.flag_rounded,
            ),
            const SizedBox(height: 10),
            _buildBannerSelector(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _cField(
                    _fromCtrl,
                    'From (City / Spot)',
                    Icons.trip_origin_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _cField(
                    _toCtrl,
                    'To (City / Spot)',
                    Icons.location_on_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _cField(
              _highwayCtrl,
              'Via Highway / Corridor (optional)',
              Icons.navigation_rounded,
            ),
            const SizedBox(height: 10),
            _cField(
              _dateCtrl,
              'Departure Date & Time',
              Icons.calendar_today_rounded,
              onTap: _pickDateTime,
            ),
            const SizedBox(height: 10),
            // Vehicle Category dropdown
            DropdownButtonFormField<VehicleCategory>(
              initialValue: _cat,
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xfff1f5f3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 13,
                  horizontal: 14,
                ),
                prefixIcon: Icon(
                  getVehicleCategoryIcon(_cat),
                  color: primaryEmerald,
                  size: 18,
                ),
              ),
              items: VehicleCategory.values
                  .map(
                    (c) => DropdownMenuItem(
                      value: c,
                      child: Text(
                        c.displayName,
                        style: const TextStyle(fontSize: 13.5),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _cat = v ?? _cat),
            ),
            const SizedBox(height: 10),
            _cField(
              _descCtrl,
              'Description (optional)',
              Icons.description_rounded,
              maxLines: 2,
            ),
            const SizedBox(height: 10),
            _cField(_nameCtrl, 'Your Name (Host)', Icons.person_rounded),
            const SizedBox(height: 10),
            _cField(
              _mobileCtrl,
              'Your Mobile Number',
              Icons.phone_rounded,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            // Public / Private toggle
            Row(
              children: [
                const Text(
                  'Convoy Visibility:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textDark,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() => _isPublicFeed = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _isPublicFeed
                          ? primaryEmerald
                          : Colors.grey.shade100,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Public 🌐',
                      style: TextStyle(
                        fontSize: 12,
                        color: _isPublicFeed ? Colors.white : textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _isPublicFeed = false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: !_isPublicFeed
                          ? primaryEmerald
                          : Colors.grey.shade100,
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Private 🔒',
                      style: TextStyle(
                        fontSize: 12,
                        color: !_isPublicFeed ? Colors.white : textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: primaryEmerald,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.add_road_rounded, size: 18),
                label: Text(
                  _loading ? 'Creating Convoy...' : 'Create Convoy',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                onPressed: _loading ? null : _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -- Edit Union Sheet ----------------------------------------------------------

class _EditUnionSheet extends StatefulWidget {
  final UnionService service;
  final TravelUnionGroup union;
  const _EditUnionSheet({required this.service, required this.union});
  @override
  State<_EditUnionSheet> createState() => _EditUnionSheetState();
}

class _EditUnionSheetState extends State<_EditUnionSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _fromCtrl;
  late final TextEditingController _toCtrl;
  late final TextEditingController _highwayCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _dateCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _mobileCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _vehicleCtrl;
  late final TextEditingController _teamSizeCtrl;
  late VehicleCategory _cat;
  late int _maxMembers;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final u = widget.union;
    _titleCtrl = TextEditingController(text: u.title);
    _fromCtrl = TextEditingController(text: u.fromLocation);
    _toCtrl = TextEditingController(text: u.toLocation);
    _highwayCtrl = TextEditingController(text: u.viaHighway);
    _descCtrl = TextEditingController(text: u.description);
    _dateCtrl = TextEditingController(text: u.departureDateStr);
    _nameCtrl = TextEditingController(text: u.hostName);
    _mobileCtrl = TextEditingController(text: u.hostMobile);
    _emailCtrl = TextEditingController(text: u.hostEmail);
    _vehicleCtrl = TextEditingController(
      text: u.members.isNotEmpty ? u.members.first.vehicle : 'Bike',
    );
    _cat = u.category;
    _maxMembers = u.maxMembers;
    _teamSizeCtrl = TextEditingController(text: '$_maxMembers');
  }

  @override
  void dispose() {
    for (final c in [
      _titleCtrl,
      _fromCtrl,
      _toCtrl,
      _highwayCtrl,
      _descCtrl,
      _dateCtrl,
      _nameCtrl,
      _mobileCtrl,
      _emailCtrl,
      _vehicleCtrl,
      _teamSizeCtrl,
    ])
      c.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final minAllowed = widget.union.acceptedMembers.length;
    final parsed = int.tryParse(_teamSizeCtrl.text.trim());
    if (parsed != null && parsed >= minAllowed) {
      _maxMembers = parsed.clamp(minAllowed > 2 ? minAllowed : 2, 1000);
    }
    setState(() => _loading = true);

    final rawMobile = _mobileCtrl.text.trim();
    final digits = rawMobile.replaceAll(RegExp(r'\D'), '');
    final formattedMobile = digits.length == 10 ? '+91 $digits' : rawMobile;

    await widget.service.updateUnion(
      unionId: widget.union.id,
      title: _titleCtrl.text.trim(),
      fromLocation: _fromCtrl.text.trim(),
      toLocation: _toCtrl.text.trim(),
      viaHighway: _highwayCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      departureDateStr: _dateCtrl.text.trim(),
      category: _cat,
      hostName: _nameCtrl.text.trim(),
      hostMobile: formattedMobile,
      hostEmail: _emailCtrl.text.trim(),
      hostVehicle: _vehicleCtrl.text.trim(),
      maxMembers: _maxMembers,
    );
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Convoy updated successfully!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bi = MediaQuery.of(context).viewInsets.bottom;
    final nb = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bi + nb),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Edit Travel Convoy',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 4),
              const Text(
                'Update details for your convoy riders.',
                style: TextStyle(fontSize: 12, color: Color(0xff64748b)),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Group Title',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _fromCtrl,
                      decoration: const InputDecoration(
                        labelText: 'From',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _toCtrl,
                      decoration: const InputDecoration(
                        labelText: 'To',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _highwayCtrl,
                decoration: const InputDecoration(
                  labelText: 'Via Highway / Corridor (Optional)',
                  prefixIcon: Icon(
                    Icons.navigation_rounded,
                    size: 18,
                    color: Color(0xFF23695A),
                  ),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _descCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Ride Description (Optional)',
                  prefixIcon: Icon(
                    Icons.description_rounded,
                    size: 18,
                    color: Color(0xFF23695A),
                  ),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _dateCtrl,
                decoration: const InputDecoration(
                  labelText: 'Departure Date & Time',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Your Name (Host)',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _mobileCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Mobile Number',
                        hintText: 'e.g. 9876543210',
                        prefixIcon: Icon(
                          Icons.phone_android_rounded,
                          size: 18,
                          color: Color(0xFF23695A),
                        ),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty)
                          return 'Mobile required';
                        final digits = v.replaceAll(RegExp(r'\D'), '');
                        if (digits.length < 10) return 'Min 10 digits required';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Gmail / Email',
                        prefixIcon: Icon(
                          Icons.email_outlined,
                          size: 18,
                          color: Color(0xFF23695A),
                        ),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Vehicle Category Selector
              const Text(
                'Vehicle / Convoy Type',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xff1e293b),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: VehicleCategory.values.map((cat) {
                  final isSelected = _cat == cat;
                  return ChoiceChip(
                    avatar: Icon(
                      getVehicleCategoryIcon(cat),
                      size: 16,
                      color: isSelected
                          ? Colors.white
                          : const Color(0xff23695a),
                    ),
                    label: Text(
                      cat.displayName,
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : const Color(0xff1e293b),
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: const Color(0xff23695a),
                    backgroundColor: const Color(0xfff1f5f9),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: isSelected
                            ? const Color(0xff23695a)
                            : Colors.grey.shade300,
                      ),
                    ),
                    showCheckmark: false,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _cat = cat);
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _vehicleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Host Vehicle / Model',
                  hintText: 'e.g. Royal Enfield Hunter 350, Thar',
                  prefixIcon: Icon(
                    Icons.commute_rounded,
                    size: 18,
                    color: Color(0xFF23695A),
                  ),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),

              // Team Size Selector
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xfff8fafc),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xff23695a)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.groups_rounded,
                            size: 20,
                            color: Color(0xff23695a),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Team Size Limit (Max Riders)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Color(0xff1e293b),
                                ),
                              ),
                              Text(
                                '$_maxMembers riders total (currently ${widget.union.acceptedMembers.length} joined)',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xff64748b),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xff23695a)
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove, size: 16),
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                                padding: EdgeInsets.zero,
                                tooltip: 'Decrease team size',
                                onPressed:
                                    _maxMembers >
                                            widget
                                                .union
                                                .acceptedMembers
                                                .length &&
                                        _maxMembers > 2
                                    ? () {
                                        setState(() {
                                          _maxMembers--;
                                          _teamSizeCtrl.text = '$_maxMembers';
                                        });
                                      }
                                    : null,
                              ),
                              SizedBox(
                                width: 46,
                                child: TextField(
                                  controller: _teamSizeCtrl,
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(4),
                                  ],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: Color(0xff23695a),
                                  ),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: 4,
                                      horizontal: 2,
                                    ),
                                    border: InputBorder.none,
                                  ),
                                  onChanged: (val) {
                                    final minAllowed =
                                        widget.union.acceptedMembers.length;
                                    final n = int.tryParse(val);
                                    if (n != null &&
                                        n >= minAllowed &&
                                        n >= 2) {
                                      setState(
                                        () => _maxMembers = n.clamp(2, 1000),
                                      );
                                    }
                                  },
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add, size: 16),
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                                padding: EdgeInsets.zero,
                                tooltip: 'Increase team size',
                                onPressed: _maxMembers < 1000
                                    ? () {
                                        setState(() {
                                          _maxMembers++;
                                          _teamSizeCtrl.text = '$_maxMembers';
                                        });
                                      }
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [2, 5, 10, 20, 50, 100].map((sz) {
                        final sel = _maxMembers == sz;
                        final minAllowed = widget.union.acceptedMembers.length;
                        final disabled = sz < minAllowed;
                        return InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: disabled
                              ? null
                              : () {
                                  setState(() {
                                    _maxMembers = sz;
                                    _teamSizeCtrl.text = '$sz';
                                  });
                                },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: sel
                                  ? const Color(0xff23695a)
                                  : (disabled
                                        ? Colors.grey.shade100
                                        : Colors.white),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: sel
                                    ? const Color(0xff23695a)
                                    : (disabled
                                          ? Colors.grey.shade200
                                          : Colors.grey.shade300),
                              ),
                            ),
                            child: Text(
                              '$sz riders',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: sel
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: sel
                                    ? Colors.white
                                    : (disabled
                                          ? Colors.grey.shade400
                                          : const Color(0xff1e293b)),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Type any number using keypad or use +/- & quick buttons. Full convoys reject new joins.',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontStyle: FontStyle.italic,
                        color: Color(0xff64748b),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xff23695a),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Save Changes',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -- Request Join Sheet --------------------------------------------------------

class _RequestJoinSheet extends StatefulWidget {
  final UnionService service;
  final TravelUnionGroup union;
  const _RequestJoinSheet({required this.service, required this.union});
  @override
  State<_RequestJoinSheet> createState() => _RequestJoinSheetState();
}

class _RequestJoinSheetState extends State<_RequestJoinSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _mobCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _vehCtrl = TextEditingController();
  VehicleCategory _cat = VehicleCategory.bike;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final savedMobile =
        widget.service.myRiderMobile ?? widget.service.myHostMobile;
    if (savedMobile != null && savedMobile.isNotEmpty) {
      _mobCtrl.text = savedMobile;
    }
    final savedEmail =
        widget.service.myRiderEmail ?? widget.service.myHostEmail;
    if (savedEmail != null && savedEmail.isNotEmpty) {
      _emailCtrl.text = savedEmail;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _mobCtrl.dispose();
    _emailCtrl.dispose();
    _vehCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (widget.union.isFull) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text(
            'Cannot join: Convoy "${widget.union.title}" is already full (${widget.union.maxMembers}/${widget.union.maxMembers} riders)!',
          ),
        ),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final auth = GoogleAuthService();
    await auth.initialize();
    var googleUser = auth.currentUser;
    if (googleUser == null || googleUser.email.trim().isEmpty) {
      googleUser = await auth.signIn();
    }
    if (googleUser == null || googleUser.email.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please sign in with Google to join this convoy.'),
          ),
        );
      }
      return;
    }
    await widget.service.syncWithGoogleUser(googleUser);
    _emailCtrl.text = googleUser.email;

    setState(() => _loading = true);

    final rawMobile = _mobCtrl.text.trim();
    final digits = rawMobile.replaceAll(RegExp(r'\D'), '');
    final formattedMobile = digits.length == 10 ? '+91 $digits' : rawMobile;

    final ok = await widget.service.requestToJoin(
      joinCodeOrId: widget.union.id,
      riderName: _nameCtrl.text.trim(),
      riderMobile: formattedMobile,
      riderEmail: googleUser.email,
      riderVehicle: _vehCtrl.text.trim(),
      category: _cat,
    );
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: ok ? primaryEmerald : Colors.red.shade700,
          content: Text(
            ok ? 'Request sent! Host will review and approve.' : 'Could not send request: Convoy is full or request already submitted.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bi = MediaQuery.of(context).viewInsets.bottom;
    final nb = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bi + nb),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Join "${widget.union.title}"',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${widget.union.fromLocation} ➔ ${widget.union.toLocation}',
                style: const TextStyle(fontSize: 12, color: Color(0xff64748b)),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.groups_rounded,
                    size: 14,
                    color: widget.union.isFull ? Colors.red : primaryEmerald,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Team Size: ${widget.union.acceptedMembers.length}/${widget.union.maxMembers} riders',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: widget.union.isFull ? Colors.red : primaryEmerald,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                widget.union.isFull
                    ? 'This convoy is currently full. No new join requests can be accepted.'
                    : 'Host will review and approve your request.',
                style: TextStyle(
                  fontSize: 12,
                  color: widget.union.isFull
                      ? Colors.red.shade700
                      : const Color(0xff64748b),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameCtrl,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Your Full Name',
                  hintStyle: const TextStyle(color: textMuted, fontSize: 13),
                  prefixIcon: const Icon(
                    Icons.person_rounded,
                    size: 18,
                    color: primaryEmerald,
                  ),
                  filled: true,
                  fillColor: const Color(0xfff1f5f3),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 13,
                    horizontal: 14,
                  ),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _mobCtrl,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Mobile Number',
                        hintStyle: const TextStyle(color: textMuted, fontSize: 13),
                        prefixIcon: const Icon(
                          Icons.phone_android_rounded,
                          size: 18,
                          color: primaryEmerald,
                        ),
                        filled: true,
                        fillColor: const Color(0xfff1f5f3),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 13,
                          horizontal: 14,
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty)
                          return 'Mobile required';
                        final digits = v.replaceAll(RegExp(r'\D'), '');
                        if (digits.length < 10) return 'Min 10 digits required';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Gmail / Email',
                        hintStyle: const TextStyle(color: textMuted, fontSize: 13),
                        prefixIcon: const Icon(
                          Icons.email_outlined,
                          size: 18,
                          color: primaryEmerald,
                        ),
                        filled: true,
                        fillColor: const Color(0xfff1f5f3),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 13,
                          horizontal: 14,
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Your Vehicle Type',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xff1e293b),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: VehicleCategory.values
                    .where((c) => c != VehicleCategory.allVehicles)
                    .map((cat) {
                      final isSelected = _cat == cat;
                      return ChoiceChip(
                        avatar: Icon(
                          getVehicleCategoryIcon(cat),
                          size: 16,
                          color: isSelected
                              ? Colors.white
                              : const Color(0xff23695a),
                        ),
                        label: Text(
                          cat.displayName,
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : const Color(0xff1e293b),
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: const Color(0xff23695a),
                        backgroundColor: const Color(0xfff1f5f9),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: isSelected
                                ? const Color(0xff23695a)
                                : Colors.grey.shade300,
                          ),
                        ),
                        showCheckmark: false,
                        onSelected: (selected) {
                          if (selected) setState(() => _cat = cat);
                        },
                      );
                    })
                    .toList(),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _vehCtrl,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Your Vehicle / Model (e.g. KTM 390 / Thar)',
                  hintStyle: const TextStyle(color: textMuted, fontSize: 13),
                  prefixIcon: const Icon(
                    Icons.two_wheeler_rounded,
                    size: 18,
                    color: primaryEmerald,
                  ),
                  filled: true,
                  fillColor: const Color(0xfff1f5f3),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 13,
                    horizontal: 14,
                  ),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xff23695a),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Send Join Request',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestsCenterSheet extends StatefulWidget {
  final UnionService service;

  const _RequestsCenterSheet({required this.service});

  @override
  State<_RequestsCenterSheet> createState() => _RequestsCenterSheetState();
}

class _RequestsCenterSheetState extends State<_RequestsCenterSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  int _tabIndex = 0; // 0: All, 1: Convoys, 2: Groups
  String _query = '';
  bool _isProcessingBulk = false;

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_onServiceUpdate);
    _searchCtrl.addListener(() {
      setState(() {
        _query = _searchCtrl.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    widget.service.removeListener(_onServiceUpdate);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _approveAll(
    List<MapEntry<TravelUnionGroup, UnionMember>> convoys,
    List<MapEntry<TravelGroup, GroupMember>> groups,
  ) async {
    setState(() => _isProcessingBulk = true);
    int approvedCount = 0;
    int skippedFullCount = 0;

    for (final c in convoys) {
      if (c.key.isFull) {
        skippedFullCount++;
        continue;
      }
      final ok = await widget.service.respondToJoinRequest(
        unionId: c.key.id,
        memberId: c.value.id,
        accept: true,
      );
      if (ok) approvedCount++;
    }

    for (final g in groups) {
      await widget.service.approveGroupMember(g.key.id, g.value.id);
      approvedCount++;
    }

    if (mounted) {
      setState(() => _isProcessingBulk = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: primaryEmerald,
          content: Text(
            skippedFullCount > 0
                ? 'Approved $approvedCount members! ($skippedFullCount skipped because convoy was full)'
                : 'Approved all $approvedCount pending members!',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final allPendingConvoys = <MapEntry<TravelUnionGroup, UnionMember>>[];
    for (final u in widget.service.unions) {
      if (widget.service.isOwner(u)) {
        for (final p in u.pendingRequests) {
          allPendingConvoys.add(MapEntry(u, p));
        }
      }
    }

    final allPendingGroups = <MapEntry<TravelGroup, GroupMember>>[];
    for (final g in widget.service.groups) {
      if (widget.service.isGroupAdmin(g)) {
        for (final m in g.members.where((m) => m.isPending)) {
          allPendingGroups.add(MapEntry(g, m));
        }
      }
    }

    List<dynamic> items = [];
    if (_tabIndex == 0) {
      items = [...allPendingConvoys, ...allPendingGroups];
    } else if (_tabIndex == 1) {
      items = allPendingConvoys;
    } else {
      items = allPendingGroups;
    }

    if (_query.isNotEmpty) {
      items = items.where((item) {
        if (item is MapEntry<TravelUnionGroup, UnionMember>) {
          return item.value.name.toLowerCase().contains(_query) ||
              item.value.mobile.toLowerCase().contains(_query) ||
              item.value.vehicle.toLowerCase().contains(_query) ||
              item.key.title.toLowerCase().contains(_query);
        } else if (item is MapEntry<TravelGroup, GroupMember>) {
          return item.value.name.toLowerCase().contains(_query) ||
              item.value.mobile.toLowerCase().contains(_query) ||
              item.key.name.toLowerCase().contains(_query);
        }
        return true;
      }).toList();
    }

    final totalCount = allPendingConvoys.length + allPendingGroups.length;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: scaffoldBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 16, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.notifications_active_rounded,
                    color: Colors.orange.shade900,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Requests Center',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: textDark,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: totalCount > 0
                                  ? Colors.orange.shade800
                                  : Colors.grey.shade400,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$totalCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        totalCount > 0
                            ? 'Manage join requests sent to your convoys and groups'
                            : 'All caught up! No pending join requests',
                        style: const TextStyle(fontSize: 12, color: textMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: textMuted),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          if (totalCount > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryEmerald,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _isProcessingBulk
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.done_all_rounded, size: 18),
                  label: Text(
                    _isProcessingBulk
                        ? 'Approving all...'
                        : 'Approve All Valid Requests ($totalCount)',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  onPressed: _isProcessingBulk
                      ? null
                      : () => _approveAll(allPendingConvoys, allPendingGroups),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search applicant name, vehicle, or phone...',
                hintStyle: const TextStyle(fontSize: 13, color: textMuted),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: textMuted,
                  size: 20,
                ),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => _searchCtrl.clear(),
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xfff1f5f3),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Row(
              children: [
                _buildFilterChip('All', totalCount, 0),
                const SizedBox(width: 8),
                _buildFilterChip('Convoys', allPendingConvoys.length, 1),
                const SizedBox(width: 8),
                _buildFilterChip('Groups', allPendingGroups.length, 2),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            totalCount == 0
                                ? Icons.verified_user_rounded
                                : Icons.search_off_rounded,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            totalCount == 0
                                ? 'No Pending Requests'
                                : 'No requests match "$_query"',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: textDark,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            totalCount == 0
                                ? 'Whenever someone asks to join your convoys or groups, they will appear here.'
                                : 'Try searching with another keyword or vehicle name.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                    itemCount: items.length,
                    itemBuilder: (ctx, idx) {
                      final item = items[idx];
                      if (item is MapEntry<TravelUnionGroup, UnionMember>) {
                        return _buildConvoyRequestCard(item);
                      } else if (item is MapEntry<TravelGroup, GroupMember>) {
                        return _buildGroupRequestCard(item);
                      }
                      return const SizedBox.shrink();
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, int count, int index) {
    final isSelected = _tabIndex == index;
    return ChoiceChip(
      selected: isSelected,
      label: Text('$label ($count)'),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
        color: isSelected ? Colors.white : textDark,
      ),
      selectedColor: primaryEmerald,
      backgroundColor: Colors.white,
      side: BorderSide(
        color: isSelected ? primaryEmerald : Colors.grey.shade300,
      ),
      onSelected: (_) => setState(() => _tabIndex = index),
    );
  }

  Widget _buildConvoyRequestCard(
    MapEntry<TravelUnionGroup, UnionMember> entry,
  ) {
    final union = entry.key;
    final member = entry.value;
    final isFull = union.isFull;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: isFull ? const Color(0xfffef2f2) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isFull ? Colors.red.shade300 : Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: isFull
                      ? Colors.red.shade100
                      : const Color(0xffe6f4ea),
                  child: Text(
                    member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: isFull ? Colors.red.shade900 : primaryEmerald,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              member.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: textDark,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xff1b5e4a),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'CONVOY 🚀',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (isFull) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.shade600,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'TEAM FULL',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Convoy: "${union.title}"',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: textDark,
                        ),
                      ),
                      Text(
                        'Route: ${union.fromLocation} ➔ ${union.toLocation}',
                        style: const TextStyle(fontSize: 11, color: textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xfff8fafc),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.two_wheeler_rounded,
                    size: 14,
                    color: textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    member.vehicle.isNotEmpty ? member.vehicle : 'Rider',
                    style: const TextStyle(fontSize: 11, color: textDark),
                  ),
                  if (member.mobile.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    const Icon(Icons.phone_rounded, size: 13, color: textMuted),
                    const SizedBox(width: 4),
                    Text(
                      member.mobile,
                      style: const TextStyle(fontSize: 11, color: textDark),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    'Team: ${union.acceptedMembers.length}/${union.maxMembers}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isFull ? Colors.red.shade700 : primaryEmerald,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text(
                      'Decline',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: () async {
                      await widget.service.respondToJoinRequest(
                        unionId: union.id,
                        memberId: member.id,
                        accept: false,
                      );
                      if (mounted) {
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Declined ${member.name}\'s request.',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: isFull
                          ? Colors.grey.shade400
                          : primaryEmerald,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: Text(
                      isFull ? 'Team Full' : 'Accept Rider',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: isFull
                        ? () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: Colors.red.shade700,
                                content: Text(
                                  'Cannot accept: "${union.title}" has reached max team size (${union.maxMembers}/${union.maxMembers})! Please edit convoy to increase team size first.',
                                ),
                              ),
                            );
                          }
                        : () async {
                            final ok = await widget.service.respondToJoinRequest(
                              unionId: union.id,
                              memberId: member.id,
                              accept: true,
                            );
                            if (mounted) {
                              setState(() {});
                              if (ok) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: primaryEmerald,
                                    content: Text(
                                      'Accepted ${member.name} into "${union.title}"!',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupRequestCard(
    MapEntry<TravelGroup, GroupMember> entry,
  ) {
    final group = entry.key;
    final member = entry.value;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: const Color(0xffe6f4ea),
                  child: Text(
                    member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: primaryEmerald,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              member.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: textDark,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: primaryEmerald,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'GROUP 👥',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Group: "${group.name}" · ${group.category}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: textDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (member.mobile.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xfff8fafc),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.phone_rounded, size: 13, color: textMuted),
                    const SizedBox(width: 4),
                    Text(
                      'Mobile: ${member.mobile}',
                      style: const TextStyle(fontSize: 11, color: textDark),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text(
                      'Decline',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: () async {
                      await widget.service.rejectGroupMember(
                        group.id,
                        member.id,
                      );
                      if (mounted) {
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Declined request from ${member.name}.',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryEmerald,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text(
                      'Approve Member',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () async {
                      await widget.service.approveGroupMember(
                        group.id,
                        member.id,
                      );
                      if (mounted) {
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: primaryEmerald,
                            content: Text(
                              'Approved ${member.name} into "${group.name}"!',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

