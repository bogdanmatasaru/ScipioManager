# Scipio Manager

A native macOS app for managing [Scipio](https://github.com/giginet/scipio) XCFramework caches. Built with SwiftUI, designed for iOS teams that use Scipio to pre-build and cache Swift Package dependencies as XCFrameworks.

![macOS 15+](https://img.shields.io/badge/macOS-15%2B-blue)
![Swift 6](https://img.shields.io/badge/Swift-6-orange)
![License](https://img.shields.io/badge/License-MIT-green)

---

## What It Does

Scipio Manager gives you a visual dashboard to:

- **Monitor** framework count, disk usage, sync status at a glance
- **Browse** all XCFrameworks with architecture slices, versions, and sizes
- **Manage** the 3-layer cache (Project → Local Disk → GCS Remote)
- **Explore** your GCS bucket with grouped/flat views, filtering, and bulk operations
- **Diagnose** common issues (missing slices, credentials, toolchain)
- **Sync** frameworks with one click (consumer-only or full build + cache)
- **Clean** caches individually or nuclear-clean everything

## Screenshots

| Dashboard | Frameworks | GCS Bucket |
|:---------:|:----------:|:----------:|
| Stats, sync controls, live console | List/detail with arch slices | Grouped by framework with stats |

## Installation

### Option 1: Download Release

Download the latest `ScipioManager.app` from [Releases](../../releases) and place it anywhere (e.g., `/Applications/` or next to your Scipio directory).

### Option 2: Build from Source

```bash
git clone https://github.com/bogdanmatasaru/ScipioManager.git
cd ScipioManager
swift build -c release
```

The binary will be at `.build/release/ScipioManager`.

To build a macOS `.app` bundle:

```bash
swift build -c release --arch arm64 --arch x86_64
# Then create the .app bundle (see Scripts/bundle.sh if available)
```

## Configuration

Scipio Manager loads settings from a `scipio-manager.json` file. It searches these locations in order:

1. **Next to the `.app` bundle** (recommended)
2. Current working directory
3. `~/.config/scipio-manager/config.json`

### Example Configuration

```json
{
  "scipio_path": "/Users/you/Projects/MyApp/Scipio",
  "bucket": {
    "name": "your-bucket-name",
    "endpoint": "https://storage.googleapis.com",
    "storage_prefix": "XCFrameworks/",
    "region": "auto"
  },
  "hmac_key_filename": "gcs-hmac.json",
  "derived_data_prefix": "MyApp-",
  "fork_organizations": ["your-org", "your-username"]
}
```

### Configuration Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `scipio_path` | `string?` | `null` | Absolute path to your Scipio directory. Auto-detected if omitted. |
| `bucket.name` | `string` | `""` | GCS/S3 bucket name for remote cache |
| `bucket.endpoint` | `string` | `https://storage.googleapis.com` | S3-compatible endpoint |
| `bucket.storage_prefix` | `string` | `XCFrameworks/` | Object key prefix in the bucket |
| `bucket.region` | `string` | `auto` | Region for S3 signing |
| `hmac_key_filename` | `string` | `gcs-hmac.json` | Name of HMAC credentials file in Scipio dir |
| `derived_data_prefix` | `string?` | `null` | Xcode DerivedData folder prefix (e.g. `MyApp-`) for targeted cleanup |
| `fork_organizations` | `[string]` | `[]` | GitHub orgs/usernames shown as "Fork" badges |

### GCS HMAC Credentials

For remote cache access, place a JSON file in your Scipio directory:

```json
{
  "accessKeyId": "GOOG1E...",
  "secretAccessKey": "..."
}
```

Or set environment variables:
```bash
export SCIPIO_GCS_HMAC_ACCESS_KEY="GOOG1E..."
export SCIPIO_GCS_HMAC_SECRET_KEY="..."
```

**How to create HMAC keys:**
1. Go to [Google Cloud Console → Storage → Settings → Interoperability](https://console.cloud.google.com/storage/settings;tab=interoperability)
2. Click "Create a key for a service account"
3. Save the Access Key and Secret as JSON

## App Features

### Dashboard
- Framework count, disk usage, last sync time, status
- One-click sync (Consumer Only or Full Build + Cache)
- Live console output during operations
- Recent activity log

### Frameworks
- Searchable list with architecture slice indicators (green = device, blue = simulator)
- Detail view with version, repository URL, size, and arch slices
- Add new dependencies to `Build/Package.swift`
- Remove dependencies (deletes from manifest and disk)

### Cache
- Visual 3-layer cache architecture (Project → Local Disk → GCS Remote)
- Individual cache location cleanup (DerivedData, SPM, Scipio local, etc.)
- Nuclear clean option to wipe everything

### GCS Bucket Browser
- Grouped view (by framework) and flat table view
- Search/filter across all entries
- Bulk delete selected entries
- Delete stale entries older than N days
- Stats: total entries, total size, framework count

### Diagnostics
- Automated health checks: XCFrameworks, slices, credentials, runner, toolchain, Package.swift
- Categorized results (Frameworks, Cache, Credentials, Toolchain)

### Settings
- Project path configuration (manual or auto-detect)
- GCS credential status and import
- Bucket configuration (name, endpoint, prefix, region)
- Build configuration info
- Config file location reference

## Project Structure

```
ScipioManager/
├── Package.swift
├── Sources/ScipioManager/
│   ├── ScipioManager.swift          # App entry point
│   ├── Models/
│   │   ├── AppConfig.swift          # Config file loading
│   │   ├── AppState.swift           # Observable app state
│   │   ├── BuildConfiguration.swift  # Build settings + BucketConfig
│   │   ├── CacheEntry.swift         # GCS bucket entry model
│   │   └── FrameworkInfo.swift      # XCFramework model
│   ├── Services/
│   │   ├── DiagnosticsService.swift # Health checks
│   │   ├── GCSBucketService.swift   # S3-compatible bucket API
│   │   ├── HMACKeyLoader.swift      # Credential loading
│   │   ├── LocalCacheService.swift  # Disk cache management
│   │   ├── PackageParser.swift      # Package.swift parsing
│   │   ├── ProcessRunner.swift      # Async process execution
│   │   ├── S3Signer.swift           # AWS SigV4 signing
│   │   └── ScipioService.swift      # Runner & sync operations
│   └── Views/
│       ├── DashboardView.swift
│       ├── FrameworksView.swift
│       ├── CacheView.swift
│       ├── BucketBrowserView.swift
│       ├── DiagnosticsView.swift
│       ├── SettingsView.swift
│       ├── SidebarView.swift
│       └── Components/
│           └── StatusBadge.swift     # Reusable UI components
├── Tests/ScipioManagerTests/
│   └── ... (22 test files, 232+ tests)
└── Resources/
    └── Info.plist
```

## Testing

```bash
# Run all unit tests
swift test

# Run with verbose output
swift test --verbose

# Run integration tests (requires real Scipio project)
SCIPIO_INTEGRATION_TEST_DIR=/path/to/your/Scipio swift test
```

The test suite includes 232+ tests covering:
- Configuration loading and serialization
- Package.swift parsing and modification
- Local cache discovery and cleanup
- S3 request signing
- GCS bucket service (mocked + live integration)
- Diagnostics engine
- Process runner
- Framework discovery

## Requirements

- macOS 15.0 (Sequoia) or later
- Swift 6.0+ toolchain
- A Scipio project setup (Build/Package.swift, Runner, etc.)
- GCS HMAC credentials for remote cache features

## License

MIT License. See [LICENSE](LICENSE) for details.

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Run the tests (`swift test`)
4. Commit your changes
5. Push to the branch
6. Open a Pull Request
