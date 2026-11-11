# Mistake Log

A minimal, local-first error log for capturing and revisiting schoolwork mistakes.
Entries are stored on the device with Hive; photos are stored with their entry.
No account or backend is used.

## Phase A

Phase A includes adding an entry with an optional photo, class and written
description; a reverse-chronological log with class and tag filters and text
search. Marking a mistake reviewed hides it from the main log for seven days;
reviewed entries are available through a Reviewed filter beside the class
filters on the main log and automatically return as unreviewed when due. Due
reviews are refreshed at app startup, when the app resumes, and while it
remains open. Mistakes can be permanently deleted with confirmation. The
interface adapts to narrow screens.

iOS and Android home-screen widgets are available in small, medium, and large
sizes. They show one unreviewed mistake each day, cycling through a shuffled
order without repeating until all current unreviewed mistakes have appeared.
All widget sizes share the same daily selection. iOS widget installation
requires the `group.com.example.mistakeLogApp` App Group to be enabled for both
the app and widget extension in the Apple Developer account.

Classes can be added, renamed, and removed from the class manager. Removing a
class moves its mistakes to Unassigned. Mistakes can be edited and assigned
custom or suggested tags, which are also searchable and filterable. Class
lists, tags, descriptions, review dates, and photos are stored locally.
Previously reviewed entries without a review date start their seven-day
interval on the first app launch with this scheduling behavior.

AI diagnosis, spaced-repetition scheduling, statistics, and data
export/import are not part of this phase yet.

## Run

Install Flutter, then run:

```sh
flutter pub get
flutter run -d chrome
```

Run the local-storage test with:

```sh
flutter test
```

Native builds:

```sh
flutter build ios --no-codesign
flutter build apk --debug
flutter build macos --debug
```
