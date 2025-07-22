import '../models/artwork_item.dart';

/// Abstract base class for all image API services
abstract class BaseImageService {
  /// The display name of this service
  String get serviceName;

  /// The service identifier (used for tabs, internal references)
  String get serviceId;

  /// Whether this service is currently available/active
  bool get isAvailable => true;

  /// Get random artworks from this service
  Future<List<ArtworkItem>> getRandomArtworks(int count);

  /// Search artworks in this service
  Future<List<ArtworkItem>> searchArtworks(
    String query, {
    int limit = 20,
    int offset = 0,
  });

  /// Get a specific artwork by its ID
  Future<ArtworkItem> getArtworkById(String id);

  /// Clear any caches this service maintains
  void clearCache({bool force = false});

  /// Check if service is currently rate limited
  bool get isRateLimited => false;

  /// Get service-specific rate limit info (optional)
  String? get rateLimitInfo => null;
}

/// Exception thrown when a service encounters rate limiting
class ServiceRateLimitException implements Exception {
  final String message;
  final Duration? retryAfter;

  const ServiceRateLimitException(this.message, {this.retryAfter});

  @override
  String toString() => 'ServiceRateLimitException: $message';
}

/// Exception thrown when a service is unavailable
class ServiceUnavailableException implements Exception {
  final String message;
  final String serviceId;

  const ServiceUnavailableException(this.message, this.serviceId);

  @override
  String toString() => 'ServiceUnavailableException: $message';
}

/// Shared utility class for image resolution filtering across all services
class ImageResolutionUtils {
  /// Check if a URL represents a low-resolution image
  static bool isLowResolution(String url) {
    return url.contains('150px') ||
        url.contains('200px') ||
        url.contains('250px') ||
        url.contains('300px') ||
        url.contains('400px') ||
        url.contains('thumb') ||
        url.contains('_sm') ||
        url.contains('_small') ||
        url.contains('_sq') ||
        url.contains('square') ||
        url.contains('pct:6.25') ||
        url.contains('pct:12.5') ||
        url.contains('pct:25') ||
        url.endsWith('_s.jpg') ||
        url.endsWith('_t.jpg') ||
        url.endsWith('_m.jpg');
  }

  /// Select the best resolution URL from a list of image URLs
  static String? selectBestResolutionUrl(List<String> urls) {
    final validUrls = urls
        .where((url) => url.isNotEmpty && !isLowResolution(url))
        .toList();

    if (validUrls.isEmpty) return null;

    // Priority order: largest to smallest resolution indicators
    final priorityPatterns = [
      'full/pct:100', // IIIF full resolution
      'full/max', // IIIF max resolution
      '1200', // Large size
      '1000',
      '800',
      '640',
      'r.jpg', // LOC high-res indicator
      '_large',
      '_l.jpg',
      'primaryImage', // Met Museum full size
    ];

    // Check each priority pattern
    for (final pattern in priorityPatterns) {
      for (final url in validUrls) {
        if (url.contains(pattern)) {
          return url;
        }
      }
    }

    // If no priority patterns found, return the longest URL (often higher res)
    validUrls.sort((a, b) => b.length.compareTo(a.length));
    return validUrls.first;
  }

  /// Try to get a larger version of an image URL by modifying patterns
  static String tryToGetLargerVersion(String originalUrl) {
    // For IIIF URLs, try to get full resolution
    if (originalUrl.contains('/iiif/')) {
      final iiifPattern = RegExp(r'(.*/iiif/[^/]+)/.*');
      final match = iiifPattern.firstMatch(originalUrl);
      if (match != null) {
        return '${match.group(1)}/full/1200,/0/default.jpg';
      }
    }

    // For LOC URLs, try to remove size restrictions
    if (originalUrl.contains('tile.loc.gov')) {
      return originalUrl
          .replaceAll('150px', '800px')
          .replaceAll('300px', '800px')
          .replaceAll('pct:12.5', 'pct:100')
          .replaceAll('pct:25', 'pct:100')
          .replaceAll('pct:50', 'pct:100');
    }

    // For Met Museum, prefer primaryImage over primaryImageSmall
    if (originalUrl.contains('images.metmuseum.org') &&
        originalUrl.contains('web-large')) {
      return originalUrl.replaceAll('web-large', 'original');
    }

    return originalUrl;
  }
}
