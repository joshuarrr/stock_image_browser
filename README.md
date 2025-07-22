# Stock Image Browser

A Flutter app that browses high-quality public domain and cc0 images that do not require attribution.

## Features

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

1. Register for a free API key at: https://api.data.gov/signup/
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

## Architecture

### Services

- **ServiceManager**: Coordinates multiple image services
- **MetMuseumService**: Interfaces with Met Museum's public API
- **SmithsonianService**: Interfaces with Smithsonian Open Access API (requires key)
- **IIIFService**: Interfaces with Library of Congress photos
- **OpenverseService**: Interfaces with CC0 images from Openverse

### Features

- **Dynamic Tab System**: Tabs appear/disappear based on service availability
- **Smart Caching**: Results cached per service and search term
- **Infinite Scroll**: Both browse and search support loading more results
- **People Filtering**: Intelligently filters out portrait photos unless explicitly searched
- **Image Quality**: Automatically selects highest resolution available

## Contributing

1. Follow Flutter/Dart style guidelines
2. Test on both iOS and Android
3. Ensure all services gracefully handle missing API keys
4. Add tests for new features

## License

MIT License - see LICENSE file for details 