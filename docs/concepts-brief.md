# DigUp Atlas: concepts brief

* **Author:** Sebastianhayashi
* **Date:** 2026-10-28
* **Status:** product-direction brief, concurrent with D0-D4 execution.
  D0 is committed and pushed (PR #1 open, not merged). D1-D4 are planned in
  `docs/digup-atlas-plan.md`. No throughput, quality, or preview-coverage
  measurement has been run. This document argues about *what to build and what
  to stop claiming*; it is not a spec, and it does not override the plan's
  acceptance items.

## Overview

DigUp Atlas is a read-only macOS digital asset map for local folders and
removable disks. After a volume has been cataloged once, a user who does not
remember a filename or a location can still find an asset by content, recognize
it from a stored preview, and reopen the original once the volume is
reconnected.

The project started from a different question: why do people want to clean up a
Mac? Research on 2024-2026 Mac discussions put storage emergencies and fear of
deleting the wrong thing well ahead of any wish for order, and cleanup itself
is served by many existing tools. One sliver looked under-served: judging
whether a file is worth keeping. Several rounds of narrowing turned that into a
smaller, checkable question — can a person find a specific forgotten file by
describing its content? The atlas is the product that question produced.

Two findings from review shape everything below.

**One: this is not an empty space.** Offline catalogs with previews have
existed commercially on macOS for about twenty years, and several products
released or updated during 2025-2026 already cover the narrow combination this
project was built around.

| Product | What it already does | Evidence |
| --- | --- | --- |
| NeoFinder | Offline catalog of unmounted drives; thumbnails for photos, RAW, PDF, PSD, video and audio; searchable while the drive is away | Vendor site and a 2026 review. The review describes catalog-based search, not full-text inside files. |
| ArchiveMind | Catalogs a drive, then searches unplugged drives by name, words inside documents, photo content and faces, with thumbnails; read-only; explicit "a catalog is not a backup" | Vendor help pages |
| Disc Content AI (Ulti.Media) | On-device AI index of transcripts, on-screen text, genres, locations; browses unplugged drives | Product page, from search results; not fetched |
| DriveVault | Scans a drive once, then searches and browses while unplugged; EXIF search, offline image previews | Product Hunt listing; not fetched |
| Synology Deep Search | Local AI search over documents and photos, including directly connected external drives; about $49.99; sold on the Mac App Store | Vendor announcement and search results; announcement page not fetched |
| Omni | Native macOS semantic search across text, code, PDFs, images, audio, video, on-device; Apache-2.0 app, CC-BY-NC-4.0 weights; 1.8 GB model plus optional 4.2 GB OCR | Repository page, read in full |
| DigUp | Local multimodal semantic indexing; MIT; the upstream of this fork | Repository and issues |
| bHive, Bina, ProFind | Local content search; some track disconnected drives or cache disk indexes | Search results; not verified individually |

Two are free and open source (Omni, DigUp). One is commercial, one-time-priced,
and on the App Store. One has twenty years of incumbency. "Offline catalog plus
compressed previews plus content search" is a crowded intersection, not a gap.
This does not by itself cancel the project, but it removes novelty as a reason
to build it, and it means every claim in this document has to be a claim about
execution or about this specific program, never about the idea being new.

**Two: the permission premise this project ran on was wrong.** Earlier rounds
asserted that the app needs Full Disk Access and therefore must ship outside
the App Store. The fork's own code contradicts that.
`Resources/DigUp.entitlements` contains exactly one key,
`com.apple.security.automation.apple-events`, and no
`com.apple.security.app-sandbox`. The app relies on
`NSRemovableVolumesUsageDescription` and the Desktop/Documents/Downloads usage
strings in `Resources/Info.plist`. On macOS, external and removable volumes are
governed by the Files and Folders category, specifically Removable Volumes,
which a user grants once for all removable drives; Full Disk Access is a
different and broader grant. Apple's 2 October 2026 announcement of tighter
Full Disk Access controls concerns that broad grant and does not foreclose this
design. Synology Deep Search selling an equivalent capability on the Mac App
Store is an existence proof of the per-volume-consent path.

Two boundaries remain and should not be over-read: a usage-description string
is not a pass to every protected location, and Mac App Store distribution would
require enabling App Sandbox, which the current build does not.

## State of the fork, verified from source

The fork is `github.com:Sebastianhayashi/new-digup`, based on upstream
`dc2651ad8299160bbe91e972f857e1a1599a8419`. D0 (`d0-fork-baseline`: independent
app identity, isolated data directories, Sparkle removed, UI driver added) is
committed and pushed. `build.noindex/DigUpAtlas.app` builds. PR #1 is open and
mergeable; its UI verification has not yet produced `DRIVE PASS`, so D0 is
submitted, not delivered. D1 is not started. Local `main` equals `origin/main`
at the upstream commit.

Reading the source corrected seven claims that earlier rounds had taken on
trust. Items 4 and 7 are blocking for D1; the rest are corrections of record.

1. **The preview cache does not exist upstream.**
   `Sources/DigUpApp/Thumbnails.swift` is an in-memory `NSCache` documented as
   "dropped when the panel closes"; the `Previews` cache is the same. There is
   no disk cache, no byte budget, no eviction. D4 is therefore not an extension
   of an existing cache but the largest new subsystem in the program, and it is
   the one the program calls its differentiator. `QLThumbnailGenerator` needs a
   readable source URL, so previews must be produced while the volume is still
   attached; a system-cache hit later cannot be relied on.

2. **`(device, inode)` is not a volume identity.** `IndexStore` indexes
   `files(device, inode)` and `Indexer.sync` matches moved files with
   `"\(file.device):\(file.inode)"`. `st_dev` is a per-boot mount number, and
   exFAT synthesizes file identifiers that can change across remounts; an
   independent report (rawmakase#573) documents exactly that on macOS FAT/exFAT
   disk images. On APFS this works, and on the cross-platform external drives
   this product targets it degrades toward delete-and-reinsert, which re-embeds.
   D1's `asset_uuid` is required work, not a refinement. It is not sufficient
   by itself: a filesystem-aware rematch strategy is also needed, and identity
   evidence has to be retained from first sight, because by the time a collision
   is detected the old content may no longer be readable.

3. **Reconciliation is destructive, and the guard is too narrow.**
   `Indexer.sync` deletes rows it did not see. Its only protection is a
   `fileExists` check on each granted root, so a root that vanished mid-crawl
   keeps its rows; nothing below that level is protected. `Crawler` enumerates
   with `errorHandler: { _, _ in true }` (Crawler.swift:86), which swallows a
   directory-level read failure and continues, so the failed subtree's files
   never appear in the crawl result and are then deleted as absent. A root that
   is present but has one unreadable subdirectory can lose that subdirectory's
   records. This is the most dangerous defect found in this review.

4. **Event resume is absent, but startup compensation exists.** `FolderWatcher`
   starts at `kFSEventStreamEventIdSinceNow` and discards event IDs and flags,
   so there is no cross-process replay. But `IndexService` initialises
   `syncRequested = true` ("the first thing it does", IndexService.swift:56),
   so the helper runs a full `Indexer.sync` on every start, and changes made
   while the app was closed are found by re-crawling rather than lost. What is
   missing is efficient, resumable incremental sync, not correctness at
   startup. D1 Lane 7 already tests the closed-app case; it needs sharpening,
   not replacement.

5. **The promised inventory does not exist yet.** `Crawler` records unsupported
   file types only as an aggregate skip count (`leftOut("other type")`), with no
   per-file record. D1's promise that every file in an authorized scope enters
   the asset inventory cannot be met by wrapping the existing
   `IndexStore.files`; it needs a discovery path separate from semantic-index
   eligibility.

6. **Identity cannot live inside the index rows it is meant to outlive.**
   `IndexStore` declares `path TEXT NOT NULL UNIQUE` on `files`, so identity is
   currently defined by path. `segments` references `files(id) ON DELETE
   CASCADE`, and `delete(_:)` issues `DELETE FROM files WHERE id = ?`. If D1
   adds `asset_uuid` as a column on `files` and D2 hangs user tags off it, then
   any delete of a file row — a genuine deletion, an unreadable subtree from
   item 3, or a path-UNIQUE collision — destroys the stable identity and orphans
   every tag bound to it. Asset identity belongs in its own persistent table,
   with a tombstone for assets that are gone, so derived index rows can be
   deleted without taking user work with them. This is a hard D1-to-D2
   dependency and cannot be left to D2.

7. **One earlier claim was wrong in mechanism, and is closed.**
   "DigUp misclassified a personal photo library as a dataset" was a real
   upstream issue (`ARahim3/DigUp#141`: a `Phone/Camera` subfolder of
   `~/Pictures` holding 756 phone photos was treated as a dataset), but the
   cause was a `looksMachineNamed` heuristic that did not recognise date-named
   camera files, not the granted-root exclusion. It was fixed upstream on
   2026-10-22 in commit `0bb6487` ("Treat date-named photos as camera
   photos"), which adds `startsWithDate` and camera-prefix checks; that commit
   is an ancestor of the fork's branch. The rule still has a live surface:
   `datasetFolders` excludes only folders that are themselves granted roots, so
   a subfolder with 300+ same-kind machine-named files is still skipped. Every
   such skip must appear in the coverage report with its reason. Separately,
   `.photoslibrary` is skipped earlier at the package stage and reported as
   "Photos library"; on an external drive whose main content is a Photos
   library, that is a scope limit the coverage report must state plainly rather
   than file under "bundle".

The D0 review of record is `.audit/D0-review-findings.md`, covering the shared
data-directory collision, stale update references, and UI-driver weaknesses.

## Analysis

Merged from six independent reviews and from external verification. Ordered by
how much each would change the project.

### 1. Two products are still being described at once

The project describes semantic search as its reason to exist, describes the
semantic layer as potentially optional, and describes a fallback product that
works without it. A reader cannot state in one sentence what the app is, and
the success criterion, the architecture, and the test design point at
different products.

The practical consequence: **if the catalog and the semantic layer ship in the
same build, no user test can attribute success to either one.** An experiment
designed to justify the architecture is confounded by it.

This does not require breaking up the program. D1 and D4 stand on their own as
a catalog-plus-preview product, and D2 and D3 add asset-map capability on top.
What it does require is that statements about which part is *doing the work*
stay separate from statements about what the program builds.

### 2. The fallback product may not exist either

"Catalog plus thumbnails is enough" was the fallback. The arithmetic is not
supportive.

- A 2 GiB preview budget at roughly 40-60 KB per preview holds 35,000 to 50,000
  previews. At 256 KB (1024 px) it holds about 8,000.
- A four-drive photo archive is plausibly 800,000 files, so preview coverage
  would be 1% to 6%.
- The 2 GiB counts only previews. Adding SQLite rows, a full-text index over
  names and paths, vectors, and the model puts total footprint around 4-6 GB
  per million assets. The program's origin story is a full disk.
- "Shared 2 GiB across all sources" and "no silent cross-drive eviction" are
  mutually unsatisfiable past one drive: the first consumes the budget and
  later drives get nothing, permanently.

Nobody has shown that a size-capped preview of a 40-page PDF, or of a folder of
similarly named photos, is enough for a person to confirm identity. That
assumption is the whole fallback product, and testing it costs hours.

The plan's current split is workable and should be kept: 2 GiB as a default
budget shared across sources, 500 MB as the performance ceiling for the
specified test fixture.

### 3. The differentiator's measurement design cannot produce a decision

Three reviewers converged on the same gap from different directions.

- The A/B/C outcomes had no mapping from measurements to outcomes. Deciding
  that mapping after seeing results is the self-serving failure this project
  warned itself against.
- Six to eight participants is a usability sample. It cannot establish a
  success-rate or time difference between two search conditions.
- The natural in-app baseline is a strawman. The real incumbent is Finder plus
  Spotlight; beating a weak in-app baseline while losing to the OS search the
  user already has makes the differentiator false.
- The stated success criterion is a walkthrough. A user who finds a file via
  thumbnails and one who finds it by description look identical inside it.

### 4. The engineering order is inverted

Recruitment, not code, is the likely bottleneck, and the falsification
experiment is sequenced after the architecture. Three reviewers proposed the
same cheaper ordering: a fixed corpus from one real library, a fixed task list,
and a comparison of filename/path browsing against content search, run as a
throwaway script or paper prototype before any Swift. If six to eight users
cannot be recruited for that, the app would not have users either.

This is a caution, not a stop order: D1's inventory work is required regardless
of how the semantic question resolves, and D4's preview store is required for
any offline product.

### 5. Search, which is D3, costs more than the plan measures

The plan's performance rule for suggestions bounds latency and helper memory.
It does not bound index size, model load cost, or the memory a resident
embedding runtime occupies on a low-RAM Mac. Brute-force search over a large
vector table is a streaming read on every query, and the model is not
lazily loadable per query. These belong in the same envelope as the rest.

### 6. The read-only claim needs precision

The app does not copy originals. It does store thumbnails of every photo and
extract text from documents: a durable, plaintext, reduced copy of the volume
inside the user's home directory, and part of Time Machine backups unless
excluded. For a tool that catalogs other people's disks, that derived store is
the more sensitive artifact. Say so in public copy, exclude the cache from
backups by default, and keep absolute paths out of diagnostics.

### 7. Prior-art work narrowed itself once

The first competitor table listed only open-source projects and omitted
commercial Mac catalogers, including one already named in this project's
earlier research. The same mistake was then made one layer up. Any future
competitor review must include commercial products and App Store listings, not
only GitHub.

## Goals vs. Non-Goals

**Product goal.** A read-only macOS digital asset map across local folders and
removable disks, so that a user who does not remember a filename or a location
can still discover an asset, recognise it, and reopen the original.

**What D0-D4 build, and how each is judged.** Asset inventory (D1), stable user
topics (D2), reviewable semantic suggestions (D3), disconnected-volume catalog
with a capped compressed preview store (D4). Acceptance is per the plan's own
boxes — unit, live, and perf evidence for each PR — not per this brief.

**Explicitly excluded this round.** Mac space cleanup, system junk removal,
deleting or moving originals, batch copy back to the Mac, backup and restore.
These are excluded by product choice, not postponed to a later phase. Revisiting
cleanup would need file-operation, safe-recovery, and space-analysis design the
program does not contain; that is real rework cost, not a measured multiple.

**Invariants that hold across the whole program.**

- Read-only with respect to user files. No copy back, move, delete, or
  duplicate removal. The terminal action is "locate and open the original."
- Scan trust follows completeness, not success. A scan is trusted only for
  subtrees it proved it enumerated completely; an unreadable, interrupted, or
  disconnected scope is unverified and is never a confirmed deletion. In
  practice this outranks every other invariant, because violating it destroys
  user records.
- Asset identity is independent of derived index rows, and survives their
  deletion.
- Coverage is visible: what is searchable, what awaits analysis, what was
  excluded and why, what was unreadable. Contents of a skipped directory are
  never reported as scanned.
- No automatic content-based skip without a visible reason.
- Scope is user-granted folders plus attached removable volumes. No NAS, no
  network volumes, no cloud-only files, no claim to cover the whole machine.
- The catalog reflects the last confirmed state, not live truth; it shows the
  last successful scan time and re-verifies on open.
- Inventory is not restricted to semantically indexable files. Every ordinary
  file in an authorized scope gets an asset record; only some get content
  analysis.

**What can be claimed today, before D4 exists.** Assets in an already-built
catalog remain findable after their volume is disconnected; previews already
generated remain viewable; after the volume is reconnected and its identity
confirmed, the original can be opened. It is not accurate to say offline
discovery is solved: D4 is unimplemented, the preview store is byte-capped, and
many file types are inventory-only.

## Key Decisions & Staging for Next Steps

The two blocking items come first. Both are D1 work and both gate D2 and D4.

**Blocking, in D1.**

1. **Scan completeness.** Track reconciliation per subtree. Unreadable,
   interrupted, or disconnected scopes are unverified and never confirm
   deletion. Lane 9 currently tests "a directory is unreadable"; it must become
   "the root is readable but a subdirectory inside it fails", asserting that
   existing asset records survive.
2. **Identity independent of index rows.** Asset identity in its own table with
   tombstones, so deleting derived rows cannot orphan user decisions. Retain
   identity evidence from first sight rather than computing it only on
   collision.

**In D1, alongside the above.**

3. Remount tests over a real exFAT image, including rename, not DMG or APFS
   alone; assert a stable `asset_uuid` and zero re-embedding of unchanged
   content.
4. Lane 7 sharpened in place: quit the app, then add, modify, rename, and
   delete while it is stopped; on relaunch assert the changes reconciled,
   unchanged assets kept their IDs, unchanged content was not re-embedded, and
   the metadata re-scan fallback still works when event history is unavailable.
5. A discovery path for inventory that does not require semantic eligibility.

**In D4.**

6. Generate and persist previews while the source is readable, during the
   initial scan or a connected-volume background pass. Never enqueue preview
   generation for an index-only volume. Show incomplete preview coverage before
   a volume is disconnected. Do not trigger downloads of cloud placeholders.
7. Keep the budget split: a 2 GiB default shared across sources, 500 MB as the
   fixture-specific performance ceiling. Final numbers still need measurement.

**Before claiming the differentiator works (D3).**

8. Pre-register the measurement: task set with ground truth, counterbalanced
   order, numeric thresholds, and the mapping from results to each outcome.
   Include Finder plus Spotlight as a third arm.
9. Run the falsification test outside the app, on one real library.
10. Run the recognizability check: twenty real files, previews at the intended
    cap, can a person confirm identity from the preview alone.

**Program-level, not yet scheduled.**

11. Competitor reality check against the commercial field, run for real rather
    than from search summaries.
12. Storage envelope with numbers for the whole derived store, not just
    previews.
13. Whether Mac App Store distribution is wanted; it requires enabling App
    Sandbox, which the current build does not.

**What would make this stop, stated before measuring:** the intersection is
already served at a comparable price by a product that needs no explanation to
install; or content search does not beat Finder plus Spotlight on real
retrieval tasks; or previews at an affordable budget do not let people confirm
identity. Any one removes the reason to build.

## Known Risks

- The intersection may be entirely occupied; novelty is not available as a
  reason to build, only execution.
- Preview coverage at an affordable budget may be single-digit percent, which
  would remove the fallback product.
- Six to eight participants cannot decide a comparison, and recruiting
  multi-drive owners may cost more than the build.
- exFAT may make asset identity permanently weaker than the design wants.
- A tool that catalogs other people's disks carries a trust problem no feature
  list addresses, and its preview cache is a durable reduced copy of their
  content.
- DigUp's throughput, memory, and classification quality remain unmeasured by
  this team.
- D0 is not yet delivered: PR #1 is open, `DRIVE PASS` is outstanding, and the
  live and perf evidence the plan requires is incomplete.

## Sources

- NeoFinder: https://www.cdfinder.de/index.html and a 2026 review,
  https://amerpie.lol/2026/03/04/neofinder-the-mac-app-that.html
- ArchiveMind: https://help.archivemind.app/guides/catalogue-an-external-drive/
- Omni: https://github.com/hanxiao/omni-macos
- Disc Content AI: https://ulti.media/disc-content-ai/
- Synology Deep Search: https://www.synology.com/en-sg/company/news/article/synologydeepsearch
- Apple Full Disk Access changes, 2 October 2026:
  https://techcrunch.com/2026/10/02/apple-says-its-tightening-macos-full-disk-access-controls-due-to-new-risks-from-ai-agents/
- Removable Volumes consent category:
  https://eclecticlight.co/2025/02/24/gaining-access-to-privacy-protected-folders/
- DigUp upstream: https://github.com/ARahim3/DigUp
- Upstream dataset fix: commit `0bb6487`, issue `ARahim3/DigUp#141`
- exFAT remount observation: `pch/rawmakase#573`
