import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../widgets/genie_app_bar.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../services/translation_service.dart';
import '../models/book.dart';
import '../models/tag.dart';
import '../widgets/bookshelf_view.dart';
import '../widgets/book_cover_grid.dart';
import '../widgets/premium_book_card.dart';
import '../theme/app_design.dart';
import '../providers/theme_provider.dart';
import '../utils/book_status.dart';

enum ViewMode {
  coverGrid, // Netflix style
  spineShelf, // Original bookshelf
  list, // Simple list
}

class BookListScreen extends StatefulWidget {
  final String? initialSearchQuery;
  final bool isTabView;
  final ValueNotifier<int>? refreshNotifier;

  const BookListScreen({
    super.key,
    this.initialSearchQuery,
    this.isTabView = false,
    this.refreshNotifier,
  });

  @override
  State<BookListScreen> createState() => _BookListScreenState();
}

class _BookListScreenState extends State<BookListScreen>
    with WidgetsBindingObserver {
  List<Book> _books = [];
  List<Book> _filteredBooks = [];

  // Filter state
  String? _selectedStatus;
  String? _tagFilter;

  // Hierarchical shelf navigation state
  List<Tag> _allTags = []; // All tags for hierarchy traversal
  List<Tag> _shelfPath = []; // Breadcrumb path (list of ancestors)
  Tag? _currentShelf; // Currently selected shelf (null = root)

  bool _isLoading = true;
  ViewMode _viewMode = ViewMode.coverGrid; // Default to cover grid
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  bool _isReordering = false;
  String? _libraryName; // Store library name for title

  final GlobalKey _addKey = GlobalKey();
  final GlobalKey _searchKey = GlobalKey();
  final GlobalKey _viewKey = GlobalKey();
  final GlobalKey _scanKey = GlobalKey();
  final GlobalKey _externalSearchKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchQuery = widget.initialSearchQuery ?? '';
    if (_searchQuery.isNotEmpty) {
      _isSearching = true;
    }

    // Listen to refresh trigger
    widget.refreshNotifier?.addListener(_handleRefreshTrigger);

    _fetchBooks();

    // Trigger background sync and context-dependent initialization manually
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Provider.of<SyncService>(context, listen: false).syncAllPeers();
      _checkWizard();

      // Initialize filters from query params
      final state = GoRouterState.of(context);
      if (state.uri.queryParameters.containsKey('tag')) {
        setState(() {
          _tagFilter = state.uri.queryParameters['tag'];
          _filterBooks();
        });
      }
    });
  }

  Future<void> _checkWizard() async {
    // Temporarily disabled - use main onboarding tour instead
    /*
    final hasSeen = await WizardService.hasSeenBooksWizard();
    if (!hasSeen && mounted) {
      WizardService.showBooksTutorial(
        context: context,
        addKey: _addKey,
        searchKey: _searchKey,
        viewKey: _viewKey,
        scanKey: _scanKey,
        externalSearchKey: _externalSearchKey,
      );
    }
    */
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh books when app comes back to foreground
    if (state == AppLifecycleState.resumed) {
      _fetchBooks();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.refreshNotifier?.removeListener(_handleRefreshTrigger);
    _searchController.dispose();
    super.dispose();
  }

  void _handleRefreshTrigger() {
    _fetchBooks();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bool isMobile = width <= 600;

    // On mobile, hide title (just show icon); on desktop, show full title
    dynamic titleWidget = _isSearching
        ? _buildSearchField() // Use custom search field with autocomplete
        : (isMobile
              ? null
              : TranslationService.translate(context, 'my_library_title'));

    if (_isReordering) {
      titleWidget = Text(
        TranslationService.translate(context, 'reordering_shelf') ??
            'Reordering Shelf...',
        style: const TextStyle(color: Colors.white, fontSize: 18),
      );
    }

    if (widget.isTabView) {
      // Just return the body content for tab view
      return Container(
        decoration: BoxDecoration(
          gradient: AppDesign.pageGradientForTheme(
            Provider.of<ThemeProvider>(context).themeStyle,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom header for tab view if needed, or reuse parts
              if (_isReordering)
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Theme.of(context).primaryColor,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          TranslationService.translate(
                                context,
                                'reordering_shelf',
                              ) ??
                              'Reordering Shelf...',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.sort_by_alpha,
                          color: Colors.white,
                        ),
                        onPressed: _autoSortByAuthor,
                      ),
                      IconButton(
                        icon: const Icon(Icons.check, color: Colors.white),
                        onPressed: _saveOrder,
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () {
                          setState(() {
                            _isReordering = false;
                            _fetchBooks();
                          });
                        },
                      ),
                    ],
                  ),
                ),

              // Title / Search Bar for Tab View
              if (!_isReordering)
                Container(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Row(
                    children: [
                      Expanded(child: _buildSearchField()),

                      // Action buttons removed (Moved to LibraryScreen AppBar)
                    ],
                  ),
                ),

              _buildFilterBar(),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.black54,
                          ),
                        ),
                      )
                    : _buildBody(),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GenieAppBar(
        title: titleWidget,
        // subtitle: _libraryName, // Handled by ThemeProvider
        leading: isMobile
            ? IconButton(
                icon: const Icon(Icons.menu, color: Colors.white),
                onPressed: () => Scaffold.of(context).openDrawer(),
              )
            : null,
        automaticallyImplyLeading: false,
        actions: [
          if (_isReordering) ...[
            IconButton(
              icon: const Icon(Icons.sort_by_alpha, color: Colors.white),
              tooltip: 'Sort A→Z by Author',
              onPressed: _autoSortByAuthor,
            ),
            IconButton(
              icon: const Icon(Icons.check, color: Colors.white),
              tooltip: 'Save Order',
              onPressed: _saveOrder,
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: 'Cancel',
              onPressed: () {
                setState(() {
                  _isReordering = false;
                  _fetchBooks(); // Reset to original order
                });
              },
            ),
          ] else ...[
            // Batch Scan Button (Only when Tag Filter is Active)
            if (_tagFilter != null && !_isSearching)
              IconButton(
                icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
                tooltip: TranslationService.translate(
                  context,
                  'scan_into_shelf',
                ),
                onPressed: () async {
                  final shelfId = _currentShelf?.id ?? _tagFilter;
                  final shelfName = _currentShelf?.fullPath ?? _tagFilter;
                  await context.push(
                    '/scan',
                    extra: {
                      'shelfId': shelfId,
                      'shelfName': shelfName,
                      'batch': true,
                    },
                  );
                  _fetchBooks(); // Refresh after scan
                },
              ),
            // Reorder Button (Only when Tag Filter is Active)
            if (_tagFilter != null && !_isSearching)
              IconButton(
                icon: const Icon(Icons.sort, color: Colors.white),
                tooltip: 'Reorder Shelf',
                onPressed: () {
                  setState(() {
                    _isReordering = true;
                    _viewMode = ViewMode.list; // Force list view for reordering
                  });
                },
              ),

            IconButton(
              key: const Key('bookSearchButton'),
              icon: Icon(
                _isSearching ? Icons.close : Icons.search,
                color: Colors.white,
              ),
              tooltip: TranslationService.translate(
                context,
                _isSearching ? 'cancel' : 'search_books',
              ),
              onPressed: () {
                setState(() {
                  if (_isSearching) {
                    _isSearching = false;
                    _searchController.clear();
                    _filterBooks();
                  } else {
                    _isSearching = true;
                  }
                });
              },
            ),
          ], // End else

          if (!_isSearching && !_isReordering) ...[
            IconButton(
              key: _viewKey,
              icon: Icon(_getViewIcon(_viewMode), color: Colors.white),
              tooltip: TranslationService.translate(
                context,
                'action_change_view',
              ),
              onPressed: () {
                setState(() {
                  _viewMode = _getNextViewMode(_viewMode);
                });
              },
            ),
            IconButton(
              key: _scanKey,
              icon: const Icon(Icons.camera_alt, color: Colors.white),
              tooltip: TranslationService.translate(context, 'scan_isbn_title'),
              onPressed: () async {
                final isbn = await context.push<String>('/scan');
                if (isbn != null && mounted) {
                  final result = await context.push(
                    '/books/add',
                    extra: {'isbn': isbn},
                  );
                  if (result == true && mounted) {
                    _fetchBooks(); // Refresh list after book was added
                  }
                }
              },
            ),
            // Online search - show on all devices
            IconButton(
              key: _externalSearchKey,
              icon: const Icon(Icons.travel_explore, color: Colors.white),
              tooltip: TranslationService.translate(
                context,
                'btn_search_online',
              ),
              onPressed: () async {
                final result = await context.push('/search/external');
                if (result == true) {
                  _fetchBooks();
                }
              },
            ),
          ],
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: AppDesign.pageGradientForTheme(
            Provider.of<ThemeProvider>(context).themeStyle,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // _buildHeader(context), // Header removed, avatar now in AppBar
              _buildFilterBar(),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.black54,
                          ),
                        ),
                      )
                    : _buildBody(),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('addBookButton'),
        onPressed: () async {
          final result = await context.push('/books/add');
          if (result == true) {
            _fetchBooks(); // Refresh if book was added
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  bool _showBorrowedConfig = true; // Store config value

  Future<void> _fetchBooks() async {
    setState(() => _isLoading = true);
    final apiService = Provider.of<ApiService>(context, listen: false);

    try {
      debugPrint(
        'Fetching books with status: $_selectedStatus, tag: $_tagFilter, search: $_searchQuery',
      );
      // Fetch all books initially, filtering will happen locally
      final books = await apiService.getBooks();

      final configRes = await apiService.getLibraryConfig();
      String? libraryName;
      if (configRes.statusCode == 200) {
        _showBorrowedConfig = configRes.data['show_borrowed_books'] != false;
        libraryName = configRes.data['library_name'] as String?;
        if (libraryName != null) {
          Provider.of<ThemeProvider>(
            context,
            listen: false,
          ).setLibraryName(libraryName);
        }
      }

      if (mounted) {
        // Also load tags for hierarchy navigation
        final tags = await apiService.getTags();

        setState(() {
          _books = books; // Store ALL books, filtering happens in _filterBooks
          _allTags = tags; // Store tags for hierarchy traversal
          _libraryName = libraryName;
          _filterBooks(); // Apply filters after fetching all books
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        debugPrint('Error loading books: $e');
      }
    }
  }

  bool _showAllBooks = false;

  // Triggered when filters change or search query changes
  void _filterBooks() {
    List<Book> tempBooks = List.from(_books);

    // Apply "Owned only" default filter
    // Exception: If user explicitly selects "wanting" (Wishlist), show them regardless of ownership
    if (!_showAllBooks && _selectedStatus != 'wanting') {
      tempBooks = tempBooks.where((b) => b.owned).toList();
    }

    // Apply "show borrowed" config logic:
    // If config says hide borrowed books, ONLY hide them if the user hasn't explicitly asked to see them.
    if (!_showBorrowedConfig && _selectedStatus != 'borrowed') {
      tempBooks = tempBooks
          .where((b) => b.readingStatus != 'borrowed')
          .toList();
    }

    // Apply status filter
    if (_selectedStatus != null) {
      tempBooks = tempBooks
          .where((book) => book.readingStatus == _selectedStatus)
          .toList();
    }

    // Apply tag filter with hierarchy support
    // When filtering by a parent tag, include books from all child tags
    if (_currentShelf != null && _allTags.isNotEmpty) {
      // Get all matching tag names (this tag + descendants)
      final matchingNames = Tag.getTagNamesWithDescendants(
        _currentShelf!,
        _allTags,
      );
      tempBooks = tempBooks.where((book) {
        final bookTags =
            book.subjects?.map((s) => s.toLowerCase()).toSet() ?? {};
        // Book matches if any of its tags match any of the filter tags
        return bookTags.any((tag) => matchingNames.contains(tag));
      }).toList();
    } else if (_tagFilter != null) {
      // Fallback to simple string match for legacy compatibility
      final filterLower = _tagFilter!.toLowerCase();
      tempBooks = tempBooks.where((book) {
        final bookTags =
            book.subjects?.map((s) => s.toLowerCase()).toSet() ?? {};
        return bookTags.contains(filterLower);
      }).toList();
    }

    // Apply search query filter
    if (_searchQuery.isNotEmpty) {
      tempBooks = tempBooks
          .where(
            (book) =>
                book.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                (book.author?.toLowerCase().contains(
                      _searchQuery.toLowerCase(),
                    ) ??
                    false),
          )
          .toList();
    }

    // Default sort: alphabetical by author surname (last word), then by title
    // Helper to extract surname (last word) from author name
    String getSurname(String? author) {
      if (author == null || author.isEmpty) return '';
      final parts = author.trim().split(RegExp(r'\s+'));
      return parts.last.toLowerCase();
    }

    tempBooks.sort((a, b) {
      final surnameA = getSurname(a.author);
      final surnameB = getSurname(b.author);
      final surnameCompare = surnameA.compareTo(surnameB);
      if (surnameCompare != 0) return surnameCompare;
      // If same surname, compare full author name
      final authorA = (a.author ?? '').toLowerCase();
      final authorB = (b.author ?? '').toLowerCase();
      final authorCompare = authorA.compareTo(authorB);
      if (authorCompare != 0) return authorCompare;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    setState(() {
      _filteredBooks = tempBooks;
    });
  }

  void _showTagFilterDialog() async {
    final apiService = Provider.of<ApiService>(context, listen: false);

    try {
      final tags = await apiService.getTags();

      if (!mounted) return;

      if (tags.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(TranslationService.translate(context, 'no_tags')),
          ),
        );
        return;
      }

      // Update local tags cache
      _allTags = tags;

      // Show hierarchical shelf navigation dialog
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) {
          return _ShelfNavigationSheet(
            tags: tags,
            currentShelf: _currentShelf,
            shelfPath: _shelfPath,
            onShelfSelected: (tag, path) {
              Navigator.pop(context);
              setState(() {
                _currentShelf = tag;
                _shelfPath = path;
                _tagFilter = tag?.fullPath;
                _filterBooks();
              });
            },
          );
        },
      );
    } catch (e) {
      debugPrint('Error loading tags: $e');
    }
  }

  // _fetchSuggestions is removed as Autocomplete now works directly on _allBooks

  Widget _buildSearchField() {
    // Use a unique key to force complete disposal when search mode changes
    // This prevents Flutter's Autocomplete async semantics from accessing unmounted state
    return Container(
      key: const ValueKey('search_autocomplete'),
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppDesign.subtleShadow,
      ),
      child: Autocomplete<Book>(
        displayStringForOption: (Book option) => option.title,
        optionsBuilder: (TextEditingValue textEditingValue) {
          if (textEditingValue.text.isEmpty) {
            return const Iterable<Book>.empty();
          }
          return _books.where((Book book) {
            return book.title.toLowerCase().contains(
                  textEditingValue.text.toLowerCase(),
                ) ||
                (book.author?.toLowerCase().contains(
                      textEditingValue.text.toLowerCase(),
                    ) ??
                    false);
          });
        },
        onSelected: (Book selection) {
          if (!mounted) return; // Guard against unmounted state
          if (selection.id == null) return;
          context.push('/books/${selection.id}', extra: selection);
        },
        fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
          // Sync internal _searchQuery with Autocomplete's controller
          if (_searchQuery != textEditingController.text) {
            textEditingController.text = _searchQuery;
          }

          // Assuming GenieAppBar is defined elsewhere and this is part of a Scaffold's appBar property
          // This part of the change seems to be misplaced based on the provided context.
          // I will integrate the subtitle part into the _buildHeader function as it's the closest
          // logical place for displaying library name in a header/appBar-like context within the provided snippet.
          // If GenieAppBar is used in the Scaffold, the subtitle should be added there.
          // Given the instruction, I'm assuming the user wants to add `subtitle: _libraryName` to an existing GenieAppBar.
          // As I cannot modify the Scaffold directly, I will make a note here.

          return TextField(
            controller: textEditingController,
            focusNode: focusNode,
            style: const TextStyle(color: Colors.black87),
            decoration: InputDecoration(
              hintText: TranslationService.translate(context, 'search_books'),
              hintStyle: const TextStyle(color: Colors.black38),
              prefixIcon: const Icon(Icons.search, color: Colors.black54),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 15,
              ),
            ),
            onChanged: (value) {
              if (!mounted) return; // Guard against unmounted state
              setState(() {
                _searchQuery = value;
                _filterBooks(); // Trigger filter on search query change
              });
            },
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4.0,
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 200,
                  maxWidth: 300,
                ), // Adjust width as needed
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (BuildContext context, int index) {
                    final Book option = options.elementAt(index);
                    return InkWell(
                      onTap: () => onSelected(option),
                      child: ListTile(
                        leading: option.coverUrl != null
                            ? CachedNetworkImage(
                                imageUrl: option.coverUrl!,
                                width: 30,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) =>
                                    const Icon(Icons.book, size: 30),
                              )
                            : const Icon(
                                Icons.book,
                                size: 30,
                                color: Colors.grey,
                              ),
                        title: Text(
                          option.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          option.author ?? 'Unknown',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Header removed - Avatar is now in GenieAppBar

  Widget _buildFilterBar() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // determine active label for status filter
    String filterLabel = TranslationService.translate(context, 'filter_all');
    IconData filterIcon = Icons.filter_list;

    bool isFilterActive = false;

    if (_showAllBooks) {
      filterLabel = TranslationService.translate(context, 'filter_all');
      filterIcon = Icons.visibility;
      isFilterActive = true;
    } else if (_selectedStatus != null) {
      isFilterActive = true;
      // Map status to label
      if (_selectedStatus == 'reading') {
        filterLabel = TranslationService.translate(
          context,
          'reading_status_reading',
        );
      } else if (_selectedStatus == 'to_read') {
        filterLabel = TranslationService.translate(
          context,
          'reading_status_to_read',
        );
      } else if (_selectedStatus == 'wanting') {
        filterLabel = TranslationService.translate(
          context,
          'reading_status_wanting',
        );
      } else if (_selectedStatus == 'read') {
        filterLabel = TranslationService.translate(
          context,
          'reading_status_read',
        );
      } else if (_selectedStatus == 'owned') {
        filterLabel = TranslationService.translate(context, 'owned_status');
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          // 1. View Mode Toggles (Left aligned)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.white24 : Colors.grey.withOpacity(0.2),
              ),
            ),
            child: Row(
              children: [
                _buildViewModeToggle(Icons.grid_view, ViewMode.coverGrid),
                _buildViewModeToggle(Icons.shelves, ViewMode.spineShelf),
                _buildViewModeToggle(Icons.list, ViewMode.list),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // 2. Tag Filter Trigger
          // If a tag is selected, show it as a clearable chip
          if (_tagFilter != null) ...[
            _buildFilterPill(
              status: 'tag_filter',
              label: '#$_tagFilter',
              isClearAction: true,
            ),
          ] else
            // Otherwise show "Shelves" button
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ScaleOnTap(
                onTap: () => _showTagFilterDialog(),
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: isDark ? theme.cardColor : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isDark
                          ? Colors.white24
                          : Colors.grey.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.label_outline,
                        size: 16,
                        color: theme.primaryColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        TranslationService.translate(context, 'tags'),
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          const SizedBox(width: 4),

          // 3. Consolidated Status Filter Dropdown
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() {
                if (value == 'all_visibility') {
                  _showAllBooks = !_showAllBooks;
                  _selectedStatus =
                      null; // Reset specific status if toggling "All"
                } else if (value == 'clear') {
                  _showAllBooks = false;
                  _selectedStatus = null;
                } else {
                  _showAllBooks = false;
                  _selectedStatus = value;
                }
                _filterBooks();
              });
            },
            offset: const Offset(0, 40),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(
                      Icons.filter_list_off,
                      color: theme.disabledColor,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(TranslationService.translate(context, 'filter_all')),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              _buildPopupItem(
                'reading',
                Icons.menu_book,
                TranslationService.translate(context, 'reading_status_reading'),
                Colors.blue,
              ),
              _buildPopupItem(
                'to_read',
                Icons.bookmark_border,
                TranslationService.translate(context, 'reading_status_to_read'),
                Colors.orange,
              ),
              _buildPopupItem(
                'wanting',
                Icons.favorite_border,
                TranslationService.translate(context, 'reading_status_wanting'),
                Colors.pink,
              ),
              _buildPopupItem(
                'read',
                Icons.check_circle_outline,
                TranslationService.translate(context, 'reading_status_read'),
                Colors.green,
              ),
              _buildPopupItem(
                'owned',
                Icons.inventory_2_outlined,
                TranslationService.translate(context, 'owned_status'),
                Colors.purple,
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'all_visibility',
                child: Row(
                  children: [
                    Icon(
                      _showAllBooks ? Icons.visibility : Icons.visibility_off,
                      color: Colors.grey,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      TranslationService.translate(
                        context,
                        'show_borrowed_books',
                      ),
                    ), // Reuse 'Show borrowed' or 'All'
                  ],
                ),
              ),
            ],
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isFilterActive
                    ? theme.primaryColor
                    : (isDark ? theme.cardColor : Colors.white),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isFilterActive
                      ? Colors.transparent
                      : (isDark
                            ? Colors.white24
                            : Colors.grey.withOpacity(0.3)),
                ),
                boxShadow: isFilterActive
                    ? [
                        BoxShadow(
                          color: theme.primaryColor.withOpacity(0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  Icon(
                    filterIcon,
                    size: 16,
                    color: isFilterActive
                        ? Colors.white
                        : (isDark ? Colors.white : Colors.black87),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    filterLabel,
                    style: TextStyle(
                      color: isFilterActive
                          ? Colors.white
                          : (isDark ? Colors.white : Colors.black87),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 18,
                    color: isFilterActive ? Colors.white70 : Colors.grey,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _buildPopupItem(
    String value,
    IconData icon,
    String label,
    Color color,
  ) {
    final isSelected = _selectedStatus == value;
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            color: isSelected ? color : color.withOpacity(0.7),
            size: 20,
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? color : null,
            ),
          ),
          if (isSelected) ...[
            const Spacer(),
            Icon(Icons.check, color: color, size: 18),
          ],
        ],
      ),
    );
  }

  Widget _buildViewModeToggle(IconData icon, ViewMode mode) {
    final bool isSelected = _viewMode == mode;
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    return ScaleOnTap(
      onTap: () {
        setState(() {
          _viewMode = mode;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).primaryColor
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: isSelected
              ? Colors.white
              : isDarkTheme
              ? Colors.white70
              : Colors.black54,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildFilterPill({
    required String? status,
    required String label,
    bool isClearAction = false,
  }) {
    final bool isSelected = _selectedStatus == status;
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    // Get icon for reading status if applicable
    IconData? statusIcon;
    Color? statusColor;
    if (status != null && !isClearAction) {
      final statusObj = individualStatuses.cast<BookStatus?>().firstWhere(
        (s) => s?.value == status,
        orElse: () => null,
      );
      if (statusObj != null) {
        statusIcon = statusObj.icon;
        statusColor = statusObj.color;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ScaleOnTap(
        onTap: () {
          if (isClearAction) {
            setState(() {
              _tagFilter = null;
              _filterBooks();
            });
          } else {
            setState(() {
              _selectedStatus = isSelected ? null : status;
              _filterBooks();
            });
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isClearAction
                ? Colors.redAccent.withOpacity(0.8)
                : (isSelected
                      ? Theme.of(context).primaryColor
                      : isDarkTheme
                      ? Theme.of(context).cardColor.withOpacity(0.8)
                      : Colors.white),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? Colors.transparent
                  : isDarkTheme
                  ? Theme.of(context).colorScheme.outline
                  : Colors.grey.withOpacity(0.3),
              width: isDarkTheme ? 1.5 : 1.0,
            ),
            boxShadow: isSelected && !isClearAction
                ? [
                    BoxShadow(
                      color: Theme.of(context).primaryColor.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isClearAction) ...[
                const Icon(Icons.close, size: 16, color: Colors.white),
                const SizedBox(width: 6),
              ] else if (statusIcon != null) ...[
                Icon(
                  statusIcon,
                  size: 16,
                  color: isSelected ? Colors.white : statusColor,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: isClearAction
                      ? Colors.white
                      : (isSelected
                            ? Colors.white
                            : Theme.of(context).textTheme.bodyMedium?.color ??
                                  Colors.black54),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onBookTap(Book book) async {
    if (book.id == null) return;
    final result = await context.push('/books/${book.id}', extra: book);
    if (result == true) {
      _fetchBooks();
    }
  }

  ViewMode _getNextViewMode(ViewMode current) {
    switch (current) {
      case ViewMode.coverGrid:
        return ViewMode.spineShelf;
      case ViewMode.spineShelf:
        return ViewMode.list;
      case ViewMode.list:
        return ViewMode.coverGrid;
    }
  }

  IconData _getViewIcon(ViewMode mode) {
    switch (mode) {
      case ViewMode.coverGrid:
        return Icons.grid_view;
      case ViewMode.spineShelf:
        return Icons.shelves;
      case ViewMode.list:
        return Icons.list;
    }
  }

  Widget _buildBody() {
    // 1. Zero State: No books in the library at all (not just filtered out)
    if (_books.isEmpty &&
        !_isLoading &&
        _searchQuery.isEmpty &&
        _tagFilter == null &&
        _selectedStatus == null) {
      return RefreshIndicator(
        onRefresh: _fetchBooks,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.menu_book_rounded,
                      size: 80,
                      color: Theme.of(context).disabledColor.withOpacity(0.5),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      TranslationService.translate(context, 'welcome_subtitle'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        color: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.color?.withOpacity(0.8),
                      ),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final isbn = await context.push<String>('/scan');
                        if (isbn != null && mounted) {
                          final result = await context.push(
                            '/books/add',
                            extra: {'isbn': isbn},
                          );
                          if (result == true && mounted) {
                            _fetchBooks(); // Refresh list after book was added
                          }
                        }
                      },
                      icon: const Icon(Icons.qr_code_scanner),
                      label: Text(
                        TranslationService.translate(
                          context,
                          'scan_first_book',
                        ),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final result = await context.push('/search/external');
                        if (result == true) {
                          _fetchBooks();
                        }
                      },
                      icon: const Icon(Icons.travel_explore),
                      label: Text(
                        TranslationService.translate(
                          context,
                          'btn_search_book_online',
                        ),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // 2. No Results: Books exist but filters/search removed them
    if (_filteredBooks.isEmpty && !_isLoading) {
      return RefreshIndicator(
        onRefresh: _fetchBooks,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search_off,
                    size: 64,
                    color: Colors.grey.withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    TranslationService.translate(context, 'no_books_found'),
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    switch (_viewMode) {
      case ViewMode.coverGrid:
        return RefreshIndicator(
          onRefresh: _fetchBooks,
          child: BookCoverGrid(books: _filteredBooks, onBookTap: _onBookTap),
        );
      case ViewMode.spineShelf:
        return RefreshIndicator(
          onRefresh: _fetchBooks,
          child: BookshelfView(books: _filteredBooks, onBookTap: _onBookTap),
        );
      case ViewMode.list:
        return RefreshIndicator(
          onRefresh: _fetchBooks,
          child: _buildListView(),
        );
    }
  }

  Widget _buildListView() {
    if (_isReordering) {
      return ReorderableListView.builder(
        itemCount: _filteredBooks.length,
        padding: const EdgeInsets.all(16),
        onReorder: (oldIndex, newIndex) {
          setState(() {
            if (oldIndex < newIndex) {
              newIndex -= 1;
            }
            final Book item = _filteredBooks.removeAt(oldIndex);
            _filteredBooks.insert(newIndex, item);
          });
        },
        itemBuilder: (context, index) {
          final book = _filteredBooks[index];
          return Card(
            key: ValueKey(book.id ?? index), // Ensure stable key
            margin: const EdgeInsets.only(bottom: 16),
            child: ListTile(
              contentPadding: const EdgeInsets.all(8),
              leading: book.coverUrl != null
                  ? CachedNetworkImage(
                      imageUrl: book.coverUrl!,
                      width: 40,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const Icon(Icons.book),
                    )
                  : const Icon(Icons.book, size: 40, color: Colors.grey),
              title: Text(book.title),
              subtitle: Text(book.author ?? 'Unknown'),
              trailing: ReorderableDragStartListener(
                index: index,
                child: const Icon(Icons.drag_handle),
              ),
            ),
          );
        },
      );
    }

    return ListView.builder(
      itemCount: _filteredBooks.length,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final book = _filteredBooks[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: PremiumBookCard(
            book: book,
            isHero: true, // Use hero layout (horizontal) for list items
            width: double.infinity,
          ),
        );
      },
    );
  }

  Future<void> _saveOrder() async {
    setState(() => _isLoading = true);
    final apiService = Provider.of<ApiService>(context, listen: false);
    try {
      final ids = _filteredBooks.map((b) => b.id!).toList();
      await apiService.reorderBooks(ids);

      setState(() {
        _isReordering = false;
        _isLoading = false;
      });
      // Don't call _fetchBooks() here - it would reload with global order
      // and lose the tag-filtered order we just saved
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Shelf order saved!')));
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error saving order: $e')));
    }
  }

  void _autoSortByAuthor() {
    setState(() {
      _filteredBooks.sort((a, b) {
        // Sort by author (null-safe), then by title if same author
        final authorA = (a.author ?? '').toLowerCase();
        final authorB = (b.author ?? '').toLowerCase();
        final authorCompare = authorA.compareTo(authorB);
        if (authorCompare != 0) return authorCompare;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sorted by author A→Z. Click ✓ to save.'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

/// Netflix-style hierarchical shelf navigation sheet
/// Shows breadcrumbs + category cards with drill-down support
class _ShelfNavigationSheet extends StatefulWidget {
  final List<Tag> tags;
  final Tag? currentShelf;
  final List<Tag> shelfPath;
  final void Function(Tag? tag, List<Tag> path) onShelfSelected;

  const _ShelfNavigationSheet({
    required this.tags,
    required this.currentShelf,
    required this.shelfPath,
    required this.onShelfSelected,
  });

  @override
  State<_ShelfNavigationSheet> createState() => _ShelfNavigationSheetState();
}

class _ShelfNavigationSheetState extends State<_ShelfNavigationSheet> {
  late List<Tag> _path;
  Tag? _currentLevel;

  @override
  void initState() {
    super.initState();
    _path = List.from(widget.shelfPath);
    _currentLevel = widget.currentShelf;
  }

  List<Tag> get _visibleTags {
    if (_currentLevel == null) {
      // Show root tags only
      final rootTags = Tag.getRootTags(widget.tags);
      // Debug: print all tags to see parentId values
      debugPrint('📚 All tags (${widget.tags.length}):');
      for (final t in widget.tags) {
        debugPrint('  - ${t.name} (id=${t.id}, parentId=${t.parentId})');
      }
      debugPrint(
        '📚 Root tags (${rootTags.length}): ${rootTags.map((t) => t.name).join(", ")}',
      );
      return rootTags;
    } else {
      // Show direct children of current level
      return Tag.getDirectChildren(_currentLevel!.id, widget.tags);
    }
  }

  void _drillDown(Tag tag) {
    setState(() {
      if (_currentLevel != null) {
        _path.add(_currentLevel!);
      }
      _currentLevel = tag;
    });
  }

  void _navigateToPath(int index) {
    setState(() {
      if (index < 0) {
        // Go to root
        _path.clear();
        _currentLevel = null;
      } else if (index < _path.length) {
        _currentLevel = _path[index];
        _path = _path.sublist(0, index);
      }
    });
  }

  void _selectCurrent() {
    widget.onShelfSelected(_currentLevel, _path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final children = _visibleTags;
    final hasChildren = children.isNotEmpty;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with title and clear button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    TranslationService.translate(context, 'filter_by_tag'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_currentLevel != null || widget.currentShelf != null)
                    TextButton.icon(
                      onPressed: () => widget.onShelfSelected(null, []),
                      icon: const Icon(Icons.clear, size: 18),
                      label: Text(
                        TranslationService.translate(context, 'clear') ??
                            'Clear',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Breadcrumb navigation
              _buildBreadcrumbs(theme),
              const SizedBox(height: 16),

              // Current shelf info and select button
              if (_currentLevel != null) ...[
                _buildCurrentShelfCard(theme),
                const SizedBox(height: 16),
              ],

              // Sub-categories section
              if (hasChildren) ...[
                Text(
                  TranslationService.translate(context, 'sub_categories') ??
                      'Sub-categories',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Category cards grid
              Expanded(
                child: hasChildren
                    ? GridView.builder(
                        controller: scrollController,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 1.8,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                        itemCount: children.length,
                        itemBuilder: (context, index) {
                          return _buildCategoryCard(children[index], theme);
                        },
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.folder_open,
                              size: 48,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.3,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              TranslationService.translate(
                                    context,
                                    'no_sub_shelves',
                                  ) ??
                                  'No sub-shelves',
                              style: TextStyle(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBreadcrumbs(ThemeData theme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Home / All shelves
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _navigateToPath(-1),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.home,
                    size: 18,
                    color: _currentLevel == null
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    TranslationService.translate(context, 'all_shelves') ??
                        'All Shelves',
                    style: TextStyle(
                      fontWeight: _currentLevel == null
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: _currentLevel == null
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Path segments
          for (int i = 0; i < _path.length; i++) ...[
            Icon(
              Icons.chevron_right,
              size: 20,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _navigateToPath(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  _path[i].name,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          ],

          // Current level
          if (_currentLevel != null) ...[
            Icon(
              Icons.chevron_right,
              size: 20,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                _currentLevel!.name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCurrentShelfCard(ThemeData theme) {
    final aggregatedCount = Tag.getAggregatedCount(_currentLevel!, widget.tags);

    return Card(
      elevation: 2,
      color: theme.colorScheme.primaryContainer,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _selectCurrent,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.folder,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentLevel!.name,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      (TranslationService.translate(
                                context,
                                'shelf_books_count',
                              ) ??
                              '%d books')
                          .replaceAll('%d', aggregatedCount.toString()),
                      style: TextStyle(
                        color: theme.colorScheme.onPrimaryContainer.withValues(
                          alpha: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _selectCurrent,
                icon: const Icon(Icons.filter_list, size: 18),
                label: Text(
                  TranslationService.translate(context, 'browse_shelf') ??
                      'Browse',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryCard(Tag tag, ThemeData theme) {
    final hasChildren = Tag.getDirectChildren(tag.id, widget.tags).isNotEmpty;
    final aggregatedCount = Tag.getAggregatedCount(tag, widget.tags);

    return Card(
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (hasChildren) {
            _drillDown(tag);
          } else {
            // No children, directly select
            widget.onShelfSelected(tag, [
              ..._path,
              if (_currentLevel != null) _currentLevel!,
            ]);
          }
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.surface,
                theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(
                    hasChildren ? Icons.folder : Icons.label,
                    color: theme.colorScheme.primary,
                    size: 24,
                  ),
                  if (hasChildren)
                    Icon(
                      Icons.chevron_right,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      size: 20,
                    ),
                ],
              ),
              const Spacer(),
              Text(
                tag.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                (TranslationService.translate(context, 'shelf_books_count') ??
                        '%d books')
                    .replaceAll('%d', aggregatedCount.toString()),
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
