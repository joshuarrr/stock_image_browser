import 'package:flutter/material.dart';
import '../services/base_image_service.dart';

class ArtworkItem {
  final int objectId;
  final String title;
  final String artist;
  final String imageUrl;
  final String? largeImageUrl;
  final String date;
  final String medium;
  final String department;
  final String source; // Which API source this came from

  ArtworkItem({
    required this.objectId,
    required this.title,
    required this.artist,
    required this.imageUrl,
    this.largeImageUrl,
    required this.date,
    required this.medium,
    required this.department,
    this.source = 'Met Museum',
  });

  factory ArtworkItem.fromMetJson(Map<String, dynamic> json) {
    // Try multiple image fields from Met Museum API, prioritizing high-res images
    String imageUrl = '';
    String? largeImageUrl;

    final candidateUrls = <String>[];

    // Collect all available image URLs
    if (json['primaryImage'] != null &&
        json['primaryImage'].toString().isNotEmpty) {
      candidateUrls.add(json['primaryImage'].toString());
    }
    if (json['primaryImageSmall'] != null &&
        json['primaryImageSmall'].toString().isNotEmpty) {
      candidateUrls.add(json['primaryImageSmall'].toString());
    }
    if (json['additionalImages'] != null && json['additionalImages'] is List) {
      final additionalImages = json['additionalImages'] as List;
      for (final img in additionalImages) {
        if (img != null && img.toString().isNotEmpty) {
          candidateUrls.add(img.toString());
        }
      }
    }

    // Use shared utility to select best resolution image
    final bestUrl = ImageResolutionUtils.selectBestResolutionUrl(candidateUrls);
    if (bestUrl != null) {
      imageUrl = bestUrl;
      largeImageUrl = ImageResolutionUtils.tryToGetLargerVersion(bestUrl);
    } else {
      // If all images are low-res, skip this item by returning with empty imageUrl
      // The service will filter this out later
    }

    return ArtworkItem(
      objectId: json['objectID'] ?? 0,
      title: json['title'] ?? 'Untitled',
      artist:
          json['artistDisplayName'] ??
          json['artistDisplayBio'] ??
          'Unknown Artist',
      imageUrl: imageUrl,
      largeImageUrl: largeImageUrl,
      date: json['objectDate'] ?? json['objectBeginDate']?.toString() ?? '',
      medium: json['medium'] ?? json['classification'] ?? '',
      department: json['department'] ?? '',
      source: 'Met Museum',
    );
  }

  factory ArtworkItem.fromSmithsonianJson(Map<String, dynamic> json) {
    // Extract image URLs from Smithsonian API response
    String imageUrl = '';
    String? largeImageUrl;

    // Check for content structure with online_media
    final content = json['content'] as Map<String, dynamic>? ?? {};
    final descriptiveNonRepeating =
        content['descriptiveNonRepeating'] as Map<String, dynamic>? ?? {};
    final onlineMedia =
        descriptiveNonRepeating['online_media'] as Map<String, dynamic>? ?? {};
    final media = onlineMedia['media'] as List? ?? [];

    final candidateUrls = <String>[];

    // Collect all image URLs from media array
    for (final mediaItem in media) {
      if (mediaItem is Map<String, dynamic>) {
        final type = mediaItem['type'] as String? ?? '';
        if (type.toLowerCase().contains('image')) {
          // Get the main content URL
          final contentUrl = mediaItem['content'] as String? ?? '';
          if (contentUrl.isNotEmpty) {
            candidateUrls.add(contentUrl);
          }

          // Also check resources for higher resolution versions
          final resources = mediaItem['resources'] as List? ?? [];
          for (final resource in resources) {
            if (resource is Map<String, dynamic>) {
              final resourceUrl = resource['url'] as String? ?? '';
              final label = resource['label'] as String? ?? '';
              if (resourceUrl.isNotEmpty &&
                  (label.toLowerCase().contains('high-resolution') ||
                      label.toLowerCase().contains('jpeg') ||
                      label.toLowerCase().contains('tiff'))) {
                candidateUrls.add(resourceUrl);
              }
            }
          }
        }
      }
    }

    // Debug: Log the JSON structure if no URLs found
    if (candidateUrls.isEmpty) {
      final title =
          json['title'] as String? ??
          content['title'] as String? ??
          (descriptiveNonRepeating['title']
                  as Map<String, dynamic>?)?['content']
              as String? ??
          'Untitled';
      final unitCode = json['unitCode'] as String? ?? 'Unknown';
      // Only log occasionally to reduce noise
      if (title.hashCode % 20 == 0) {
        print(
          'SmithsonianService: Sample item without images: "$title" ($unitCode)',
        );
      }
    }

    // Use shared utility to select best resolution image
    final bestUrl = ImageResolutionUtils.selectBestResolutionUrl(candidateUrls);
    if (bestUrl != null) {
      imageUrl = bestUrl;
      largeImageUrl = ImageResolutionUtils.tryToGetLargerVersion(bestUrl);
    }

    // Extract metadata - try multiple locations for title
    final title =
        json['title'] as String? ??
        content['title'] as String? ??
        (descriptiveNonRepeating['title'] as Map<String, dynamic>?)?['content']
            as String? ??
        'Untitled';

    // Try to extract artist/creator info
    final freetext = content['freetext'] as Map<String, dynamic>? ?? {};
    final notes = freetext['notes'] as List? ?? [];
    final names = freetext['name'] as List? ?? [];
    String artist = 'Unknown';

    // First try names field for authors/artists
    for (final name in names) {
      if (name is Map<String, dynamic>) {
        final label = name['label'] as String? ?? '';
        final content = name['content'] as String? ?? '';
        if (label.toLowerCase().contains('artist') ||
            label.toLowerCase().contains('creator') ||
            label.toLowerCase().contains('maker') ||
            label.toLowerCase().contains('author')) {
          artist = content;
          break;
        }
      }
    }

    // If no artist found in names, try notes
    if (artist == 'Unknown') {
      for (final note in notes) {
        if (note is Map<String, dynamic>) {
          final label = note['label'] as String? ?? '';
          final content = note['content'] as String? ?? '';
          if (label.toLowerCase().contains('artist') ||
              label.toLowerCase().contains('creator') ||
              label.toLowerCase().contains('maker')) {
            artist = content;
            break;
          }
        }
      }
    }

    // Extract date
    final indexedStructured =
        content['indexedStructured'] as Map<String, dynamic>? ?? {};
    final dates = indexedStructured['date'] as List? ?? [];
    String date = '';
    if (dates.isNotEmpty) {
      date = dates.first.toString();
    }

    // If no structured date, try freetext date
    if (date.isEmpty) {
      final freetextDates = freetext['date'] as List? ?? [];
      for (final dateItem in freetextDates) {
        if (dateItem is Map<String, dynamic>) {
          final content = dateItem['content'] as String? ?? '';
          if (content.isNotEmpty) {
            date = content;
            break;
          }
        }
      }
    }

    // Extract place/department info
    final places = indexedStructured['place'] as List? ?? [];
    final unitCode =
        json['unitCode'] as String? ??
        content['unitCode'] as String? ??
        descriptiveNonRepeating['unit_code'] as String? ??
        '';

    String department = unitCode;
    if (places.isNotEmpty) {
      department += ' - ${places.first}';
    }

    // Extract medium/object type
    final objectTypes = indexedStructured['object_type'] as List? ?? [];
    String medium = '';
    if (objectTypes.isNotEmpty) {
      medium = objectTypes.first.toString();
    }

    // If no structured object type, try freetext
    if (medium.isEmpty) {
      final freetextObjectTypes = freetext['objectType'] as List? ?? [];
      for (final typeItem in freetextObjectTypes) {
        if (typeItem is Map<String, dynamic>) {
          final content = typeItem['content'] as String? ?? '';
          if (content.isNotEmpty) {
            medium = content;
            break;
          }
        }
      }
    }

    return ArtworkItem(
      objectId:
          json['id']?.toString().hashCode ?? 0, // Smithsonian uses string IDs
      title: title,
      artist: artist,
      imageUrl: imageUrl,
      largeImageUrl: largeImageUrl,
      date: date,
      medium: medium,
      department: department.isNotEmpty ? department : 'Smithsonian',
      source: 'Smithsonian',
    );
  }

  factory ArtworkItem.fromIIIFJson(Map<String, dynamic> json, String source) {
    // Extract basic metadata
    final title = json['title'] as String? ?? 'Untitled';
    final creator =
        json['creator'] as String? ??
        json['artist'] as String? ??
        'Unknown Artist';
    final date = json['date'] as String? ?? '';
    final identifier =
        json['identifier'] as String? ?? json['id'] as String? ?? '';

    // Handle IIIF image URLs
    String imageUrl = '';
    String? largeImageUrl;

    if (json['iiifBase'] != null) {
      final iiifBase = json['iiifBase'] as String;
      imageUrl = '$iiifBase/full/600,/0/default.jpg';
      largeImageUrl = '$iiifBase/full/1200,/0/default.jpg';
    } else if (json['imageUrl'] != null) {
      imageUrl = json['imageUrl'] as String;
      largeImageUrl = json['largeImageUrl'] as String? ?? imageUrl;
    }

    // Extract additional metadata
    final description = json['description'] as String? ?? '';
    final subject = json['subject'] as String? ?? '';
    final medium = subject.isNotEmpty
        ? subject
        : description.isNotEmpty
        ? description
        : 'IIIF Digital Collection';
    final department = json['department'] as String? ?? source;

    return ArtworkItem(
      objectId: identifier.isNotEmpty ? identifier.hashCode : json.hashCode,
      title: title,
      artist: creator,
      imageUrl: imageUrl,
      largeImageUrl: largeImageUrl,
      date: date,
      medium: medium,
      department: department,
      source: 'IIIF Collections',
    );
  }
}

class ApiSource {
  final String id;
  final String name;
  final IconData icon;
  final bool isActive;

  const ApiSource({
    required this.id,
    required this.name,
    required this.icon,
    this.isActive = true,
  });
}

// Predefined API sources that match the tab structure
class ApiSources {
  static const all = ApiSource(id: 'all', name: 'All', icon: Icons.apps);

  static const metMuseum = ApiSource(
    id: 'met-museum',
    name: 'Met Museum',
    icon: Icons.museum,
  );

  static const smithsonian = ApiSource(
    id: 'smithsonian',
    name: 'Smithsonian',
    icon: Icons.account_balance,
    isActive: true, // Now implemented!
  );

  static const iiif = ApiSource(
    id: 'iiif',
    name: 'Library of Congress',
    icon: Icons.auto_stories,
    isActive: true, // Now implemented!
  );

  static const openverse = ApiSource(
    id: 'openverse',
    name: 'Openverse',
    icon: Icons.public,
    isActive: true, // Now implemented!
  );

  static const List<ApiSource> allSources = [
    all,
    metMuseum,
    smithsonian,
    iiif,
    openverse,
  ];
}
