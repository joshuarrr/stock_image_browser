import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/artwork_item.dart';

class ImageDetailScreen extends StatelessWidget {
  final ArtworkItem artwork;

  const ImageDetailScreen({super.key, required this.artwork});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A131F), // Default bg
      appBar: AppBar(
        title: Text(
          artwork.title.isNotEmpty ? artwork.title : 'Piece',
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: const Color(0xFF1A131F), // Default bg
        foregroundColor: const Color(0xFFFFFFFF), // Text default
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back,
            color: Color(0xFFFFFFFF), // Icon default
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          // Main image with hero animation
          Expanded(
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: const Color(0x5C583473), // Surface default
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Hero(
                  tag: 'artwork-${artwork.objectId}',
                  child: InteractiveViewer(
                    minScale: 1.1,
                    maxScale: 4.0,
                    child: CachedNetworkImage(
                      imageUrl: artwork.largeImageUrl ?? artwork.imageUrl,
                      fit: BoxFit.cover,
                      placeholder:
                          (context, url) => const Center(
                            child: CircularProgressIndicator(
                              color: Color(0x80FFFFFF), // Icon secondary
                            ),
                          ),
                      errorWidget:
                          (context, url, error) => Container(
                            color: const Color(0x5C583473), // Surface default
                            child: const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.image_not_supported,
                                    size: 64,
                                    color: Color(0x80FFFFFF), // Icon secondary
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    'Image not available',
                                    style: TextStyle(
                                      color: Color(
                                        0x80FFFFFF,
                                      ), // Text secondary
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Only show source
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            child: Text(
              'Source: ${artwork.source}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0x80FFFFFF), // Text secondary
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
