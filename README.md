# Stock Image Browser

A Flutter app that browses high-quality public domain and cc0 images that do not require attribution.

## Overview

- **Multi-Source Browsing**: Browse images from Met Museum, Smithsonian, Library of Congress, and Openverse
- **Smart Search**: Search across all sources with infinite scroll
- **Intelligent Filtering**: Automatically filters out low-resolution images and unwanted content
- **Caching**: Smart caching for instant tab switching and state preservation
- **High-Quality Images**: Only displays high-resolution, exhibition-quality images

### APIs

- **Met Museum API**: No key required (public API)
- **Smithsonian Open Access API:** Key Required -- see below
- **Library of Congress**: No key required (public API)
- **Openverse**: No key required (public API)

## Setup

### Prerequisites

- Flutter SDK (latest stable version)
- Dart SDK
- iOS Simulator or Android Emulator (for mobile testing)

### API Keys

#### Smithsonian Open Access API (Optional)

The Smithsonian service requires an API key. Without it, the Smithsonian tab will not appear.

1. Register for a free API key at: <https://api.data.gov/signup/>
2. Set the environment variable when running the app:

```bash
# For development
flutter run --dart-define=SMITHSONIAN_API_KEY=your_api_key_here

# For building
flutter build --dart-define=SMITHSONIAN_API_KEY=your_api_key_here
```

**Alternative setup methods:**

- **VS Code**: Add to your launch.json:

```json
{
    "name": "Flutter",
    "type": "dart",
    "request": "launch",
    "program": "lib/main.dart",
    "toolArgs": ["--dart-define=SMITHSONIAN_API_KEY=your_api_key_here"]
}
```

### Running the App

1. Clone the repository
2. Install dependencies:

```bash
flutter pub get
```

3. Run the app:

```bash
#cd to stock_app  
cd stock_app/

# Without Smithsonian (3 services)
flutter run

# With Smithsonian (4 services)
flutter run --dart-define=SMITHSONIAN_API_KEY=your_api_key_here
```

## Services

- **ServiceManager**: Coordinates multiple image services
- **MetMuseumService**: Interfaces with Met Museum's public API
- **SmithsonianService**: Interfaces with Smithsonian Open Access API (requires key)
- **IIIFService**: Interfaces with Library of Congress photos
- **OpenverseService**: Interfaces with CC0 images from Openverse

## License

MIT License
