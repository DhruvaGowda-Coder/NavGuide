import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../device/auth/google_auth_service.dart';
import '../../device/unions/union_service.dart';
import '../../domain/union_models.dart';
import 'convoy_details_screen.dart';
import 'edit_convoy_sheet.dart';

const Color _emerald = Color(0xff23695a);
const Color _textDark = Color(0xff1e293b);
const Color _textMuted = Color(0xff64748b);
const Color _bg = Color(0xfff7f9f6);

class GroupDetailScreen extends StatefulWidget {
  final String groupId;
  const GroupDetailScreen({super.key, required this.groupId});

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen>
    with SingleTickerProviderStateMixin {
  final UnionService _service = UnionService();
  late TabController _tabs;
  final TextEditingController _chatCtrl = TextEditingController();
  final ScrollController _chatScroll = ScrollController();

  Timer? _liveSyncTimer;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _service.addListener(_rebuild);
    _service.syncWithFirebase();
    _liveSyncTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        _service.syncWithFirebase();
      }
    });
  }

  @override
  void dispose() {
    _liveSyncTimer?.cancel();
    _tabs.dispose();
    _service.removeListener(_rebuild);
    _chatCtrl.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  TravelGroup? get _group =>
      _service.groups.where((g) => g.id == widget.groupId).firstOrNull;

  bool get _isAdmin {
    final g = _group;
    return g != null && _service.isGroupAdmin(g);
  }

  bool get _isMember {
    final g = _group;
    return g != null && _service.isGroupMember(g);
  }

  Future<GoogleUserProfile?> _ensureSignedInForSync() async {
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
            ),
          );
        }
        return null;
      }
      await _service.syncWithGoogleUser(user);
      return user;
    } catch (_) {
      return null;
    }
  }

  void _sendChat() {
    final g = _group;
    final text = _chatCtrl.text.trim();
    if (text.isEmpty || g == null) return;
    final gUser = GoogleAuthService().currentUser;
    final myId = _service.myDeviceId;
    final String myName;
    if (_isAdmin) {
      myName = g.admins.firstOrNull?.name ?? gUser?.displayName ?? 'Admin';
    } else {
      final myMobs = {
        if (_service.myRiderMobile != null && _service.myRiderMobile!.isNotEmpty)
          _service.myRiderMobile!,
        if (_service.myHostMobile != null && _service.myHostMobile!.isNotEmpty)
          _service.myHostMobile!,
      };
      final myMember = g.members
          .where((m) => myMobs.contains(m.mobile))
          .firstOrNull;
      myName = myMember?.name ?? gUser?.displayName ?? 'Rider';
    }
    _service.sendGroupChatMessage(
      widget.groupId,
      text: text,
      senderName: myName,
      senderId: myId,
      isAdmin: _isAdmin,
    );
    _chatCtrl.clear();
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_chatScroll.hasClients) {
        _chatScroll.animateTo(
          _chatScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showJoinSheet() {
    final g = _group;
    if (g == null) return;
    final googleName = GoogleAuthService().currentUser?.displayName;
    final nameCtrl = TextEditingController(
      text: (googleName != null && googleName.isNotEmpty) ? googleName : '',
    );
    final mobCtrl = TextEditingController(
      text: _service.myRiderMobile ?? _service.myHostMobile ?? '',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, _) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            24 +
                MediaQuery.of(ctx).viewInsets.bottom +
                MediaQuery.of(ctx).padding.bottom,
          ),
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
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  children: [
                    SizedBox(
                      height: 75,
                      width: double.infinity,
                      child: _buildGroupBanner(g),
                    ),
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.72),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      left: 10,
                      right: 10,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.25),
                              shape: BoxShape.circle,
                            ),
                            child: Text(g.emoji, style: const TextStyle(fontSize: 16)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  g.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${g.category} · ${g.isPublic ? "Public" : "Private"}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                g.isPublic ? 'Join ${g.name}' : 'Request to Join ${g.name}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _textDark,
                ),
              ),
              if (!g.isPublic) ...[
                const SizedBox(height: 4),
                Text(
                  'This is a private group. Admin will review and approve your request.',
                  style: TextStyle(fontSize: 11.5, color: Colors.orange.shade800),
                ),
              ],
              const SizedBox(height: 14),
              _inputField(nameCtrl, 'Your Full Name', Icons.person_rounded),
              const SizedBox(height: 10),
              _inputField(
                mobCtrl,
                'Mobile Number',
                Icons.phone_rounded,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _emerald,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () async {
                    if (nameCtrl.text.trim().isEmpty ||
                        mobCtrl.text.trim().isEmpty)
                      return;
                    final googleUser = await _ensureSignedInForSync();
                    if (googleUser == null || !mounted) return;
                    await _service.joinGroup(
                      g.id,
                      name: nameCtrl.text.trim(),
                      mobile: mobCtrl.text.trim(),
                    );
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: _emerald,
                          content: Text(
                            g.isPublic
                                ? 'Joined ${g.name}!'
                                : 'Request sent! Waiting for admin approval.',
                          ),
                        ),
                      );
                    }
                  },
                  child: Text(
                    g.isPublic ? 'Join Group' : 'Send Request',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
          'Are you sure you want to delete "${_group?.name}"?\nAll group convoys and chat messages will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: _textMuted)),
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
      final gName = _group?.name ?? 'Group';
      await _service.deleteGroup(widget.groupId);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('"$gName" has been deleted.')));
      }
    }
  }

  Future<void> _confirmDeleteConvoy(TravelUnionGroup convoy) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(
              Icons.delete_outline_rounded,
              color: Colors.redAccent,
              size: 24,
            ),
            SizedBox(width: 8),
            Text('Delete Convoy?'),
          ],
        ),
        content: Text(
          'Are you sure you want to remove and delete "${convoy.title}" from this group?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: _textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _service.removeConvoyFromGroup(widget.groupId, convoy.id);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Convoy "${convoy.title}" deleted.')),
        );
      }
    }
  }

  Future<void> _confirmLeaveGroup() async {
    final g = _group;
    if (g == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.exit_to_app_rounded, color: Colors.redAccent, size: 24),
            SizedBox(width: 8),
            Text('Leave Group'),
          ],
        ),
        content: Text(
          'Are you sure you want to leave "${g.name}"?\nYou will lose access to member convoys and group chat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: _textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Leave Group'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _service.leaveGroup(g.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('You left "${g.name}".')));
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _toggleConvoyPublicity(TravelUnionGroup convoy) async {
    final newPublic = !convoy.isPublicFeed;
    await _service.setConvoyPublicity(convoy.id, newPublic);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: newPublic ? _emerald : Colors.blueGrey,
          content: Text(
            newPublic
                ? 'Convoy "${convoy.title}" is now PUBLIC in the Convoys tab!'
                : 'Convoy "${convoy.title}" is now GROUP ONLY.',
          ),
        ),
      );
    }
  }

  Future<void> _confirmDeleteGroupMessage(GroupChatMessage m) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(
              Icons.delete_outline_rounded,
              color: Colors.redAccent,
              size: 22,
            ),
            SizedBox(width: 8),
            Text('Delete Message?'),
          ],
        ),
        content: Text(
          'Delete "${m.text.length > 40 ? '${m.text.substring(0, 40)}...' : m.text}" for everyone in this group?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: _textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _service.deleteGroupChatMessage(widget.groupId, m.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Message deleted.')));
      }
    }
  }

  void _shareGroupLink() {
    final g = _group;
    if (g == null) return;
    final cleanLink = 'https://navguardian.app/group/${g.id}';
    SharePlus.instance.share(ShareParams(text: cleanLink, subject: g.name));
  }

  Future<void> _showCreateConvoySheet() async {
    final g = _group;
    if (g == null) return;
    final googleUser = await _ensureSignedInForSync();
    if (googleUser == null || !mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.90,
        ),
        child: _CreateGroupConvoySheet(group: g, service: _service),
      ),
    );
  }

  Widget _inputField(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    TextInputType? keyboardType,
  }) => TextField(
    controller: ctrl,
    keyboardType: keyboardType,
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

  String _formatMemberSince(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays < 1) return 'Joined today';
    if (diff.inDays == 1) return 'Joined yesterday';
    if (diff.inDays < 30) return 'Joined ${diff.inDays}d ago';
    if (diff.inDays < 365) return 'Joined ${(diff.inDays / 30).floor()}mo ago';
    return 'Joined ${(diff.inDays / 365).floor()}y ago';
  }

  String _formatDate(DateTime dt) {
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
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  Future<void> _confirmRemoveMember(TravelGroup g, GroupMember m) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(
              Icons.person_remove_rounded,
              color: Colors.redAccent,
              size: 22,
            ),
            SizedBox(width: 8),
            Text('Remove Member?'),
          ],
        ),
        content: Text(
          'Are you sure you want to remove "${m.name}" from "${g.name}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: _textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _service.removeGroupMember(g.id, m.id);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${m.name} removed from group.')),
        );
      }
    }
  }

  Future<void> _confirmTransferAdmin(TravelGroup g, GroupMember m) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.admin_panel_settings_rounded, color: _emerald, size: 24),
            SizedBox(width: 8),
            Text('Make Admin?'),
          ],
        ),
        content: Text(
          'Promote "${m.name}" to Group Admin for "${g.name}"?\n\nThey will be able to manage members, create group convoys, and update group settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: _textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _emerald),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Make Admin'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final success = await _service.transferGroupAdmin(
        groupId: g.id,
        targetMemberId: m.id,
      );
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? '🛡️ ${m.name} is now an Admin of ${g.name}!'
                  : 'Failed to update admin role.',
            ),
            backgroundColor: _emerald,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showEditAboutSheet(TravelGroup g) {
    final nameCtrl = TextEditingController(text: g.name);
    final descCtrl = TextEditingController(text: g.description);
    String selectedCategory = g.category;
    bool isPublic = g.isPublic;
    String selectedEmoji = g.emoji;
    String selectedBanner = g.imageUrl.isNotEmpty
        ? g.imageUrl
        : UnionService.defaultScenicBanners[0];

    final emojis = [
      '👥',
      '🚗',
      '🏍️',
      '🚌',
      '🏕️',
      '✈️',
      '🛤️',
      '🚂',
      '⛵',
      '🧭',
      '🏔️',
    ];
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
    if (!categories.contains(selectedCategory)) {
      categories.insert(0, selectedCategory);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            24 +
                MediaQuery.of(ctx).viewInsets.bottom +
                MediaQuery.of(ctx).padding.bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.88,
            ),
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
                  Row(
                    children: [
                      const Icon(
                        Icons.edit_note_rounded,
                        color: _emerald,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Edit Group Details',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _textDark,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: _textMuted,
                        ),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Emoji selector
                  const Text(
                    'Group Icon / Emoji',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: emojis.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final em = emojis[i];
                        final isSel = em == selectedEmoji;
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setModal(() => selectedEmoji = em);
                          },
                          child: Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSel
                                  ? _emerald.withValues(alpha: 0.15)
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSel ? _emerald : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Text(
                              em,
                              style: const TextStyle(fontSize: 22),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Name Field
                  const Text(
                    'Group Name',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _inputField(nameCtrl, 'Group Name', Icons.groups_rounded),
                  const SizedBox(height: 12),

                  // Description Field
                  const Text(
                    'About / Description',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: descCtrl,
                    maxLines: 3,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Tell members what this group is about...',
                      hintStyle: const TextStyle(
                        color: _textMuted,
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: const Color(0xfff1f5f3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 14,
                      ),
                      prefixIcon: const Icon(
                        Icons.description_rounded,
                        color: _emerald,
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Category dropdown
                  const Text(
                    'Category',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: categories.contains(selectedCategory)
                        ? selectedCategory
                        : (categories.isNotEmpty ? categories.first : null),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xfff1f5f3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 14,
                      ),
                      prefixIcon: const Icon(
                        Icons.category_rounded,
                        color: _emerald,
                        size: 18,
                      ),
                    ),
                    items: categories
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(
                              c,
                              style: const TextStyle(fontSize: 13.5),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setModal(
                      () => selectedCategory = v ?? selectedCategory,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Public / Private toggle
                  Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Group Privacy',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _textDark,
                            ),
                          ),
                          Text(
                            isPublic
                                ? 'Anyone can join instantly'
                                : 'Admin approval required to join',
                            style: const TextStyle(
                              fontSize: 11,
                              color: _textMuted,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Switch.adaptive(
                        value: isPublic,
                        activeTrackColor: _emerald,
                        onChanged: (v) => setModal(() => isPublic = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Scenic Travel Banner Picker
                  const Text(
                    'Scenic Cover Banner',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 80,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: UnionService.defaultScenicBanners.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, i) {
                        final bPath = UnionService.defaultScenicBanners[i];
                        final isSel = bPath == selectedBanner;
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setModal(() => selectedBanner = bPath);
                          },
                          child: Container(
                            width: 120,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSel ? _emerald : Colors.grey.shade300,
                                width: isSel ? 2.5 : 1,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.asset(
                                  bPath,
                                  fit: BoxFit.cover,
                                  cacheWidth: 240,
                                ),
                                if (isSel)
                                  Container(
                                    color: _emerald.withValues(alpha: 0.35),
                                    child: const Center(
                                      child: Icon(
                                        Icons.check_circle_rounded,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Save Changes Button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _emerald,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.save_rounded, size: 18),
                      label: const Text(
                        'Save Changes',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      onPressed: () async {
                        if (nameCtrl.text.trim().isEmpty) return;
                        await _service.updateGroup(
                          g.id,
                          name: nameCtrl.text.trim(),
                          description: descCtrl.text.trim(),
                          category: selectedCategory,
                          isPublic: isPublic,
                          emoji: selectedEmoji,
                          imageUrl: selectedBanner,
                        );
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        if (mounted) {
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: _emerald,
                              content: Text('Group details updated!'),
                            ),
                          );
                        }
                      },
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

  void _showAllMembersSheet(TravelGroup g, List<GroupMember> members) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.of(ctx).padding.bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.85,
              ),
              child: Column(
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
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _emerald.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.people_alt_rounded,
                          color: _emerald,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Members Directory (${members.length})',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: _textDark,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: _textMuted,
                        ),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: members.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final m = members[i];
                        return _buildMemberCard(g, m, showActions: true);
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMemberCard(
    TravelGroup g,
    GroupMember m, {
    bool showActions = true,
  }) {
    final isAdmin = m.role == GroupMemberRole.admin;
    final myMob = _service.myHostMobile ?? _service.myRiderMobile;
    final isMe = myMob != null && myMob.isNotEmpty && m.mobile == myMob;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMe ? _emerald.withValues(alpha: 0.04) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMe ? _emerald.withValues(alpha: 0.3) : Colors.grey.shade200,
          width: isMe ? 1.2 : 1,
        ),
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
          // Avatar with status ring
          Stack(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: isAdmin
                      ? const LinearGradient(
                          colors: [Color(0xFF0F9D58), Color(0xFF1B5E20)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : LinearGradient(
                          colors: [Colors.grey.shade300, Colors.grey.shade400],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                ),
                child: Center(
                  child: Text(
                    m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: isAdmin ? Colors.white : Colors.grey.shade800,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.shade700,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),

          // Member Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        m.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _textDark,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: _emerald.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'You',
                          style: TextStyle(
                            fontSize: 10,
                            color: _emerald,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(
                      Icons.privacy_tip_outlined,
                      size: 11,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      'Phone hidden',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '•',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.access_time_rounded,
                      size: 11,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      _formatMemberSince(m.joinedAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Role Badge & Actions
          if (isAdmin)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF81C784), width: 0.8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('👑', style: TextStyle(fontSize: 10)),
                  SizedBox(width: 3),
                  Text(
                    'Admin',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF2E7D32),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            )
          else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Rider',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (_isAdmin && showActions) ...[
              IconButton(
                icon: const Icon(
                  Icons.admin_panel_settings_rounded,
                  color: _emerald,
                  size: 20,
                ),
                tooltip: 'Promote to Admin',
                padding: const EdgeInsets.only(left: 4),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => _confirmTransferAdmin(g, m),
              ),
              IconButton(
                icon: const Icon(
                  Icons.person_remove_rounded,
                  color: Colors.redAccent,
                  size: 18,
                ),
                tooltip: 'Remove Member',
                padding: const EdgeInsets.only(left: 4),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => _confirmRemoveMember(g, m),
              ),
            ],
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = _group;
    if (g == null) {
      return const Scaffold(body: Center(child: Text('Group not found')));
    }

    final approved = g.approvedMembers;
    final pending = g.pendingMembers;
    final groupConvoys = _service.unions
        .where((u) => g.convoyIds.contains(u.id))
        .toList();

    return Scaffold(
      backgroundColor: _bg,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            pinned: true,
            backgroundColor: const Color(0xff0e382d),
            foregroundColor: Colors.white,
            elevation: 0,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(g.emoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    g.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.share_rounded, color: Colors.white70),
                tooltip: 'Share Group Link',
                onPressed: _shareGroupLink,
              ),
              if (_isAdmin)
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.white70,
                  ),
                  tooltip: 'Delete Group',
                  onPressed: _confirmDeleteGroup,
                )
              else if (_isMember)
                IconButton(
                  icon: const Icon(Icons.logout_rounded, color: Colors.white70),
                  tooltip: 'Leave Group',
                  onPressed: _confirmLeaveGroup,
                ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                tooltip: 'Refresh Group',
                onPressed: () async {
                  HapticFeedback.selectionClick();
                  await _service.syncWithFirebase();
                  if (mounted) setState(() {});
                },
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(88),
              child: Container(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage(
                      g.imageUrl.isNotEmpty
                          ? g.imageUrl
                          : UnionService.getRandomScenicBanner(g.id.hashCode),
                    ),
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(
                      const Color(0xff0e382d).withValues(alpha: 0.88),
                      BlendMode.darken,
                    ),
                  ),
                  gradient: const LinearGradient(
                    colors: [Color(0xff0e382d), Color(0xff164e3f)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          _statBubble('${approved.length}', 'Members'),
                          const SizedBox(width: 8),
                          _statBubble('${groupConvoys.length}', 'Convoys'),
                          const SizedBox(width: 8),
                          _statBubble(
                            g.isPublic ? 'Public' : 'Private',
                            g.isPublic ? '🌐' : '🔒',
                          ),
                        ],
                      ),
                    ),
                    TabBar(
                      controller: _tabs,
                      indicatorColor: Colors.greenAccent,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white60,
                      labelStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      tabs: [
                        const Tab(text: 'About'),
                        Tab(
                          text: !g.isPublic && !_isMember ? 'Locked' : 'Chat',
                        ),
                        const Tab(text: 'Convoys'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabs,
          children: [
            // About
            RefreshIndicator(
              color: _emerald,
              onRefresh: () async {
                await _service.syncWithFirebase();
                if (mounted) setState(() {});
              },
              child: _buildAbout(g, approved, pending),
            ),
            // Chat
            _buildChat(g),
            // Convoys
            RefreshIndicator(
              color: _emerald,
              onRefresh: () async {
                await _service.syncWithFirebase();
                if (mounted) setState(() {});
              },
              child: _buildConvoys(g, groupConvoys),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBubble(String value, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    ),
  );

  Widget _buildGroupBanner(TravelGroup g) {
    final bannerPath = g.imageUrl.isNotEmpty
        ? g.imageUrl
        : UnionService.getRandomScenicBanner(g.id.hashCode);

    if (bannerPath.startsWith('assets/')) {
      return Image.asset(bannerPath, fit: BoxFit.cover, cacheWidth: 800);
    }
    return Image.network(
      bannerPath,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Image.asset(
        UnionService.getRandomScenicBanner(g.id.hashCode),
        fit: BoxFit.cover,
        cacheWidth: 800,
      ),
    );
  }

  // About
  Widget _buildAbout(
    TravelGroup g,
    List<GroupMember> approved,
    List<GroupMember> pending,
  ) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final isPending = _service.isGroupPending(g);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 16, 16, 48 + bottomInset),
      children: [
        // ── Top Banner with Scenic Cover & Edit Action ──
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              SizedBox(
                height: 140,
                width: double.infinity,
                child: _buildGroupBanner(g),
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.78),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 12,
                left: 14,
                right: 14,
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white60, width: 1.2),
                      ),
                      child: Text(
                        g.emoji,
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            g.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
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
                          Text(
                            g.category,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_isAdmin)
                      InkWell(
                        onTap: () => _showEditAboutSheet(g),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white38,
                              width: 0.8,
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.edit_rounded,
                                size: 13,
                                color: Colors.white,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Edit',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── About Group Card with Edit Option ──
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: _emerald,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'About Group',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _emerald,
                    ),
                  ),
                  const Spacer(),
                  if (_isAdmin)
                    InkWell(
                      onTap: () => _showEditAboutSheet(g),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _emerald.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.edit_note_rounded,
                              size: 16,
                              color: _emerald,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Edit About',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _emerald,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                g.description.isEmpty
                    ? 'No description yet. Tap "Edit About" to add one!'
                    : g.description,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: _textDark,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _infoPill(Icons.category_rounded, g.category),
                  _infoPill(
                    g.isPublic ? Icons.public_rounded : Icons.lock_rounded,
                    g.isPublic ? 'Public Group' : 'Private Group',
                  ),
                  _infoPill(
                    Icons.calendar_today_rounded,
                    'Created ${_formatDate(g.createdAt)}',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── Pending Join Requests (Admin Only) ──
        if (_isAdmin && pending.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF9E6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.amber.shade300, width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.person_add_rounded,
                        color: Colors.orange.shade900,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Pending Join Requests (${pending.length})',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final m in pending)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: Row(
                      children: [
                        _avatar(
                          m.name,
                          Colors.orange.shade100,
                          Colors.orange.shade800,
                          radius: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.name,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                  color: _textDark,
                                ),
                              ),
                              Text(
                                'Phone hidden for privacy',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.check_circle_rounded,
                            color: Colors.green,
                            size: 28,
                          ),
                          tooltip: 'Approve',
                          onPressed: () =>
                              _service.approveGroupMember(g.id, m.id),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.cancel_rounded,
                            color: Colors.redAccent,
                            size: 28,
                          ),
                          tooltip: 'Decline',
                          onPressed: () =>
                              _service.rejectGroupMember(g.id, m.id),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        // ── Modernized Community Members Section ──
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _emerald.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.groups_rounded,
                      color: _emerald,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Community Members (${approved.length})',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _textDark,
                    ),
                  ),
                  const Spacer(),
                  if (approved.length > 5)
                    GestureDetector(
                      onTap: () => _showAllMembersSheet(g, approved),
                      child: const Text(
                        'View All',
                        style: TextStyle(
                          color: _emerald,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              for (final m in approved.take(5))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildMemberCard(g, m, showActions: true),
                ),
              if (approved.length > 5)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _emerald,
                        side: BorderSide(
                          color: _emerald.withValues(alpha: 0.4),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: () => _showAllMembersSheet(g, approved),
                      child: Text(
                        'View All ${approved.length} Members',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (isPending) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade300, width: 1.2),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.hourglass_top_rounded,
                  color: Colors.amber.shade900,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  '⏳ Join Request Pending Approval',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade900,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              icon: const Icon(
                Icons.cancel_outlined,
                size: 16,
                color: Colors.redAccent,
              ),
              label: const Text(
                'Cancel Request',
                style: TextStyle(color: Colors.redAccent),
              ),
              onPressed: _confirmLeaveGroup,
            ),
          ),
        ] else if (!_isMember) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _emerald,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: Icon(
                g.isPublic ? Icons.group_add_rounded : Icons.lock_open_rounded,
                size: 18,
              ),
              label: Text(
                g.isPublic ? 'Join Group' : 'Request to Join',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: _showJoinSheet,
            ),
          ),
        ] else if (!_isAdmin) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: BorderSide(
                  color: Colors.redAccent.withValues(alpha: 0.5),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text(
                'Leave Group',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: _confirmLeaveGroup,
            ),
          ),
        ],
        SizedBox(height: 24 + MediaQuery.of(context).padding.bottom),
      ],
    );
  }

  // ── Chat ───────────────────────────────────────────────────────────────────

  Widget _buildChat(TravelGroup g) {
    if (!g.isPublic && !_isMember) {
      final isPending = _service.isGroupPending(g);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: const BoxDecoration(
                  color: Color(0xFFEFF6F3),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPending ? Icons.hourglass_top_rounded : Icons.lock_rounded,
                  size: 38,
                  color: isPending ? Colors.amber.shade800 : _emerald,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                isPending ? 'Request Pending Approval' : 'Private Group Chat',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _textDark,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isPending
                    ? 'Your join request was sent to the group admin. Once approved, group chat will open automatically!'
                    : 'Join request approval is required before chat messages are visible.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: _textMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              if (isPending)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                  ),
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text(
                    'Cancel Request',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: _confirmLeaveGroup,
                )
              else
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _emerald,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                  ),
                  icon: const Icon(Icons.lock_open_rounded, size: 16),
                  label: const Text(
                    'Request to Join',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: _showJoinSheet,
                ),
            ],
          ),
        ),
      );
    }

    final msgs = g.chatMessages;
    final media = MediaQuery.of(context);
    final double navBarHeight = math.max(
      48.0,
      math.max(media.padding.bottom, media.viewPadding.bottom),
    );
    final bool isKeyboardOpen = media.viewInsets.bottom > 20;
    final double chatBottomPad = isKeyboardOpen ? 8.0 : (12.0 + navBarHeight);

    return Column(
      children: [
        Expanded(
          child: msgs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 48,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'No messages yet.',
                        style: TextStyle(color: Colors.grey.shade400),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _chatScroll,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) {
                    final m = msgs[i];
                    final isMe = m.senderId == _service.myDeviceId;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        mainAxisAlignment: isMe
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (!isMe) ...[
                            _avatar(
                              m.senderName,
                              m.isAdmin
                                  ? const Color(0xffd4edda)
                                  : Colors.grey.shade100,
                              m.isAdmin ? _emerald : _textMuted,
                              radius: 14,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Column(
                            crossAxisAlignment: isMe
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              if (!isMe)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 4,
                                    bottom: 2,
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        m.senderName,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: m.isAdmin
                                              ? _emerald
                                              : _textMuted,
                                          fontWeight: m.isAdmin
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                      if (m.isAdmin) ...[
                                        const SizedBox(width: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _emerald,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: const Text(
                                            'Admin',
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
                                ),
                              GestureDetector(
                                onLongPress: (isMe || _isAdmin)
                                    ? () => _confirmDeleteGroupMessage(m)
                                    : null,
                                child: Container(
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(context).size.width *
                                        0.68,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 9,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isMe ? _emerald : Colors.white,
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(14),
                                      topRight: const Radius.circular(14),
                                      bottomLeft: Radius.circular(
                                        isMe ? 14 : 2,
                                      ),
                                      bottomRight: Radius.circular(
                                        isMe ? 2 : 14,
                                      ),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.05,
                                        ),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    m.text,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      color: isMe ? Colors.white : _textDark,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 3,
                                  left: 4,
                                  right: 4,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _fmtTime(m.timestamp),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: _textMuted,
                                      ),
                                    ),
                                    if (isMe || _isAdmin) ...[
                                      const SizedBox(width: 4),
                                      GestureDetector(
                                        onTap: () =>
                                            _confirmDeleteGroupMessage(m),
                                        child: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 13,
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        if (_isMember)
          Container(
            padding: EdgeInsets.fromLTRB(12, 8, 8, chatBottomPad),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade100)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatCtrl,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: const TextStyle(
                        color: _textMuted,
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: const Color(0xfff1f5f3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 16,
                      ),
                    ),
                    onSubmitted: (_) => _sendChat(),
                  ),
                ),
                const SizedBox(width: 6),
                Material(
                  color: _emerald,
                  shape: const CircleBorder(),
                  child: InkWell(
                    onTap: _sendChat,
                    customBorder: const CircleBorder(),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 12 + navBarHeight),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade100)),
            ),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _emerald,
                  side: const BorderSide(color: _emerald),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.group_add_rounded, size: 16),
                label: const Text(
                  'Join to participate in chat',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                onPressed: _showJoinSheet,
              ),
            ),
          ),
      ],
    );
  }

  // ── Convoys ────────────────────────────────────────────────────────────────

  Future<void> _showEditConvoySheet(TravelUnionGroup convoy) async {
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditConvoySheet(convoy: convoy, service: _service),
    );
    if (updated == true && mounted) {
      setState(() {});
    }
  }

  Widget _buildConvoys(TravelGroup g, List<TravelUnionGroup> convoys) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (_isAdmin || _isMember)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _emerald,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                icon: const Icon(Icons.add_road_rounded, size: 18),
                label: const Text(
                  'Create Convoy for Group',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: _showCreateConvoySheet,
              ),
            ),
          ),
        if (convoys.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Column(
                children: [
                  Icon(
                    Icons.route_rounded,
                    size: 52,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isAdmin
                        ? 'No convoys yet.\nTap "Create Convoy" to plan one!'
                        : 'No convoys posted yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade500, height: 1.5),
                  ),
                ],
              ),
            ),
          )
        else
          for (final convoy in convoys)
            _ConvoyMiniCard(
              convoy: convoy,
              canEdit: _isAdmin || _service.canEditConvoy(convoy),
              canDelete: _isAdmin || _service.canEditConvoy(convoy),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ConvoyDetailsScreen(unionId: convoy.id),
                  ),
                );
              },
              onEdit: () => _showEditConvoySheet(convoy),
              onDelete: () => _confirmDeleteConvoy(convoy),
              onTogglePublicity: _isAdmin
                  ? () => _toggleConvoyPublicity(convoy)
                  : null,
            ),
      ],
    );
  }

  String _fmtTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ─── Mini Convoy Card with scenic banner & route preview ─────────────────────

class _ConvoyMiniCard extends StatelessWidget {
  final TravelUnionGroup convoy;
  final VoidCallback onTap;
  final bool canEdit;
  final VoidCallback? onEdit;
  final bool canDelete;
  final VoidCallback? onDelete;
  final VoidCallback? onTogglePublicity;

  const _ConvoyMiniCard({
    required this.convoy,
    required this.onTap,
    this.canEdit = false,
    this.onEdit,
    this.canDelete = false,
    this.onDelete,
    this.onTogglePublicity,
  });

  @override
  Widget build(BuildContext context) {
    final u = convoy;
    final bannerPath = u.imageUrl.isNotEmpty
        ? u.imageUrl
        : UnionService.getRandomScenicBanner(u.id.hashCode);

    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child: Stack(
                  children: [
                    SizedBox(
                      height: 110,
                      width: double.infinity,
                      child: bannerPath.startsWith('assets/')
                          ? Image.asset(
                              bannerPath,
                              fit: BoxFit.cover,
                              cacheWidth: 600,
                            )
                          : Image.network(
                              bannerPath,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Image.asset(
                                UnionService.getRandomScenicBanner(
                                  u.id.hashCode,
                                ),
                                fit: BoxFit.cover,
                                cacheWidth: 600,
                              ),
                            ),
                    ),
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.black.withValues(alpha: 0.35),
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.8),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          u.statusTag,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: u.isPublicFeed
                              ? const Color(0xff10b981).withValues(alpha: 0.9)
                              : Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              u.isPublicFeed
                                  ? Icons.public_rounded
                                  : Icons.lock_outline_rounded,
                              size: 11,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              u.isPublicFeed ? 'Public' : 'Group Only',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 7,
                      left: 10,
                      right: 10,
                      child: Row(
                        children: [
                          const Icon(
                            Icons.place_rounded,
                            color: Colors.greenAccent,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              u.fromLocation,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white70,
                              size: 12,
                            ),
                          ),
                          Flexible(
                            child: Text(
                              u.toLocation,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            u.title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: _textDark,
                            ),
                          ),
                        ),
                        if (canEdit && onEdit != null) ...[
                          Tooltip(
                            message: 'Edit Convoy',
                            child: InkWell(
                              onTap: onEdit,
                              borderRadius: BorderRadius.circular(12),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(
                                  Icons.edit_rounded,
                                  size: 19,
                                  color: _emerald,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        if (canDelete && onTogglePublicity != null)
                          Tooltip(
                            message: u.isPublicFeed
                                ? 'Make Group Only'
                                : 'Make Public in Convoys Tab',
                            child: InkWell(
                              onTap: onTogglePublicity,
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  u.isPublicFeed
                                      ? Icons.public_rounded
                                      : Icons.public_off_rounded,
                                  size: 19,
                                  color: u.isPublicFeed
                                      ? _emerald
                                      : Colors.grey,
                                ),
                              ),
                            ),
                          ),
                        if (canDelete && onDelete != null) ...[
                          const SizedBox(width: 4),
                          Tooltip(
                            message: 'Delete Convoy',
                            child: InkWell(
                              onTap: onDelete,
                              borderRadius: BorderRadius.circular(12),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(
                                  Icons.delete_outline_rounded,
                                  size: 19,
                                  color: Colors.redAccent,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _pill(Icons.calendar_today_rounded, u.departureDateStr),
                        const SizedBox(width: 8),
                        _pill(Icons.timer_rounded, u.estimatedDuration),
                        const SizedBox(width: 8),
                        _pill(
                          Icons.group_rounded,
                          '${u.acceptedMembers.length}/${u.maxMembers} Riders',
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
  }

  Widget _pill(IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 11, color: _emerald),
      const SizedBox(width: 3),
      Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          color: _textMuted,
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  );
}

// ─── Create Group Convoy Sheet ────────────────────────────────────────────────

class _CreateGroupConvoySheet extends StatefulWidget {
  final TravelGroup group;
  final UnionService service;
  const _CreateGroupConvoySheet({required this.group, required this.service});

  @override
  State<_CreateGroupConvoySheet> createState() =>
      _CreateGroupConvoySheetState();
}

class _CreateGroupConvoySheetState extends State<_CreateGroupConvoySheet> {
  final _titleCtrl = TextEditingController();
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  final _highwayCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  VehicleCategory _cat = VehicleCategory.bike;
  bool _isPublicFeed = false;
  late String _selectedBanner;
  bool _isSubmitting = false;

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
        data: Theme.of(ctx)
            .copyWith(colorScheme: const ColorScheme.light(primary: _emerald)),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 6, minute: 0),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx)
            .copyWith(colorScheme: const ColorScheme.light(primary: _emerald)),
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

  Future<void> _create() async {
    if (_titleCtrl.text.trim().isEmpty ||
        _fromCtrl.text.trim().isEmpty ||
        _toCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill title, from, and to locations.'),
        ),
      );
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

    setState(() => _isSubmitting = true);

    final admin = widget.group.admins.firstOrNull;
    final myName = admin?.name.isNotEmpty == true ? admin!.name : 'Rider Host';
    final myMobile = widget.service.myHostMobile?.isNotEmpty == true
        ? widget.service.myHostMobile!
        : (widget.service.myRiderMobile?.isNotEmpty == true
              ? widget.service.myRiderMobile!
              : (admin?.mobile.isNotEmpty == true
                    ? admin!.mobile
                    : '+91 99000 00000'));

    try {
      final convoy = await widget.service.createUnion(
        title: _titleCtrl.text.trim(),
        fromLocation: _fromCtrl.text.trim(),
        toLocation: _toCtrl.text.trim(),
        viaHighway: _highwayCtrl.text.trim(),
        departureDateStr: _dateCtrl.text.trim().isEmpty
            ? 'TBD'
            : _dateCtrl.text.trim(),
        category: _cat,
        hostName: myName,
        hostMobile: myMobile,
        hostEmail: googleUser.email,
        hostVehicle: _cat.shortLabel,
        description: _descCtrl.text.trim(),
        isPublicFeed: _isPublicFeed,
        imageUrl: _selectedBanner,
      );
      await widget.service.linkConvoyToGroup(widget.group.id, convoy.id);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: _emerald,
            content: Text(
              'Convoy created with scenic banner & linked to group!',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error creating convoy: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final navPad = math.max(
      48.0,
      math.max(media.padding.bottom, media.viewPadding.bottom),
    );
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
              const Text(
                'Create Group Convoy',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: _textDark,
                ),
              ),
              const SizedBox(height: 14),

              // Live Banner Preview
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
                        'Attached Cover Banner',
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

              // Scenic Banner Selector
              const Text(
                'Choose Cover Banner',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _textDark,
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
                    final b = UnionService.defaultScenicBanners[i];
                    final isSel = b == _selectedBanner;
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedBanner = b);
                      },
                      child: Container(
                        width: 80,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSel ? _emerald : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.asset(
                                b,
                                fit: BoxFit.cover,
                                cacheWidth: 200,
                              ),
                              if (isSel)
                                Container(
                                  color: _emerald.withValues(alpha: 0.35),
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
              const SizedBox(height: 14),

              _f(_titleCtrl, 'Convoy Title', Icons.flag_rounded),
              const SizedBox(height: 10),
              _f(
                _fromCtrl,
                'From (City / Location)',
                Icons.trip_origin_rounded,
              ),
              const SizedBox(height: 10),
              _f(_toCtrl, 'To (City / Location)', Icons.location_on_rounded),
              const SizedBox(height: 10),
              _f(
                _highwayCtrl,
                'Via Highway (optional, e.g. NH 48)',
                Icons.alt_route_rounded,
              ),
              const SizedBox(height: 10),
              _f(
                _dateCtrl,
                'Departure Date & Time',
                Icons.calendar_today_rounded,
                readOnly: true,
                onTap: _pickDateTime,
              ),
              const SizedBox(height: 10),
              _f(
                _descCtrl,
                'Description (optional)',
                Icons.description_rounded,
                maxLines: 2,
              ),
              const SizedBox(height: 10),
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
                  prefixIcon: const Icon(
                    Icons.directions_car_rounded,
                    color: _emerald,
                    size: 18,
                  ),
                ),
                items: VehicleCategory.values
                    .map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(
                          c.shortLabel,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _cat = v ?? _cat),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xfff1f5f3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isPublicFeed
                          ? Icons.public_rounded
                          : Icons.lock_outline_rounded,
                      size: 20,
                      color: _isPublicFeed ? _emerald : Colors.grey,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Show in Public Convoys Tab',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _textDark,
                            ),
                          ),
                          Text(
                            _isPublicFeed
                                ? 'Visible to everyone in Convoys tab'
                                : 'Only visible to members inside this group',
                            style: const TextStyle(
                              fontSize: 11,
                              color: _textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      activeTrackColor: _emerald,
                      value: _isPublicFeed,
                      onChanged: (val) => setState(() => _isPublicFeed = val),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _emerald,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.add_road_rounded, size: 18),
                  label: Text(
                    _isSubmitting ? 'Creating Convoy...' : 'Create Convoy',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: _isSubmitting ? null : _create,
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
  }) => TextField(
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

// ─── Shared helpers ────────────────────────────────────────────────────────────

Widget _card({required Widget child}) => Container(
  width: double.infinity,
  padding: const EdgeInsets.all(14),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(14),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.05),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ],
  ),
  child: child,
);

Widget _avatar(String name, Color bg, Color fg, {double radius = 17}) =>
    CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.8,
        ),
      ),
    );

Widget _infoPill(IconData icon, String label) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  decoration: BoxDecoration(
    color: _emerald.withValues(alpha: 0.08),
    borderRadius: BorderRadius.circular(20),
  ),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 12, color: _emerald),
      const SizedBox(width: 4),
      Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          color: _emerald,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  ),
);
