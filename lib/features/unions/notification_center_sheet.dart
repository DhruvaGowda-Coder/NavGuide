import 'package:flutter/material.dart';

import '../../device/unions/union_service.dart';
import '../../domain/union_models.dart';
import 'convoy_details_screen.dart';
import 'group_detail_screen.dart';

const Color _primaryEmerald = Color(0xff23695a);
const Color _primaryEmeraldDark = Color(0xff184e43);
const Color _scaffoldBg = Color(0xfff7f9f6);
const Color _textDark = Color(0xff1e293b);
const Color _textMuted = Color(0xff64748b);

void showNotificationCenterSheet(BuildContext context, [UnionService? service]) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => NotificationCenterSheet(service: service ?? UnionService()),
  );
}

class NotificationCenterSheet extends StatefulWidget {
  final UnionService service;

  const NotificationCenterSheet({super.key, required this.service});

  @override
  State<NotificationCenterSheet> createState() => _NotificationCenterSheetState();
}

class _NotificationCenterSheetState extends State<NotificationCenterSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  int _tabIndex = 0; // 0: All, 1: Requests, 2: Accepted, 3: Chats, 4: Alerts
  String _query = '';
  bool _isProcessingBulk = false;

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_onServiceUpdate);
    // Explicitly sync immediately when opening the notification sheet
    widget.service.syncWithFirebase();
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
          backgroundColor: _primaryEmerald,
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
    // 1. Pending join requests to my convoys
    final allPendingConvoys = <MapEntry<TravelUnionGroup, UnionMember>>[];
    for (final u in widget.service.unions) {
      if (widget.service.isOwner(u)) {
        for (final p in u.pendingRequests) {
          allPendingConvoys.add(MapEntry(u, p));
        }
      }
    }

    // 2. Pending join requests to my groups
    final allPendingGroups = <MapEntry<TravelGroup, GroupMember>>[];
    for (final g in widget.service.groups) {
      if (widget.service.isGroupAdmin(g)) {
        for (final m in g.members.where((m) => m.isPending)) {
          allPendingGroups.add(MapEntry(g, m));
        }
      }
    }

    // 3. Convoys where I was accepted as a member (joined but not host)
    final myAcceptedConvoys = <TravelUnionGroup>[];
    for (final u in widget.service.unions) {
      if (!widget.service.isOwner(u) && widget.service.isMyConvoy(u)) {
        myAcceptedConvoys.add(u);
      }
    }

    // 4. Groups where I was accepted as a member
    final myAcceptedGroups = <TravelGroup>[];
    for (final g in widget.service.groups) {
      if (!widget.service.isGroupAdmin(g) && widget.service.isMemberOfGroup(g)) {
        myAcceptedGroups.add(g);
      }
    }

    // 5. Recent chat messages in my convoys and groups
    final recentChats = <_ChatNotificationItem>[];
    final myPhone = widget.service.myRiderMobile ?? widget.service.myHostMobile ?? '';
    for (final u in widget.service.unions) {
      if (widget.service.isMyConvoy(u)) {
        for (final msg in u.chatMessages.reversed.take(4)) {
          if (myPhone.isEmpty || msg.senderMobile.trim() != myPhone.trim()) {
            recentChats.add(_ChatNotificationItem(
              title: u.title,
              sender: msg.senderName,
              text: msg.text,
              time: msg.timestamp,
              isConvoy: true,
              targetId: u.id,
            ));
          }
        }
      }
    }
    for (final g in widget.service.groups) {
      if (widget.service.isMemberOfGroup(g)) {
        for (final msg in g.chatMessages.reversed.take(4)) {
          recentChats.add(_ChatNotificationItem(
            title: g.name,
            sender: msg.senderName,
            text: msg.text,
            time: msg.timestamp,
            isConvoy: false,
            targetId: g.id,
          ));
        }
      }
    }
    recentChats.sort((a, b) => b.time.compareTo(a.time));

    // 6. Active emergency alerts
    final activeAlerts = <MapEntry<TravelUnionGroup, ConvoyEmergencyAlert>>[];
    for (final u in widget.service.unions) {
      if (widget.service.isMyConvoy(u) && u.hasActiveEmergency) {
        for (final a in u.activeAlerts) {
          activeAlerts.add(MapEntry(u, a));
        }
      }
    }

    final totalRequests = allPendingConvoys.length + allPendingGroups.length;
    final totalAccepted = myAcceptedConvoys.length + myAcceptedGroups.length;
    final totalActionable = totalRequests + activeAlerts.length;

    // Filter items based on selected tab
    List<dynamic> items = [];
    if (_tabIndex == 0) {
      // All
      items = [
        ...activeAlerts,
        ...allPendingConvoys,
        ...allPendingGroups,
        ...myAcceptedConvoys.map((c) => _AcceptedConvoyItem(c)),
        ...myAcceptedGroups.map((g) => _AcceptedGroupItem(g)),
        ...recentChats,
      ];
    } else if (_tabIndex == 1) {
      // Requests
      items = [...allPendingConvoys, ...allPendingGroups];
    } else if (_tabIndex == 2) {
      // Accepted
      items = [
        ...myAcceptedConvoys.map((c) => _AcceptedConvoyItem(c)),
        ...myAcceptedGroups.map((g) => _AcceptedGroupItem(g)),
      ];
    } else if (_tabIndex == 3) {
      // Chats
      items = recentChats;
    } else if (_tabIndex == 4) {
      // Alerts
      items = activeAlerts;
    }

    // Query filter
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
        } else if (item is _AcceptedConvoyItem) {
          return item.convoy.title.toLowerCase().contains(_query) ||
              item.convoy.fromLocation.toLowerCase().contains(_query) ||
              item.convoy.toLocation.toLowerCase().contains(_query);
        } else if (item is _AcceptedGroupItem) {
          return item.group.name.toLowerCase().contains(_query) ||
              item.group.category.toLowerCase().contains(_query);
        } else if (item is _ChatNotificationItem) {
          return item.title.toLowerCase().contains(_query) ||
              item.sender.toLowerCase().contains(_query) ||
              item.text.toLowerCase().contains(_query);
        } else if (item is MapEntry<TravelUnionGroup, ConvoyEmergencyAlert>) {
          return item.key.title.toLowerCase().contains(_query) ||
              item.value.riderName.toLowerCase().contains(_query) ||
              item.value.emergencyType.toLowerCase().contains(_query) ||
              item.value.note.toLowerCase().contains(_query);
        }
        return true;
      }).toList();
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
      decoration: const BoxDecoration(
        color: _scaffoldBg,
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
                    color: totalActionable > 0 ? Colors.orange.shade100 : Colors.teal.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    totalActionable > 0
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_rounded,
                    color: totalActionable > 0 ? Colors.orange.shade900 : _primaryEmerald,
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
                            'Notification Center',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: _textDark,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (totalActionable > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade800,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$totalActionable new',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10.5,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        totalActionable > 0
                            ? '$totalRequests join request${totalRequests == 1 ? '' : 's'} waiting for approval'
                            : 'All up-to-date! Live sync active via Firebase',
                        style: const TextStyle(fontSize: 12, color: _textMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Sync now',
                  icon: const Icon(Icons.sync_rounded, color: _primaryEmerald),
                  onPressed: () async {
                    await widget.service.syncWithFirebase();
                    if (mounted) setState(() {});
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: _textMuted),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          if (totalRequests > 1 && (_tabIndex == 0 || _tabIndex == 1))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _primaryEmerald,
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
                        : 'Approve All Pending Requests ($totalRequests)',
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
                hintText: 'Search notifications, applicant name, chat...',
                hintStyle: const TextStyle(fontSize: 13, color: _textMuted),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: _textMuted,
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
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('All', items.length, 0),
                  const SizedBox(width: 8),
                  _buildFilterChip('Requests', totalRequests, 1),
                  const SizedBox(width: 8),
                  _buildFilterChip('Accepted', totalAccepted, 2),
                  const SizedBox(width: 8),
                  _buildFilterChip('Chats', recentChats.length, 3),
                  if (activeAlerts.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _buildFilterChip('SOS Alerts', activeAlerts.length, 4, isAlert: true),
                  ],
                ],
              ),
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
                            _query.isEmpty
                                ? Icons.mark_email_read_rounded
                                : Icons.search_off_rounded,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _query.isEmpty
                                ? 'No Notifications Right Now'
                                : 'No notifications match "$_query"',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: _textDark,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _query.isEmpty
                                ? 'Whenever someone requests to join, you get accepted, or new chats arrive, they appear here live.'
                                : 'Try searching with another keyword or vehicle name.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: _textMuted,
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
                      } else if (item is _AcceptedConvoyItem) {
                        return _buildAcceptedConvoyCard(item.convoy);
                      } else if (item is _AcceptedGroupItem) {
                        return _buildAcceptedGroupCard(item.group);
                      } else if (item is _ChatNotificationItem) {
                        return _buildChatCard(item);
                      } else if (item is MapEntry<TravelUnionGroup, ConvoyEmergencyAlert>) {
                        return _buildAlertCard(item);
                      }
                      return const SizedBox.shrink();
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, int count, int index, {bool isAlert = false}) {
    final isSelected = _tabIndex == index;
    return InkWell(
      onTap: () => setState(() => _tabIndex = index),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (isAlert ? Colors.redAccent.shade700 : _primaryEmerald)
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? (isAlert ? Colors.redAccent.shade700 : _primaryEmerald)
                : Colors.grey.shade300,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: (isAlert ? Colors.redAccent : _primaryEmerald).withValues(alpha: 0.25),
                    blurRadius: 4,
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
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : _textDark,
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.25)
                    : (isAlert ? Colors.red.shade100 : Colors.grey.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : (isAlert ? Colors.red.shade800 : _textMuted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConvoyRequestCard(MapEntry<TravelUnionGroup, UnionMember> entry) {
    final union = entry.key;
    final member = entry.value;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: _primaryEmerald.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.drive_eta_rounded, color: _primaryEmerald, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Convoy: ${union.title}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _primaryEmeraldDark,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Pending',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade900,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: _primaryEmerald.withValues(alpha: 0.15),
                child: Text(
                  member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _primaryEmeraldDark,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '📱 ${member.mobile}${member.vehicle.isNotEmpty ? '  •  🚗 ${member.vehicle}' : ''}',
                      style: const TextStyle(fontSize: 11.5, color: _textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent.shade700,
                    side: BorderSide(color: Colors.redAccent.shade200),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () async {
                    await widget.service.respondToJoinRequest(
                      unionId: union.id,
                      memberId: member.id,
                      accept: false,
                    );
                    if (mounted) setState(() {});
                  },
                  child: const Text('Decline', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _primaryEmerald,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () async {
                    final ok = await widget.service.respondToJoinRequest(
                      unionId: union.id,
                      memberId: member.id,
                      accept: true,
                    );
                    if (mounted) {
                      setState(() {});
                      if (!ok) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Cannot accept: Convoy has reached capacity limit!'),
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Accept', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGroupRequestCard(MapEntry<TravelGroup, GroupMember> entry) {
    final group = entry.key;
    final member = entry.value;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.group_rounded, color: Colors.blue, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Community Group: ${group.name}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.blueAccent,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Pending',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade900,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.blue.withValues(alpha: 0.15),
                child: Text(
                  member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '📱 ${member.mobile}',
                      style: const TextStyle(fontSize: 11.5, color: _textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent.shade700,
                    side: BorderSide(color: Colors.redAccent.shade200),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () async {
                    await widget.service.rejectGroupMember(group.id, member.id);
                    if (mounted) setState(() {});
                  },
                  child: const Text('Decline', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () async {
                    await widget.service.approveGroupMember(group.id, member.id);
                    if (mounted) setState(() {});
                  },
                  child: const Text('Approve', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAcceptedConvoyCard(TravelUnionGroup convoy) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.teal.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded, color: Colors.teal, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🎉 Convoy Request Accepted!',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: _primaryEmeraldDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'You were accepted into "${convoy.title}". Tap to view route & live chat.',
                  style: const TextStyle(fontSize: 11.5, color: _textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _primaryEmerald,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ConvoyDetailsScreen(unionId: convoy.id),
                ),
              );
            },
            child: const Text('Open', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildAcceptedGroupCard(TravelGroup group) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.verified_rounded, color: Colors.blue, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🎉 Group Request Approved!',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'You are now an active member of "${group.name}".',
                  style: const TextStyle(fontSize: 11.5, color: _textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GroupDetailScreen(groupId: group.id),
                ),
              );
            },
            child: const Text('Open', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildChatCard(_ChatNotificationItem chat) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: chat.isConvoy ? _primaryEmerald.withValues(alpha: 0.12) : Colors.blue.withValues(alpha: 0.12),
            child: Icon(
              chat.isConvoy ? Icons.chat_bubble_rounded : Icons.forum_rounded,
              color: chat.isConvoy ? _primaryEmerald : Colors.blue,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${chat.sender} in ${chat.title}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: _textDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      _formatShortTime(chat.time),
                      style: const TextStyle(fontSize: 10, color: _textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  chat.text,
                  style: const TextStyle(fontSize: 12, color: _textDark),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: _textMuted),
            onPressed: () {
              Navigator.of(context).pop();
              if (chat.isConvoy) {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ConvoyDetailsScreen(unionId: chat.targetId)),
                );
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => GroupDetailScreen(groupId: chat.targetId)),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAlertCard(MapEntry<TravelUnionGroup, ConvoyEmergencyAlert> item) {
    final alert = item.value;
    final union = item.key;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade300, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🚨 Emergency in "${union.title}"',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${alert.riderName}: ${alert.emergencyType}${alert.note.isNotEmpty ? ' — ${alert.note}' : ''}',
                  style: TextStyle(fontSize: 12, color: Colors.red.shade800),
                ),
              ],
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ConvoyDetailsScreen(unionId: union.id)),
              );
            },
            child: const Text('Respond', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _formatShortTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _AcceptedConvoyItem {
  final TravelUnionGroup convoy;
  _AcceptedConvoyItem(this.convoy);
}

class _AcceptedGroupItem {
  final TravelGroup group;
  _AcceptedGroupItem(this.group);
}

class _ChatNotificationItem {
  final String title;
  final String sender;
  final String text;
  final DateTime time;
  final bool isConvoy;
  final String targetId;

  _ChatNotificationItem({
    required this.title,
    required this.sender,
    required this.text,
    required this.time,
    required this.isConvoy,
    required this.targetId,
  });
}
