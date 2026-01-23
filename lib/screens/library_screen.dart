import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../services/translation_service.dart';
import '../widgets/genie_app_bar.dart';
import '../providers/theme_provider.dart';
import 'book_list_screen.dart';
import 'shelves_screen.dart';
import 'collection/collection_list_screen.dart';
import 'collection/import_curated_list_screen.dart' as import_curated;
import 'collection/import_shared_list_screen.dart';

class LibraryScreen extends StatefulWidget {
  final int initialIndex;

  const LibraryScreen({super.key, this.initialIndex = 0});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    final collectionEnabled = Provider.of<ThemeProvider>(
      context,
      listen: false,
    ).collectionsEnabled;
    // 3 tabs if collections enabled, else 2
    final length = collectionEnabled ? 3 : 2;
    _tabController = TabController(
      length: length,
      vsync: this,
      initialIndex: widget.initialIndex < length ? widget.initialIndex : 0,
    );
    _tabController.addListener(_handleTabSelection);
  }

  @override
  void didUpdateWidget(LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialIndex != oldWidget.initialIndex) {
      _tabController.animateTo(widget.initialIndex, duration: Duration.zero);
    }
  }

  void _handleTabSelection() {
    setState(() {});
  }

  final ValueNotifier<int> _refreshNotifier = ValueNotifier<int>(0);

  @override
  void dispose() {
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    _refreshNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final width = MediaQuery.of(context).size.width;
    final isMobile = width <= 600;

    // Get filter tag to force rebuild of BookListScreen when it changes
    final tagFilter = GoRouterState.of(context).uri.queryParameters['tag'];

    return Scaffold(
      appBar: GenieAppBar(
        title: TranslationService.translate(context, 'library'),
        leading: isMobile
            ? IconButton(
                icon: const Icon(Icons.menu, color: Colors.white),
                onPressed: () => Scaffold.of(context).openDrawer(),
              )
            : null,
        automaticallyImplyLeading: false,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          onTap: (index) {
            switch (index) {
              case 0:
                context.go('/books');
                break;
              case 1:
                context.go('/shelves');
                break;
              case 2:
                if (themeProvider.collectionsEnabled) {
                  context.go('/collections');
                }
                break;
            }
          },
          tabs: [
            Tab(
              icon: const Icon(Icons.book),
              text: TranslationService.translate(context, 'books'),
            ),
            Tab(
              icon: const Icon(Icons.shelves),
              text: TranslationService.translate(context, 'shelves'),
            ),
            if (themeProvider.collectionsEnabled)
              Tab(
                icon: const Icon(Icons.collections_bookmark),
                text: TranslationService.translate(context, 'collections'),
              ),
          ],
        ),
        actions: _buildActions(context),
      ),
      body: IndexedStack(
        index: _tabController.index,
        children: [
          BookListScreen(
            key: ValueKey(tagFilter),
            isTabView: true,
            refreshNotifier: _refreshNotifier,
          ),
          const ShelvesScreen(isTabView: true),
          if (themeProvider.collectionsEnabled)
            const CollectionListScreen(isTabView: true),
        ],
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton(
              heroTag: 'library_add_fab',
              key: const Key('addBookButton'),
              onPressed: () async {
                final result = await context.push('/books/add');
                if (result == true) {
                  _refreshNotifier.value++;
                }
              },
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width <= 600;

    // Books Tab (Index 0)
    if (_tabController.index == 0) {
      if (isMobile) {
        return [
          IconButton(
            icon: const Icon(Icons.camera_alt, color: Colors.white),
            tooltip: TranslationService.translate(context, 'btn_scan_book'),
            onPressed: () async {
              final isbn = await context.push<String>('/scan');
              if (isbn != null && context.mounted) {
                final result = await context.push(
                  '/books/add',
                  extra: {'isbn': isbn},
                );
                if (result == true) {
                  _refreshNotifier.value++;
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.travel_explore, color: Colors.white),
            tooltip: TranslationService.translate(
              context,
              'btn_search_online_cta',
            ),
            onPressed: () async {
              final result = await context.push('/search/external');
              if (result == true) {
                _refreshNotifier.value++;
              }
            },
          ),
        ];
      }

      return [
        TextButton.icon(
          icon: const Icon(Icons.camera_alt, color: Colors.white),
          label: Text(
            TranslationService.translate(context, 'btn_scan_book'),
            style: const TextStyle(color: Colors.white),
          ),
          onPressed: () async {
            final isbn = await context.push<String>('/scan');
            if (isbn != null && context.mounted) {
              final result = await context.push(
                '/books/add',
                extra: {'isbn': isbn},
              );
              // Trigger refresh if book was added
              if (result == true) {
                _refreshNotifier.value++;
              }
            }
          },
        ),
        TextButton.icon(
          icon: const Icon(Icons.travel_explore, color: Colors.white),
          label: Text(
            TranslationService.translate(context, 'btn_search_online_cta'),
            style: const TextStyle(color: Colors.white),
          ),
          onPressed: () async {
            final result = await context.push('/search/external');
            // Trigger refresh if book was added from search
            if (result == true) {
              _refreshNotifier.value++;
            }
          },
        ),
      ];
    }

    // Collections Tab (Index 2 if enabled)
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    if (themeProvider.collectionsEnabled && _tabController.index == 2) {
      if (isMobile) {
        return [
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: Text(
              TranslationService.translate(context, 'discover'),
              style: const TextStyle(fontSize: 11),
            ),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      const import_curated.ImportCuratedListScreen(),
                ),
              );
            },
          ),
          const SizedBox(width: 4),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            icon: const Icon(Icons.file_open, size: 16),
            label: Text(
              TranslationService.translate(context, 'import_list'),
              style: const TextStyle(fontSize: 11),
            ),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ImportSharedListScreen(),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
        ];
      }

      return [
        TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.white.withValues(alpha: 0.1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          icon: const Icon(Icons.auto_awesome, size: 16),
          label: Text(TranslationService.translate(context, 'discover')),
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    const import_curated.ImportCuratedListScreen(),
              ),
            );
          },
        ),
        const SizedBox(width: 4),
        TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.white.withValues(alpha: 0.1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          icon: const Icon(Icons.file_open, size: 16),
          label: Text(TranslationService.translate(context, 'import_list')),
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ImportSharedListScreen(),
              ),
            );
          },
        ),
        const SizedBox(width: 8),
      ];
    }

    return [];
  }
}
