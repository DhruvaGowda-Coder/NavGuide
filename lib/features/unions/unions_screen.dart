import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../device/unions/union_service.dart';
import '../../domain/union_models.dart';

class UnionsScreen extends StatefulWidget {
  const UnionsScreen({super.key});
  @override
  State<UnionsScreen> createState() => _UnionsScreenState();
}

class _UnionsScreenState extends State<UnionsScreen> {
  static const Color primaryEmerald = Color(0xff23695a);
  static const Color textDark = Color(0xff1e293b);
  static const Color textMuted = Color(0xff64748b);
  static const Color scaffoldBg = Color(0xfff7f9f6);
  static const int _pageSize = 8;

  final UnionService _service = UnionService();
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  int _visibleCount = _pageSize;

  @override
  void initState() {
    super.initState();
    _service.initialize();
    _service.addListener(_onServiceUpdate);
    _searchCtrl.addListener(() {
      setState(() {
        _searchQuery = _searchCtrl.text.trim().toLowerCase();
        _visibleCount = _pageSize;
      });
    });
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceUpdate);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onServiceUpdate() { if (mounted) setState(() {}); }

  Future<void> _makeCall(String p) async {
    try { await launchUrl(Uri.parse('tel:$p'), mode: LaunchMode.externalApplication); } catch (_) {}
  }
  Future<void> _sendEmail(String e) async {
    try { await launchUrl(Uri.parse('mailto:$e'), mode: LaunchMode.externalApplication); } catch (_) {}
  }

  void _openCreate() => showModalBottomSheet(
    context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
    builder: (_) => _CreateUnionSheet(service: _service),
  );

  void _openEdit(TravelUnionGroup union) => showModalBottomSheet(
    context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
    builder: (_) => _EditUnionSheet(service: _service, union: union),
  );

  void _openRequestJoin(TravelUnionGroup union) => showModalBottomSheet(
    context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
    builder: (_) => _RequestJoinSheet(service: _service, union: union),
  );

  Future<void> _confirmDelete(TravelUnionGroup union) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 26),
          SizedBox(width: 8),
          Text('Delete Convoy?'),
        ]),
        content: Text('Are you sure you want to delete "${union.title}"?\nThis will remove the convoy for everyone.'),
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

  Future<void> _confirmLeave(TravelUnionGroup union) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(children: [
          Icon(Icons.logout_rounded, color: Colors.redAccent, size: 24),
          SizedBox(width: 8),
          Text('Exit Convoy?'),
        ]),
        content: Text('Are you sure you want to leave "${union.title}"?\nYou will no longer be a rider in this group.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Stay', style: TextStyle(color: textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Leave Convoy'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _service.leaveUnion(union.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('You left "${union.title}".')),
        );
      }
    }
  }

  Future<void> _confirmKickMember(TravelUnionGroup union, UnionMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(children: [
          Icon(Icons.person_remove_rounded, color: Colors.redAccent, size: 24),
          SizedBox(width: 8),
          Text('Kick Rider?'),
        ]),
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
          SnackBar(content: Text('"${member.name}" was removed from the convoy.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final allUnions = _service.unions;
    final filtered = _searchQuery.isEmpty ? allUnions : allUnions.where((u) =>
      u.title.toLowerCase().contains(_searchQuery) ||
      u.fromLocation.toLowerCase().contains(_searchQuery) ||
      u.toLocation.toLowerCase().contains(_searchQuery) ||
      u.hostName.toLowerCase().contains(_searchQuery)).toList();
    final visible = filtered.take(_visibleCount).toList();
    final hasMore = filtered.length > _visibleCount;

    // Only show pending approvals to the OWNER of the union!
    final allPending = <MapEntry<TravelUnionGroup, UnionMember>>[];
    for (final u in allUnions) {
      if (_service.isOwner(u)) {
        for (final p in u.pendingRequests) {
          allPending.add(MapEntry(u, p));
        }
      }
    }

    return Scaffold(
      backgroundColor: scaffoldBg,
      body: SafeArea(
        child: RefreshIndicator(
          color: primaryEmerald,
          onRefresh: () async {
            await _service.syncWithFirebase();
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
        // Header
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(18,16,18,0),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xff1b4332), Color(0xff23695a)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: primaryEmerald.withValues(alpha:0.25), blurRadius:12, offset:const Offset(0,4))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha:0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.groups_rounded, color: Colors.greenAccent, size: 28)),
                const SizedBox(width:12),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Travel Unions & Convoys', style: TextStyle(color: Colors.white, fontSize:19, fontWeight: FontWeight.bold)),
                  SizedBox(height:2),
                  Text('Browse or join any convoy — host approves riders', style: TextStyle(color: Colors.white70, fontSize:12)),
                ])),
              ]),
              const SizedBox(height:18),
              SizedBox(width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: primaryEmerald,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical:13)),
                  icon: const Icon(Icons.add_circle_outline_rounded, size:18),
                  label: const Text('Create a Union / Convoy', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: _openCreate,
                )),
            ]),
          ),
        )),

        // Search bar
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(18,14,18,6),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search by destination, route or host...',
              hintStyle: const TextStyle(fontSize:13, color: textMuted),
              prefixIcon: const Icon(Icons.search_rounded, color: textMuted, size:20),
              suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(icon: const Icon(Icons.close_rounded, size:18), onPressed: () => _searchCtrl.clear())
                : null,
              filled: true, fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical:12, horizontal:16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade200)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade200)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: primaryEmerald, width:1.5)),
            ),
          ),
        )),

        // Pending approvals (host side only)
        if (allPending.isNotEmpty)
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(18,10,18,4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.mark_email_unread_rounded, color: Colors.orange, size:18),
                const SizedBox(width:6),
                Text('Pending Join Approvals (${allPending.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize:14, color: textDark)),
              ]),
              const SizedBox(height:8),
              for (final entry in allPending)
                Card(
                  margin: const EdgeInsets.only(bottom:8),
                  color: const Color(0xfffffbeb),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.orange.shade200)),
                  child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
                    CircleAvatar(backgroundColor: Colors.orange.shade100,
                      child: Text(entry.value.name[0].toUpperCase(),
                        style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.bold))),
                    const SizedBox(width:12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(entry.value.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize:14)),
                      Text('Wants to join "${entry.key.title}" · ${entry.value.vehicle}',
                        style: const TextStyle(fontSize:11, color: textMuted)),
                    ])),
                    const SizedBox(width:4),
                    IconButton(icon: const Icon(Icons.check_circle_rounded, color: Colors.green, size:28), tooltip: 'Accept',
                      onPressed: () => _service.respondToJoinRequest(unionId: entry.key.id, memberId: entry.value.id, accept: true)),
                    IconButton(icon: const Icon(Icons.cancel_rounded, color: Colors.redAccent, size:28), tooltip: 'Decline',
                      onPressed: () => _service.respondToJoinRequest(unionId: entry.key.id, memberId: entry.value.id, accept: false)),
                  ])),
                ),
            ]),
          )),

        // Section header
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(18,10,18,8),
          child: Row(children: [
            Text(filtered.isEmpty ? 'No Unions Found' : 'Active Unions & Convoys (${filtered.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize:14, color: textDark)),
            const Spacer(),
            GestureDetector(onTap: () => _service.syncWithFirebase(),
              child: const Row(children: [
                Icon(Icons.sync_rounded, size:14, color: primaryEmerald),
                SizedBox(width:4),
                Text('Sync', style: TextStyle(fontSize:12, color: primaryEmerald, fontWeight: FontWeight.w600)),
              ])),
          ]),
        )),

        // Empty state
        if (filtered.isEmpty)
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(18,32,18,32),
            child: Column(children: [
              Icon(Icons.group_off_rounded, size:64, color: Colors.grey.shade300),
              const SizedBox(height:16),
              Text(_searchQuery.isNotEmpty ? 'No unions match "$_searchQuery"' : 'No active unions yet.\nBe the first to create one!',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade500, height:1.5)),
            ]),
          )),

        // Union cards
        SliverList(delegate: SliverChildBuilderDelegate(
          (ctx, i) {
            final u = visible[i];
            final isOwner = _service.isOwner(u);
            final myStatus = _service.myMembershipStatus(u);
            return _UnionCard(
              union: u,
              isOwner: isOwner,
              myStatus: myStatus,
              onCall: _makeCall,
              onEmail: _sendEmail,
              onRequestJoin: () => _openRequestJoin(u),
              onEdit: () => _openEdit(u),
              onDelete: () => _confirmDelete(u),
              onLeave: () => _confirmLeave(u),
              onKickMember: (m) => _confirmKickMember(u, m),
            );
          },
          childCount: visible.length,
        )),

        // Load more
        if (hasMore)
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(18,4,18,12),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: primaryEmerald,
                side: const BorderSide(color: primaryEmerald),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical:12)),
              onPressed: () => setState(() => _visibleCount += _pageSize),
              child: Text('Load More (${filtered.length - _visibleCount} remaining)',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          )),

        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    ),
  ),
),
);
}
}

// -- Union Card ----------------------------------------------------------------

class _UnionCard extends StatefulWidget {
  final TravelUnionGroup union;
  final bool isOwner;
  final UnionMemberStatus? myStatus;
  final void Function(String) onCall;
  final void Function(String) onEmail;
  final VoidCallback onRequestJoin;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onLeave;
  final void Function(UnionMember) onKickMember;

  const _UnionCard({
    required this.union,
    required this.isOwner,
    required this.myStatus,
    required this.onCall,
    required this.onEmail,
    required this.onRequestJoin,
    required this.onEdit,
    required this.onDelete,
    required this.onLeave,
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

  IconData _catIcon(VehicleCategory c) => switch(c) {
    VehicleCategory.bike       => Icons.two_wheeler_rounded,
    VehicleCategory.car        => Icons.directions_car_rounded,
    VehicleCategory.bicycle    => Icons.pedal_bike_rounded,
    VehicleCategory.soloWalker => Icons.directions_walk_rounded,
    VehicleCategory.other      => Icons.commute_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final u = widget.union;
    final accepted = u.members.where((m) => m.status == UnionMemberStatus.accepted).toList();
    final full = accepted.length >= u.maxMembers;

    return Padding(padding: const EdgeInsets.fromLTRB(18,0,18,12),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18),
          border: widget.isOwner ? Border.all(color: primaryEmerald.withValues(alpha: 0.35), width: 1.5) : null,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.06), blurRadius:8, offset:const Offset(0,2))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Info header
          Padding(padding: const EdgeInsets.fromLTRB(16,14,8,12), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: primaryEmerald.withValues(alpha:0.1), shape: BoxShape.circle),
                child: Icon(_catIcon(u.category), size:16, color: primaryEmerald)),
              const SizedBox(width:10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(child: Text(u.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize:15, color: textDark))),
                    if (widget.isOwner) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: primaryEmerald,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('YOUR CONVOY', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ]),
                ],
              )),
              Container(padding: const EdgeInsets.symmetric(horizontal:8, vertical:4),
                decoration: BoxDecoration(color: (full ? Colors.red : primaryEmerald).withValues(alpha:0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(full ? 'Full' : '${accepted.length}/${u.maxMembers} Riders',
                  style: TextStyle(fontSize:11, fontWeight: FontWeight.bold, color: full ? Colors.red : primaryEmerald))),
              
              // Only OWNER sees the Edit & Delete menu!
              if (widget.isOwner)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, color: textMuted, size: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onSelected: (val) {
                    if (val == 'edit') widget.onEdit();
                    if (val == 'delete') widget.onDelete();
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(children: [
                        Icon(Icons.edit_rounded, size: 18, color: primaryEmerald),
                        SizedBox(width: 8),
                        Text('Edit Convoy', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete_forever_rounded, size: 18, color: Colors.redAccent),
                        SizedBox(width: 8),
                        Text('Delete Convoy', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.redAccent)),
                      ]),
                    ),
                  ],
                )
              else
                const SizedBox(width: 8),
            ]),
            const SizedBox(height:6),
            Row(children: [
              const Icon(Icons.route_rounded, size:14, color: textMuted), const SizedBox(width:6),
              Flexible(child: Text('${u.fromLocation}  ➔  ${u.toLocation}',
                style: const TextStyle(fontSize:12, fontWeight: FontWeight.w600, color: textDark))),
            ]),
            const SizedBox(height:4),
            Row(children: [
              const Icon(Icons.schedule_rounded, size:14, color: textMuted), const SizedBox(width:6),
              Text(u.departureDateStr, style: const TextStyle(fontSize:12, color: textMuted)),
            ]),
            const SizedBox(height:10),
            Row(children: [
              const Icon(Icons.person_rounded, size:14, color: textMuted), const SizedBox(width:6),
              Text('Host: ${u.hostName}', style: const TextStyle(fontSize:12, fontWeight: FontWeight.w600, color: textDark)),
              const Spacer(),
              GestureDetector(onTap: () => widget.onCall(u.hostMobile),
                child: Container(padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: primaryEmerald.withValues(alpha:0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.call_rounded, size:14, color: primaryEmerald))),
              const SizedBox(width:6),
              GestureDetector(onTap: () => widget.onEmail(u.hostEmail),
                child: Container(padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: primaryEmerald.withValues(alpha:0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.email_rounded, size:14, color: primaryEmerald))),
              const SizedBox(width:8),
            ]),
          ])),
          const Divider(height:1, indent:16, endIndent:16),

          // Expand members
          if (accepted.isNotEmpty)
            InkWell(onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(padding: const EdgeInsets.symmetric(horizontal:16, vertical:10),
                child: Row(children: [
                  Text(_expanded ? 'Hide Members' : 'View ${accepted.length} Member${accepted.length>1?"s":""}',
                    style: const TextStyle(fontSize:12, fontWeight: FontWeight.w600, color: primaryEmerald)),
                  const SizedBox(width:4),
                  Icon(_expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    size:16, color: primaryEmerald),
                ]))),
          if (_expanded && accepted.isNotEmpty)
            Padding(padding: const EdgeInsets.fromLTRB(16,0,16,12),
              child: Column(children: accepted.map((m) => Container(
                margin: const EdgeInsets.only(bottom:8),
                padding: const EdgeInsets.symmetric(horizontal:12, vertical:8),
                decoration: BoxDecoration(color: const Color(0xfff8fafc),
                  borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
                child: Row(children: [
                  CircleAvatar(radius:14, backgroundColor: primaryEmerald.withValues(alpha:0.15),
                    child: Text(m.name[0].toUpperCase(),
                      style: const TextStyle(color: primaryEmerald, fontWeight: FontWeight.bold, fontSize:11))),
                  const SizedBox(width:10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize:12)),
                      if (m.email == u.hostEmail)
                        Container(margin: const EdgeInsets.only(left:6),
                          padding: const EdgeInsets.symmetric(horizontal:5, vertical:1),
                          decoration: BoxDecoration(color: primaryEmerald, borderRadius: BorderRadius.circular(4)),
                          child: const Text('HOST', style: TextStyle(color: Colors.white, fontSize:8, fontWeight: FontWeight.bold))),
                    ]),
                    Text(m.vehicle, style: const TextStyle(fontSize:10, color: Colors.grey)),
                  ])),
                  IconButton(constraints: const BoxConstraints(minWidth:30, minHeight:30),
                    icon: const Icon(Icons.call_rounded, size:15, color: primaryEmerald),
                    onPressed: () => widget.onCall(m.mobile)),
                  IconButton(constraints: const BoxConstraints(minWidth:30, minHeight:30),
                    icon: const Icon(Icons.email_rounded, size:15, color: primaryEmerald),
                    onPressed: () => widget.onEmail(m.email)),
                  if (widget.isOwner && m.email != u.hostEmail)
                    IconButton(
                      constraints: const BoxConstraints(minWidth:30, minHeight:30),
                      icon: const Icon(Icons.person_remove_rounded, size:16, color: Colors.redAccent),
                      tooltip: 'Kick Rider',
                      onPressed: () => widget.onKickMember(m),
                    ),
                ]),
              )).toList())),

          // Action button area
          Padding(
            padding: const EdgeInsets.fromLTRB(16,4,16,14),
            child: SizedBox(
              width: double.infinity,
              child: _buildActionButton(context, full),
            ),
          ),
        ]),
      ));
  }

  Widget _buildActionButton(BuildContext context, bool full) {
    // 1. If user is the Host/Owner
    if (widget.isOwner) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primaryEmerald.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: primaryEmerald.withValues(alpha: 0.25)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_rounded, size: 16, color: primaryEmerald),
            SizedBox(width: 8),
            Text('You are the Host of this Convoy',
              style: TextStyle(color: primaryEmerald, fontWeight: FontWeight.bold, fontSize: 13)),
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
              padding: const EdgeInsets.symmetric(vertical: 11),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_rounded, size: 16, color: Colors.green),
                  SizedBox(width: 8),
                  Text('Joined Convoy',
                    style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: BorderSide(color: Colors.red.shade200),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            ),
            icon: const Icon(Icons.logout_rounded, size: 16),
            label: const Text('Exit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
              padding: const EdgeInsets.symmetric(vertical: 11),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.hourglass_top_rounded, size: 16, color: Colors.orange.shade800),
                  const SizedBox(width: 8),
                  Text('Pending Approval',
                    style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: BorderSide(color: Colors.red.shade200),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            ),
            onPressed: widget.onLeave,
            child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ],
      );
    }

    // 4. Default: Request to join
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: primaryEmerald,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 11),
      ),
      icon: const Icon(Icons.person_add_alt_1_rounded, size: 16, color: Colors.white),
      label: Text(full ? 'Group Full' : 'Request to Join',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      onPressed: full ? null : widget.onRequestJoin,
    );
  }
}

// -- Create Union Sheet --------------------------------------------------------

class _CreateUnionSheet extends StatefulWidget {
  final UnionService service;
  const _CreateUnionSheet({required this.service});
  @override
  State<_CreateUnionSheet> createState() => _CreateUnionSheetState();
}

class _CreateUnionSheetState extends State<_CreateUnionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl  = TextEditingController();
  final _fromCtrl   = TextEditingController();
  final _toCtrl     = TextEditingController();
  final _dateCtrl   = TextEditingController(text: 'Tomorrow · 06:00 AM');
  final _nameCtrl   = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _emailCtrl  = TextEditingController();
  final _vehicleCtrl= TextEditingController(text: 'Royal Enfield 350');
  VehicleCategory _cat = VehicleCategory.bike;
  bool _loading = false;

  @override
  void dispose() {
    for (final c in [_titleCtrl,_fromCtrl,_toCtrl,_dateCtrl,_nameCtrl,_mobileCtrl,_emailCtrl,_vehicleCtrl]) c.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    await widget.service.createUnion(
      title: _titleCtrl.text.trim(), fromLocation: _fromCtrl.text.trim(),
      toLocation: _toCtrl.text.trim(), departureDateStr: _dateCtrl.text.trim(),
      category: _cat, hostName: _nameCtrl.text.trim(),
      hostMobile: _mobileCtrl.text.trim(), hostEmail: _emailCtrl.text.trim(),
      hostVehicle: _vehicleCtrl.text.trim(),
    );
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Union created! Others can now request to join.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bi = MediaQuery.of(context).viewInsets.bottom;
    final nb = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20,16,20,16+bi+nb),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: SingleChildScrollView(child: Form(key: _formKey, child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width:36, height:4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height:14),
        const Text('Create Travel Union / Convoy', style: TextStyle(fontWeight: FontWeight.bold, fontSize:18)),
        const SizedBox(height:4),
        const Text('Riders can browse and request to join your convoy.', style: TextStyle(fontSize:12, color: Color(0xff64748b))),
        const SizedBox(height:16),
        TextFormField(controller: _titleCtrl, decoration: const InputDecoration(labelText:'Group Title (e.g. Coorg Biking Convoy)', border: OutlineInputBorder()), validator: (v)=>(v==null||v.isEmpty)?'Required':null),
        const SizedBox(height:10),
        Row(children:[
          Expanded(child: TextFormField(controller: _fromCtrl, decoration: const InputDecoration(labelText:'From', border: OutlineInputBorder()), validator: (v)=>(v==null||v.isEmpty)?'Required':null)),
          const SizedBox(width:10),
          Expanded(child: TextFormField(controller: _toCtrl, decoration: const InputDecoration(labelText:'To', border: OutlineInputBorder()), validator: (v)=>(v==null||v.isEmpty)?'Required':null)),
        ]),
        const SizedBox(height:10),
        TextFormField(controller: _dateCtrl, decoration: const InputDecoration(labelText:'Departure Date & Time', border: OutlineInputBorder())),
        const SizedBox(height:10),
        TextFormField(controller: _nameCtrl, decoration: const InputDecoration(labelText:'Your Name (Host)', border: OutlineInputBorder()), validator: (v)=>(v==null||v.isEmpty)?'Required':null),
        const SizedBox(height:10),
        Row(children:[
          Expanded(child: TextFormField(controller: _mobileCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText:'Mobile No', border: OutlineInputBorder()), validator: (v)=>(v==null||v.isEmpty)?'Required':null)),
          const SizedBox(width:10),
          Expanded(child: TextFormField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText:'Gmail / Email', border: OutlineInputBorder()), validator: (v)=>(v==null||v.isEmpty)?'Required':null)),
        ]),
        const SizedBox(height:10),
        TextFormField(controller: _vehicleCtrl, decoration: const InputDecoration(labelText:'Your Vehicle (e.g. RE Himalayan)', border: OutlineInputBorder())),
        const SizedBox(height:16),
        SizedBox(width: double.infinity, child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xff23695a), padding: const EdgeInsets.symmetric(vertical:14)),
          onPressed: _loading ? null : _submit,
          child: _loading ? const SizedBox(height:20, width:20, child: CircularProgressIndicator(strokeWidth:2, color: Colors.white))
            : const Text('Create Convoy', style: TextStyle(fontWeight: FontWeight.bold, fontSize:16)))),
      ]))));
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
  late final TextEditingController _dateCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _mobileCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _vehicleCtrl;
  late VehicleCategory _cat;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final u = widget.union;
    _titleCtrl   = TextEditingController(text: u.title);
    _fromCtrl    = TextEditingController(text: u.fromLocation);
    _toCtrl      = TextEditingController(text: u.toLocation);
    _dateCtrl    = TextEditingController(text: u.departureDateStr);
    _nameCtrl    = TextEditingController(text: u.hostName);
    _mobileCtrl  = TextEditingController(text: u.hostMobile);
    _emailCtrl   = TextEditingController(text: u.hostEmail);
    _vehicleCtrl = TextEditingController(text: u.members.isNotEmpty ? u.members.first.vehicle : 'Bike');
    _cat         = u.category;
  }

  @override
  void dispose() {
    for (final c in [_titleCtrl,_fromCtrl,_toCtrl,_dateCtrl,_nameCtrl,_mobileCtrl,_emailCtrl,_vehicleCtrl]) c.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    await widget.service.updateUnion(
      unionId: widget.union.id,
      title: _titleCtrl.text.trim(),
      fromLocation: _fromCtrl.text.trim(),
      toLocation: _toCtrl.text.trim(),
      departureDateStr: _dateCtrl.text.trim(),
      category: _cat,
      hostName: _nameCtrl.text.trim(),
      hostMobile: _mobileCtrl.text.trim(),
      hostEmail: _emailCtrl.text.trim(),
      hostVehicle: _vehicleCtrl.text.trim(),
      maxMembers: widget.union.maxMembers,
    );
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Convoy updated successfully!')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bi = MediaQuery.of(context).viewInsets.bottom;
    final nb = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20,16,20,16+bi+nb),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: SingleChildScrollView(child: Form(key: _formKey, child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width:36, height:4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height:14),
        const Text('Edit Travel Convoy', style: TextStyle(fontWeight: FontWeight.bold, fontSize:18)),
        const SizedBox(height:4),
        const Text('Update details for your convoy riders.', style: TextStyle(fontSize:12, color: Color(0xff64748b))),
        const SizedBox(height:16),
        TextFormField(controller: _titleCtrl, decoration: const InputDecoration(labelText:'Group Title', border: OutlineInputBorder()), validator: (v)=>(v==null||v.isEmpty)?'Required':null),
        const SizedBox(height:10),
        Row(children:[
          Expanded(child: TextFormField(controller: _fromCtrl, decoration: const InputDecoration(labelText:'From', border: OutlineInputBorder()), validator: (v)=>(v==null||v.isEmpty)?'Required':null)),
          const SizedBox(width:10),
          Expanded(child: TextFormField(controller: _toCtrl, decoration: const InputDecoration(labelText:'To', border: OutlineInputBorder()), validator: (v)=>(v==null||v.isEmpty)?'Required':null)),
        ]),
        const SizedBox(height:10),
        TextFormField(controller: _dateCtrl, decoration: const InputDecoration(labelText:'Departure Date & Time', border: OutlineInputBorder())),
        const SizedBox(height:10),
        TextFormField(controller: _nameCtrl, decoration: const InputDecoration(labelText:'Your Name (Host)', border: OutlineInputBorder()), validator: (v)=>(v==null||v.isEmpty)?'Required':null),
        const SizedBox(height:10),
        Row(children:[
          Expanded(child: TextFormField(controller: _mobileCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText:'Mobile No', border: OutlineInputBorder()), validator: (v)=>(v==null||v.isEmpty)?'Required':null)),
          const SizedBox(width:10),
          Expanded(child: TextFormField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText:'Gmail / Email', border: OutlineInputBorder()), validator: (v)=>(v==null||v.isEmpty)?'Required':null)),
        ]),
        const SizedBox(height:10),
        TextFormField(controller: _vehicleCtrl, decoration: const InputDecoration(labelText:'Host Vehicle', border: OutlineInputBorder())),
        const SizedBox(height:16),
        SizedBox(width: double.infinity, child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xff23695a), padding: const EdgeInsets.symmetric(vertical:14)),
          onPressed: _loading ? null : _submit,
          child: _loading ? const SizedBox(height:20, width:20, child: CircularProgressIndicator(strokeWidth:2, color: Colors.white))
            : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold, fontSize:16)))),
      ]))));
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
  final _formKey   = GlobalKey<FormState>();
  final _nameCtrl  = TextEditingController();
  final _mobCtrl   = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _vehCtrl   = TextEditingController();
  VehicleCategory _cat = VehicleCategory.bike;
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose(); _mobCtrl.dispose(); _emailCtrl.dispose(); _vehCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final ok = await widget.service.requestToJoin(
      joinCodeOrId: widget.union.id,
      riderName: _nameCtrl.text.trim(), riderMobile: _mobCtrl.text.trim(),
      riderEmail: _emailCtrl.text.trim(), riderVehicle: _vehCtrl.text.trim(),
      category: _cat,
    );
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'Request sent! Host will approve your join.' : 'Could not send request. Try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bi = MediaQuery.of(context).viewInsets.bottom;
    final nb = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20,16,20,16+bi+nb),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: SingleChildScrollView(child: Form(key: _formKey, child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width:36, height:4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height:14),
        Text('Join "${widget.union.title}"', style: const TextStyle(fontWeight: FontWeight.bold, fontSize:18)),
        const SizedBox(height:2),
        Text('${widget.union.fromLocation} ➔ ${widget.union.toLocation}', style: const TextStyle(fontSize:12, color: Color(0xff64748b))),
        const SizedBox(height:4),
        const Text('Host will review and approve your request.', style: TextStyle(fontSize:12, color: Color(0xff64748b))),
        const SizedBox(height:16),
        TextFormField(controller: _nameCtrl, decoration: const InputDecoration(labelText:'Your Full Name', border: OutlineInputBorder()), validator: (v)=>(v==null||v.isEmpty)?'Required':null),
        const SizedBox(height:10),
        Row(children:[
          Expanded(child: TextFormField(controller: _mobCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText:'Mobile No', border: OutlineInputBorder()), validator: (v)=>(v==null||v.isEmpty)?'Required':null)),
          const SizedBox(width:10),
          Expanded(child: TextFormField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText:'Gmail / Email', border: OutlineInputBorder()), validator: (v)=>(v==null||v.isEmpty)?'Required':null)),
        ]),
        const SizedBox(height:10),
        TextFormField(controller: _vehCtrl, decoration: const InputDecoration(labelText:'Your Vehicle (e.g. KTM 390)', border: OutlineInputBorder()), validator: (v)=>(v==null||v.isEmpty)?'Required':null),
        const SizedBox(height:16),
        SizedBox(width: double.infinity, child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xff23695a), padding: const EdgeInsets.symmetric(vertical:14)),
          onPressed: _loading ? null : _submit,
          child: _loading ? const SizedBox(height:20, width:20, child: CircularProgressIndicator(strokeWidth:2, color: Colors.white))
            : const Text('Send Join Request', style: TextStyle(fontWeight: FontWeight.bold, fontSize:16)))),
      ]))));
  }
}
