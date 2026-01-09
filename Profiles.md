# REA Profiles API

## Preamble

Decent espresso machines support loading dynamic profiles, with either pressure
or flow-based steps.
The first public specification of the JSON version of these profiles I know about,
has been defined by [Jeff Kletsky](https://pyde1.readthedocs.io/en/latest/profile_json.html)
\- it's actually a version 2.1 of the specification it seems.
REA supports loading these profiles to the espresso machine
either directly through the '/de1/profile'
endpoint or by updating the '/workflow' endpoint, which is more suited
for updating the entire system.

The REA Profile data object definition lives in
[lib/models/data/profile.dart](./lib/src/models/data/profile.dart).

## Requirements

As users begin to use REA, either in standalone or 'gateway'
mode, a need for managing the profiles arises naturally.
A central storage system is best suited for this type
of storage, since users might use REA in combination
with different clients. Ensuring a
consistent experience when browsing their profiles library
is crucial.

As one of the aforementioned users, I anticipate the
need for at least the following functionalities:

- list all available profiles
- add a new profile
- delete a profile
- update a profile
- import & export of the whole profile library for maintenance reasons
- a fast and efficient underlying storage system
- being able to track which profiles have evolved from previous
  profiles and which are completely new

### API and Storage

A collection of curated original and most popular public profiles
will be bundled with REA in the flutter `assets/defaultProfiles`
folder. On startup REA should check whether these profiles are
already present in the profile storage and if not, insert them

#### Storage data type model

To preserve portability an envelope around the original JSON
profile schema should be created. I like the name `ProfileRecord`.
The enveloping data object should be able to
contain additional meta data, for example the reference id
or `parentId`, which could be nullable,
to the original profile the current profile was derived from.

Since the users will be able to add and delete `ProfileRecord`s
at will, a system must be put in place to protect default profiles
from being deleted. Therefore a `visibility` field could be used
in order to both control as well as indicate what the current
state of the `ProfileRecord` is. E.g. default profiles can not
be deleted, only hidden, imported / created profiles can be deleted,
but perhaps it would be sensible to keep them hidden for a
configurable time period (e.g. 30 days), before actually deleting
them from the database.

#### Storage implementation

The storage system should be easily replaceable if needed,
therefore I think an abstraction tailored to our needs is
a good bet. We can then replace and use different storage
implementations as needed in the future.
For the initial concrete profile storage system implementation
either Hive or SQLite with JSON support could be used, some
additional thinking could be spent on this and then a choice made
based on the best suitability for our use-case.

#### API implementation

The api should be a REST CRUD API, with the addition of being
capable to either create a completely new `ProfileRecord` or linking an
update to an existing record via a `parentId` field. This will come in
handy in the future as well, when we will want to have
local change and evolution tracking.
Additionally, the API should know that the default profiles can
not be deleted and can only be hidden.

### Advanced topics (Future To-Dos)

As users continue to explore the possibilities and capabilities
of their espresso machines, so will their profiles change and evolve.
Eventually implementing a change tracking system will become
a real task. This is why a `ProfileRecord` data object is used instead
of `Profile` directly.
Using an enclosing data object gives us the required flexibility
to add our own metadata and maintain a sort of 'inheritance chain'
a user might wish to traverse and inspect how a certain profile has
evolved. It is also a real possibility that eventually the `ProfileRecord`
library will be synced with an actual Web API, allowing users to sign
in to multiple devices and share their library across all of them.

---

## Implementation

The Profiles API has been fully implemented following the requirements above. This section documents the architecture, usage, and available endpoints.

### Architecture

The implementation follows REA's standard layered architecture with clear separation of concerns:

```
┌─────────────────────────────────────┐
│      REST API (ProfileHandler)      │  ← 11 endpoints
├─────────────────────────────────────┤
│   Business Logic (ProfileController)│  ← Validation, versioning, defaults
├─────────────────────────────────────┤
│  Storage Interface                  │  ← Abstract interface
│  (ProfileStorageService)            │
├─────────────────────────────────────┤
│  Storage Implementation             │  ← Concrete Hive implementation
│  (HiveProfileStorageService)        │
└─────────────────────────────────────┘
```

#### Key Components

**ProfileRecord** (`lib/src/models/data/profile_record.dart`)
- Envelope around `Profile` with metadata
- Fields: `id`, `profile`, `parentId`, `visibility`, `isDefault`, `createdAt`, `updatedAt`, `metadata`
- Immutable with `copyWith` support
- Full JSON serialization

**Visibility Enum**
- `visible`: Normal state, shown in UI
- `hidden`: Hidden from UI but not deleted (used for default profiles)
- `deleted`: Soft delete state (user profiles only, can be purged)

**ProfileStorageService** (`lib/src/services/storage/profile_storage_service.dart`)
- Abstract interface defining all storage operations
- Allows swapping implementations (Hive, SQLite, etc.)
- Methods: `store`, `get`, `getAll`, `update`, `delete`, `getByParentId`, `storeAll`, `count`

**HiveProfileStorageService** (`lib/src/services/storage/hive_profile_storage.dart`)
- Concrete implementation using Hive NoSQL storage
- Box name: `'profiles'`
- Fast key-value operations with filtering support
- Batch operations for import/export

**ProfileController** (`lib/src/controllers/profile_controller.dart`)
- Business logic and validation layer
- Auto-loads default profiles from `assets/defaultProfiles/` on first startup
- Enforces default profile protection (cannot be deleted, only hidden)
- Validates parent profile existence before creating children
- Profile lineage tracking via `getLineage()`
- Import/export with detailed results (imported/skipped/failed counts)
- Exposes `profileCount` stream for UI updates

**ProfileHandler** (`lib/src/services/webserver/profile_handler.dart`)
- REST API endpoints with comprehensive error handling
- Request validation and proper HTTP status codes
- Logging for all operations

### Content-Based Hash IDs

REA uses **content-based hashing** for profile identification instead of random UUIDs or custom IDs. This provides:
- **Automatic deduplication**: Identical profiles have identical IDs across all installations
- **Cloud sync support**: Same profile content = same ID everywhere
- **Conflict-free merging**: No manual conflict resolution needed
- **Provable identity**: ID proves the profile content hasn't changed

#### Hash Types

Profiles use three SHA-256 hashes:

**1. Profile Hash (Primary ID)**
- Calculated from execution-relevant fields:
  - `beverage_type`, `steps`, `tank_temperature`, `target_weight`, `target_volume`, `target_volume_count_start`, `version`
- Format: `profile:<first_16_chars_of_hash>`
- Example: `profile:a3f2c8b4d1e6f9a2`
- Used as the profile record's unique ID

**2. Metadata Hash**
- Calculated from presentation fields:
  - `title`, `author`, `notes`
- Full 64-character SHA-256 hash
- Detects cosmetic changes (title translations, author attribution, etc.)

**3. Compound Hash**
- Hash of (profile_hash + metadata_hash)
- Detects ANY changes to the profile
- Useful for sync conflict detection

#### How It Works

```dart
// Two profiles with same execution but different metadata
Profile profile1 = Profile(
  title: "Espresso",
  author: "Alice",
  steps: [...],
  tankTemperature: 93.0,
  ...
);

Profile profile2 = Profile(
  title: "Espresso Classico",  // Different title
  author: "Bob",                // Different author
  steps: [...],                 // Same execution
  tankTemperature: 93.0,        // Same settings
  ...
);

// Both get the SAME profile hash (ID)
record1.id == record2.id  // true! 

// But different metadata hashes
record1.metadataHash != record2.metadataHash  // true

// And different compound hashes
record1.compoundHash != record2.compoundHash  // true
```

This enables REA to:
- Identify functionally identical profiles regardless of name/author
- Detect cosmetic changes without creating duplicate entries
- Merge profile libraries from multiple sources automatically

#### Default Profiles

Default profiles are bundled in `assets/defaultProfiles/`:
- `manifest.json`: Simple list of filenames
- Individual `.json` files for each profile
- Loaded automatically on first startup
- IDs calculated from content (same calculation everywhere)
- Marked with `isDefault: true`
- Cannot be permanently deleted (only hidden)
- Can be restored via `/api/v1/profiles/restore/{filename}` endpoint

Manifest structure:
```json
{
  "version": "1.0.0",
  "description": "Default espresso profiles bundled with REA Prime",
  "profiles": [
    "best_practice.json",
    "cremina.json",
    "manual_flow.json"
  ]
}
```

#### Migration from Old Installations

**Clean slate approach**: Existing installations with UUID-based profiles should either:
1. **Reinstall** - Fresh install with hash-based IDs
2. **Database reset** - Clear profiles (shot history preserved separately)

No automatic migration is provided since hash-based IDs fundamentally change the identity model.

### Profile Versioning

Profiles support version tracking through parent-child relationships:

```
Original Profile (id: A, parentId: null)
  ├── Modified v1 (id: B, parentId: A)
  └── Modified v2 (id: C, parentId: A)
        └── Modified v2.1 (id: D, parentId: C)
```

Use the `/api/v1/profiles/{id}/lineage` endpoint to retrieve the full version tree (all parents and children).

### API Endpoints

All endpoints return JSON and use appropriate HTTP status codes.

#### List Profiles
```http
GET /api/v1/profiles
```

Query parameters:
- `visibility`: Filter by visibility state (`visible`, `hidden`, `deleted`)
- `includeHidden`: Include hidden profiles (boolean)
- `parentId`: Filter by parent ID (for version tracking)

Response: Array of `ProfileRecord` objects

#### Get Single Profile
```http
GET /api/v1/profiles/{id}
```

Response: Single `ProfileRecord` object or 404 if not found

#### Create Profile
```http
POST /api/v1/profiles
Content-Type: application/json

{
  "profile": { /* Profile object */ },
  "parentId": "optional-parent-uuid",
  "metadata": { /* optional metadata */ }
}
```

Response: Created `ProfileRecord` (201) or validation error (400)

#### Update Profile
```http
PUT /api/v1/profiles/{id}
Content-Type: application/json

{
  "profile": { /* Updated Profile object */ },
  "metadata": { /* optional metadata */ }
}
```

Note: Cannot modify the `profile` field of default profiles (only metadata).

Response: Updated `ProfileRecord` (200) or error (400/404)

#### Delete Profile
```http
DELETE /api/v1/profiles/{id}
```

Behavior:
- Default profiles: Changes visibility to `hidden`
- User profiles: Changes visibility to `deleted` (soft delete)

Response: Success message with profile ID (200) or error (404)

#### Change Visibility
```http
PUT /api/v1/profiles/{id}/visibility
Content-Type: application/json

{
  "visibility": "visible" | "hidden" | "deleted"
}
```

Note: Cannot set default profiles to `deleted` state.

Response: Updated `ProfileRecord` (200) or error (400/404)

#### Get Profile Lineage
```http
GET /api/v1/profiles/{id}/lineage
```

Returns the full version history/tree (all parents and children).

Response: Array of `ProfileRecord` objects in lineage order

#### Permanently Delete Profile
```http
DELETE /api/v1/profiles/{id}/purge
```

**Warning**: Permanently removes profile from storage. Cannot purge default profiles.

Response: Success message (200) or error (400/404)

#### Import Profiles
```http
POST /api/v1/profiles/import
Content-Type: application/json

[
  { /* ProfileRecord */ },
  { /* ProfileRecord */ },
  ...
]
```

Batch import from backup. Skips profiles that already exist.

Response:
```json
{
  "imported": 10,
  "skipped": 2,
  "failed": 0,
  "errors": []
}
```

#### Export Profiles
```http
GET /api/v1/profiles/export?includeHidden=false&includeDeleted=false
```

Query parameters:
- `includeHidden`: Include hidden profiles (boolean, default: false)
- `includeDeleted`: Include deleted profiles (boolean, default: false)

Response: JSON array of all `ProfileRecord` objects

#### Restore Default Profile
```http
POST /api/v1/profiles/restore/{filename}
```

Restores a bundled default profile from assets by filename (e.g., `best_practice.json`).

Response: Restored `ProfileRecord` (200) or error (404)

### Usage Examples

**Create a new profile:**
```bash
curl -X POST http://localhost:8080/api/v1/profiles \
  -H "Content-Type: application/json" \
  -d '{
    "profile": {
      "version": "2",
      "title": "My Custom Profile",
      "author": "Jane Doe",
      "beverage_type": "espresso",
      "steps": [...],
      "tank_temperature": 93
    }
  }'
```

**Create a modified version (child profile):**
```bash
curl -X POST http://localhost:8080/api/v1/profiles \
  -H "Content-Type: application/json" \
  -d '{
    "profile": {...},
    "parentId": "parent-profile-uuid"
  }'
```

**Hide a default profile:**
```bash
curl -X DELETE http://localhost:8080/api/v1/profiles/{id}
```

**Restore a hidden default profile:**
```bash
curl -X PUT http://localhost:8080/api/v1/profiles/{id}/visibility \
  -H "Content-Type: application/json" \
  -d '{"visibility": "visible"}'
```

**Export all profiles for backup:**
```bash
curl http://localhost:8080/api/v1/profiles/export > profiles_backup.json
```

**Import profiles from backup:**
```bash
curl -X POST http://localhost:8080/api/v1/profiles/import \
  -H "Content-Type: application/json" \
  -d @profiles_backup.json
```

### Testing

Unit tests are located in `test/profile_test.dart` and cover:
- ProfileRecord serialization/deserialization
- Storage CRUD operations
- Default profile protection
- Profile versioning and lineage tracking
- Import/export functionality
- Visibility state management

Run tests with:
```bash
flutter test test/profile_test.dart
```

### Storage Details

**Why Hive?**
- Already integrated in REA
- Native Dart/Flutter support
- Excellent for document-oriented JSON storage
- Fast key-value operations
- No SQL migration complexity
- Cross-platform support (all required platforms except web)

**Performance Characteristics:**
- Hive is fast for < 10,000 records
- Profile libraries unlikely to exceed 1,000 profiles
- No in-memory caching needed initially
- Filtering by visibility is efficient enough
- Batch operations optimize import/export

**Future Considerations:**
If storage needs change (e.g., complex queries, relationships), the abstract `ProfileStorageService` interface allows easy migration to SQLite or other systems without changing controller or API code.

### Integration with Workflow API

To use a profile with the DE1 machine, either:

1. **Direct upload to machine:**
```bash
curl -X POST http://localhost:8080/api/v1/de1/profile \
  -H "Content-Type: application/json" \
  -d '{...profile...}'
```

2. **Via Workflow API (recommended):**
```bash
# Get the profile
PROFILE=$(curl http://localhost:8080/api/v1/profiles/{id})

# Update workflow with the profile
curl -X PUT http://localhost:8080/api/v1/workflow \
  -H "Content-Type: application/json" \
  -d "{\"profile\": $(echo $PROFILE | jq '.profile')}"
```

The Workflow API approach updates the entire workflow context (profile + dose + grinder + coffee data).

### Error Handling

All endpoints follow consistent error handling:

**400 Bad Request:**
- Invalid visibility value
- Missing required fields
- Invalid parent ID
- Attempting to delete/modify default profile incorrectly

**404 Not Found:**
- Profile ID doesn't exist
- Default profile filename not found

**500 Internal Server Error:**
- Storage failures
- Unexpected exceptions
- Includes error message and stack trace in logs

Example error response:
```json
{
  "error": "Profile not found",
  "id": "profile-uuid"
}
```

### Future Enhancements

- **Cloud Sync**: Sync profiles across devices via cloud API
- **Change Tracking**: Detailed diff between profile versions
- **Tags/Categories**: Organize profiles by category, beverage type, etc.
- **Search**: Full-text search in profile metadata and content
- **Sharing**: Share profiles with other users (export as shareable link)
- **Auto-cleanup**: Configurable purge of old deleted profiles (e.g., 30 days)
- **Conflict Resolution**: Handle sync conflicts when using multiple devices
- **Profile Templates**: Pre-configured templates for common brewing styles

