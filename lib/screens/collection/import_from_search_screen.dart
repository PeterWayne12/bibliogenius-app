import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/collection.dart';

import '../../services/translation_service.dart';
import '../../services/api_service.dart';
import '../../services/open_library_service.dart';
import '../../widgets/cached_book_cover.dart';
import '../../widgets/hierarchical_tag_selector.dart';
import '../../widgets/collection_selector.dart';

class ImportFromSearchScreen extends StatefulWidget {
  final Collection? initialCollection;

  const ImportFromSearchScreen({Key? key, this.initialCollection})
    : super(key: key);

  @override
  _ImportFromSearchScreenState createState() => _ImportFromSearchScreenState();
}

class _ImportFromSearchScreenState extends State<ImportFromSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final OpenLibraryService _openLibraryService = OpenLibraryService();

  List<OpenLibraryBook> _searchResults = [];
  final Set<OpenLibraryBook> _selectedBooks = {};

  // New state for multi-selection
  List<String> _selectedTags = [];
  List<Collection> _selectedCollections = [];

  bool _isLoading = false;
  bool _isImporting = false;
  bool _importAsOwned = false;
  bool _showOptions = true; // To toggle visibility of tags/collections
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.initialCollection != null) {
      _selectedCollections.add(widget.initialCollection!);
    }
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.length < 3) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _searchResults = [];
      _selectedBooks.clear();
      FocusScope.of(context).unfocus(); // Hide keyboard
    });

    try {
      final results = await _openLibraryService.searchBooks(query);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isLoading = false;
          if (results.isEmpty) {
            _errorMessage = 'Aucun résultat trouvé.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Erreur de recherche : $e';
        });
      }
    }
  }

  void _toggleSelection(OpenLibraryBook book) {
    setState(() {
      if (_selectedBooks.contains(book)) {
        _selectedBooks.remove(book);
      } else {
        _selectedBooks.add(book);
      }
    });
  }

  Future<void> _importSelected() async {
    if (_selectedBooks.isEmpty) return;

    setState(() {
      _isImporting = true;
    });

    final apiService = Provider.of<ApiService>(context, listen: false);
    int successCount = 0;
    int failCount = 0;

    for (final olBook in _selectedBooks) {
      try {
        // 1. Prepare book data
        int? bookId;

        final bookData = {
          'title': olBook.title,
          'author': olBook.author,
          'isbn': olBook.isbn,
          'publisher': olBook.publisher,
          'publication_year': olBook.year,
          'cover_url': olBook.coverUrl,
          'summary': olBook.summary,
          'reading_status': _importAsOwned ? 'to_read' : 'wanting',
          'owned': _importAsOwned,
          'subjects': _selectedTags
              .map((t) => t.split(' > ').last)
              .toList(), // Add tags
        };

        // 2. Create/Find Book
        final response = await apiService.createBook(bookData);

        if (response.statusCode == 201) {
          final data = response.data;
          if (data is Map && data.containsKey('book')) {
            bookId = data['book']['id'];
          } else {
            bookId = data['id'];
          }
        } else {
          // If creation failed (duplicate), try to find
          if (olBook.isbn != null && olBook.isbn!.isNotEmpty) {
            final existing = await apiService.findBookByIsbn(olBook.isbn!);
            if (existing != null) {
              bookId = existing.id;
            }
          }

          if (bookId == null) {
            // Try by title
            final books = await apiService.getBooks(title: olBook.title);
            if (books.isNotEmpty) {
              bookId = books.first.id;
            }
          }
        }

        // 3. Link to Collections
        if (bookId != null) {
          successCount++; // Count as success even if collection linking fails slightly

          for (final collection in _selectedCollections) {
            try {
              if (collection.id.isNotEmpty) {
                await apiService.addBookToCollection(collection.id, bookId);
              }
            } catch (e) {
              debugPrint('Failed to add to collection ${collection.name}: $e');
            }
          }
        } else {
          failCount++;
          debugPrint('Failed to import/find book: ${olBook.title}');
        }
      } catch (e) {
        debugPrint('Error importing ${olBook.title}: $e');
        failCount++;
      }
    }

    if (mounted) {
      setState(() {
        _isImporting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$successCount livres importés. ($failCount échecs)'),
        ),
      );

      if (successCount > 0) {
        Navigator.pop(context, true); // Return true to refresh
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          TranslationService.translate(context, 'external_search_title'),
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: TranslationService.translate(
                        context,
                        'search_placeholder',
                      ),
                      hintText: TranslationService.translate(
                        context,
                        'search_hint_example',
                      ),
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _isLoading ? null : _search,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          TranslationService.translate(context, 'search_btn'),
                        ),
                ),
              ],
            ),
          ),

          // Collapsible Options Panel (Tags & Collections)
          ExpansionTile(
            title: Text(
              TranslationService.translate(context, 'import_options'),
            ),
            initiallyExpanded: _showOptions,
            onExpansionChanged: (val) => setState(() => _showOptions = val),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tags
                    Text(
                      '${TranslationService.translate(context, 'add_tags')} :',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    HierarchicalTagSelector(
                      selectedTags: _selectedTags,
                      onTagsChanged: (list) {
                        setState(() => _selectedTags = list);
                      },
                    ),
                    const SizedBox(height: 16),

                    // Collections
                    Text(
                      '${TranslationService.translate(context, 'add_to_collections_label')} :',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    CollectionSelector(
                      selectedCollections: _selectedCollections,
                      onChanged: (list) {
                        setState(() => _selectedCollections = list);
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),

          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ),

          // Search Results Control Bar
          if (_searchResults.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Text(
                      TranslationService.translate(
                        context,
                        'selected_books_count',
                        params: {'count': _selectedBooks.length.toString()},
                      ),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Text(
                      TranslationService.translate(context, 'mark_as_owned'),
                    ),
                    Switch(
                      value: _importAsOwned,
                      onChanged: (val) {
                        setState(() => _importAsOwned = val);
                      },
                    ),
                  ],
                ),
              ),
            ),

          const Divider(),

          // Results List
          Expanded(
            child: ListView.builder(
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final book = _searchResults[index];
                final isSelected = _selectedBooks.contains(book);

                return ListTile(
                  leading: CachedBookCover(
                    imageUrl: book.coverUrl,
                    width: 40,
                    height: 60,
                  ),
                  title: Text(book.title),
                  subtitle: Text('${book.author} (${book.year})'),
                  trailing: Checkbox(
                    value: isSelected,
                    onChanged: (val) => _toggleSelection(book),
                  ),
                  onTap: () => _toggleSelection(book),
                );
              },
            ),
          ),

          // Floating Action Button for Import (visible when books are selected)
          if (_selectedBooks.isNotEmpty)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isImporting ? null : _importSelected,
                    icon: const Icon(Icons.download),
                    label: Text(
                      _isImporting
                          ? 'Importation...'
                          : 'Importer ${_selectedBooks.length} livre(s)',
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
