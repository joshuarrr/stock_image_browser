import 'dart:async';
import '../models/artwork_item.dart';
import 'base_image_service.dart';

/// Manages multiple image services and provides unified access
class ServiceManager {
  final Map<String, BaseImageService> _services = {};
  String _activeServiceId = 'all'; // 'all' means use all services

  /// Register a new service
  void registerService(BaseImageService service) {
    _services[service.serviceId] = service;
  }

  /// Unregister a service
  void unregisterService(String serviceId) {
    _services.remove(serviceId);
  }

  /// Get all registered services
  List<BaseImageService> get availableServices =>
      _services.values.where((service) => service.isAvailable).toList();

  /// Get service by ID
  BaseImageService? getService(String serviceId) => _services[serviceId];

  /// Set the active service (or 'all' for all services)
  void setActiveService(String serviceId) {
    if (serviceId == 'all' || _services.containsKey(serviceId)) {
      _activeServiceId = serviceId;
    }
  }

  /// Get the currently active service ID
  String get activeServiceId => _activeServiceId;

  /// Get random artworks from active service(s)
  Future<List<ArtworkItem>> getRandomArtworks(int count) async {
    if (_activeServiceId == 'all') {
      return _getRandomArtworksFromAll(count);
    }

    // Debug logging to verify which service is being used
    print('ServiceManager: Getting $count artworks from $_activeServiceId');

    final service = _services[_activeServiceId];
    if (service == null || !service.isAvailable) {
      throw ServiceUnavailableException(
        'Service $_activeServiceId is not available',
        _activeServiceId,
      );
    }

    final results = await service.getRandomArtworks(count);
    print(
      'ServiceManager: $_activeServiceId returned ${results.length} artworks',
    );

    // Verify that all results are actually from the expected service
    final unexpectedSources =
        results.where((artwork) {
          final expectedSource = _getExpectedSourceName(_activeServiceId);
          return expectedSource != null && artwork.source != expectedSource;
        }).toList();

    if (unexpectedSources.isNotEmpty) {
      print(
        'ServiceManager: WARNING - Found ${unexpectedSources.length} artworks from wrong sources:',
      );
      for (final artwork in unexpectedSources) {
        print(
          '  - "${artwork.title}" from ${artwork.source} (expected: ${_getExpectedSourceName(_activeServiceId)})',
        );
      }
    }

    return results;
  }

  String? _getExpectedSourceName(String serviceId) {
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
        return null;
    }
  }

  /// Search artworks in active service(s)
  Future<List<ArtworkItem>> searchArtworks(
    String query, {
    int limit = 20,
    int offset = 0,
  }) async {
    if (_activeServiceId == 'all') {
      return _searchArtworksInAll(query, limit: limit, offset: offset);
    }

    // Debug logging to verify which service is being used for search
    print(
      'ServiceManager: Searching "$query" in $_activeServiceId (limit: $limit, offset: $offset)',
    );

    final service = _services[_activeServiceId];
    if (service == null || !service.isAvailable) {
      throw ServiceUnavailableException(
        'Service $_activeServiceId is not available',
        _activeServiceId,
      );
    }

    final results = await service.searchArtworks(
      query,
      limit: limit,
      offset: offset,
    );
    print(
      'ServiceManager: $_activeServiceId search returned ${results.length} results',
    );

    // Verify that all results are actually from the expected service
    final unexpectedSources =
        results.where((artwork) {
          final expectedSource = _getExpectedSourceName(_activeServiceId);
          return expectedSource != null && artwork.source != expectedSource;
        }).toList();

    if (unexpectedSources.isNotEmpty) {
      print(
        'ServiceManager: WARNING - Search found ${unexpectedSources.length} artworks from wrong sources:',
      );
      for (final artwork in unexpectedSources) {
        print(
          '  - "${artwork.title}" from ${artwork.source} (expected: ${_getExpectedSourceName(_activeServiceId)})',
        );
      }
    }

    return results;
  }

  /// Get artwork by ID from any service that has it
  Future<ArtworkItem?> getArtworkById(
    String id, {
    String? preferredServiceId,
  }) async {
    // Try preferred service first if specified
    if (preferredServiceId != null) {
      final service = _services[preferredServiceId];
      if (service != null && service.isAvailable) {
        try {
          return await service.getArtworkById(id);
        } catch (e) {
          // Fall through to try other services
        }
      }
    }

    // Try all services
    for (final service in availableServices) {
      try {
        return await service.getArtworkById(id);
      } catch (e) {
        // Continue to next service
      }
    }

    return null;
  }

  /// Clear caches for all services
  void clearAllCaches({bool force = false}) {
    for (final service in _services.values) {
      service.clearCache(force: force);
    }
  }

  /// Get rate limit status for all services
  Map<String, String> getRateLimitStatus() {
    final status = <String, String>{};
    for (final service in _services.values) {
      if (service.isRateLimited) {
        status[service.serviceId] = service.rateLimitInfo ?? 'Rate limited';
      }
    }
    return status;
  }

  // Private methods

  Future<List<ArtworkItem>> _getRandomArtworksFromAll(int count) async {
    final services = availableServices;
    if (services.isEmpty) {
      throw ServiceUnavailableException('No services available', 'all');
    }

    // Ensure minimum 9 artworks per service, distribute remaining count
    const minPerService = 9;
    final baseTotal = services.length * minPerService;
    final remainingCount = count > baseTotal ? count - baseTotal : 0;
    final extraPerService =
        remainingCount > 0 ? (remainingCount / services.length).ceil() : 0;
    final requestPerService = minPerService + extraPerService;

    final futures = <Future<List<ArtworkItem>>>[];

    for (final service in services) {
      if (!service.isRateLimited) {
        futures.add(_safeGetRandomArtworks(service, requestPerService));
      }
    }

    if (futures.isEmpty) {
      throw ServiceRateLimitException('All services are rate limited');
    }

    final results = await Future.wait(futures);
    final allArtworks = <ArtworkItem>[];
    for (final artworks in results) {
      allArtworks.addAll(artworks);
    }

    // Shuffle and take requested count
    allArtworks.shuffle();
    return allArtworks.take(count).toList();
  }

  Future<List<ArtworkItem>> _searchArtworksInAll(
    String query, {
    int limit = 20,
    int offset = 0,
  }) async {
    final services = availableServices;
    if (services.isEmpty) {
      throw ServiceUnavailableException('No services available', 'all');
    }

    // Calculate per-service limits and offsets for parallel searching
    final limitPerService = limit ~/ services.length + 1;
    final offsetPerService = offset ~/ services.length;

    // Search in parallel across all services
    final futures = services
        .where((service) => !service.isRateLimited)
        .map(
          (service) => _safeSearchArtworks(
            service,
            query,
            limit: limitPerService,
            offset: offsetPerService,
          ),
        );

    if (futures.isEmpty) {
      throw ServiceRateLimitException('All services are rate limited');
    }

    final results = await Future.wait(futures);
    final allResults = <ArtworkItem>[];

    print(
      'ServiceManager: Combining search results from ${results.length} services',
    );
    for (int i = 0; i < results.length; i++) {
      final serviceResults = results[i];
      allResults.addAll(serviceResults);
      print(
        'ServiceManager: Added ${serviceResults.length} results from service ${i + 1}',
      );
    }

    // Count results by source
    final resultsBySource = <String, int>{};
    for (final artwork in allResults) {
      resultsBySource[artwork.source] =
          (resultsBySource[artwork.source] ?? 0) + 1;
    }
    print('ServiceManager: Final combined results by source: $resultsBySource');

    // Return up to limit, with some variety from each service
    final finalResults = allResults.take(limit).toList();
    print(
      'ServiceManager: Returning ${finalResults.length} combined search results',
    );
    return finalResults;
  }

  Future<List<ArtworkItem>> _safeGetRandomArtworks(
    BaseImageService service,
    int count,
  ) async {
    try {
      return await service.getRandomArtworks(count);
    } catch (e) {
      // Only log non-rate-limit errors to reduce noise
      if (!e.toString().contains('Rate limited') &&
          !e.toString().contains('403')) {
        print('ServiceManager: Error from ${service.serviceName}: $e');
      }
      return <ArtworkItem>[];
    }
  }

  Future<List<ArtworkItem>> _safeSearchArtworks(
    BaseImageService service,
    String query, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      print(
        'ServiceManager: Calling ${service.serviceName} for search "$query"',
      );
      final results = await service.searchArtworks(
        query,
        limit: limit,
        offset: offset,
      );
      print(
        'ServiceManager: ${service.serviceName} returned ${results.length} search results',
      );

      // Log first few results for debugging
      if (results.isNotEmpty && service.serviceName == 'Openverse') {
        print('ServiceManager: Openverse results sample:');
        for (int i = 0; i < results.length && i < 3; i++) {
          print('  - ${results[i].title} from ${results[i].source}');
        }
      }

      return results;
    } catch (e) {
      // Only log non-rate-limit errors to reduce noise
      if (!e.toString().contains('Rate limited') &&
          !e.toString().contains('403')) {
        print('ServiceManager: Search error from ${service.serviceName}: $e');
      }
      print(
        'ServiceManager: ${service.serviceName} search failed, returning empty list',
      );
      return <ArtworkItem>[];
    }
  }
}
