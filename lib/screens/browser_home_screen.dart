import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/artwork_item.dart';
import '../services/service_manager.dart';
import '../services/met_museum_service.dart';
import '../services/smithsonian_service.dart';
import '../services/iiif_service.dart';
import '../services/openverse_service.dart';
import 'image_detail_screen.dart';

class BrowserHomeScreen extends StatefulWidget {
  const BrowserHomeScreen({super.key});

  @override
  State<BrowserHomeScreen> createState() => _BrowserHomeScreenState();
}

class _BrowserHomeScreenState extends State<BrowserHomeScreen>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late TabController _tabController;
  late AnimationController _shimmerController;
  late Animation<double> _shimmerAnimation;
  late ServiceManager _serviceManager;

  List<ArtworkItem> _randomArtworks = [];
  List<ArtworkItem> _searchResults = [];
  bool _isLoading = false;
  bool _isRefreshing = false; // Track refresh state separately
  bool _isSearching = false;
  bool _isLoadingMore = false;
  DateTime? _lastRateLimitTime; // Track when we last got rate limited
  String _errorMessage = '';
  int _retryCount = 0;
  static const int maxRetries = 3;

  // Search result caching per service
  // Structure: Map<serviceId, Map<query, List<ArtworkItem>>>
  final Map<String, Map<String, List<ArtworkItem>>> _searchCache = {};
  final Map<String, List<ArtworkItem>> _randomCache =
      {}; // Cache random results too

  // Track if we've loaded data to prevent unnecessary reloads after navigation
  bool _hasInitiallyLoaded = false;
  double _lastScrollPosition = 0.0; // Track scroll position for restoration

  // Search debouncing and cancellation
  Timer? _searchDebounceTimer;
  Completer<void>? _currentSearchCompleter;
  static const Duration _searchDebounceDelay = Duration(milliseconds: 500);

  // Dynamic tab management
  List<String> _availableServiceIds = [];
  List<Tab> _availableTabs = [];

  @override
  void initState() {
    super.initState();

    // Initialize ServiceManager and register services
    _serviceManager = ServiceManager();
    _serviceManager.registerService(MetMuseumService());
    _serviceManager.registerService(SmithsonianService());
    _serviceManager.registerService(IIIFService());
    _serviceManager.registerService(OpenverseService());

    // Build dynamic tab system based on available services
    _buildDynamicTabs();
    _tabController = TabController(
      length: _availableServiceIds.length,
      vsync: this,
    );

    // Initialize shimmer animation
    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _shimmerAnimation = Tween<double>(begin: -2.0, end: 2.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );

    _shimmerController.repeat();

    // Add scroll listener for infinite scroll
    _scrollController.addListener(_onScroll);

    // Add tab controller listener to switch services
    _tabController.addListener(_onTabChanged);

    // Use post-frame callback to ensure widget is fully built before loading
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Check if we have cached data for current service before loading
      final currentServiceId = _serviceManager.activeServiceId;
      if (_randomCache.containsKey(currentServiceId)) {
        // Use cached data and don't reload
        setState(() {
          _randomArtworks = _randomCache[currentServiceId]!;
          _hasInitiallyLoaded = true;
        });
      } else if (!_hasInitiallyLoaded) {
        // Only load if we haven't loaded before
        _loadRandomArtworks(); // Initial load uses regular loading state
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _shimmerController.dispose();
    _scrollController.dispose();

    // Clean up search resources
    _searchDebounceTimer?.cancel();
    _currentSearchCompleter?.complete();

    super.dispose();
  }

  void _onScroll() {
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final threshold = maxScroll - 200;

    if (currentScroll >= threshold) {
      // Start loading more when user is 200px from bottom
      // But avoid spamming when rate limited
      final now = DateTime.now();
      final rateLimitCooldown =
          _lastRateLimitTime != null &&
          now.difference(_lastRateLimitTime!).inSeconds < 10;

      if (!_isLoadingMore &&
          !_isLoading &&
          !_isSearching &&
          !rateLimitCooldown) {
        final currentQuery = _searchController.text.trim();
        if (currentQuery.isEmpty) {
          // Load more random artworks
          _loadMoreArtworks();
        } else {
          // Load more search results
          _loadMoreSearchResults(currentQuery);
        }
      }
    }
  }

  void _buildDynamicTabs() {
    // Always include 'All' as the first tab
    _availableServiceIds = ['all'];
    _availableTabs = [const Tab(text: 'All')];

    // Add tabs for available services
    final services = _serviceManager.availableServices;
    for (final service in services) {
      _availableServiceIds.add(service.serviceId);

      String tabLabel;
      switch (service.serviceId) {
        case 'met-museum':
          tabLabel = 'Met Museum';
          break;
        case 'smithsonian':
          tabLabel = 'Smithsonian';
          break;
        case 'iiif':
          tabLabel = 'Library';
          break;
        case 'openverse':
          tabLabel = 'Openverse';
          break;
        default:
          tabLabel = service.serviceName;
      }
      _availableTabs.add(Tab(text: tabLabel));
    }
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;

    // Use dynamic service IDs instead of hardcoded list
    final selectedServiceId = _availableServiceIds[_tabController.index];

    // Only switch if it's an available service (all services in _availableServiceIds are available by definition)
    if (_availableServiceIds.contains(selectedServiceId)) {
      _serviceManager.setActiveService(selectedServiceId);
      print('BrowserHomeScreen: Switched to service: $selectedServiceId');

      // Check if we're currently searching
      final currentQuery = _searchController.text.trim();

      if (currentQuery.isEmpty) {
        // Handle random artwork loading with smart preservation
        if (_randomCache.containsKey(selectedServiceId)) {
          // Use cached random results - ensure immediate display
          setState(() {
            _randomArtworks = List<ArtworkItem>.from(
              _randomCache[selectedServiceId]!,
            );
            _searchResults = [];
            _isLoading = false;
            _isSearching = false;
          });
        } else {
          // Preserve existing artworks from the target service and load more
          _switchToServiceWithPreservation(selectedServiceId);
        }
      } else {
        // Handle search results with caching
        if (_searchCache.containsKey(selectedServiceId) &&
            _searchCache[selectedServiceId]!.containsKey(currentQuery)) {
          // Use cached search results - instant tab switching!
          final cachedResults = _searchCache[selectedServiceId]![currentQuery]!;
          setState(() {
            _searchResults = List<ArtworkItem>.from(cachedResults);
            _randomArtworks = [];
            _isLoading = false;
            _isSearching = false;
          });
        } else {
          // Need to perform search for this service
          setState(() {
            _searchResults = [];
            _randomArtworks = [];
            _isSearching = true; // Show loading state
          });
          _performSearch(currentQuery);
        }
      }
    }
  }

  Future<void> _switchToServiceWithPreservation(
    String selectedServiceId,
  ) async {
    print(
      'BrowserHomeScreen: Switching to service with preservation: $selectedServiceId',
    );

    // Extract existing artworks that match the target service
    List<ArtworkItem> preservedArtworks = [];

    if (selectedServiceId != 'all') {
      // Get the service name to match against artwork.source
      String targetSource = _getSourceNameFromServiceId(selectedServiceId);
      print('BrowserHomeScreen: Looking for artworks from: $targetSource');

      preservedArtworks =
          _randomArtworks
              .where((artwork) => artwork.source == targetSource)
              .toList();

      print(
        'BrowserHomeScreen: Found ${preservedArtworks.length} preserved artworks from $targetSource',
      );
    }

    // Clear current display and show preserved artworks immediately
    setState(() {
      _randomArtworks = preservedArtworks;
      _searchResults = [];
      _isLoading = false; // Prevent loading state flicker
      _isSearching = false;
    });

    // Calculate how many more artworks we need
    const targetCount = 24; // Reduced target for faster loading
    final needsMore = targetCount - preservedArtworks.length;

    print(
      'BrowserHomeScreen: Need $needsMore more artworks (have ${preservedArtworks.length}, target $targetCount)',
    );

    if (needsMore > 0) {
      // Load additional artworks to reach target count
      await _loadAdditionalRandomArtworks(needsMore);
    }
  }

  String _getSourceNameFromServiceId(String serviceId) {
    switch (serviceId) {
      case 'met-museum':
        return 'Met Museum';
      case 'smithsonian':
        return 'Smithsonian';
      case 'iiif':
        return 'Library of Congress';
      case 'openverse':
        return 'Openverse';
      default:
        return '';
    }
  }

  Future<void> _loadAdditionalRandomArtworks(int count) async {
    try {
      final additionalArtworks = await _serviceManager.getRandomArtworks(count);

      if (mounted && additionalArtworks.isNotEmpty) {
        setState(() {
          _randomArtworks.addAll(additionalArtworks);
        });

        // Cache the combined results
        final currentServiceId = _serviceManager.activeServiceId;
        _randomCache[currentServiceId] = _randomArtworks;
      }
    } catch (e) {
      print('Error loading additional artworks: $e');
      // If loading fails, at least we have the preserved artworks
    }
  }

  Future<void> _loadMoreArtworks() async {
    if (_isLoadingMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      // Try to get a good batch size - keep requesting until we get at least 5 new artworks
      List<ArtworkItem> allNewArtworks = [];
      int attempts = 0;
      const maxAttempts = 3;
      const targetCount = 5; // Minimum artworks to add per scroll

      while (allNewArtworks.length < targetCount && attempts < maxAttempts) {
        attempts++;

        final batchSize =
            attempts == 0
                ? 8
                : 12 + (attempts * 5); // Increase batch size on retries
        final moreArtworks = await _serviceManager.getRandomArtworks(batchSize);

        // Add unique artworks (avoid duplicates)
        for (final artwork in moreArtworks) {
          final isDuplicate =
              allNewArtworks.any(
                (existing) => existing.objectId == artwork.objectId,
              ) ||
              _randomArtworks.any(
                (existing) => existing.objectId == artwork.objectId,
              );
          if (!isDuplicate) {
            allNewArtworks.add(artwork);
          }
        }

        // If we got no new artworks in this batch, break early
        if (moreArtworks.isEmpty) {
          break;
        }
      }

      if (mounted && allNewArtworks.isNotEmpty) {
        setState(() {
          _randomArtworks.addAll(allNewArtworks);
          _isLoadingMore = false;
        });
      } else {
        if (mounted) {
          setState(() {
            _isLoadingMore = false;
          });
        }
      }
    } catch (e) {
      String errorMsg = e.toString();
      if (errorMsg.contains('Rate limited') ||
          errorMsg.contains('403') ||
          errorMsg.contains('All services are rate limited')) {
        // Mark the time we got rate limited to prevent spam
        _lastRateLimitTime = DateTime.now();
      } else {
        print('Error loading more artworks: $e');
      }

      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMoreSearchResults(String query) async {
    if (_isLoadingMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      // Calculate offset based on current results
      final currentOffset = _searchResults.length;
      const batchSize = 10; // Load 10 more results at a time

      final moreResults = await _serviceManager.searchArtworks(
        query,
        limit: batchSize,
        offset: currentOffset,
      );

      if (mounted && moreResults.isNotEmpty) {
        setState(() {
          _searchResults.addAll(moreResults);
          _isLoadingMore = false;
        });

        // Update cache with new results
        _cacheSearchResults(query, _searchResults);
      } else {
        if (mounted) {
          setState(() {
            _isLoadingMore = false;
          });
        }
      }
    } catch (e) {
      String errorMsg = e.toString();
      if (errorMsg.contains('Rate limited') ||
          errorMsg.contains('403') ||
          errorMsg.contains('All services are rate limited')) {
        // Mark the time we got rate limited to prevent spam
        _lastRateLimitTime = DateTime.now();
      } else {
        print('Error loading more search results: $e');
      }

      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadRandomArtworks({bool isRefresh = false}) async {
    if ((!isRefresh && _isLoading) || (isRefresh && _isRefreshing)) return;

    // Prevent multiple concurrent loads
    if (_isLoadingMore) return;

    if (mounted) {
      setState(() {
        if (isRefresh) {
          _isRefreshing = true;
        } else {
          _isLoading = true;
        }
        _errorMessage = '';
      });
    }

    try {
      final artworks = await _serviceManager.getRandomArtworks(
        48,
      ); // Request 12 per service (4 services) to ensure min 9 each

      if (mounted) {
        setState(() {
          _randomArtworks = artworks;
          _isLoading = false;
          _isRefreshing = false;
          _retryCount = 0; // Reset retry count on success
          _hasInitiallyLoaded =
              true; // Mark that we've successfully loaded data
        });

        // Cache random results for current service
        final currentServiceId = _serviceManager.activeServiceId;
        _randomCache[currentServiceId] = artworks;
      }
    } catch (e) {
      if (mounted) {
        String errorMsg = e.toString();

        // Show user-friendly messages for common errors
        if (errorMsg.contains('Rate limited')) {
          errorMsg =
              'API rate limited - please wait a moment before refreshing';
        } else if (errorMsg.contains('403')) {
          errorMsg =
              'API temporarily unavailable - please try again in a moment';
        } else if (errorMsg.contains('timeout')) {
          errorMsg = 'Connection timeout - check your internet connection';
        }

        setState(() {
          _isLoading = false;
          _isRefreshing = false;
          _errorMessage = 'Failed to load artworks: $errorMsg';
        });

        // Don't auto-retry if rate limited - let user manually refresh
        // Also increase delay to give API more time to recover
        if (_randomArtworks.isEmpty &&
            _retryCount < maxRetries &&
            !errorMsg.contains('Rate limited') &&
            !errorMsg.contains('403')) {
          Future.delayed(const Duration(seconds: 5), () {
            if (mounted) {
              _retryWithBackoff();
            }
          });
        }
      }
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      _retryCount = 0; // Reset retry count when manually refreshing
      _isLoadingMore = false; // Reset loading more state
      _randomArtworks.clear(); // Clear existing artworks
      _hasInitiallyLoaded = false; // Reset loaded flag to allow fresh loading
    });

    // Clear service caches
    _serviceManager.clearAllCaches();

    // Clear our local search and random caches
    _searchCache.clear();
    _randomCache.clear();

    await _loadRandomArtworks(isRefresh: true);
  }

  Future<void> _retryWithBackoff() async {
    if (_retryCount >= maxRetries) {
      if (mounted) {
        setState(() {
          _errorMessage =
              'Max retries reached. Pull down to refresh or try again.';
        });
      }
      return;
    }

    _retryCount++;

    // Exponential backoff: wait 2^retryCount seconds
    await Future.delayed(Duration(seconds: 2 * _retryCount));

    if (mounted) {
      await _loadRandomArtworks();
    }
  }

  void _onSearchChanged(String query) {
    // Cancel any existing search timer
    _searchDebounceTimer?.cancel();

    if (query.isEmpty) {
      _cancelCurrentSearch();
      setState(() {
        _searchResults = [];
        _isSearching = false;
        _errorMessage = '';
      });
      return;
    }

    // Start new debounce timer
    _searchDebounceTimer = Timer(_searchDebounceDelay, () {
      _performSearch(query);
    });
  }

  void _cancelCurrentSearch() {
    // Cancel any ongoing search
    if (_currentSearchCompleter != null &&
        !_currentSearchCompleter!.isCompleted) {
      _currentSearchCompleter!.complete();
    }
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) return;

    // Cancel any previous search
    _cancelCurrentSearch();

    // Create new search completer
    _currentSearchCompleter = Completer<void>();

    setState(() {
      _isSearching = true;
      _errorMessage = '';
    });

    try {
      final results = await _serviceManager.searchArtworks(query, limit: 20);

      // Check if this search was cancelled
      if (_currentSearchCompleter!.isCompleted) {
        return; // Search was cancelled, don't update UI
      }

      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });

        // Cache results per service for future tab switching
        _cacheSearchResults(query, results);
      }
    } catch (e) {
      // Check if this search was cancelled
      if (_currentSearchCompleter!.isCompleted) {
        return; // Search was cancelled, don't update UI
      }

      if (mounted) {
        setState(() {
          _isSearching = false;
          _errorMessage = 'Search failed: ${e.toString()}';
        });
      }
    } finally {
      // Mark search as completed
      if (!_currentSearchCompleter!.isCompleted) {
        _currentSearchCompleter!.complete();
      }
    }
  }

  void _cacheSearchResults(String query, List<ArtworkItem> results) {
    // Group results by source/service for individual service caching
    final Map<String, List<ArtworkItem>> resultsByService = {
      'all': results, // Cache the complete "All" results
    };

    // Group by individual services based on artwork source
    for (final artwork in results) {
      String serviceId;
      switch (artwork.source) {
        case 'Met Museum':
          serviceId = 'met-museum';
          break;
        case 'Smithsonian':
          serviceId = 'smithsonian';
          break;
        case 'Library of Congress':
        case 'IIIF Collections':
          serviceId = 'iiif';
          break;
        case 'Openverse':
          serviceId = 'openverse';
          break;
        default:
          continue; // Skip unknown sources
      }

      resultsByService.putIfAbsent(serviceId, () => []);
      resultsByService[serviceId]!.add(artwork);
    }

    // Cache results for each service
    for (final entry in resultsByService.entries) {
      final serviceId = entry.key;
      final serviceResults = entry.value;

      if (serviceResults.isNotEmpty) {
        _searchCache.putIfAbsent(serviceId, () => {});
        _searchCache[serviceId]![query] = serviceResults;

        // Limit cache size to prevent memory bloat (keep last 10 searches per service)
        if (_searchCache[serviceId]!.length > 10) {
          final oldestKey = _searchCache[serviceId]!.keys.first;
          _searchCache[serviceId]!.remove(oldestKey);
        }
      }
    }
  }

  void _clearSearch() {
    // Cancel any ongoing search operations
    _searchDebounceTimer?.cancel();
    _cancelCurrentSearch();

    _searchController.clear();
    setState(() {
      _searchResults = [];
      _isSearching = false;
      _errorMessage = '';
    });

    // Load random artworks if we don't have any
    final currentServiceId = _serviceManager.activeServiceId;
    if (_randomCache.containsKey(currentServiceId)) {
      // Use cached random results
      setState(() {
        _randomArtworks = _randomCache[currentServiceId]!;
      });
    } else if (_randomArtworks.isEmpty && !_isLoading) {
      _loadRandomArtworks();
    }
  }

  /// Remove failed Openverse items from the grid to prevent persistent placeholders
  void _removeFailedOpenverseItem(ArtworkItem failedItem) {
    setState(() {
      // Remove from current display lists
      _randomArtworks.removeWhere(
        (item) => item.objectId == failedItem.objectId,
      );
      _searchResults.removeWhere(
        (item) => item.objectId == failedItem.objectId,
      );

      // Remove from cache to prevent it from reappearing
      final currentServiceId = _serviceManager.activeServiceId;
      if (_randomCache.containsKey(currentServiceId)) {
        _randomCache[currentServiceId]!.removeWhere(
          (item) => item.objectId == failedItem.objectId,
        );
      }

      // Remove from search cache
      for (final serviceCache in _searchCache.values) {
        for (final queryResults in serviceCache.values) {
          queryResults.removeWhere(
            (item) => item.objectId == failedItem.objectId,
          );
        }
      }
    });

    print('Removed failed Openverse item: ${failedItem.title}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshData,
                backgroundColor: Colors.white,
                color: Colors.deepPurple,
                child: _buildContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(12),
        ),
        child: TextField(
          controller: _searchController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Search images...',
            hintStyle: const TextStyle(color: Colors.grey),
            prefixIcon: const Icon(Icons.search, color: Colors.grey),
            suffixIcon:
                _searchController.text.isNotEmpty
                    ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.grey),
                      onPressed: _clearSearch,
                    )
                    : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
          onChanged: (value) {
            setState(() {}); // Rebuild to show/hide clear icon
            _onSearchChanged(value);
          },
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.black,
      margin: const EdgeInsets.only(bottom: 20.0),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        indicatorColor: Colors.deepPurple,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey,
        indicatorWeight: 2,
        dividerColor: Colors.grey[800], // Dark gray border instead of white
        labelPadding: const EdgeInsets.symmetric(horizontal: 20),
        tabs: _availableTabs,
      ),
    );
  }

  Widget _buildContent() {
    // Show loading state first if we're loading/searching (but not refreshing) and have no content
    if ((_isLoading || _isSearching) &&
        !_isRefreshing &&
        _randomArtworks.isEmpty &&
        _searchResults.isEmpty) {
      return _buildLoadingGrid();
    }

    // Show error state if there's an error and no content
    if (_errorMessage.isNotEmpty &&
        _randomArtworks.isEmpty &&
        _searchResults.isEmpty &&
        !_isRefreshing) {
      return _buildErrorState();
    }

    final artworks =
        _searchController.text.isNotEmpty ? _searchResults : _randomArtworks;

    // Show empty state if no artworks and not loading/refreshing/searching
    if (artworks.isEmpty && !_isLoading && !_isRefreshing && !_isSearching) {
      return _buildEmptyState();
    }

    return _buildImageGrid(artworks);
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Oops! Something went wrong',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage,
              style: const TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _refreshData,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                ),
                if (_retryCount < maxRetries) ...[
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _retryWithBackoff,
                    icon: const Icon(Icons.timer),
                    label: Text('Retry (${_retryCount + 1}/$maxRetries)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Pull down to refresh',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    // Check if we have cached data available before showing empty state
    final currentServiceId = _serviceManager.activeServiceId;
    final currentQuery = _searchController.text.trim();

    final hasCachedData =
        currentQuery.isEmpty
            ? _randomCache.containsKey(currentServiceId)
            : _searchCache.containsKey(currentServiceId) &&
                _searchCache[currentServiceId]!.containsKey(currentQuery);

    // If we have cached data but artworks list is empty, we're probably in a transition state
    if (hasCachedData) {
      return _buildLoadingGrid(); // Show loading instead of empty to prevent flicker
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.image_search, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No images loaded yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Images should load automatically. If not, try the button below or pull down to refresh.',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _refreshData,
              icon: const Icon(Icons.refresh),
              label: const Text('Load Random Artworks'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageGrid(List<ArtworkItem> artworks) {
    // Calculate total items including shimmer placeholders when loading more
    final shimmerCount = _isLoadingMore ? 6 : 0; // 2 rows of 3 items
    final totalItemCount = artworks.length + shimmerCount;

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(10.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 9 / 16, // 16:9 aspect ratio for portrait layout
        crossAxisSpacing: 10.0,
        mainAxisSpacing: 10.0,
      ),
      itemCount: totalItemCount,
      itemBuilder: (context, index) {
        // Show actual artwork tiles first
        if (index < artworks.length) {
          final artwork = artworks[index];
          return _buildImageTile(artwork);
        }
        // Show shimmer placeholders for loading more
        else {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: _buildShimmer(),
          );
        }
      },
    );
  }

  Widget _buildShimmer({double? height}) {
    return AnimatedBuilder(
      animation: _shimmerAnimation,
      builder: (context, child) {
        return Container(
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(
                -1.0 + _shimmerAnimation.value,
                -1.0 + _shimmerAnimation.value,
              ),
              end: Alignment(
                1.0 + _shimmerAnimation.value,
                1.0 + _shimmerAnimation.value,
              ),
              colors: const [
                Color(0xFF1A0D1F), // Dark purple
                Color(0xFF2D1A35), // Medium dark purple
                Color(0xFF4A2C5A), // Medium purple
                Color(0xFF6B3D7A), // Lighter purple
                Color(0xFF4A2C5A), // Medium purple
                Color(0xFF2D1A35), // Medium dark purple
                Color(0xFF1A0D1F), // Dark purple
              ],
              stops: const [0.0, 0.15, 0.3, 0.5, 0.7, 0.85, 1.0],
            ),
            borderRadius: BorderRadius.circular(8.0),
          ),
        );
      },
    );
  }

  Widget _buildLoadingGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(10.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 9 / 16,
        crossAxisSpacing: 10.0,
        mainAxisSpacing: 10.0,
      ),
      itemCount: 12,
      itemBuilder: (context, index) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: _buildShimmer(),
        );
      },
    );
  }

  Widget _buildImageTile(ArtworkItem artwork) {
    return GestureDetector(
      onTap: () async {
        // Save current scroll position
        _lastScrollPosition =
            _scrollController.hasClients ? _scrollController.offset : 0.0;

        // Navigate to detail and wait for return
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ImageDetailScreen(artwork: artwork),
          ),
        );

        // When returning from detail view, ensure we have our cached data

        final currentServiceId = _serviceManager.activeServiceId;
        final currentQuery = _searchController.text.trim();

        if (currentQuery.isEmpty &&
            _randomCache.containsKey(currentServiceId)) {
          // Restore random artworks from cache if they're missing
          if (_randomArtworks.isEmpty ||
              _randomArtworks.length < _randomCache[currentServiceId]!.length) {
            setState(() {
              _randomArtworks = _randomCache[currentServiceId]!;
            });

            // Restore scroll position after rebuild
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_scrollController.hasClients && _lastScrollPosition > 0) {
                _scrollController.jumpTo(
                  _lastScrollPosition.clamp(
                    0.0,
                    _scrollController.position.maxScrollExtent,
                  ),
                );
              }
            });
          }
        } else if (currentQuery.isNotEmpty &&
            _searchCache.containsKey(currentServiceId) &&
            _searchCache[currentServiceId]!.containsKey(currentQuery)) {
          // Restore search results from cache if they're missing
          if (_searchResults.isEmpty ||
              _searchResults.length <
                  _searchCache[currentServiceId]![currentQuery]!.length) {
            setState(() {
              _searchResults = _searchCache[currentServiceId]![currentQuery]!;
            });

            // Restore scroll position after rebuild
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_scrollController.hasClients && _lastScrollPosition > 0) {
                _scrollController.jumpTo(
                  _lastScrollPosition.clamp(
                    0.0,
                    _scrollController.position.maxScrollExtent,
                  ),
                );
              }
            });
          }
        }
      },
      child: Hero(
        tag:
            'artwork-${artwork.objectId}-${artwork.source}-${artwork.hashCode}',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: artwork.largeImageUrl ?? artwork.imageUrl,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(
                  milliseconds: 0,
                ), // Instant fade-in for Hero animation
                fadeOutDuration: const Duration(
                  milliseconds: 0,
                ), // Instant fade-out for Hero animation
                placeholder: (context, url) => _buildShimmer(),
                errorWidget: (context, url, error) {
                  // For Openverse images that reach this point, remove them from the grid entirely
                  if (artwork.source == 'Openverse') {
                    // Schedule removal of this failed item after the current build
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _removeFailedOpenverseItem(artwork);
                    });
                    // Return empty container until removal
                    return const SizedBox.shrink();
                  }

                  print('Image failed to load: $url');
                  print('Error: $error');

                  // For other services, show retry option
                  return Container(
                    color: Colors.grey[800],
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.broken_image,
                          color: Colors.grey,
                          size: 20,
                        ),
                        const SizedBox(height: 2),
                        GestureDetector(
                          onTap: () {
                            // Clear cache for this image and retry
                            CachedNetworkImage.evictFromCache(artwork.imageUrl);
                            if (artwork.largeImageUrl != null) {
                              CachedNetworkImage.evictFromCache(
                                artwork.largeImageUrl!,
                              );
                            }
                            setState(() {}); // Trigger rebuild to retry
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.deepPurple.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text(
                              'Retry',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              // Tiny source badge
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getSourceIcon(artwork.source),
                        size: 10,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        _getSourceAbbreviation(artwork.source),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getSourceIcon(String source) {
    switch (source) {
      case 'Met Museum':
        return Icons.museum;
      case 'Smithsonian':
        return Icons.account_balance;
      default:
        return Icons.image;
    }
  }

  String _getSourceAbbreviation(String source) {
    switch (source) {
      case 'Met Museum':
        return 'MET';
      case 'Smithsonian':
        return 'SI';
      case 'Library of Congress':
        return 'LOC';
      default:
        return source.substring(0, 2).toUpperCase();
    }
  }
}
