import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../models/artwork_item.dart';
import 'base_image_service.dart';

class IIIFService extends BaseImageService {
  static const Duration timeout = Duration(seconds: 15);
  static const Duration requestDelay = Duration(milliseconds: 300);
  static const String baseUrl = 'https://www.loc.gov';

  @override
  String get serviceName => 'Library of Congress';

  @override
  String get serviceId => 'iiif';

  @override
  bool get isRateLimited => _rateLimitBackoff > 0;

  @override
  String? get rateLimitInfo =>
      _rateLimitBackoff > 0
          ? 'Rate limited - waiting ${_rateLimitBackoff}s'
          : null;

  // Instance variables for rate limiting and caching
  DateTime? _lastRequestTime;
  int _rateLimitBackoff = 0;
  final Set<String> _usedIds =
      <String>{}; // Tracks original API IDs to prevent duplicates

  // IIIF endpoints - these are real endpoints that support IIIF standards
  static const List<IIIFEndpoint> _endpoints = [
    IIIFEndpoint(
      name: 'Digital Public Library of America',
      baseUrl: 'https://dp.la/primary-source-sets',
      searchEndpoint: 'https://api.dp.la/v2/items',
      apiKey: null, // DPLA requires registration but has a free tier
    ),
    IIIFEndpoint(
      name: 'Internet Archive',
      baseUrl: 'https://iiif.archivelab.org',
      searchEndpoint: 'https://archive.org/advancedsearch.php',
      apiKey: null,
    ),
    IIIFEndpoint(
      name: 'Yale Center for British Art',
      baseUrl: 'https://collections.britishart.yale.edu/iiif',
      searchEndpoint: 'https://collections.britishart.yale.edu/oai',
      apiKey: null,
    ),
    IIIFEndpoint(
      name: 'Harvard Art Museums',
      baseUrl: 'https://iiif.lib.harvard.edu',
      searchEndpoint: 'https://api.harvardartmuseums.org/object',
      apiKey: null, // Requires API key for full access
    ),
  ];

  @override
  Future<List<ArtworkItem>> getRandomArtworks(int count) async {
    try {
      await _throttleRequest();

      // Use a wide variety of search terms to get diverse results, avoiding people-heavy topics
      final searchTerms = [
        'photograph',
        'art',
        'landscape',
        'vintage',
        'historic',
        'american',
        'building',
        'architecture',
        'nature',
        'city',
        'street',
        'transportation',
        'railroad',
        'ship',
        'aviation',
        'automobile',
        'bridge',
        'farm',
        'agriculture',
        'industry',
        'factory',
        'mining',
        'logging',
        'fishing',
        // Removed people-heavy terms: 'sports', 'baseball', 'football', 'celebration', 'parade', 'festival'
        'church',
        'school',
        'university',
        'library',
        'hotel',
        'restaurant',
        'store',
        'market',
        'business',
        'fire',
        'frontier',
        'western',
        'southern',
        'northern',
        'eastern',
        'midwest',
        'california',
        'new york',
        'texas',
        'florida',
        'washington',
        'mountain',
        'river',
        'lake',
        'ocean',
        'forest',
        'desert',
        'park',
        'garden',
        'flower',
        'tree',
        'animal',
        'horse',
        'dog',
        'cat',
        'bird',
        'boat',
        'train',
        'plane',
        'car',
        'bicycle',
        'construction',
        'demolition',
        'renovation',
        'exhibition',
        'fair',
        'carnival',
        'circus',
        'newspaper',
        'magazine',
        'book',
        'manuscript',
        'document',
        'letter',
        'map',
        'poster',
        'advertisement',
        'sign',
        'stamp',
        'postcard',
      ];
      // Sometimes use multiple search terms for more diverse results
      String searchQuery;
      if (Random().nextBool() && searchTerms.length > 2) {
        // 50% chance to use two terms with OR
        final term1 = searchTerms[Random().nextInt(searchTerms.length)];
        var term2 = searchTerms[Random().nextInt(searchTerms.length)];
        while (term2 == term1 && searchTerms.length > 1) {
          term2 = searchTerms[Random().nextInt(searchTerms.length)];
        }
        searchQuery = '$term1 OR $term2';
      } else {
        searchQuery = searchTerms[Random().nextInt(searchTerms.length)];
      }

      // Add random pagination to get different result sets, but keep it reasonable
      final randomStart = Random().nextInt(
        50,
      ); // Reduced from 500 to 50 to avoid pagination beyond available results
      final queryParams = {
        'q': searchQuery,
        'fo': 'json',
        'c': (count + 5).toString(), // Get a few extra results for filtering
        'sp': randomStart.toString(), // Random starting page/offset
      };

      final uri = Uri.parse(
        '$baseUrl/photos/',
      ).replace(queryParameters: queryParams);
      final response = await http.get(uri).timeout(timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] as List? ?? [];

        final artworks = <ArtworkItem>[];
        for (final result in results) {
          try {
            final originalId = result['id'] as String?;
            if (originalId != null && !_usedIds.contains(originalId)) {
              final artwork = _parseLibraryOfCongressItem(result);
              if (artwork != null && artwork.imageUrl.isNotEmpty) {
                artworks.add(artwork);
                _usedIds.add(originalId);
              }
            }
          } catch (e) {
            continue;
          }
        }

        _resetRateLimitBackoff();

        // Shuffle results for better randomness
        artworks.shuffle();

        final finalArtworks = artworks.take(count).toList();
        return finalArtworks;
      } else if (response.statusCode == 404 && randomStart > 1) {
        // Fallback: try page 1 if random page failed (likely beyond available pages)
        final fallbackParams = Map<String, String>.from(queryParams);
        fallbackParams['sp'] = '1';
        final fallbackUri = Uri.parse(
          '$baseUrl/photos/',
        ).replace(queryParameters: fallbackParams);
        final fallbackResponse = await http.get(fallbackUri).timeout(timeout);

        if (fallbackResponse.statusCode == 200) {
          final data = json.decode(fallbackResponse.body);
          final results = data['results'] as List? ?? [];

          final artworks = <ArtworkItem>[];
          for (final result in results) {
            try {
              final artwork = _parseLibraryOfCongressItem(result);
              if (artwork != null &&
                  artwork.imageUrl.isNotEmpty &&
                  !_usedIds.contains(artwork.objectId.toString())) {
                artworks.add(artwork);
                _usedIds.add(artwork.objectId.toString());
              }
            } catch (e) {
              continue;
            }
          }

          artworks.shuffle();
          final finalArtworks = artworks.take(count).toList();
          return finalArtworks;
        }
        // If fallback also failed, fall through to the final else
      } else if (response.statusCode == 429) {
        _handleRateLimit();
        throw ServiceRateLimitException(
          'Rate limited by Library of Congress API',
        );
      }

      // If we reach here, all requests failed
      throw Exception('Failed to load artworks: HTTP ${response.statusCode}');
    } catch (e) {
      print('IIIFService: Error loading random artworks: $e');
      if (e.toString().contains('Rate limited')) {
        throw ServiceRateLimitException(
          'Rate limited by Library of Congress API. Please wait a moment before refreshing.',
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

      // Calculate starting page from offset (LOC uses sp parameter for page offset)
      final startPage =
          (offset / 20).floor() +
          1; // LOC typically returns ~20 results per page

      final queryParams = {
        'q': query,
        'fo': 'json',
        'c': limit.toString(),
        'sp': startPage.toString(),
      };

      final uri = Uri.parse(
        '$baseUrl/photos/',
      ).replace(queryParameters: queryParams);
      final response = await http.get(uri).timeout(timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] as List? ?? [];

        final artworks = <ArtworkItem>[];
        for (final result in results) {
          try {
            final artwork = _parseLibraryOfCongressItem(result);
            if (artwork != null && artwork.imageUrl.isNotEmpty) {
              artworks.add(artwork);
            }
          } catch (e) {
            continue;
          }
        }

        _resetRateLimitBackoff();
        return artworks;
      } else if (response.statusCode == 429) {
        _handleRateLimit();
        throw ServiceRateLimitException(
          'Rate limited by Library of Congress API',
        );
      } else {
        throw Exception(
          'Failed to search artworks: HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      if (e is ServiceRateLimitException) rethrow;
      throw Exception('Failed to search artworks: $e');
    }
  }

  @override
  Future<ArtworkItem> getArtworkById(String id) async {
    await _throttleRequest();

    // For Library of Congress, try to construct the resource URL
    final resourceUrl = 'https://www.loc.gov/resource/$id/';

    return ArtworkItem(
      objectId: id.hashCode,
      title: 'Library of Congress Item $id',
      artist: 'Unknown Artist',
      imageUrl: resourceUrl,
      largeImageUrl: resourceUrl,
      date: '',
      medium: 'Digital Collection',
      department: 'Library of Congress',
      source: 'Library of Congress',
    );
  }

  @override
  void clearCache({bool force = false}) {
    if (force) {
      print('IIIFService: Force clearing cache and used IDs');
      _usedIds.clear();
      _rateLimitBackoff = 0;
    } else {
      print('IIIFService: Smart refresh - only clearing used IDs');
      _usedIds.clear();
    }
  }

  // Private helper methods

  Future<void> _throttleRequest() async {
    if (_rateLimitBackoff > 0) {
      final backoffDelay = Duration(seconds: _rateLimitBackoff);
      if (_rateLimitBackoff >= 5) {
        print('IIIFService: Rate limited - waiting ${backoffDelay.inSeconds}s');
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
      print('IIIFService: Rate limited - backoff set to ${_rateLimitBackoff}s');
    }
  }

  ArtworkItem? _parseLibraryOfCongressItem(Map<String, dynamic> item) {
    try {
      // Extract basic info
      final title = item['title'] as String? ?? 'Untitled';
      final id = item['id'] as String?;

      if (id == null || id.isEmpty) return null;

      // Extract creator/artist information from contributor array or item.contributors
      final contributors = item['contributor'] as List? ?? [];
      final itemData = item['item'] as Map<String, dynamic>? ?? {};
      final itemContributors = itemData['contributors'] as List? ?? [];

      String artist = 'Unknown Artist';

      // Try contributor field first (simple list)
      if (contributors.isNotEmpty) {
        artist = contributors.first.toString();
      }
      // Then try item.contributors (more structured)
      else if (itemContributors.isNotEmpty) {
        artist = itemContributors.first.toString();
      }

      // Extract dates
      final date = item['date'] as String? ?? itemData['date'] as String? ?? '';

      // Extract image URLs - LOC provides direct image URLs
      String imageUrl = '';
      String? largeImageUrl;

      // Try image_url array first (top level)
      final imageUrls = item['image_url'] as List? ?? [];
      if (imageUrls.isNotEmpty) {
        // Filter and prioritize high-resolution images
        final processedUrls = <String>[];
        for (final url in imageUrls) {
          final urlStr = url.toString().split('#').first;

          // Skip low-resolution thumbnails
          if (urlStr.contains('150px') ||
              urlStr.contains('200px') ||
              urlStr.contains('250px') ||
              urlStr.contains('300px') ||
              urlStr.contains('thumb') ||
              urlStr.contains('_sm') ||
              urlStr.contains('_small')) {
            continue;
          }

          processedUrls.add(urlStr);
        }

        if (processedUrls.isEmpty) {
          // If no high-res images found, skip this item
          return null;
        }

        // Use shared utility to select best resolution image
        String? bestUrl = ImageResolutionUtils.selectBestResolutionUrl(
          processedUrls,
        );
        if (bestUrl != null) {
          imageUrl = bestUrl;
          largeImageUrl = ImageResolutionUtils.tryToGetLargerVersion(bestUrl);
        } else {
          imageUrl = processedUrls.first;
          largeImageUrl = ImageResolutionUtils.tryToGetLargerVersion(
            processedUrls.first,
          );
        }
      }
      // Fallback: try item level image URLs
      else if (itemData.isNotEmpty) {
        final serviceLow = itemData['service_low'] as String? ?? '';
        final serviceMedium = itemData['service_medium'] as String? ?? '';
        final serviceHigh = itemData['service_high'] as String? ?? '';
        final thumbGallery = itemData['thumb_gallery'] as String? ?? '';

        // Prioritize higher resolution services using shared utility
        if (serviceHigh.isNotEmpty &&
            !ImageResolutionUtils.isLowResolution(serviceHigh)) {
          imageUrl = serviceHigh;
          largeImageUrl = ImageResolutionUtils.tryToGetLargerVersion(
            serviceHigh,
          );
        } else if (serviceMedium.isNotEmpty &&
            !ImageResolutionUtils.isLowResolution(serviceMedium)) {
          imageUrl = serviceMedium;
          largeImageUrl = ImageResolutionUtils.tryToGetLargerVersion(
            serviceMedium,
          );
        } else if (serviceLow.isNotEmpty &&
            !ImageResolutionUtils.isLowResolution(serviceLow)) {
          imageUrl = serviceLow;
          largeImageUrl = ImageResolutionUtils.tryToGetLargerVersion(
            serviceLow,
          );
        } else if (thumbGallery.isNotEmpty &&
            !ImageResolutionUtils.isLowResolution(thumbGallery)) {
          imageUrl = thumbGallery;
          largeImageUrl = ImageResolutionUtils.tryToGetLargerVersion(
            thumbGallery,
          );
        } else {
          // All images are low resolution, skip this item
          return null;
        }
      }

      // If still no image URL, try resources array as last resort
      if (imageUrl.isEmpty) {
        final resources = item['resources'] as List? ?? [];
        if (resources.isNotEmpty) {
          for (final resource in resources) {
            if (resource is Map<String, dynamic>) {
              final resourceImage = resource['image'] as String? ?? '';
              if (resourceImage.isNotEmpty &&
                  !ImageResolutionUtils.isLowResolution(resourceImage)) {
                imageUrl = resourceImage;
                largeImageUrl = ImageResolutionUtils.tryToGetLargerVersion(
                  resourceImage,
                );
                break;
              }
            }
          }
        }

        // If still no high-res image found, skip this item entirely
        if (imageUrl.isEmpty) {
          return null;
        }
      }

      // Validate and clean up image URLs
      if (imageUrl.isNotEmpty) {
        // Filter out placeholder/icon/collection images
        if (imageUrl.contains('/static/images/') ||
            imageUrl.contains('/static/collections/') ||
            imageUrl.endsWith('.svg') ||
            imageUrl.contains('original-format') ||
            imageUrl.contains('memory.loc.gov/pp/grp.gif') ||
            imageUrl.contains('500_500.jpg') ||
            imageUrl.endsWith('grp.gif')) {
          return null;
        }

        // Filter out photos of people/portraits unless explicitly searching for people
        final titleLower = title.toLowerCase();
        final subjects = item['subject'] as List? ?? [];
        final subjectsText = subjects.join(' ').toLowerCase();

        // Enhanced people detection keywords
        final peopleKeywords = [
          'portrait',
          'portraits',
          'man',
          'woman',
          'men',
          'women',
          'person',
          'people',
          'family',
          'child',
          'children',
          'baby',
          'boy',
          'girl',
          'mrs.',
          'mr.',
          'miss',
          'president',
          'senator',
          'governor',
          'mayor',
          'judge',
          'doctor',
          'nurse',
          'teacher',
          'worker',
          'soldier',
          'officer',
          'captain',
          'general',
          'american indian',
          'native american',
          'african american',
          'wedding',
          'ceremony',
          'graduation',
          'funeral',
          'meeting',
          'conference',
          'group of',
          'couple',
          'self-portrait',
          'headshot',
          'bust',
          'crowd',
          'audience',
          'spectators',
          'gathering',
          'celebration',
          'parade',
          'demonstration',
          'protest',
          'rally',
          'team',
          'players',
          'athletes',
          'performers',
          'musicians',
          'dancers',
          'actors',
          'staff',
          'employees',
          'workers',
          'officials',
          'delegates',
          'representatives',
          'students',
          'graduates',
          'class of',
          'reunion',
        ];

        // Check for names patterns (brackets with names) - enhanced
        final hasPersonName = RegExp(
          r'\[[\w\s]+,?\s+(american\s+)?indian\]|\[[\w\s]*\s+(portrait|man|woman|person|people)\]|\[[\w\s]+(family|children|child|boy|girl)\]',
        ).hasMatch(titleLower);

        // Check title and subjects for people keywords
        final hasPeopleKeywords = peopleKeywords.any(
          (keyword) =>
              titleLower.contains(keyword) || subjectsText.contains(keyword),
        );

        // Enhanced check for personal names in titles (Last, First format or titles)
        final hasPersonalName = RegExp(
          r'\b[A-Z][a-z]+,\s+[A-Z][a-z]+\b|\b(Mr\.|Mrs\.|Miss|Dr\.|Prof\.|Sen\.|Rep\.|Gen\.|Col\.|Capt\.)\s+[A-Z][a-z]+',
        ).hasMatch(title);

        // Check if search query is specifically about people (if we had access to it)
        // For now, we'll be more aggressive about filtering people photos
        if (hasPersonName || hasPeopleKeywords || hasPersonalName) {
          return null;
        }

        // Ensure URL starts with https
        if (!imageUrl.startsWith('http')) {
          imageUrl = 'https:$imageUrl';
        }
        if (largeImageUrl != null && !largeImageUrl!.startsWith('http')) {
          largeImageUrl = 'https:$largeImageUrl';
        }
      }

      // If still no image URL, skip this item
      if (imageUrl.isEmpty) {
        return null;
      }

      // Extract subject/medium information
      final subjects = item['subject'] as List? ?? [];
      final itemMedium = itemData['medium'] as List? ?? [];
      String medium = 'Photograph';

      if (subjects.isNotEmpty) {
        final subjectList = subjects.whereType<String>().take(3).join(', ');
        if (subjectList.isNotEmpty) {
          medium = subjectList;
        }
      } else if (itemMedium.isNotEmpty) {
        medium = itemMedium.first.toString();
      }

      // Extract department/collection info
      final partof = item['partof'] as List? ?? [];
      String department = 'Library of Congress';

      if (partof.isNotEmpty) {
        department = 'Library of Congress - ${partof.first}';
      }

      // Generate unique objectId from full ID to avoid collisions
      int objectId = id.hashCode;

      return ArtworkItem(
        objectId: objectId,
        title: title,
        artist: artist,
        imageUrl: imageUrl,
        largeImageUrl: largeImageUrl,
        date: date,
        medium: medium,
        department: department,
        source: 'Library of Congress',
      );
    } catch (e) {
      print('Error parsing LOC item: $e');
      return null;
    }
  }

  Future<List<ArtworkItem>> _getInternetArchiveArtworks(int count) async {
    try {
      await _throttleRequest();

      // Internet Archive advanced search for images
      final queryParams = {
        'q':
            'collection:metropolitanmuseumofart-gallery OR collection:brooklynmuseum OR collection:rijksmuseum',
        'fl': 'identifier,title,creator,date,description,subject',
        'rows': count.toString(),
        'page': '1',
        'output': 'json',
        'sort[]': 'random',
      };

      final uri = Uri.parse(
        'https://archive.org/advancedsearch.php',
      ).replace(queryParameters: queryParams);

      final response = await http.get(uri).timeout(timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final docs = data['response']?['docs'] as List? ?? [];

        final artworks = <ArtworkItem>[];
        for (final doc in docs) {
          try {
            final artwork = _parseInternetArchiveDoc(doc);
            if (artwork != null &&
                !_usedIds.contains(artwork.objectId.toString())) {
              artworks.add(artwork);
              _usedIds.add(artwork.objectId.toString());
            }
          } catch (e) {
            continue;
          }
        }

        _resetRateLimitBackoff();
        return artworks;
      } else if (response.statusCode == 429) {
        _handleRateLimit();
        throw ServiceRateLimitException('Rate limited by Internet Archive');
      }
    } catch (e) {
      // Fall back to mock data if Internet Archive is not available
    }

    return [];
  }

  Future<List<ArtworkItem>> _searchInternetArchive(
    String query, {
    int limit = 10,
  }) async {
    try {
      await _throttleRequest();

      final queryParams = {
        'q':
            '$query AND (collection:metropolitanmuseumofart-gallery OR collection:brooklynmuseum)',
        'fl': 'identifier,title,creator,date,description,subject',
        'rows': limit.toString(),
        'output': 'json',
      };

      final uri = Uri.parse(
        'https://archive.org/advancedsearch.php',
      ).replace(queryParameters: queryParams);

      final response = await http.get(uri).timeout(timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final docs = data['response']?['docs'] as List? ?? [];

        final artworks = <ArtworkItem>[];
        for (final doc in docs) {
          try {
            final artwork = _parseInternetArchiveDoc(doc);
            if (artwork != null) {
              artworks.add(artwork);
            }
          } catch (e) {
            continue;
          }
        }

        return artworks;
      }
    } catch (e) {
      // Fall back to filtering mock data
    }

    return [];
  }

  ArtworkItem? _parseInternetArchiveDoc(Map<String, dynamic> doc) {
    final identifier = doc['identifier'] as String?;
    if (identifier == null) return null;

    final title = doc['title'] as String? ?? 'Untitled';
    final creator = doc['creator'] as String? ?? 'Unknown Artist';
    final date = doc['date'] as String? ?? '';
    final subject = doc['subject'] as dynamic;

    String subjectStr = '';
    if (subject is List) {
      subjectStr = subject.join(', ');
    } else if (subject is String) {
      subjectStr = subject;
    }

    // Internet Archive IIIF image URL format
    final imageUrl =
        'https://iiif.archivelab.org/iiif/$identifier/full/600,/0/default.jpg';
    final largeImageUrl =
        'https://iiif.archivelab.org/iiif/$identifier/full/1200,/0/default.jpg';

    return ArtworkItem(
      objectId: identifier.hashCode,
      title: title,
      artist: creator,
      imageUrl: imageUrl,
      largeImageUrl: largeImageUrl,
      date: date,
      medium: subjectStr.isNotEmpty ? subjectStr : 'Digital Collection',
      department: 'Internet Archive - IIIF',
      source: 'IIIF Collections',
    );
  }

  Future<ArtworkItem> _getInternetArchiveById(String id) async {
    // For Internet Archive, the ID is the identifier
    final imageUrl =
        'https://iiif.archivelab.org/iiif/$id/full/600,/0/default.jpg';
    final largeImageUrl =
        'https://iiif.archivelab.org/iiif/$id/full/1200,/0/default.jpg';

    return ArtworkItem(
      objectId: id.hashCode,
      title: 'Archive Item $id',
      artist: 'Unknown Artist',
      imageUrl: imageUrl,
      largeImageUrl: largeImageUrl,
      date: '',
      medium: 'Digital Archive',
      department: 'Internet Archive - IIIF',
      source: 'IIIF Collections',
    );
  }

  // Mock IIIF data for demonstration and fallback
  Future<List<ArtworkItem>> _getMockIIIFArtworks(int count) async {
    final random = Random();
    final artworks = <ArtworkItem>[];

    // Use some real IIIF image URLs from various institutions
    final mockData = [
      {
        'id': 'mock_yale_001',
        'title': 'Portrait of a Gentleman',
        'artist': 'Thomas Gainsborough',
        'date': '1770-1780',
        'iiifBase': 'https://manifests.britishart.yale.edu/iiif/2/obj:1001',
        'department': 'Yale Center for British Art',
      },
      {
        'id': 'mock_harvard_001',
        'title': 'Still Life with Flowers',
        'artist': 'Rachel Ruysch',
        'date': '1690-1700',
        'iiifBase': 'https://iiif.lib.harvard.edu/iiif/2/001234567',
        'department': 'Harvard Art Museums',
      },
      {
        'id': 'mock_dpla_001',
        'title': 'American Landscape',
        'artist': 'Albert Bierstadt',
        'date': '1860-1870',
        'iiifBase': 'https://dpla.iiif.server/iiif/2/item567',
        'department': 'Digital Public Library of America',
      },
      // Add more mock entries...
      {
        'id': 'mock_europeana_001',
        'title': 'Medieval Manuscript',
        'artist': 'Anonymous Scribe',
        'date': '1300-1400',
        'iiifBase': 'https://iiif.europeana.eu/iiif/2/manuscript456',
        'department': 'Europeana Collections',
      },
      {
        'id': 'mock_bodleian_001',
        'title': 'Ancient Map',
        'artist': 'Cartographer Unknown',
        'date': '1650',
        'iiifBase': 'https://iiif.bodleian.ox.ac.uk/iiif/2/map789',
        'department': 'Bodleian Library',
      },
    ];

    for (int i = 0; i < count && i < mockData.length; i++) {
      final item = mockData[i];

      // Create IIIF-compliant URLs
      final imageUrl = '${item['iiifBase']}/full/600,/0/default.jpg';
      final largeImageUrl = '${item['iiifBase']}/full/1200,/0/default.jpg';

      artworks.add(
        ArtworkItem(
          objectId: item['id'].hashCode,
          title: item['title']!,
          artist: item['artist']!,
          imageUrl: imageUrl,
          largeImageUrl: largeImageUrl,
          date: item['date']!,
          medium: 'IIIF Digital Collection',
          department: item['department']!,
          source: 'IIIF Collections',
        ),
      );
    }

    return artworks;
  }

  Future<List<ArtworkItem>> _searchMockIIIF(
    String query, {
    int limit = 10,
  }) async {
    final mockArtworks = await _getMockIIIFArtworks(20);
    final lowerQuery = query.toLowerCase();

    final filtered =
        mockArtworks
            .where((artwork) {
              return artwork.title.toLowerCase().contains(lowerQuery) ||
                  artwork.artist.toLowerCase().contains(lowerQuery) ||
                  artwork.medium.toLowerCase().contains(lowerQuery) ||
                  artwork.department.toLowerCase().contains(lowerQuery);
            })
            .take(limit)
            .toList();

    return filtered;
  }

  Future<ArtworkItem> _getMockIIIFById(String id) async {
    final mockArtworks = await _getMockIIIFArtworks(20);
    return mockArtworks.firstWhere(
      (artwork) => artwork.objectId.toString() == id.hashCode.toString(),
      orElse: () => throw Exception('IIIF artwork not found: $id'),
    );
  }
}

class IIIFEndpoint {
  final String name;
  final String baseUrl;
  final String searchEndpoint;
  final String? apiKey;

  const IIIFEndpoint({
    required this.name,
    required this.baseUrl,
    required this.searchEndpoint,
    this.apiKey,
  });
}
