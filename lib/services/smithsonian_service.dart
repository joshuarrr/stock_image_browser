import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/artwork_item.dart';
import 'base_image_service.dart';

class SmithsonianService extends BaseImageService {
  static const String baseUrl = 'https://api.si.edu/openaccess/api/v1.0';
  static const Duration timeout = Duration(seconds: 10);

  // API key for Smithsonian Open Access API
  static const String apiKey = 'Z5vu6cWPwUXkacegAmmcvKEX4qAFuwB8F80mmD5z';

  @override
  String get serviceName => 'Smithsonian';

  @override
  String get serviceId => 'smithsonian';

  // Smithsonian API is generally more permissive than Met Museum
  @override
  bool get isRateLimited => false;

  @override
  String? get rateLimitInfo => null;

  @override
  Future<List<ArtworkItem>> getRandomArtworks(int count) async {
    try {
      // Use a very simple approach - search for items that are likely to have images
      final queryParams = {
        'api_key': apiKey,
        'q': '*:*',
        'fqs': ['online_media_type:"Images"'].join(' AND '),
        'sort': 'random',
        'rows':
            (count * 10).toString(), // Get many more to account for filtering
        'start': '0',
      };

      final uri = Uri.parse(
        '$baseUrl/search',
      ).replace(queryParameters: queryParams);
      final response = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final rows = data['response']?['rows'] as List? ?? [];

        final artworks = <ArtworkItem>[];
        int processedCount = 0;

        for (final row in rows) {
          processedCount++;
          try {
            // Skip obvious library/book items
            final unitCode = row['unitCode'] as String? ?? '';
            if (unitCode == 'SIL') {
              continue; // Skip Smithsonian Libraries items
            }

            final artwork = ArtworkItem.fromSmithsonianJson(row);
            // Only include items with high-resolution images
            if (artwork.imageUrl.isNotEmpty) {
              artworks.add(artwork);
              // Only log occasionally to reduce noise
              if (artworks.length % 3 == 1) {
                print(
                  'SmithsonianService: ✓ Sample artwork: "${artwork.title}" from $unitCode',
                );
              }
              if (artworks.length >= count) break; // Stop when we have enough
            }
          } catch (e) {
            // Skip items that can't be parsed
            continue;
          }
        }

        print(
          'SmithsonianService: Processed $processedCount items, loaded ${artworks.length} high-res artworks',
        );
        return artworks;
      } else if (response.statusCode == 429) {
        throw ServiceRateLimitException(
          'Rate limited by Smithsonian API',
          retryAfter: Duration(seconds: 60),
        );
      } else {
        throw Exception(
          'Failed to load random artworks: HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      print('SmithsonianService: Error loading random artworks: $e');
      if (e is ServiceRateLimitException) rethrow;
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
      // Use a smarter search approach - combine user query with visual-focused terms
      // and target specific museum departments that have visual specimens
      final queryParams = {
        'api_key': apiKey,
        'q': '$query AND (specimen OR object OR artwork OR collection)',
        'fqs': [
          'online_media_type:"Images"',
          'unit_code:"NMNHBOTANY" OR unit_code:"NMNHBIRDS" OR unit_code:"NMNHMAMMALS" OR unit_code:"NMNHINV" OR unit_code:"NMNHENTO" OR unit_code:"NMNHHERPS" OR unit_code:"NMNHFISHES" OR unit_code:"NMNHMINSCI" OR unit_code:"NMNHPALEO" OR unit_code:"CHNDM" OR unit_code:"FSG" OR unit_code:"SAAM" OR unit_code:"NPG" OR unit_code:"HMSG" OR unit_code:"NMAfA"', // Target visual departments
        ].join(' AND '),
        'rows':
            (limit * 15).toString(), // Get many more to account for filtering
        'start': offset.toString(),
      };

      final uri = Uri.parse(
        '$baseUrl/search',
      ).replace(queryParameters: queryParams);
      final response = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final rows = data['response']?['rows'] as List? ?? [];

        print(
          'SmithsonianService: API returned ${rows.length} items for search "$query"',
        );

        final artworks = <ArtworkItem>[];
        int processedCount = 0;

        for (final row in rows) {
          processedCount++;
          try {
            // Skip obvious non-visual items
            final unitCode = row['unitCode'] as String? ?? '';
            if (unitCode == 'SIL' ||
                unitCode == 'SLA_SRO' ||
                unitCode == 'SILNMAHTL') {
              continue; // Skip libraries and research archives
            }

            final artwork = ArtworkItem.fromSmithsonianJson(row);

            // Only include items with high-resolution images
            if (artwork.imageUrl.isNotEmpty) {
              artworks.add(artwork);
              // Only log occasionally to reduce noise
              if (artworks.length % 3 == 1) {
                print(
                  'SmithsonianService: ✓ Sample: "${artwork.title}" from $unitCode',
                );
              }
              if (artworks.length >= limit) break; // Stop when we have enough
            }
          } catch (e) {
            // Skip items that can't be parsed
            continue;
          }
        }

        print(
          'SmithsonianService: Processed $processedCount items, search found ${artworks.length} high-res artworks for "$query"',
        );
        return artworks;
      } else if (response.statusCode == 429) {
        throw ServiceRateLimitException(
          'Rate limited by Smithsonian API',
          retryAfter: Duration(seconds: 60),
        );
      } else {
        throw Exception(
          'Failed to search artworks: HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      print('SmithsonianService: Error searching artworks: $e');
      if (e is ServiceRateLimitException) rethrow;
      throw Exception('Failed to search artworks: $e');
    }
  }

  @override
  Future<ArtworkItem> getArtworkById(String id) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/content/$id?api_key=$apiKey'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return ArtworkItem.fromSmithsonianJson(data['response']);
      } else if (response.statusCode == 429) {
        throw ServiceRateLimitException(
          'Rate limited by Smithsonian API',
          retryAfter: Duration(seconds: 60),
        );
      } else {
        throw Exception(
          'Failed to load artwork $id: HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      print('SmithsonianService: Error loading artwork $id: $e');
      if (e is ServiceRateLimitException) rethrow;
      throw Exception('Failed to load artwork $id: $e');
    }
  }

  @override
  void clearCache({bool force = false}) {
    // Smithsonian API doesn't require caching like Met Museum
    print('SmithsonianService: Cache cleared');
  }
}
