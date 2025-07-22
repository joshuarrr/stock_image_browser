import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../models/artwork_item.dart';
import 'base_image_service.dart';

class MetMuseumService extends BaseImageService {
  static const String baseUrl =
      'https://collectionapi.metmuseum.org/public/collection/v1';
  static const Duration timeout = Duration(seconds: 10);
  static const Duration requestDelay = Duration(milliseconds: 200);

  @override
  String get serviceName => 'Met Museum';

  @override
  String get serviceId => 'met-museum';

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
  final Set<int> _usedIds = <int>{};
  List<int>? _allObjectIds;

  @override
  Future<List<ArtworkItem>> getRandomArtworks(int count) async {
    try {
      // Try to get highlighted artworks first
      List<int>? highlightIds = await _getHighlightIds();

      List<int> sourceIds;
      if (highlightIds != null && highlightIds.length >= count * 3) {
        sourceIds = highlightIds;
      } else {
        sourceIds = await _getAllObjectIds();
      }

      if (sourceIds.isEmpty) return [];

      // Get random subset avoiding duplicates
      final randomIds = _getRandomUniqueIds(sourceIds, count);

      // Fetch artwork details
      final artworks = <ArtworkItem>[];
      int processed = 0;

      for (final id in randomIds) {
        processed++;
        final artwork = await _getArtworkByIdSafe(id);
        if (artwork != null) {
          artworks.add(artwork);
        }

        if (artworks.length >= 12) break;
      }

      return artworks;
    } catch (e) {
      print('MetMuseumService: Error loading random artworks: $e');
      if (e.toString().contains('Rate limited')) {
        throw ServiceRateLimitException(
          'Rate limited by Met Museum API. Please wait a moment before refreshing.',
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

      final response = await http
          .get(
            Uri.parse(
              '$baseUrl/search?q=${Uri.encodeComponent(query)}&hasImages=true',
            ),
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final objectIds = List<int>.from(data['objectIDs'] ?? []);
        _resetRateLimitBackoff();

        if (objectIds.isEmpty) return [];

        // Apply offset to skip already fetched results
        final startIndex = offset;
        if (startIndex >= objectIds.length) return [];

        final endIndex = (startIndex + limit).clamp(0, objectIds.length);
        final targetIds = objectIds.sublist(startIndex, endIndex);

        final artworks = <ArtworkItem>[];

        for (final id in targetIds) {
          final artwork = await _getArtworkByIdSafe(id);
          if (artwork != null && artwork.imageUrl.isNotEmpty) {
            artworks.add(artwork);
          }
          if (artworks.length >= limit) break;
        }

        return artworks;
      } else if (response.statusCode == 403) {
        _handleRateLimit();
        throw ServiceRateLimitException(
          'Rate limited by Met Museum API. Please wait a moment before searching.',
          retryAfter: Duration(seconds: _rateLimitBackoff),
        );
      } else {
        // Fallback to filtering random artworks
        return _searchInRandomArtworks(query, limit, offset: offset);
      }
    } catch (e) {
      if (e is ServiceRateLimitException) rethrow;

      // Fallback to filtering random artworks
      try {
        return _searchInRandomArtworks(query, limit, offset: offset);
      } catch (fallbackError) {
        throw Exception('Failed to search artworks: $e');
      }
    }
  }

  @override
  Future<ArtworkItem> getArtworkById(String id) async {
    final objectId = int.tryParse(id);
    if (objectId == null) {
      throw Exception('Invalid Met Museum artwork ID: $id');
    }

    await _throttleRequest();

    final response = await http
        .get(Uri.parse('$baseUrl/objects/$objectId'))
        .timeout(timeout);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      _resetRateLimitBackoff();
      return ArtworkItem.fromMetJson(data);
    } else if (response.statusCode == 403) {
      _handleRateLimit();
      throw ServiceRateLimitException(
        'Rate limited by Met Museum API.',
        retryAfter: Duration(seconds: _rateLimitBackoff),
      );
    } else {
      throw Exception(
        'Failed to load artwork $id: HTTP ${response.statusCode}',
      );
    }
  }

  @override
  void clearCache({bool force = false}) {
    if (force) {
      _allObjectIds = null;
      _usedIds.clear();
      _rateLimitBackoff = 0;
    } else {
      _usedIds.clear();
    }
  }

  // Private helper methods

  Future<void> _throttleRequest() async {
    if (_rateLimitBackoff > 0) {
      final backoffDelay = Duration(seconds: _rateLimitBackoff);
      // Only log significant backoffs to reduce noise
      if (_rateLimitBackoff >= 5) {
        print(
          'MetMuseumService: Rate limited - waiting ${backoffDelay.inSeconds}s',
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
    // Only log when backoff gets significant to reduce noise
    if (_rateLimitBackoff >= 5) {
      print(
        'MetMuseumService: Rate limited - backoff set to ${_rateLimitBackoff}s',
      );
    }
  }

  Future<List<int>?> _getHighlightIds() async {
    try {
      await _throttleRequest();

      final response = await http
          .get(Uri.parse('$baseUrl/search?isHighlight=true&hasImages=true'))
          .timeout(timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final ids = List<int>.from(data['objectIDs'] ?? []);
        _resetRateLimitBackoff();
        return ids;
      } else if (response.statusCode == 403) {
        _handleRateLimit();
      }
    } catch (e) {
      // Silently fail, will fallback to all objects
    }
    return null;
  }

  Future<List<int>> _getAllObjectIds() async {
    if (_allObjectIds == null) {
      await _throttleRequest();

      final response = await http
          .get(Uri.parse('$baseUrl/objects'))
          .timeout(timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _allObjectIds = List<int>.from(data['objectIDs'] ?? []);

        _resetRateLimitBackoff();
      } else if (response.statusCode == 403) {
        _handleRateLimit();
        throw ServiceRateLimitException(
          'Rate limited by Met Museum API.',
          retryAfter: Duration(seconds: _rateLimitBackoff),
        );
      } else {
        throw Exception('Failed to fetch object IDs: ${response.statusCode}');
      }
    }

    return _allObjectIds ?? [];
  }

  Set<int> _getRandomUniqueIds(List<int> sourceIds, int count) {
    final random = Random();
    final randomIds = <int>{};
    final availableIds =
        sourceIds.where((id) => !_usedIds.contains(id)).toList();

    // Reset used IDs if running low
    if (availableIds.length < count * 2) {
      print('MetMuseumService: Resetting used IDs cache');
      _usedIds.clear();
      availableIds.clear();
      availableIds.addAll(sourceIds);
    }

    int attempts = 0;
    while (randomIds.length < count && attempts < count * 5) {
      final randomIndex = random.nextInt(availableIds.length);
      final id = availableIds[randomIndex];
      if (!_usedIds.contains(id)) {
        randomIds.add(id);
        _usedIds.add(id);
      }
      attempts++;
    }

    return randomIds;
  }

  Future<ArtworkItem?> _getArtworkByIdSafe(int objectId) async {
    try {
      final artwork = await getArtworkById(objectId.toString());
      // Filter out items with no image or low-resolution images only
      if (artwork.imageUrl.isEmpty) {
        return null;
      }
      return artwork;
    } catch (e) {
      // Don't log individual artwork fetch failures to reduce noise
      return null;
    }
  }

  Future<List<ArtworkItem>> _searchInRandomArtworks(
    String query,
    int limit, {
    int offset = 0,
  }) async {
    final randomArtworks = await getRandomArtworks(50 + offset + limit);
    final lowerQuery = query.toLowerCase();

    final filtered =
        randomArtworks
            .where((artwork) {
              return artwork.title.toLowerCase().contains(lowerQuery) ||
                  artwork.artist.toLowerCase().contains(lowerQuery) ||
                  artwork.medium.toLowerCase().contains(lowerQuery) ||
                  artwork.department.toLowerCase().contains(lowerQuery);
            })
            .skip(offset)
            .take(limit)
            .toList();

    return filtered;
  }

  // Additional helper methods for compatibility
  bool hasEnoughUnusedIds(int needed) {
    if (_allObjectIds == null) return false;
    final availableIds =
        _allObjectIds!.where((id) => !_usedIds.contains(id)).length;
    return availableIds >= needed * 3;
  }
}

// Keep the Department class for compatibility
class Department {
  final int departmentId;
  final String displayName;

  Department({required this.departmentId, required this.displayName});

  factory Department.fromJson(Map<String, dynamic> json) {
    return Department(
      departmentId: json['departmentId'],
      displayName: json['displayName'],
    );
  }
}
