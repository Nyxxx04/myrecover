import 'package:flutter/material.dart';

import '../screens/inbox_screen.dart';
import '../services/auth_service.dart';
import '../services/inbox_service.dart';
import '../theme.dart';

enum _MenuAction { notifications, theme, logout }

/// Three-line menu for the app bar. A white number on the icon counts unread
/// notifications.
class AppMenu extends StatefulWidget {
  const AppMenu({super.key, required this.uid});
  final String uid;

  @override
  State<AppMenu> createState() => _AppMenuState();
}

class _AppMenuState extends State<AppMenu> {
  late final _entries = InboxService.instance.entries(widget.uid);

  void _select(_MenuAction action) {
    switch (action) {
      case _MenuAction.notifications:
        Navigator.push(context, MaterialPageRoute(builder: (_) => InboxScreen(uid: widget.uid)));
      case _MenuAction.theme:
        toggleThemeMode();
      case _MenuAction.logout:
        AuthService.instance.logout();
    }
  }

  PopupMenuItem<_MenuAction> _item(_MenuAction value, IconData icon, String label) => PopupMenuItem(
    value: value,
    child: Row(
      children: [
        // App bar icons are white; these sit on the menu's light background.
        Icon(icon, size: 22, color: Theme.of(context).colorScheme.onSurface),
        const SizedBox(width: 14),
        Text(label),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => StreamBuilder<List<InboxEntry>>(
    stream: _entries,
    builder: (context, snap) {
      final unread = (snap.data ?? const <InboxEntry>[]).where((e) => !e.read).length;
      final dark = context.isDark;
      return PopupMenuButton<_MenuAction>(
        tooltip: 'Menu',
        onSelected: _select,
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        icon: Badge(
          isLabelVisible: unread > 0,
          backgroundColor: Colors.red,
          textColor: Colors.white,
          label: Text(unread > 9 ? '9+' : '$unread'),
          child: const Icon(Icons.menu),
        ),
        itemBuilder: (_) => [
          _item(
            _MenuAction.notifications,
            Icons.notifications_outlined,
            unread > 0 ? 'Notifications ($unread)' : 'Notifications',
          ),
          _item(
            _MenuAction.theme,
            dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            dark ? 'Light mode' : 'Dark mode',
          ),
          _item(_MenuAction.logout, Icons.logout, 'Log out'),
        ],
      );
    },
  );
}
