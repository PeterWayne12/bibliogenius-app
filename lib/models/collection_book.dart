class CollectionBook {
  final int bookId;
  final String title;
  final String? author;
  final String? coverUrl;
  final DateTime addedAt;
  final bool isOwned;

  CollectionBook({
    required this.bookId,
    required this.title,
    this.author,
    this.coverUrl,
    required this.addedAt,
    required this.isOwned,
  });

  factory CollectionBook.fromJson(Map<String, dynamic> json) {
    return CollectionBook(
      bookId: json['book_id'],
      title: json['title'],
      author: json['author'],
      coverUrl: json['cover_url'],
      addedAt: DateTime.parse(json['added_at']),
      isOwned: json['is_owned'] ?? false,
    );
  }
}
