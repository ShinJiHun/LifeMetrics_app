import 'dart:math';

import 'package:flutter/material.dart';

import '../models/Post.dart';

class PostCard extends StatelessWidget {
  final Post post;
  const PostCard({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(userName: post.userName, avatarUrl: post.userAvatarUrl, location: post.location),
          _Image(imageUrl: post.imageUrl),
          const SizedBox(height: 8),
          const _ActionRow(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${post.likes} likes', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 6),
                RichText(
                  text: TextSpan(
                    style: Theme.of(context).textTheme.bodyMedium,
                    children: [
                      TextSpan(text: post.userName, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const TextSpan(text: '  '),
                      TextSpan(text: post.caption),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class _Header extends StatelessWidget {
  final String userName;
  final String avatarUrl;
  final String location;
  const _Header({required this.userName, required this.avatarUrl, required this.location});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              CircleAvatar(radius: 20, backgroundImage: NetworkImage(avatarUrl)),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(userName, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(location, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz),
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

class _Image extends StatelessWidget {
  final String imageUrl;
  const _Image({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Ink.image(
        image: NetworkImage(imageUrl),
        fit: BoxFit.cover,
        child: InkWell(onTap: () {}),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      width: MediaQuery.of(context).size.width,
      color: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(onPressed: () {}, icon: const Icon(Icons.favorite_border)),
              IconButton(onPressed: () {}, icon: const Icon(Icons.chat_outlined)),
              IconButton(onPressed: () {}, icon: const Icon(Icons.send)),
            ],
          ),
          IconButton(onPressed: () {}, icon: const Icon(Icons.bookmark_border)),
        ],
      ),
    );
  }
}
