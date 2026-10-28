import 'package:flutter/material.dart';

import '../background.dart';
import '../models/app_user.dart';
import '../models/item.dart';
import '../services/auth_service.dart';
import '../services/item_service.dart';
import '../services/match_watcher.dart';
import '../services/notifier.dart';
import '../services/search_history.dart';
import '../theme.dart';
import '../widgets/ai_widgets.dart';
import '../widgets/animations.dart';
import '../widgets/item_card.dart';
import '../widgets/item_list.dart';
import 'item_form.dart';

class UserHome extends StatefulWidget {
  const UserHome({super.key, required this.user});
  final AppUser user;

  @override
  State<UserHome> createState() => _UserHomeState();
}

class _UserHomeState extends State<UserHome> {
  int _tab = 0;
  late final _myItems = ItemService.instance.itemsOf(widget.user.uid);
  late final _allItems = ItemService.instance.allItems();
  late final _history = SearchHistory(widget.user.uid);

  @override
  void initState() {
    super.initState();
    _startWatching();
  }

  /// Notification permission, the periodic background job, and a first check now.
  Future<void> _startWatching() async {
    await Notifier.requestPermission();
    await scheduleBackgroundChecks();
    await MatchWatcher.run();
  }

  /// Progress of a found item, without revealing who claimed it.
  Widget? _claimFooter(Item item) {
    if (item.isLost) return null;
    final (icon, text, color) = switch (item.claimStatus) {
      'claimed' => ('🎉', 'Claimed by its owner. Thank you for handing it in!', foundColor),
      'review' => ('⏳', 'Someone claimed this item. The admin is verifying it.', aiColor),
      _ when item.isProtected => ('🛡', 'Protected: AI and the admin check anyone who claims this item.', aiColor),
      _ => (null, null, null),
    };
    if (text == null) return null;
    return Text('$icon $text', style: TextStyle(color: color, fontSize: 13));
  }

  Future<void> _delete(String id) async {
    if (!await confirmDialog(context, 'Delete this item?')) return;
    await ItemService.instance.delete(id);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item deleted.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MyRecover'),
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
          FilteredItemList(
            stream: _myItems,
            emptyText: "You haven't reported any items yet",
            itemBuilder: (context, item) => ItemCard(
              item: item,
              footer: _claimFooter(item),
              actions: [
                TextButton.icon(
                  onPressed: () => showMatches(context, item, widget.user),
                  style: TextButton.styleFrom(foregroundColor: aiColor),
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: Text(item.isLost ? 'Find matches' : 'Find owner'),
                ),
                TextButton.icon(
                  onPressed: () => _delete(item.id),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Delete'),
                ),
              ],
            ),
          ),
          FilteredItemList(
            stream: _allItems,
            emptyText: 'No items to discover',
            history: _history,
            aiSearch: true,
            itemBuilder: (context, item) => ItemCard(
              item: item,
              actions: [if (item.userId != widget.user.uid) contactAction(context, item, widget.user)],
            ),
          ),
          ItemForm(
            user: widget.user,
            onSaved: () {
              setState(() => _tab = 0);
              MatchWatcher.run();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item reported successfully!')));
            },
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          setState(() => _tab = i);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'My Items'),
          NavigationDestination(icon: Icon(Icons.explore_outlined), label: 'Discover'),
          NavigationDestination(icon: Icon(Icons.add_circle_outline), label: 'Report Item'),
        ],
      ),
    );
  }
}
