import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import '../widgets/genie_app_bar.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../models/book.dart';
// import 'genie_chat_screen.dart'; // Removed as we use route string
import '../providers/theme_provider.dart';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:universal_html/html.dart' as html;
import 'dart:io' as io;
import 'package:dio/dio.dart' show Response;
import 'dart:convert';
import '../services/auth_service.dart';

import '../widgets/premium_book_card.dart';
import '../services/quote_service.dart';
import '../models/quote.dart';
import '../theme/app_design.dart';
import '../services/backup_reminder_service.dart';
import 'statistics_screen.dart';
import '../utils/app_constants.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  Quote? _dailyQuote;
  String? _userName;
  String? _lastLocale;
  final Map<String, dynamic> _stats = {};
  List<Book> _recentBooks = [];
  List<Book> _readingListBooks = [];
  Book? _heroBook;
  String? _libraryName;
  bool _quoteExpanded = false;

  Map<String, dynamic>? _config; // For settings
  Map<String, dynamic>? _userInfo; // For settings
  Map<String, dynamic>? _userStatus; // For settings logic (gamification etc)

  final GlobalKey _addKey = GlobalKey(debugLabel: 'dashboard_add');
  final GlobalKey _statsKey = GlobalKey(debugLabel: 'dashboard_stats');
  final GlobalKey _menuKey = GlobalKey(debugLabel: 'dashboard_menu');

  // Search preferences state
  Map<String, bool> _searchPrefs = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchDashboardData();
    // Verify locale changes on startup/init
    // Removed redundant _fetchDashboardData call in postFrameCallback
    // Add delay to ensure layout is complete and stable before showing wizard
    Future.delayed(const Duration(seconds: 1), _checkWizard);
    _checkBackupReminder();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final themeProvider = Provider.of<ThemeProvider>(context);
    final currentLocale = themeProvider.locale.languageCode;
    if (_lastLocale != null && _lastLocale != currentLocale) {
      _lastLocale = currentLocale;
      _fetchQuote();
    }
  }

  void _checkBackupReminder() async {
    if (await BackupReminderService.shouldShowReminder()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          BackupReminderService.showReminderDialog(context);
        }
      });
    }
  }

  void _checkWizard() async {
    // DISABLED: Dashboard spotlight wizard disabled for alpha release
    // to avoid UI issues during theme transitions
    return;

    /*
    if (!mounted) return;
    
    // Skip wizard completely for Kid profile
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    if (themeProvider.isKid) return;

    if (!await WizardService.hasSeenDashboardWizard()) {
      if (mounted) {
         WizardService.showDashboardWizard(
          context: context,
          addKey: _addKey,
          searchKey: _searchKey,
          statsKey: _statsKey,
          menuKey: _menuKey,
          onFinish: () {},
        );
      }
    }
    */
  }

  Future<void> _fetchDashboardData() async {
    final api = Provider.of<ApiService>(context, listen: false);
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    // Background fetch of translations
    TranslationService.fetchTranslations(context);

    setState(() => _isLoading = true);

    try {
      try {
        print('Dashboard: Fetching books...');
        var books = await api.getBooks();
        print('Dashboard: Books fetched. Count: ${books.length}');

        print('Dashboard: Fetching config...');
        final configRes = await api.getLibraryConfig();
        print('Dashboard: Config fetched. Status: ${configRes.statusCode}');

        if (configRes.statusCode == 200) {
          final config = configRes.data;
          if (config['show_borrowed_books'] != true) {
            books = books.where((b) => b.readingStatus != 'borrowed').toList();
          }
          // Store library name
          final name = config['library_name'] ?? config['name'];
          if (name != null) {
            themeProvider.setLibraryName(name);
          }
          if (mounted) {
            setState(() {
              _libraryName = name;
            });
          }
        }

        if (mounted) {
          setState(() {
            _stats['total_books'] = books.length;
            _stats['borrowed_count'] = books
                .where((b) => b.readingStatus == 'borrowed')
                .length;

            final readingListCandidates = books
                .where((b) => ['reading', 'to_read'].contains(b.readingStatus))
                .toList();

            readingListCandidates.sort((a, b) {
              if (a.readingStatus == 'reading' && b.readingStatus != 'reading')
                return -1;
              if (a.readingStatus != 'reading' && b.readingStatus == 'reading')
                return 1;
              return 0;
            });

            _readingListBooks = readingListCandidates.take(10).toList();

            final readingListIds = _readingListBooks.map((b) => b.id).toSet();

            final recentCandidates = books
                .where((b) => !readingListIds.contains(b.id))
                .toList();
            recentCandidates.sort((a, b) => (b.id ?? 0).compareTo(a.id ?? 0));

            _recentBooks = recentCandidates.take(10).toList();

            _heroBook = _readingListBooks.isNotEmpty
                ? _readingListBooks.first
                : (_recentBooks.isNotEmpty ? _recentBooks.first : null);
            if (_heroBook != null) {
              _readingListBooks.removeWhere((book) => book.id == _heroBook!.id);
              _recentBooks.removeWhere((book) => book.id == _heroBook!.id);
            }
          });
        }
      } catch (e) {
        debugPrint('Error fetching books: $e');
      }

      try {
        print('Dashboard: Fetching contacts...');
        final contactsRes = await api.getContacts();
        print('Dashboard: Contacts fetched.');
        if (contactsRes.statusCode == 200) {
          final List<dynamic> contactsData = contactsRes.data['contacts'];
          if (mounted) {
            setState(() {
              _stats['contacts_count'] = contactsData.length;
            });
          }
        }
      } catch (e) {
        debugPrint('Error fetching contacts: $e');
      }

      try {
        print('Dashboard: Fetching user status...');
        final statusRes = await api.getUserStatus();
        print('Dashboard: User status fetched.');
        if (statusRes.statusCode == 200) {
          final statusData = statusRes.data;
          if (mounted) {
            setState(() {
              _stats['active_loans'] = statusData['loans_count'] ?? 0;
              _userName = statusData['name'];
              _userStatus = statusData; // Store full status for settings

              // Load search prefs from user status
              if (_userStatus != null && _userStatus!['config'] != null) {
                final config = _userStatus!['config'];
                if (config['fallback_preferences'] != null) {
                  final prefs = config['fallback_preferences'] as Map;
                  prefs.forEach((key, value) {
                    if (value is bool) {
                      _searchPrefs[key.toString()] = value;
                    }
                  });
                }
              }
            });
          }
        }

        // Fetch Config and Me for Settings Tab
        print('Dashboard: Fetching config and me...');
        final configRes = await api.getLibraryConfig();
        final meRes = await api.getMe();

        if (mounted) {
          setState(() {
            _config = configRes.data;
            _userInfo = meRes.data;

            // Sync library name from config
            final name = _config?['library_name'] ?? _config?['name'];
            if (name != null) {
              themeProvider.setLibraryName(name);
              _libraryName = name;
            }

            // Sync profile type
            final profileType = _config?['profile_type'];
            if (profileType != null) {
              themeProvider.setProfileType(profileType);
            }
          });
        }
      } catch (e) {
        debugPrint('Error fetching user status: $e');
      }

      // Fetch quote separate from main data to allow localized refresh
      // Only fetch if quotes module is enabled
      if (themeProvider.quotesEnabled) {
        print('Dashboard: Fetching quote...');
        await _fetchQuote();
        print('Dashboard: Quote fetched.');
      }

      if (mounted) {
        print('Dashboard: Loading complete. Setting _isLoading = false');
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching dashboard data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'error_loading_dashboard')}: $e',
            ),
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _fetchQuote() async {
    try {
      final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
      final allBooks = [..._recentBooks, ..._readingListBooks];

      // Even if books are empty, we try to fetch a quote (service handles fallback)
      final quoteService = QuoteService();
      final quote = await quoteService.fetchRandomQuote(
        allBooks,
        locale: themeProvider.locale.languageCode,
      );

      if (mounted) {
        setState(() {
          _dailyQuote = quote;
        });
      }
    } catch (e) {
      debugPrint('Error fetching quote: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isKid = themeProvider.isKid;
    final isLibrarian = themeProvider.isLibrarian;

    debugPrint('DashboardScreen: build called');
    debugPrint(
      'DashboardScreen: isKid=$isKid, isLibrarian=$isLibrarian, isLoading=$_isLoading',
    );
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 600;

    // Greeting logic removed as per user request

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GenieAppBar(
        title: 'BiblioGenius',
        // subtitle: _libraryName, // Handled by ThemeProvider
        leading: isWide
            ? null
            : IconButton(
                key: _menuKey,
                icon: const Icon(Icons.menu, color: Colors.white),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
        automaticallyImplyLeading: false,
        showQuickActions: false,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 4,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withValues(alpha: 0.6),
          isScrollable: !isWide, // Scrollable on mobile to prevent cramping
          tabAlignment: !isWide
              ? TabAlignment.start
              : TabAlignment.fill, // Align start on mobile
          labelStyle: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: isWide ? 16 : 15,
            letterSpacing: 0.5,
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          tabs: [
            Tab(
              icon: const Icon(Icons.dashboard_rounded, size: 22),
              text: TranslationService.translate(context, 'dashboard'),
            ),
            Tab(
              icon: const Icon(Icons.insights_rounded, size: 22),
              text: TranslationService.translate(context, 'nav_statistics'),
            ),
            Tab(
              icon: const Icon(Icons.settings_rounded, size: 22),
              text: TranslationService.translate(context, 'configuration'),
            ),
          ],
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: AppDesign.pageGradientForTheme(
            Provider.of<ThemeProvider>(context).themeStyle,
          ),
        ),
        child: SafeArea(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Tab 1: Dashboard
              _buildDashboardTab(context, isWide, themeProvider, isKid),
              // Tab 2: Statistics
              const StatisticsContent(),
              // Tab 3: Configuration
              _buildConfigurationTab(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardTab(
    BuildContext context,
    bool isWide,
    ThemeProvider themeProvider,
    bool isKid,
  ) {
    return _isLoading
        ? const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          )
        : RefreshIndicator(
            onRefresh: _fetchDashboardData,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(
                top: kToolbarHeight + kTextTabBarHeight,
                left: isWide ? 32 : 16,
                right: isWide ? 32 : 16,
                bottom: 16,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isWide ? 900 : double.infinity,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. [REMOVED] Quick Actions (now in AppBar)
                      // const SizedBox(height: 32),

                      // 2. Header with Quote (if enabled)
                      if (themeProvider.quotesEnabled) ...[
                        _buildHeader(context),
                        const SizedBox(height: 24),
                      ],

                      // Stats Row - Responsive Layout (2x2 on small screens)
                      LayoutBuilder(
                        key: _statsKey,
                        builder: (context, constraints) {
                          // Build list of stat cards based on conditions
                          final statCards = <Widget>[
                            _buildStatCard(
                              context,
                              TranslationService.translate(context, 'my_books'),
                              (_stats['total_books'] ?? 0).toString(),
                              Icons.menu_book,
                              onTap: () => context.push('/books'),
                            ),
                            _buildStatCard(
                              context,
                              TranslationService.translate(
                                context,
                                'lent_status',
                              ),
                              (_stats['active_loans'] ?? 0).toString(),
                              Icons.arrow_upward,
                              isAccent: true,
                            ),
                            if (!themeProvider.isLibrarian)
                              _buildStatCard(
                                context,
                                TranslationService.translate(
                                  context,
                                  'borrowed_status',
                                ),
                                (_stats['borrowed_count'] ?? 0).toString(),
                                Icons.arrow_downward,
                              ),
                            if (!isKid)
                              _buildStatCard(
                                context,
                                themeProvider.isLibrarian
                                    ? TranslationService.translate(
                                        context,
                                        'borrowers',
                                      )
                                    : TranslationService.translate(
                                        context,
                                        'contacts',
                                      ),
                                (_stats['contacts_count'] ?? 0).toString(),
                                Icons.people,
                              ),
                          ];

                          // Use 2x2 grid for narrow screens (< 400px)
                          if (constraints.maxWidth < 400 &&
                              statCards.length > 2) {
                            // Split into rows of 2
                            final firstRow = statCards.take(2).toList();
                            final secondRow = statCards.skip(2).toList();
                            return Column(
                              children: [
                                Row(
                                  children:
                                      firstRow
                                          .expand(
                                            (w) => [
                                              Expanded(child: w),
                                              const SizedBox(width: 12),
                                            ],
                                          )
                                          .toList()
                                        ..removeLast(),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children:
                                      secondRow
                                          .expand(
                                            (w) => [
                                              Expanded(child: w),
                                              const SizedBox(width: 12),
                                            ],
                                          )
                                          .toList()
                                        ..removeLast(),
                                ),
                              ],
                            );
                          }

                          // Use Row for wide screens
                          return Row(
                            children:
                                statCards
                                    .expand(
                                      (w) => [
                                        Expanded(child: w),
                                        const SizedBox(width: 12),
                                      ],
                                    )
                                    .toList()
                                  ..removeLast(),
                          );
                        },
                      ),

                      const SizedBox(height: 24),

                      const SizedBox(height: 32),

                      // Main Content Container
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_heroBook != null && !isKid)
                            // Hero Section
                            _buildHeroBook(context, _heroBook!),

                          // Recent Books
                          if (_recentBooks.isNotEmpty) ...[
                            _buildSectionTitle(
                              context,
                              TranslationService.translate(
                                context,
                                'recent_books',
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 15,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: _buildBookList(
                                context,
                                _recentBooks,
                                TranslationService.translate(
                                  context,
                                  'no_recent_books',
                                ),
                              ),
                            ),
                            const SizedBox(height: 32),
                          ],

                          // Reading List
                          if (_readingListBooks.isNotEmpty) ...[
                            _buildSectionTitle(
                              context,
                              TranslationService.translate(
                                context,
                                'reading_list',
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 15,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: _buildBookList(
                                context,
                                _readingListBooks,
                                TranslationService.translate(
                                  context,
                                  'no_reading_list',
                                ),
                              ),
                            ),
                          ],

                          const SizedBox(height: 32),
                          if (!isKid)
                            Center(
                              child: ScaleOnTap(
                                child: TextButton.icon(
                                  onPressed: () => context.push('/statistics'),
                                  icon: const Icon(
                                    Icons.insights,
                                    color: Colors.black54,
                                  ),
                                  label: Text(
                                    TranslationService.translate(
                                      context,
                                      'view_insights',
                                    ),
                                    style: TextStyle(color: Colors.black54),
                                  ),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 16,
                                    ),
                                    backgroundColor: Colors.black.withValues(
                                      alpha: 0.05,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(30),
                                      side: BorderSide(
                                        color: Colors.black.withValues(
                                          alpha: 0.1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
  }

  Widget _buildConfigurationTab(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    // Safety check for user info
    final hasPassword = _userInfo?['has_password'] ?? false;
    final mfaEnabled = _userInfo?['mfa_enabled'] ?? false;
    final email = _userInfo?['email'] ?? '';

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        top: kToolbarHeight + 48 + MediaQuery.of(context).padding.top + 16,
        left: 16,
        right: 16,
        bottom: 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Modules Section
          Text(
            TranslationService.translate(context, 'modules') ?? 'Modules',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                _buildModuleToggle(
                  context,
                  'quotes_module',
                  'quotes_module_desc',
                  Icons.format_quote,
                  themeProvider.quotesEnabled,
                  (value) => themeProvider.setQuotesEnabled(value),
                ),
                _buildModuleToggle(
                  context,
                  'gamification_module',
                  'gamification_desc',
                  Icons.emoji_events,
                  themeProvider.gamificationEnabled,
                  (value) => themeProvider.setGamificationEnabled(value),
                ),
                _buildModuleToggle(
                  context,
                  'collections_module',
                  'collections_module_desc',
                  Icons.collections_bookmark,
                  themeProvider.collectionsEnabled,
                  (value) => themeProvider.setCollectionsEnabled(value),
                ),
                _buildModuleToggle(
                  context,
                  'commerce_module',
                  'commerce_module_desc',
                  Icons.storefront,
                  themeProvider.commerceEnabled,
                  (value) => themeProvider.setCommerceEnabled(value),
                ),
                _buildModuleToggle(
                  context,
                  'audio_module',
                  'audio_module_desc',
                  Icons.headphones,
                  themeProvider.audioEnabled,
                  (value) => themeProvider.setAudioEnabled(value),
                ),
                _buildModuleToggle(
                  context,
                  'network_module',
                  'network_module_desc',
                  Icons.hub,
                  themeProvider.networkEnabled,
                  (value) => themeProvider.setNetworkEnabled(value),
                ),
                _buildModuleToggle(
                  context,
                  'module_edition_browser',
                  'module_edition_browser_desc',
                  Icons.layers,
                  themeProvider.editionBrowserEnabled,
                  (value) => themeProvider.setEditionBrowserEnabled(value),
                ),
                _buildModuleToggle(
                  context,
                  'enable_borrowing_module',
                  'borrowing_module_desc',
                  Icons.swap_horiz,
                  themeProvider.canBorrowBooks,
                  (value) => themeProvider.setCanBorrowBooks(value),
                ),
                _buildModuleToggle(
                  context,
                  'module_digital_formats',
                  'module_digital_formats_desc',
                  Icons.tablet_mac,
                  themeProvider.digitalFormatsEnabled,
                  (value) => themeProvider.setDigitalFormatsEnabled(value),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.account_tree),
                  title: Text(
                    TranslationService.translate(context, 'enable_taxonomy') ??
                        'Hierarchical Tags',
                  ),
                  subtitle: const Text('Gestion de sous-étagères'),
                  value: AppConstants.enableHierarchicalTags,
                  onChanged: (bool value) async {
                    setState(() {
                      AppConstants.enableHierarchicalTags = value;
                    });
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('enableHierarchicalTags', value);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            TranslationService.translate(
                                  context,
                                  'restart_required_for_changes',
                                ) ??
                                'Please restart the app for changes to take full effect',
                          ),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 24),

          // App Settings Section
          Text(
            TranslationService.translate(context, 'app_settings') ??
                'App Settings',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.library_books),
                  title: Text(
                    TranslationService.translate(context, 'library_name') ??
                        'Library Name',
                  ),
                  subtitle: Text(_libraryName ?? 'My Library'),
                  trailing: const Icon(Icons.edit),
                  onTap: () {
                    // TODO: Implement rename dialog if needed or keep it read-only for now
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(
                    TranslationService.translate(context, 'profile_type') ??
                        'Profile Type',
                  ),
                  subtitle: Text(themeProvider.profileType.toUpperCase()),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 24),

          // Security Section
          Text(
            TranslationService.translate(context, 'security') ?? 'Security',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.lock),
                  title: Text(
                    TranslationService.translate(context, 'password') ??
                        'Password',
                  ),
                  subtitle: Text(
                    hasPassword
                        ? '********'
                        : (TranslationService.translate(context, 'not_set') ??
                              'Not set'),
                  ),
                  trailing: TextButton(
                    onPressed: _showChangePasswordDialog,
                    child: Text(
                      TranslationService.translate(context, 'change') ??
                          'Change',
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.security),
                  title: Text(
                    TranslationService.translate(context, 'two_factor_auth') ??
                        'Two-Factor Authentication',
                  ),
                  subtitle: Text(
                    mfaEnabled
                        ? (TranslationService.translate(context, 'enabled') ??
                              'Enabled')
                        : (TranslationService.translate(context, 'disabled') ??
                              'Disabled'),
                  ),
                  trailing: Switch(
                    value: mfaEnabled,
                    onChanged: (val) {
                      if (val) {
                        _setupMfa();
                      } else {
                        // Disable MFA logic (todo)
                      }
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 24),

          // Search Configuration
          _buildSearchConfiguration(context),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 24),

          // Integrations
          _buildMcpIntegrationSection(),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 24),

          // Data Management
          Text(
            TranslationService.translate(context, 'data_management') ??
                'Data Management',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              ElevatedButton.icon(
                onPressed: _exportData,
                icon: const Icon(Icons.download),
                label: Text(
                  TranslationService.translate(context, 'export_backup') ??
                      'Export Backup',
                ),
              ),
              ElevatedButton.icon(
                onPressed: _importBackup,
                icon: const Icon(Icons.upload),
                label: Text(
                  TranslationService.translate(context, 'import_backup') ??
                      'Import Backup',
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => context.push('/shelves-management'),
                icon: const Icon(Icons.folder_special),
                label: Text(
                  TranslationService.translate(context, 'manage_shelves') ??
                      'Manage Shelves',
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 24),

          // Session / Logout
          OutlinedButton.icon(
            onPressed: () async {
              final authService = Provider.of<AuthService>(
                context,
                listen: false,
              );
              // Small delay to ensure any pending theme/UI updates are settled
              await Future.delayed(const Duration(milliseconds: 200));

              await authService.logout();
              if (mounted) {
                context.go('/login');
              }
            },
            icon: const Icon(Icons.logout),
            label: Text(TranslationService.translate(context, 'logout')),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              foregroundColor: Colors.red,
            ),
          ),
          const SizedBox(height: 100), // Bottom padding
        ],
      ),
    );
  }

  Widget _buildSearchConfiguration(BuildContext context) {
    // Defaults matching ExternalSearchScreen logic
    final deviceLang = Localizations.localeOf(context).languageCode;
    final bnfDefault = deviceLang == 'fr';
    final googleDefault = false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          TranslationService.translate(context, 'search_sources') ??
              'Search Sources',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              _buildSwitchTile(
                context,
                'Inventaire.io',
                'source_inventaire_desc',
                _searchPrefs['inventaire'] ?? true,
                (val) => _updateSearchPreference('inventaire', val),
                icon: Icons.language,
              ),
              _buildSwitchTile(
                context,
                'Bibliothèque Nationale (BNF)',
                'source_bnf_desc',
                _searchPrefs['bnf'] ?? bnfDefault,
                (val) => _updateSearchPreference('bnf', val),
                icon: Icons.account_balance,
              ),
              _buildSwitchTile(
                context,
                'OpenLibrary',
                'source_openlibrary_desc',
                _searchPrefs['openlibrary'] ?? true,
                (val) => _updateSearchPreference('openlibrary', val),
                icon: Icons.local_library,
              ),
              _buildSwitchTile(
                context,
                'Google Books',
                'source_google_desc',
                _searchPrefs['google_books'] ?? googleDefault,
                (val) => _updateSearchPreference('google_books', val),
                icon: Icons.search,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchTile(
    BuildContext context,
    String title,
    String subtitleKey,
    bool value,
    ValueChanged<bool> onChanged, {
    IconData? icon,
  }) {
    return SwitchListTile(
      secondary: icon != null ? Icon(icon) : null,
      title: Text(title),
      subtitle: Text(
        TranslationService.translate(context, subtitleKey) ?? subtitleKey,
      ),
      value: value,
      onChanged: onChanged,
    );
  }

  Future<void> _updateSearchPreference(String source, bool enabled) async {
    setState(() {
      _searchPrefs[source] = enabled;
    });

    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.updateGamificationConfig(fallbackPreferences: _searchPrefs);

      // Update local _userStatus config to reflect changes
      if (_userStatus != null) {
        if (_userStatus!['config'] == null) {
          _userStatus!['config'] = {};
        }
        _userStatus!['config']['fallback_preferences'] = _searchPrefs;
      }
    } catch (e) {
      debugPrint('Error updating search preference: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'error_update')}: $e',
            ),
          ),
        );
      }
    }
  }

  Widget _buildModuleToggle(
    BuildContext context,
    String titleKey,
    String descKey,
    IconData icon,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: SwitchListTile(
        secondary: Icon(icon),
        title: Text(TranslationService.translate(context, titleKey)),
        subtitle: Text(TranslationService.translate(context, descKey)),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    if (_dailyQuote == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Theme-aware colors - dark wood for Sorbonne, warm gradient for light themes
    final bgColor = isDark
        ? const Color(0xFF2D1810)
        : const Color(0xFFFFFBF5); // Warm cream white
    final gradientColors = isDark
        ? [const Color(0xFF2D1810), const Color(0xFF3D2518)]
        : [
            const Color(0xFFFFF8F0),
            const Color(0xFFFFE8D6),
          ]; // Warm peach gradient
    final textColor = isDark
        ? const Color(0xFFC4A35A)
        : const Color(0xFF8B5A2B); // Richer brown

    // Check if quote is long (more than ~100 chars typically needs expansion)
    final isLongQuote = _dailyQuote!.text.length > 120;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        GestureDetector(
          onTap: isLongQuote
              ? () => setState(() => _quoteExpanded = !_quoteExpanded)
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradientColors,
              ),
              borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
              border: isDark
                  ? Border.all(color: const Color(0xFF5D3A1A), width: 1)
                  : Border.all(color: const Color(0xFFE8D4C4), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                // Decorative background icon
                Positioned(
                  right: -20,
                  top: -16,
                  child: Icon(
                    Icons.format_quote_rounded,
                    size: 120,
                    color: textColor.withValues(alpha: 0.08),
                  ),
                ),
                // Content
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedCrossFade(
                        duration: const Duration(milliseconds: 200),
                        crossFadeState: _quoteExpanded || !isLongQuote
                            ? CrossFadeState.showSecond
                            : CrossFadeState.showFirst,
                        firstChild: Text(
                          _dailyQuote!.text,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.4,
                            fontStyle: FontStyle.italic,
                            color: textColor,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        secondChild: Text(
                          _dailyQuote!.text,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.4,
                            fontStyle: FontStyle.italic,
                            color: textColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Expand/collapse indicator for long quotes
                          if (isLongQuote)
                            AnimatedRotation(
                              duration: const Duration(milliseconds: 200),
                              turns: _quoteExpanded ? 0.5 : 0,
                              child: Icon(
                                Icons.keyboard_arrow_down,
                                size: 20,
                                color: textColor.withValues(alpha: 0.6),
                              ),
                            )
                          else
                            const SizedBox.shrink(),
                          // Author attribution
                          Expanded(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Container(
                                  width: 16,
                                  height: 1,
                                  color: textColor.withValues(alpha: 0.3),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    _dailyQuote!.author,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: textColor,
                                      letterSpacing: 0.3,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    bool isAccent = false,
    VoidCallback? onTap,
  }) {
    final isSorbonne =
        Provider.of<ThemeProvider>(context, listen: false).themeStyle ==
        'sorbonne';
    final cardBg = isAccent
        ? Theme.of(context).primaryColor
        : (isSorbonne ? const Color(0xFF2D1810) : Colors.white);
    final borderClr = isAccent
        ? Colors.transparent
        : (isSorbonne
              ? const Color(0xFF5D3A1A)
              : Colors.grey.withValues(alpha: 0.3));
    final iconClr = isAccent
        ? Colors.white
        : (isSorbonne
              ? const Color(0xFFC4A35A)
              : Theme.of(context).primaryColor);
    final valueClr = isAccent
        ? Colors.white
        : (isSorbonne ? const Color(0xFFD4A855) : Colors.black87);
    final labelClr = isAccent
        ? Colors.white70
        : (isSorbonne ? const Color(0xFF8B7355) : Colors.black54);

    return ScaleOnTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderClr),
          boxShadow: isAccent
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ]
              : AppDesign.subtleShadow,
        ),
        child: Builder(
          builder: (context) {
            final isDesktop = MediaQuery.of(context).size.width > 600;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: iconClr, size: isDesktop ? 28 : 24),
                SizedBox(height: isDesktop ? 16 : 12),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: isDesktop ? 32 : 24,
                    fontWeight: FontWeight.bold,
                    color: valueClr,
                  ),
                ),
                SizedBox(height: isDesktop ? 6 : 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: isDesktop ? 14 : 12,
                    fontWeight: FontWeight.w500,
                    color: labelClr,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    IconData icon = Icons.auto_stories;
    if (title.toLowerCase().contains('recent') ||
        title.toLowerCase().contains('récent')) {
      icon = Icons.history;
    } else if (title.toLowerCase().contains('reading') ||
        title.toLowerCase().contains('lecture')) {
      icon = Icons.bookmark;
    } else if (title.toLowerCase().contains('action')) {
      icon = Icons.bolt;
    }

    final isSorbonne =
        Provider.of<ThemeProvider>(context, listen: false).themeStyle ==
        'sorbonne';
    final accentColors = isSorbonne
        ? [const Color(0xFF8B4513), const Color(0xFF5D3A1A)]
        : [const Color(0xFF667eea), const Color(0xFF764ba2)];
    final iconColor = isSorbonne
        ? const Color(0xFFC4A35A)
        : const Color(0xFF667eea);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 28,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: accentColors,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isSorbonne ? const Color(0xFFD4A855) : Colors.black87,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionCard(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required double width,
  }) {
    return ScaleOnTap(
      onTap: onTap,
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.1), width: 1.5),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookList(
    BuildContext context,
    List<Book> books,
    String emptyMessage,
  ) {
    if (books.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: AppDesign.glassDecoration(),
        child: Center(
          child: Text(
            emptyMessage,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
        ),
      );
    }

    return SizedBox(
      height: 260,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: books.length,
        padding: const EdgeInsets.only(top: 8, bottom: 4, left: 4, right: 4),
        clipBehavior: Clip.none,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(right: 16),
            child: PremiumBookCard(book: books[index]),
          );
        },
      ),
    );
  }

  Widget _buildHeroBook(BuildContext context, Book book) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: SizedBox(
        width: double.infinity,
        height: 300,
        child: PremiumBookCard(
          book: book,
          isHero: true,
          width: double.infinity,
          height: 300,
        ),
      ),
    );
  }

  Widget _buildKidActionCard(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap, {
    Key? key,
  }) {
    return ScaleOnTap(
      onTap: onTap,
      child: Container(
        key: key,
        height: 140,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: AppDesign.subtleShadow,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: color),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMcpIntegrationSection() {
    return Consumer<ThemeProvider>(
      builder: (context, theme, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              TranslationService.translate(context, 'integrations') ??
                  'Integrations',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Card(
              child: SwitchListTile(
                title: const Text('MCP Server'),
                subtitle: const Text(
                  'Enable Model Context Protocol integration for Claude Desktop',
                ),
                secondary: const Icon(Icons.integration_instructions),
                value: theme.mcpEnabled,
                onChanged: (val) => theme.setMcpEnabled(val),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportData() async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'preparing_backup'),
            ),
          ),
        );
      }

      final apiService = Provider.of<ApiService>(context, listen: false);
      final response = await apiService.exportData();

      if (kIsWeb) {
        // Web export: trigger download directly
        final blob = html.Blob([response.data]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute(
            'download',
            'bibliogenius_backup_${DateTime.now().toIso8601String().split('T')[0]}.json',
          )
          ..click();
        html.Url.revokeObjectUrl(url);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                TranslationService.translate(context, 'backup_downloaded'),
              ),
            ),
          );
        }
      } else {
        // Mobile/Desktop export: use share_plus
        final directory = await getTemporaryDirectory();
        final filename =
            'bibliogenius_backup_${DateTime.now().toIso8601String().split('T')[0]}.json';
        final file = io.File('${directory.path}/$filename');
        await file.writeAsBytes(response.data);

        await Share.shareXFiles([
          XFile(file.path),
        ], text: 'My BiblioGenius Backup');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'export_fail')}: $e',
            ),
          ),
        );
      }
    }
  }

  Future<void> _importBackup() async {
    try {
      // Pick a file (JSON for backup, CSV/TXT for book list)
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'csv', 'txt'],
        withData: kIsWeb,
      );

      if (result == null || result.files.isEmpty) {
        return; // User cancelled
      }

      final file = result.files.first;
      final extension = file.extension?.toLowerCase();

      // If it's a CSV or TXT, redirect to book import
      if (extension == 'csv' || extension == 'txt') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                TranslationService.translate(context, 'importing_books'),
              ),
            ),
          );
        }

        final apiService = Provider.of<ApiService>(context, listen: false);
        late final Response response;

        if (kIsWeb) {
          // On web, bytes are loaded into memory
          if (file.bytes == null) throw Exception('No file data');
          response = await apiService.importBooks(
            file.bytes!,
            filename: file.name,
          );
        } else {
          // On native, use path
          if (file.path == null) throw Exception('No file path');
          response = await apiService.importBooks(file.path!);
        }

        if (mounted) {
          if (response.statusCode == 200) {
            final imported = response.data['imported'];
            _fetchDashboardData(); // Refresh

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${TranslationService.translate(context, 'import_success')} $imported ${TranslationService.translate(context, 'books')}',
                ),
                backgroundColor: Colors.green,
              ),
            );
          } else {
            throw Exception(response.data['error'] ?? 'Import failed');
          }
        }
        return;
      }

      // JSON Backup Import Logic
      List<int> bytes;
      if (kIsWeb) {
        if (file.bytes == null) throw Exception('Could not read file');
        bytes = file.bytes!;
      } else {
        if (file.path == null) throw Exception('File path is null');
        final ioFile = io.File(file.path!);
        bytes = await ioFile.readAsBytes();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'importing_backup'),
            ),
          ),
        );
      }

      final apiService = Provider.of<ApiService>(context, listen: false);
      final response = await apiService.importBackup(bytes);

      if (response.statusCode == 200) {
        final data = response.data;
        final booksCount = data['books_imported'] ?? 0;
        final message = data['message'] ?? 'Import successful';

        if (mounted) {
          _fetchDashboardData();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$message - $booksCount ${TranslationService.translate(context, 'books_imported')}',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception(response.data['error'] ?? 'Import failed');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'import_fail')}: $e',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _setupMfa() async {
    final apiService = Provider.of<ApiService>(context, listen: false);

    // Check if we're in FFI/local mode where MFA is not supported
    if (apiService.useFfi) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.info_outline, color: Theme.of(context).primaryColor),
              const SizedBox(width: 8),
              Text(
                TranslationService.translate(context, 'two_factor_auth') ??
                    'Two-Factor Authentication',
              ),
            ],
          ),
          content: Text(
            TranslationService.translate(context, 'mfa_requires_server') ??
                'Two-factor authentication is only available when connected to a remote BiblioGenius server. In local mode, your data is already secured on your device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(TranslationService.translate(context, 'ok') ?? 'OK'),
            ),
          ],
        ),
      );
      return;
    }

    try {
      final response = await apiService.setup2Fa();
      final data = response.data;
      final secret = data['secret'];
      final qrCode = data['qr_code']; // Base64 string

      if (!mounted) return;

      final codeController = TextEditingController();
      String? verifyError;

      await showDialog(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(
              TranslationService.translate(context, 'setup_2fa') ?? 'Setup 2FA',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    TranslationService.translate(context, 'scan_qr_code') ??
                        'Scan this QR code with your authenticator app:',
                  ),
                  const SizedBox(height: 16),
                  if (qrCode != null)
                    Image.memory(base64Decode(qrCode), height: 200, width: 200),
                  const SizedBox(height: 16),
                  SelectableText(
                    '${TranslationService.translate(context, 'secret_key') ?? 'Secret Key'}: $secret',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: codeController,
                    decoration: InputDecoration(
                      labelText:
                          TranslationService.translate(
                            context,
                            'verification_code',
                          ) ??
                          'Verification Code',
                      errorText: verifyError,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  TranslationService.translate(context, 'cancel') ?? 'Cancel',
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  setState(() => verifyError = null);
                  final code = codeController.text.trim();
                  if (code.length != 6) {
                    setState(
                      () => verifyError =
                          TranslationService.translate(
                            context,
                            'invalid_code',
                          ) ??
                          'Invalid code',
                    );
                    return;
                  }

                  try {
                    await apiService.verify2Fa(secret, code);
                    if (mounted) {
                      Navigator.pop(context); // Close dialog
                      _fetchDashboardData(); // Refresh status
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            TranslationService.translate(
                                  context,
                                  'mfa_enabled_success',
                                ) ??
                                'MFA Enabled Successfully',
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    setState(
                      () => verifyError =
                          TranslationService.translate(
                            context,
                            'verification_failed',
                          ) ??
                          'Verification failed',
                    );
                  }
                },
                child: Text(
                  TranslationService.translate(context, 'verify') ?? 'Verify',
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'error_initializing_mfa') ?? 'Error initializing MFA'}: $e',
            ),
          ),
        );
      }
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final hasPassword = await authService.hasPasswordSet();

    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    String? errorText;

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            hasPassword
                ? (TranslationService.translate(context, 'change_password') ??
                      'Change Password')
                : (TranslationService.translate(context, 'set_password') ??
                      'Set Password'),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!hasPassword)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      TranslationService.translate(
                            context,
                            'first_time_password',
                          ) ??
                          'Set a password to protect your data',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                if (hasPassword)
                  TextField(
                    controller: currentPasswordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText:
                          TranslationService.translate(
                            context,
                            'current_password',
                          ) ??
                          'Current Password',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                if (hasPassword) const SizedBox(height: 16),
                TextField(
                  controller: newPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText:
                        TranslationService.translate(context, 'new_password') ??
                        'New Password',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: confirmPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText:
                        TranslationService.translate(
                          context,
                          'confirm_password',
                        ) ??
                        'Confirm Password',
                    errorText: errorText,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                TranslationService.translate(context, 'cancel') ?? 'Cancel',
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                // Validate
                if (newPasswordController.text.length < 4) {
                  setState(
                    () => errorText =
                        TranslationService.translate(
                          context,
                          'password_too_short',
                        ) ??
                        'Password must be at least 4 characters',
                  );
                  return;
                }
                if (newPasswordController.text !=
                    confirmPasswordController.text) {
                  setState(
                    () => errorText =
                        TranslationService.translate(
                          context,
                          'passwords_dont_match',
                        ) ??
                        'Passwords do not match',
                  );
                  return;
                }

                if (hasPassword) {
                  // Verify old password first
                  final isValid = await authService.verifyPassword(
                    currentPasswordController.text,
                  );
                  if (!isValid) {
                    setState(
                      () => errorText =
                          TranslationService.translate(
                            context,
                            'password_incorrect',
                          ) ??
                          'Incorrect password',
                    );
                    return;
                  }
                  // Change password
                  await authService.changePassword(
                    currentPasswordController.text,
                    newPasswordController.text,
                  );
                } else {
                  // First time setting password
                  await authService.savePassword(newPasswordController.text);
                }

                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        TranslationService.translate(
                              context,
                              'password_changed_success',
                            ) ??
                            'Password changed successfully',
                      ),
                    ),
                  );
                }
              },
              child: Text(
                TranslationService.translate(context, 'save') ?? 'Save',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
