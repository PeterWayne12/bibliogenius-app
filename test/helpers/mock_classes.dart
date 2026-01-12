import 'package:app/services/api_service.dart';
import 'package:app/services/auth_service.dart';
import 'package:app/models/book.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class MockAuthService extends AuthService {
  @override
  Future<String?> getToken() async => 'mock_token';
}

class MockApiService extends ApiService {
  MockApiService() : super(MockAuthService(), baseUrl: 'http://mock');

  // Track calls
  final List<String> lookups = [];
  final List<String> createdBooks = [];

  // Mock Data
  Book? existingBook;
  Map<String, dynamic>? lookupResult;

  @override
  Future<Book?> findBookByIsbn(String isbn) async {
    lookups.add('findBookByIsbn:$isbn');
    return existingBook;
  }

  @override
  Future<Map<String, dynamic>?> lookupBook(
    String isbn, {
    Locale? locale,
  }) async {
    lookups.add('lookupBook:$isbn');
    return lookupResult;
  }

  @override
  Future<Response> createBook(Map<String, dynamic> bookData) async {
    createdBooks.add(bookData['isbn']);
    return Response(
      requestOptions: RequestOptions(path: '/api/books'),
      statusCode: 201,
      data: {'id': 123, 'title': bookData['title']},
    );
  }

  @override
  Future<void> addBookToCollection(String collectionId, int bookId) async {
    lookups.add('addBookToCollection:$collectionId:$bookId');
  }
}

// Manual mock since we can't extend MobileScannerController easily (it involves ValueNotifiers etc)
// Actually we CAN extend it.
class MockMobileScannerController extends MobileScannerController {
  @override
  Future<void> toggleTorch() async {}

  @override
  Future<void> switchCamera() async {}

  @override
  Future<void> dispose() async {}
}
