import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../models/artwork_item.dart';
import 'base_image_service.dart';

class OpenverseService extends BaseImageService {
  static const String baseUrl = 'https://api.openverse.org/v1';
  static const Duration timeout = Duration(seconds: 10);
  static const Duration requestDelay = Duration(milliseconds: 500);

  @override
  String get serviceName => 'Openverse';

  @override
  String get serviceId => 'openverse';

  @override
  bool get isRateLimited => _rateLimitBackoff > 0;

  @override
  String? get rateLimitInfo => _rateLimitBackoff > 0
      ? 'Rate limited - waiting ${_rateLimitBackoff}s'
      : null;

  // Instance variables for rate limiting and caching
  DateTime? _lastRequestTime;
  int _rateLimitBackoff = 0;
  final Set<String> _usedIds = <String>{};

  @override
  Future<List<ArtworkItem>> getRandomArtworks(int count) async {
    try {
      // Use a diverse set of search terms to get varied results across all categories
      final randomTerms = [
        // Nature & Landscapes (5 terms - 17%)
        'nature',
        'landscape',
        'mountains',
        'forest',
        'sunset',

        // Art & Design (5 terms - 17%)
        'art',
        'abstract',
        'painting',
        'sculpture',
        'design',

        // Architecture & Urban (5 terms - 17%)
        'architecture',
        'building',
        'city',
        'street',
        'bridge',

        // Objects & Still Life (5 terms - 17%)
        'vintage',
        'furniture',
        'books',
        'tools',
        'texture',

        // Transportation & Tech (5 terms - 17%)
        'vehicle',
        'airplane',
        'train',
        'boat',
        'technology',

        // Cultural & Historical (5 terms - 17%)
        'museum',
        'monument',
        'historic',
        'cultural',
        'photography',
      ];

      final random = Random();
      final randomTerm = randomTerms[random.nextInt(randomTerms.length)];

      return await searchArtworks(randomTerm, limit: count);
    } catch (e) {
      print('OpenverseService: Error loading random artworks: $e');
      if (e.toString().contains('Rate limited')) {
        throw ServiceRateLimitException(
          'Rate limited by Openverse API. Please wait a moment before refreshing.',
          retryAfter: Duration(seconds: _rateLimitBackoff),
        );
      }
      throw Exception('Failed to load random artworks: $e');
    }
  }

  @override
  Future<List<ArtworkItem>> searchArtworks(
    String query, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      await _throttleRequest();

      // Openverse API limits anonymous requests to page_size <= 20
      // Using higher values returns HTTP 401 Unauthorized
      final pageSize = limit > 20 ? 20 : limit;

      // Calculate page number from offset (1-based)
      final page = (offset / pageSize).floor() + 1;

      // Check if user is specifically searching for people-related content
      final searchingForPeople = _isSearchingForPeople(query);

      // Build search URL with CC0 license filter
      String searchQuery = query;
      if (!searchingForPeople) {
        // Add exclusion terms for people/portraits when not specifically searching for them
        searchQuery +=
            ' -people -person -portrait -face -man -woman -child -baby -human -family -wedding -selfie';
      }

      final searchUrl = Uri.parse(
        '$baseUrl/images/?q=${Uri.encodeComponent(searchQuery)}&license=cc0&page_size=$pageSize&page=$page&mature=false',
      );

      final response = await http
          .get(
            searchUrl,
            headers: {
              'User-Agent': 'StockApp/1.0 (https://example.com/contact)',
            },
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = List<Map<String, dynamic>>.from(data['results'] ?? []);
        _resetRateLimitBackoff();

        if (results.isEmpty) {
          return [];
        }

        final artworks = <ArtworkItem>[];

        // First pass: Parse all results without validation for speed
        final candidateArtworks = <ArtworkItem>[];
        for (final result in results) {
          try {
            // Filter out low-resolution images
            final imageUrl = result['url'] as String?;
            if (imageUrl == null ||
                imageUrl.isEmpty ||
                ImageResolutionUtils.isLowResolution(imageUrl)) {
              continue;
            }

            final artwork = _parseOpenverseResult(result);
            if (artwork != null &&
                !_usedIds.contains(artwork.objectId.toString()) &&
                _shouldIncludeArtwork(artwork, query)) {
              candidateArtworks.add(artwork);
            }
          } catch (e) {
            // Skip problematic items
            continue;
          }
        }

        // For searches, be less aggressive with validation to get more results quickly
        if (candidateArtworks.length <= 6) {
          // If we have very few results, validate them to ensure quality
          print(
            'OpenverseService: Few results (${candidateArtworks.length}), validating all',
          );
          const batchSize = 6;
          for (
            int i = 0;
            i < candidateArtworks.length && artworks.length < limit;
            i += batchSize
          ) {
            final batch = candidateArtworks.skip(i).take(batchSize).toList();

            final validationFutures = batch
                .map(
                  (artwork) => _isUrlAccessible(
                    artwork.imageUrl,
                  ).then((isValid) => isValid ? artwork : null),
                )
                .toList();

            final validatedBatch = await Future.wait(validationFutures);

            for (final artwork in validatedBatch) {
              if (artwork != null && artworks.length < limit) {
                artworks.add(artwork);
                _usedIds.add(artwork.objectId.toString());
              }
            }
          }
        } else {
          // If we have many results, just do basic filtering and skip URL validation for speed
          print(
            'OpenverseService: Many results (${candidateArtworks.length}), skipping validation for speed',
          );
          for (final artwork in candidateArtworks) {
            if (artworks.length < limit) {
              // Only reject obviously bad URLs
              if (_isObviouslyBadUrl(artwork.imageUrl)) {
                continue;
              }
              artworks.add(artwork);
              _usedIds.add(artwork.objectId.toString());
            }
          }
        }

        return artworks;
      } else if (response.statusCode == 429) {
        _handleRateLimit();
        throw ServiceRateLimitException(
          'Rate limited by Openverse API. Please wait a moment before searching.',
          retryAfter: Duration(seconds: _rateLimitBackoff),
        );
      } else {
        throw Exception(
          'Failed to search Openverse: HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      if (e is ServiceRateLimitException) rethrow;
      print('OpenverseService: Search error: $e');
      throw Exception('Failed to search artworks: $e');
    }
  }

  @override
  Future<ArtworkItem> getArtworkById(String id) async {
    try {
      await _throttleRequest();

      final response = await http
          .get(
            Uri.parse('$baseUrl/images/$id/'),
            headers: {
              'User-Agent': 'StockApp/1.0 (https://example.com/contact)',
            },
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _resetRateLimitBackoff();

        final artwork = _parseOpenverseResult(data);
        if (artwork == null) {
          throw Exception('Failed to parse artwork data for ID: $id');
        }

        return artwork;
      } else if (response.statusCode == 429) {
        _handleRateLimit();
        throw ServiceRateLimitException(
          'Rate limited by Openverse API.',
          retryAfter: Duration(seconds: _rateLimitBackoff),
        );
      } else {
        throw Exception(
          'Failed to load artwork $id: HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      if (e is ServiceRateLimitException) rethrow;
      throw Exception('Failed to get artwork by ID: $e');
    }
  }

  @override
  void clearCache({bool force = false}) {
    _usedIds.clear();
    if (force) {
      _rateLimitBackoff = 0;
    }
  }

  // Private helper methods

  /// Quick URL accessibility check with minimal timeout to avoid delays
  Future<bool> _isUrlAccessible(String url) async {
    try {
      // First check for obviously bad URLs
      if (url.contains('notdig.gif') ||
          url.contains('placeholder') ||
          url.contains('error') ||
          url.contains('404') ||
          url.contains('missing')) {
        return false;
      }

      final response = await http
          .head(
            Uri.parse(url),
            headers: {
              'User-Agent': 'StockApp/1.0 (https://example.com/contact)',
              'Accept': 'image/*',
            },
          )
          .timeout(
            const Duration(milliseconds: 1200),
          ); // Slightly longer timeout for thorough check

      // Be more strict about what constitutes a valid response
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Also check content type if available
        final contentType = response.headers['content-type'];
        if (contentType != null && !contentType.startsWith('image/')) {
          return false;
        }
        return true;
      }

      return false;
    } catch (e) {
      // Any error (timeout, network, 404, etc.) means skip this image
      return false;
    }
  }

  /// Quick check for obviously bad URLs without making HTTP requests
  bool _isObviouslyBadUrl(String url) {
    return url.contains('notdig.gif') ||
        url.contains('placeholder') ||
        url.contains('error') ||
        url.contains('404') ||
        url.contains('missing') ||
        url.contains('thumb.gif') ||
        url.contains('icon.gif');
  }

  ArtworkItem? _parseOpenverseResult(Map<String, dynamic> data) {
    try {
      final id = data['id']?.toString() ?? '';
      final title = data['title']?.toString() ?? 'Untitled';
      final creator = data['creator']?.toString() ?? 'Unknown Creator';

      // Try multiple URL fields and pick the best one
      final primaryUrl = data['url']?.toString() ?? '';
      final thumbnailUrl = data['thumbnail']?.toString() ?? '';
      final detailUrl = data['detail_url']?.toString() ?? '';

      // Debug logging for URL analysis (reduced verbosity)
      // Uncomment for detailed debugging:
      // print('OpenverseService: Parsing item "$title"');
      // print('  - Primary URL: $primaryUrl');
      // print('  - Thumbnail URL: $thumbnailUrl');
      // print('  - Detail URL: $detailUrl');

      // Select the best available image URL
      String imageUrl = _selectBestImageUrl([
        primaryUrl,
        thumbnailUrl,
        detailUrl,
      ]);

      // print('  - Selected URL: $imageUrl');

      // Get source information
      final source = data['source']?.toString() ?? 'Openverse';

      if (id.isEmpty || imageUrl.isEmpty) {
        print('OpenverseService: Skipping item - missing ID or URL: $title');
        return null;
      }

      // Use primary URL as main image, but ensure we have different fallback URLs
      String largeImageUrl;
      if (primaryUrl.isNotEmpty &&
          _isValidImageUrl(primaryUrl) &&
          primaryUrl != imageUrl) {
        largeImageUrl = primaryUrl;
      } else if (thumbnailUrl.isNotEmpty &&
          _isValidImageUrl(thumbnailUrl) &&
          thumbnailUrl != imageUrl) {
        largeImageUrl = thumbnailUrl;
      } else {
        largeImageUrl = imageUrl; // Same as main image
      }

      // If we're using a Flickr URL as primary, prefer Openverse URLs as fallbacks
      if (imageUrl.contains('flickr.com')) {
        if (thumbnailUrl.isNotEmpty && !thumbnailUrl.contains('flickr.com')) {
          largeImageUrl = thumbnailUrl;
        }
      }

      // print('  - Final large URL: $largeImageUrl');

      return ArtworkItem(
        objectId: id.hashCode, // Convert string ID to int
        title: title,
        artist: creator,
        imageUrl: imageUrl,
        largeImageUrl: largeImageUrl,
        date: '', // Openverse doesn't typically provide creation year
        medium: 'Digital Image',
        department: source,
        source: 'Openverse',
      );
    } catch (e) {
      print('OpenverseService: Error parsing result: $e');
      return null;
    }
  }

  Future<void> _throttleRequest() async {
    if (_rateLimitBackoff > 0) {
      final backoffDelay = Duration(seconds: _rateLimitBackoff);
      if (_rateLimitBackoff >= 5) {
        print(
          'OpenverseService: Rate limited - waiting ${backoffDelay.inSeconds}s',
        );
      }
      await Future.delayed(backoffDelay);
      _rateLimitBackoff = (_rateLimitBackoff * 1.5).ceil();
    }

    if (_lastRequestTime != null) {
      final timeSinceLastRequest = DateTime.now().difference(_lastRequestTime!);
      if (timeSinceLastRequest < requestDelay) {
        final waitTime = requestDelay - timeSinceLastRequest;
        await Future.delayed(waitTime);
      }
    }
    _lastRequestTime = DateTime.now();
  }

  void _resetRateLimitBackoff() {
    _rateLimitBackoff = 0;
  }

  void _handleRateLimit() {
    _rateLimitBackoff = _rateLimitBackoff == 0 ? 2 : _rateLimitBackoff;
    if (_rateLimitBackoff >= 5) {
      print(
        'OpenverseService: Rate limited - backoff set to ${_rateLimitBackoff}s',
      );
    }
  }

  /// Check if the user is specifically searching for people-related content
  bool isSearchingForPeople(String query) => _isSearchingForPeople(query);

  bool _isSearchingForPeople(String query) {
    final lowerQuery = query.toLowerCase();
    final peopleKeywords = [
      'people',
      'person',
      'portrait',
      'face',
      'man',
      'woman',
      'child',
      'baby',
      'human',
      'family',
      'wedding',
      'selfie',
      'crowd',
      'group',
      'team',
      'couple',
      'mother',
      'father',
      'kid',
      'boy',
      'girl',
      'businessman',
      'businesswoman',
      'worker',
      'doctor',
      'nurse',
    ];

    return peopleKeywords.any((keyword) => lowerQuery.contains(keyword));
  }

  /// Check if an artwork should be included based on content filtering
  bool shouldIncludeArtwork(ArtworkItem artwork, String query) =>
      _shouldIncludeArtwork(artwork, query);

  bool _shouldIncludeArtwork(ArtworkItem artwork, String query) {
    // If user is specifically searching for people, include all results
    if (_isSearchingForPeople(query)) {
      return true;
    }

    // Filter out likely people/portrait photos based on title and tags
    final combinedText = '${artwork.title} ${artwork.artist} ${artwork.medium}'
        .toLowerCase();

    final peopleIndicators = [
      'portrait',
      'face',
      'person',
      'people',
      'man',
      'woman',
      'child',
      'baby',
      'human',
      'family',
      'wedding',
      'selfie',
      'headshot',
      'mugshot',
      'profile',
      'businessman',
      'businesswoman',
      'crowd',
    ];

    // If the artwork contains people indicators, exclude it
    if (peopleIndicators.any((indicator) => combinedText.contains(indicator))) {
      return false;
    }

    return true;
  }

  /// Validate if a URL is a proper image URL
  bool _isValidImageUrl(String url) {
    if (url.isEmpty) return false;

    try {
      final uri = Uri.parse(url);

      // Must have a valid scheme
      if (!uri.hasScheme || !['http', 'https'].contains(uri.scheme)) {
        return false;
      }

      // Must have a host
      if (!uri.hasAuthority || uri.host.isEmpty) {
        return false;
      }

      // Check for common image extensions (but don't require them, as some URLs don't have extensions)
      final path = uri.path.toLowerCase();
      final commonImageExts = [
        '.jpg',
        '.jpeg',
        '.png',
        '.gif',
        '.webp',
        '.bmp',
        '.svg',
      ];

      // If it has an extension, it should be an image extension
      if (path.contains('.')) {
        final hasValidExt = commonImageExts.any((ext) => path.endsWith(ext));
        if (!hasValidExt) {
          // Expanded list of known image hosts for Openverse
          final knownImageHosts = [
            'flickr.com',
            'wikimedia.org',
            'staticflickr.com',
            'live.staticflickr.com',
            'upload.wikimedia.org',
            'commons.wikimedia.org',
            'cdn.pixabay.com',
            'images.unsplash.com',
            'source.unsplash.com',
            'rawpixel.com',
            'burst.shopify.com',
            // Additional hosts commonly used by Openverse
            'picryl.com',
            'wordpress.com',
            'wp.com',
            'blogspot.com',
            'imgur.com',
            'cdn.openverse.org',
            'openverse.org',
            'pexels.com',
            'stockvault.net',
            'nappy.co',
            'freestocks.org',
          ];

          final hostMatches = knownImageHosts.any(
            (host) => uri.host.contains(host),
          );
          if (!hostMatches) {
            // Don't reject - let's be more permissive for Openverse
            // Many legitimate image URLs come from unknown hosts
          }
        }
      }

      // URL validation passed - silent success
      return true;
    } catch (e) {
      // URL validation failed - silent failure (normal for many URLs)
      return false;
    }
  }

  /// Select the best image URL from available options
  String _selectBestImageUrl(List<String> urls) {
    // Selecting best URL from available options (silent processing)

    final validUrls = <String>[];

    // First pass: collect all valid URLs and enforce HTTPS
    for (final url in urls) {
      if (url.isNotEmpty) {
        // Convert HTTP to HTTPS for better compatibility
        final httpsUrl = url.startsWith('http://')
            ? url.replaceFirst('http://', 'https://')
            : url;

        if (_isValidImageUrl(httpsUrl)) {
          validUrls.add(httpsUrl);
        }
      }
    }

    if (validUrls.isEmpty) {
      return '';
    }

    // Priority 1: URLs from known reliable hosts (prefer HTTPS)
    final reliableHosts = [
      'wikimedia.org',
      'upload.wikimedia.org',
      'commons.wikimedia.org',
      'staticflickr.com',
      'live.staticflickr.com',
      'flickr.com',
    ];

    for (final url in validUrls) {
      try {
        final uri = Uri.parse(url);
        if (uri.scheme == 'https' &&
            reliableHosts.any((host) => uri.host.contains(host))) {
          return url;
        }
      } catch (e) {
        continue;
      }
    }

    // Priority 2: Any HTTPS URL with image extension
    final imageExts = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'];
    for (final url in validUrls) {
      try {
        final uri = Uri.parse(url);
        if (uri.scheme == 'https' &&
            imageExts.any((ext) => uri.path.toLowerCase().endsWith(ext))) {
          return url;
        }
      } catch (e) {
        continue;
      }
    }

    // Priority 3: Any HTTPS URL
    for (final url in validUrls) {
      try {
        final uri = Uri.parse(url);
        if (uri.scheme == 'https') {
          return url;
        }
      } catch (e) {
        continue;
      }
    }

    // Priority 4: Any valid URL (fallback)
    final selectedUrl = validUrls.first;
    return selectedUrl;
  }
}
