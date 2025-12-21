import 'package:dio/dio.dart';

class OpenLibraryBook {
  final String title;
  final String author;
  final String? isbn;
  final String? publisher;
  final int? year;
  final String? coverUrl;
  final String? key;
  final String? summary;

  OpenLibraryBook({
    required this.title,
    required this.author,
    this.isbn,
    this.publisher,
    this.year,
    this.coverUrl,
    this.key,
    this.summary,
  });

  factory OpenLibraryBook.fromJson(Map<String, dynamic> json) {
    // Extract author
    String author = 'Unknown Author';
    if (json['author_name'] != null &&
        (json['author_name'] as List).isNotEmpty) {
      author = json['author_name'][0];
    }

    // Extract ISBN (prefer 13, then 10)
    String? isbn;
    if (json['isbn'] != null && (json['isbn'] as List).isNotEmpty) {
      isbn = json['isbn'][0];
    }

    // Extract Publisher
    String? publisher;
    if (json['publisher'] != null && (json['publisher'] as List).isNotEmpty) {
      publisher = json['publisher'][0];
    }

    // Extract Year
    int? year;
    if (json['first_publish_year'] != null) {
      year = json['first_publish_year'];
    }

    // Extract Cover
    String? coverUrl;
    if (json['cover_i'] != null) {
      coverUrl = 'https://covers.openlibrary.org/b/id/${json['cover_i']}-L.jpg';
    }

    return OpenLibraryBook(
      title: json['title'] ?? 'Unknown Title',
      author: author,
      isbn: isbn,
      publisher: publisher,
      year: year,
      coverUrl: coverUrl,
      key: json['key'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'author': author,
      'isbn': isbn,
      'publisher': publisher,
      'publication_year': year?.toString(),
      'cover_url': coverUrl,
      'key': key,
    };
  }
}

class OpenLibraryService {
  final Dio _dio = Dio();
  final String _baseUrl = 'https://openlibrary.org';

  Future<List<OpenLibraryBook>> searchBooks(String query) async {
    if (query.length < 3) return [];

    try {
      final response = await _dio.get(
        '$_baseUrl/search.json',
        queryParameters: {
          'q': query,
          'limit': 10,
          'fields':
              'title,author_name,isbn,publisher,first_publish_year,cover_i,key',
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['docs'] != null) {
          return (data['docs'] as List)
              .map((doc) => OpenLibraryBook.fromJson(doc))
              .toList();
        }
      }
      return [];
    } catch (e) {
      print('Error searching Open Library: $e');
      // Fallback to Inventaire.io when Open Library fails
      return _searchInventaireFallback(query);
    }
  }

  /// Fallback search using Inventaire.io when Open Library is unavailable
  Future<List<OpenLibraryBook>> _searchInventaireFallback(String query) async {
    try {
      print('Falling back to Inventaire.io for search...');
      final response = await _dio.get(
        'https://inventaire.io/api/search',
        queryParameters: {
          'types': 'works',
          'search': query,
          'limit': 10,
          'lang': 'en',
        },
      );

      if (response.statusCode == 200) {
        final results = response.data['results'] as List? ?? [];
        return results.map((item) {
          final label = item['label'] as String? ?? 'Unknown Title';
          final description = item['description'] as String?;
          final uri = item['uri'] as String?;

          // Inventaire doesn't return author in search results directly
          // but description often contains author info
          String author = 'Unknown Author';
          if (description != null && description.contains(' by ')) {
            author = description.split(' by ').last.trim();
          }

          // Inventaire uses Wikidata-style entity URIs
          String? coverUrl;
          if (uri != null) {
            coverUrl = 'https://inventaire.io/img/entities/$uri';
          }

          return OpenLibraryBook(
            title: label,
            author: author,
            isbn: null,
            publisher: null,
            year: null,
            coverUrl: coverUrl,
            key: uri,
          );
        }).toList();
      }
      return [];
    } catch (e) {
      print('Inventaire fallback also failed: $e');
      return [];
    }
  }

  Future<OpenLibraryBook?> lookupByIsbn(String isbn) async {
    try {
      // 1. Try OpenLibrary first
      final response = await _dio.get(
        '$_baseUrl/isbn/${isbn.replaceAll(RegExp(r'[^0-9X]'), '')}.json',
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      if (response.statusCode == 200) {
        final data = response.data;

        // Extract basic info
        String title = data['title'] ?? 'Unknown Title';
        String? publisher;
        int? year;
        String? coverUrl;

        // Extract publishers
        if (data['publishers'] != null &&
            (data['publishers'] as List).isNotEmpty) {
          publisher = data['publishers'][0];
        }

        // Extract publish date and parse year
        if (data['publish_date'] != null) {
          final publishDate = data['publish_date'] as String;
          final yearMatch = RegExp(r'\d{4}').firstMatch(publishDate);
          if (yearMatch != null) {
            year = int.tryParse(yearMatch.group(0)!);
          }
        }

        // Get cover from cover IDs
        if (data['covers'] != null && (data['covers'] as List).isNotEmpty) {
          final coverId = data['covers'][0];
          coverUrl = 'https://covers.openlibrary.org/b/id/$coverId-L.jpg';
        }

        // Extract author
        String author = 'Unknown Author';
        if (data['authors'] != null && (data['authors'] as List).isNotEmpty) {
          try {
            final authorRef = data['authors'][0];
            if (authorRef is Map && authorRef['key'] != null) {
              final authorKey = authorRef['key'] as String;
              final authorResponse = await _dio.get(
                '$_baseUrl$authorKey.json',
                options: Options(
                  validateStatus: (status) => status! < 500,
                  receiveTimeout: const Duration(seconds: 3),
                ),
              );

              if (authorResponse.statusCode == 200 &&
                  authorResponse.data['name'] != null) {
                author = authorResponse.data['name'];
              }
            }
          } catch (e) {
            print('Failed to fetch author details: $e');
          }
        }

        if (author == 'Unknown Author' && data['by_statement'] != null) {
          author = data['by_statement'] as String;
        }

        return OpenLibraryBook(
          title: title,
          author: author,
          isbn: isbn,
          publisher: publisher,
          year: year,
          coverUrl: coverUrl,
          key: data['key'],
          summary: data['notes'] is String ? data['notes'] : null,
        );
      }
    } catch (e) {
      print('OpenLibrary lookup failed, trying Google Books: $e');
    }

    // 2. Fallback to Google Books
    final googleResult = await _lookupGoogleBooksByIsbn(isbn);
    if (googleResult != null) return googleResult;

    // 3. Last fallback to Inventaire.io
    return _lookupInventaireByIsbn(isbn);
  }

  Future<OpenLibraryBook?> _lookupGoogleBooksByIsbn(String isbn) async {
    try {
      print('Trying Google Books fallback for ISBN: $isbn');
      final cleanIsbn = isbn.replaceAll(RegExp(r'[^0-9]'), '');
      final response = await _dio.get(
        'https://www.googleapis.com/books/v1/volumes',
        queryParameters: {'q': 'isbn:$cleanIsbn'},
        options: Options(receiveTimeout: const Duration(seconds: 8)),
      );

      if (response.statusCode == 200 &&
          response.data['items'] != null &&
          (response.data['items'] as List).isNotEmpty) {
        final item = response.data['items'][0]['volumeInfo'];
        final title = item['title'] ?? 'Unknown Title';
        final authors = (item['authors'] as List?)?.join(', ') ?? 'Unknown Author';
        final publisher = item['publisher'];
        final publishedDate = item['publishedDate'] as String?;
        int? year;
        if (publishedDate != null) {
          final match = RegExp(r'\d{4}').firstMatch(publishedDate);
          if (match != null) year = int.tryParse(match.group(0)!);
        }
        final coverUrl = item['imageLinks']?['thumbnail']?.replaceFirst('http:', 'https:');

        return OpenLibraryBook(
          title: title,
          author: authors,
          isbn: isbn,
          publisher: publisher,
          year: year,
          coverUrl: coverUrl,
          summary: item['description'],
        );
      }
    } catch (e) {
      print('Google Books lookup failed: $e');
    }
    return null;
  }

  Future<OpenLibraryBook?> _lookupInventaireByIsbn(String isbn) async {
    try {
      print('Trying Inventaire.io fallback for ISBN: $isbn');
      final cleanIsbn = isbn.replaceAll(RegExp(r'[^0-9X]'), '');
      final response = await _dio.get(
        'https://inventaire.io/api/entities',
        queryParameters: {
          'action': 'by-isbn',
          'isbn': cleanIsbn,
        },
        options: Options(receiveTimeout: const Duration(seconds: 8)),
      );

      if (response.statusCode == 200 && response.data != null) {
        // Inventaire returns a map where keys are ISBNs or entity IDs
        final entities = response.data;
        if (entities.isEmpty) return null;

        // Find the first entity that looks like a work or edition
        for (var entity in entities.values) {
          final label = entity['label'] as String?;
          if (label == null) continue;

          // For detail, we'd need to fetch Wikidata/Inventaire linked data
          // but let's take what we can get from the summary entity
          return OpenLibraryBook(
            title: label,
            author: 'Unknown Author', // Hard to get without further fetch
            isbn: isbn,
            key: entity['uri'],
          );
        }
      }
    } catch (e) {
      print('Inventaire ISBN lookup failed: $e');
    }
    return null;
  }
}
