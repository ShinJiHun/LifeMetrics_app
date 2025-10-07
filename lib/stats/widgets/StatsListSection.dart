import 'package:flutter/material.dart';

class StatsListSection extends StatelessWidget {
  final String latestActivityDate;
  final double totalDistance;

  const StatsListSection({
    super.key,
    required this.latestActivityDate,
    required this.totalDistance,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _ListItem(icon: Icons.subscriptions, title: "Subscription overview"),
        _ListItem(icon: Icons.timeline, title: "Activities", subtitle: latestActivityDate),
        _ListItem(
          icon: Icons.bar_chart,
          title: "Statistics",
          subtitle: "This year: ${totalDistance.toStringAsFixed(1)} km",
        ),
        const _ListItem(icon: Icons.route, title: "Routes", subtitle: "2"),
        const _ListItem(icon: Icons.place, title: "Segments"),
        const _ListItem(icon: Icons.emoji_events, title: "Best Efforts", subtitle: "See All"),
        const _ListItem(icon: Icons.article_outlined, title: "Posts"),
      ],
    );
  }
}

class _ListItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const _ListItem({required this.icon, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.black87),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: subtitle != null
          ? Text(subtitle!, style: TextStyle(color: Colors.grey[600]))
          : null,
      trailing: const Icon(Icons.chevron_right),
    );
  }
}
