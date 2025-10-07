class Post {
  final String userName;
  final String userAvatarUrl;
  final String imageUrl;
  final String location;
  final String caption;
  final int likes;

  const Post({
    required this.userName,
    required this.userAvatarUrl,
    required this.imageUrl,
    required this.location,
    required this.caption,
    required this.likes,
  });
}
