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
