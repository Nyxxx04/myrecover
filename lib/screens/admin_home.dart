import 'package:flutter/material.dart';

import '../background.dart';

import '../models/app_user.dart';
import '../models/item.dart';
import '../services/auth_service.dart';
import '../services/claim_service.dart';
import '../services/item_service.dart';
import '../services/match_watcher.dart';
import '../services/notifier.dart';
import '../theme.dart';
import '../widgets/ai_widgets.dart';
import '../widgets/item_card.dart';
import '../widgets/item_list.dart';
import 'admin_claims.dart';
import 'admin_edit_screen.dart';
import 'item_form.dart';
import '../widgets/animations.dart';

class AdminHome extends StatefulWidget {
  const AdminHome({super.key, required this.user});
  final AppUser user;

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _tab = 0;
  // One Firestore listener per tab; a shared broadcast stream would not
  // replay the latest snapshot to tabs that subscribe later.
  late final _statsItems = ItemService.instance.allItems();
  late final _manageItems = ItemService.instance.allItems();
  late final _returnedCount = ItemService.instance.returnedCount();
  late final _claimItems = ItemService.instance.allItems();
  late final _claims = ClaimService.instance.allClaims().asBroadcastStream();
  late final _badgeItems = ItemService.instance.allItems();

  @override
  void initState() {
    super.initState();
    _startWatching();
  }

  /// Admins can report found items too, so their phone also judges claims
  /// and gets match notifications (now and in the background).
  Future<void> _startWatching() async {
    await Notifier.requestPermission();
    await scheduleBackgroundChecks();
    await MatchWatcher.run();
  }

  Future<void> _delete(Item item) async {
    if (!await confirmDialog(context, 'Delete ${item.title}?')) return;
    await ItemService.instance.delete(item.id);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item deleted.')));
  }

  void _addItem() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (routeContext) => Scaffold(
          appBar: AppBar(title: const Text('Add New Item')),
          body: ItemForm(
            user: widget.user,
            submitLabel: 'Add Item',
            onSaved: () {
              Navigator.pop(routeContext);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item added successfully!')));
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MyRecover Admin'),
        actions: [
          Center(
            child: Text(widget.user.username, style: const TextStyle(color: Colors.white70)),
          ),
          IconButton(tooltip: 'Log out', icon: const Icon(Icons.logout), onPressed: AuthService.instance.logout),
        ],
      ),
      body: FadeIndexedStack(
        index: _tab,
        children: [
          _Dashboard(stream: _statsItems, returned: _returnedCount),
          FilteredItemList(
            stream: _manageItems,
            aiSearch: true,
            emptyText: 'No items yet',
            header: PressScale(
              child: OutlinedButton.icon(
                onPressed: () => showModeration(context),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  foregroundColor: Colors.deepOrange,
                  side: const BorderSide(color: Colors.deepOrange),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.policy_outlined),
                label: const Text('Check for fake reports'),
              ),
            ),
            itemBuilder: (context, item) => ItemCard(
              item: item,
              showReporter: true,
              showStatus: true,
              actions: [
                TextButton.icon(
                  onPressed: () =>
                      Navigator.push(context, MaterialPageRoute(builder: (_) => AdminEditScreen(item: item))),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                ),
                TextButton.icon(
                  onPressed: () => _delete(item),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Delete'),
                ),
              ],
            ),
          ),
          AdminClaims(claims: _claims, items: _claimItems),
        ],
      ),
      floatingActionButton: _tab == 1
          ? FloatingActionButton.extended(
              onPressed: _addItem,
              icon: const Icon(Icons.add),
              label: const Text('Add Item'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
          const NavigationDestination(icon: Icon(Icons.list_alt), label: 'Manage'),
          NavigationDestination(
            // Claims awaiting a decision on reports that are still open.
            icon: StreamBuilder<List<Item>>(
              stream: _badgeItems,
              builder: (context, items) => StreamBuilder<List<Claim>>(
                stream: _claims,
                builder: (context, claims) {
                  final open = {for (final i in items.data ?? <Item>[]) i.id};
                  final count = (claims.data ?? []).where((c) => c.awaitsAdmin && open.contains(c.itemId)).length;
                  return Badge(
                    isLabelVisible: count > 0,
                    label: Text('$count'),
                    child: const Icon(Icons.shield_outlined),
                  );
                },
              ),
            ),
            label: 'Claims',
          ),
        ],
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.stream, required this.returned});
  final Stream<List<Item>> stream;
  final Stream<int> returned;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Item>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Could not load stats.\n${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final items = snap.data!;
        final lost = items.where((i) => i.type == 'lost').length;
        final found = items.where((i) => i.type == 'found').length;

        return StreamBuilder<int>(
          stream: returned,
          builder: (context, returnedSnap) {
            final returned = returnedSnap.data ?? 0;
            final stats = [
              ('Lost Items', 'still missing', lost, lostColor),
              ('Found Items', 'waiting for owner', found, foundColor),
              ('Returned', 'back with owner', returned, pendingColor),
              ('Total Active', 'lost + found', items.length, brandGreen),
            ];
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.25,
                  children: [
                    for (final (i, (label, hint, count, color)) in stats.indexed)
                      AnimatedEntry(
                        index: i,
                        child: Card(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(label, style: const TextStyle(color: Colors.grey)),
                                const SizedBox(height: 6),
                                CountUp(
                                  count,
                                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: color),
                                ),
                                Text(hint, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                AnimatedEntry(
                  index: 4,
                  child: _BreakdownCard(lost: lost, found: found, returned: returned),
                ),
                const SizedBox(height: 12),
                AnimatedEntry(
                  index: 5,
                  child: AiInsightsCard(items: items, returned: returned),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// One bar split by lost / found / returned, so the proportions read at a glance.
class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.lost, required this.found, required this.returned});
  final int lost;
  final int found;
  final int returned;

  @override
  Widget build(BuildContext context) {
    final parts = [('Lost', lost, lostColor), ('Found', found, foundColor), ('Returned', returned, pendingColor)];
    final total = lost + found + returned;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Breakdown', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 14,
                child: ColoredBox(
                  color: const Color(0xFFE5E7EB),
                  child: LayoutBuilder(
                    builder: (context, box) => Row(
                      children: [
                        // Segments grow from zero to their share of the bar.
                        for (final (_, count, color) in parts)
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: total == 0 ? 0 : count / total),
                            duration: motionSlow,
                            curve: Curves.easeOutCubic,
                            builder: (context, f, _) => Container(width: box.maxWidth * f, color: color),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            for (final (label, count, color) in parts)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(label)),
                    Text(
                      total == 0 ? '0%' : '${(count * 100 / total).round()}%  ($count)',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
