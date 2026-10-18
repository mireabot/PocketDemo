# PocketDemo

PocketDemo is an offline-first iOS app for browsing and editing recordings stored on a server. Each recording has a title, a summary and a transcript. The repo also contains the server, a small Bun and SQLite backend that two simulators can share.

The app works without a connection. Edits are saved on the device first and sent when the network comes back. When two devices change the same recording, the app shows both versions and lets you choose.

## What you can do with a recording

- Browse the list, newest first. The app loads 30 recordings at a time and fetches the next 30 as you scroll.
- Open a recording to read its summary and transcript. The app downloads a transcript the first time you open it and keeps it for offline reading.
- Edit the title and summary, online or offline. A card shows "Waiting to sync" until the server accepts the change.
- Delete a recording from the detail screen or from the list's context menu.
- Pull to refresh to see changes made on another device.
- Turn on the airplane switch in the toolbar to take one simulator offline without touching the other.

## How conflicts are resolved

Every recording has a version number that grows with each write, and the server records which device last changed each field. An edit carries the version it started from. The server rejects a field only when both are true: another device changed it after that version, and the server's value differs from the requested one.

- Edits to different fields both apply. Two devices that type the same value get no conflict. A device's own earlier edits never conflict with its later ones.
- When a field conflicts, the server returns `409` with the current recording. If the server value still matches what the field was before your edit, the app retries on the new version. Otherwise the recording moves to "Needs attention", where the detail screen shows the original, your version and the other device's version. You keep yours, keep theirs or write a merged value. Editing and deleting that recording stay disabled until you choose.
- Deleting a recording that another device changed also returns `409`. The app shows the newer copy and asks whether to keep it or delete it anyway.
- If another device deleted the recording, the server returns `410`. The app removes it and shows a notice that your unsynced changes were discarded. There is no undelete.

Each edit carries an idempotency key. If the server applies an edit but the response never arrives, the app sends the same key again and the server returns the saved result instead of applying the edit twice.

## Run it

You need Bun, Xcode 26 and an iOS 26 simulator.

```bash
make backend   # starts the server on http://127.0.0.1:8787 with 100 sample recordings
make project   # generates the Xcode project
```

Open the project in Xcode and run the app on two simulators, for example iPhone 17 Pro and iPhone Air. Both talk to the same server. If you ran an earlier build, delete the app from each simulator first, because the local database schema has changed.

## Usage

With the backend running, open a recording, tap Edit, then tap Save. Save is a menu with four modes, so each network failure from the brief can be reproduced on one simulator without touching the other:

- **Save.** A normal write.
- **Save on a slow network.** The server answers like an overloaded link: the first byte comes after 0.4 to 1.2 s, then the reply trickles in over a few seconds. Turn on the airplane switch during the wait to cut a request in progress.
- **Save, server applies it, reply lost.** The server saves the edit and cuts the connection 1 s later. The app keeps the edit as "Waiting to sync" and resends it on the next refresh, and the server answers with its saved reply instead of applying the edit twice.
- **Save, request never reaches the server.** The request fails before it leaves the device. The edit waits locally until the next refresh, and a conflict shows up then if another device changed the same field in the meantime.

The airplane switch in the list's toolbar takes one simulator offline. Pull to refresh, the airplane switch and returning to the app all send waiting edits. For faults on every request from one device, see the fault endpoints in [backend/README.md](backend/README.md).

## Documentation

| Document | What it covers |
| --- | --- |
| [backend/DESIGN.md](backend/DESIGN.md) | The sync design end to end: API, cursors, paging, the edit queue, conflicts, transcript cache, server resets |
| [backend/README.md](backend/README.md) | Endpoints, fault controls and how to run the server tests |
| [ios-architecture-review.md](ios-architecture-review.md) | App architecture: packages, the sync supervisor, the local database and the view models |
| [Layers/Foundation/PocketUI/DESIGN.md](Layers/Foundation/PocketUI/DESIGN.md) | Shared UI components and styling |
| [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) | What is simplified or left for later |
| [designs_not_taken.md](designs_not_taken.md) | Approaches considered and dropped, with the reason for each |
