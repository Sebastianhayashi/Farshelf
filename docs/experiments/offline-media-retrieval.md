# Offline media retrieval pilot: experiment design

* **Author:** Sebastianhayashi
* **Date:** 2026-10-28
* **Status:** experiment design. Not an approved engineering plan. Does not
  change `docs/digup-atlas-plan.md` or any milestone in it.

## What this document decides, and what it does not

It defines one pilot, the gates that decide whether the pilot passed, and what
happens if it fails. It does not authorise D2 (manual topics) or D3 (semantic
suggestions); both stay suspended until this pilot's value gate is met. It does
not modify D0-D4. The plan stays in place for tracking.

The pilot exists to answer one question before the program spends more: can a
person who does not remember a filename or a location find a specific photo or
video on a disconnected drive, using a catalog and a stored preview, faster or
more reliably than they can today?

## Scope of the pilot

| Dimension | In the pilot |
| --- | --- |
| Sources | One local folder, one external drive, or several external drives, all through the same catalog |
| Media in target tasks | Photos and videos |
| Retrieval | Filename, path, type, date, source, media attributes. No mandatory model download |
| Preview | Photos: persistent thumbnails. Videos: a representative frame or a small contact sheet, chosen by this experiment rather than assumed |
| Disconnected state | Catalog records and already-generated previews remain visible; the original requires reconnection |
| Terminal action | Verify the correct source, then open the original. No copy, move, or delete |

Explicitly outside the pilot: manual topics, semantic topic suggestions, PDF
page previews, batch operations, cleanup, copying files to the Mac, NAS or
network volumes, cloud-only placeholders.

A local folder that never disconnects is supported by the same catalog, but the
pilot does not claim it is more useful than Finder for that case. Technical
support is not evidence of value.

## The pilot is a falsification instrument, not a preview of the product

The pilot should be the cheapest thing that can disprove the premise. Three
rules follow.

1. The user-facing artifact is a throwaway HTML prototype, not a built app.
2. Video contact sheets for the prototype are made by hand for roughly a dozen
   clips. No extraction pipeline is built for the experiment.
3. Technical correctness is tested separately, on synthetic media, with no
   human participants.

If the pilot is expanded to "look like the product," it stops being able to
disprove anything cheaply.

## Gate A+C: one user study, two comparisons

Recognisability and value are measured in the same session with the same
materials. Splitting them across weeks lets the stimuli and the participants'
memory decay, and the earlier plan's serial ordering cost more than it bought.

Two comparisons, kept separate because they answer different questions.

| Question | Comparator | What a result may conclude |
| --- | --- | --- |
| Is this loop better than what the user does today? | The user's own method: memory, Finder or Spotlight while connected, reattaching drives one at a time | Whether a real problem is solved |
| Is a new product needed? | The same task and material in an existing catalog tool (Katalog or NeoFinder, whichever the participant can run during the session) | Whether there is a perceptible advantage over tools that already exist |

The first is need validity. The second is competitive difference. Finder being
helpless while a drive is unplugged does not establish the second.

**Stimulus.** Anonymous real material only. Photos at the intended preview
size, roughly 256 px, to test whether identity can be confirmed at that size.
Videos as hand-built contact sheets at three frame counts (1, 3, 5) with and
without timecode, so the frame-count decision comes from data.

**Task cells.** Four cells: single-source photos, multi-source photos,
single-source videos, multi-source videos.

**Sample-size honesty.** Six to eight participants cannot populate four cells
with any statistical power. This study detects gross design failure, not effect
size. It is not permitted to report a rate difference between conditions as if
it were established. What it can do:

- Observe every participant attempting every cell, within-subject,
  counterbalanced for order and using matched but non-identical stimuli to
  limit learning effects.
- Record where a participant fails outright, misunderstands "not cached" or
  "disconnected," or chooses the wrong file with confidence.

If four cells prove too many for the recruited group, drop cells rather than
thinning them. Two well-covered cells beat four underpowered ones.

**Separate the costs.** First-scan preparation time and preview generation time
are recorded and reported next to retrieval time. They are part of the product
assessment, not an implementation detail to be excluded so the retrieval number
looks better.

## Gate C failure conditions, registered before the session

These are directional conditions for a small sample. They are written down
before any participant is recruited, because deciding them afterwards is
self-serving.

The pilot fails Gate C if any of the following holds:

1. Any participant cannot find an item that exists in a cataloged source
   within a generous time limit, on a task where the item's preview was
   generated.
2. Median time to find does not improve on the participant's own current
   method, across the cells that were run.
3. Participants routinely misread the disconnected or not-cached state as "the
   file is gone," after the interface says otherwise.
4. Any participant, given a description of the file they half-remember, picks a
   wrong file and is confident about it. Wrong-but-confident is worse than
   slow, because it means the preview cannot be trusted to disambiguate.
5. The existing catalog tool completes the same task comparably well and is
   already installed or freely available. This fails the competitive
   difference question even if need validity holds.

Passing requires the opposite of all five. Partial passes are recorded as
partial; they do not silently become "close enough."

## Gate B: technical correctness, no participants

Synthetic media and real file systems. Every item below is a pass/fail
blocking condition, not a nicety.

- **Identity across remounts.** Real exFAT image, plus APFS. Index, eject,
  remount at a different path, rename files between mounts. Assets keep their
  identity; no unchanged content is re-embedded.
- **Subdirectory read failure.** The root stays readable, one subdirectory
  inside it fails to enumerate. No asset under it is deleted, and the failure
  is visible in coverage reporting.
- **Whole-source disappearance.** Eject mid-scan and eject between scans. The
  previous trusted snapshot survives. A zero-result scan never confirms
  deletion.
- **Same content, different assets.** Two byte-identical files in different
  locations. They do not merge into one asset. Previews key on asset identity
  and content version, never on path alone and never on content hash alone.
- **Preview durability.** Previews generated while the source is readable
  survive an app restart and a disconnection. A preview never generated is
  reported as missing, never as cached.
- **Preview task interruption.** Kill the app during generation. Partial work
  is discarded or completed idempotently, and the database passes an integrity
  check.
- **Model independence.** Catalog and photo previews work with no model
  downloaded. Semantic search, when the model is present, does not change the
  metadata result set.
- **Volume identity confusion.** Two drives, similar names, one reformatted.
  The app does not point at the wrong drive and does not merge the catalogs.

Any wrong deletion or wrong asset association blocks the pilot regardless of
how the user study went.

## What the fault-injection evidence already establishes

Three independent implementations confuse "the walk finished" with "every
subtree was read." This is why Gate B treats it as a hard gate rather than a
quality matter.

- **DigUp.** `Crawler` enumerates with `errorHandler: { _, _ in true }` and
  continues; `Indexer.sync` then deletes rows it did not see. Only a root that
  vanished entirely is protected.
- **DiskGallery.** On a directory read failure the catch block increments
  `unreadable`, marks the directory processed, and continues. The failed
  directory row is deleted from the queue and never retried, and when the queue
  empties the snapshot is updated with `isComplete = 1` unconditionally.
- **Meguri.** `walk()` returns from that directory's callback on a `readdir`
  failure; `syncFiles()` builds its `seen` set from only successfully
  discovered paths and sets `deleted_at` on anything absent. Abort is handled
  correctly; a swallowed read error is not.

Recoll does handle the adjacent problem with `idxnoautopurge` and
`recollindex --nopurge`, keeping index data for files that are temporarily
inaccessible. That is a global switch, not a per-subtree judgement, so it
avoids the damage without proving which subtrees were fully read. It is worth
citing as evidence that the failure mode is real and taken seriously by
long-lived software, not as a solution to copy.

The conclusion for this project: the completeness state machine is not
optional, and green CI on an existing project is not evidence that it was
built. It has to be verified by fault injection here.

## Two-phase publication, borrowed from Katalog

Katalog's catalog creation runs in two stages: build the file listing, then
extract metadata and checksums. Its documentation states the catalog is usable
as soon as stage one ends, and that stopping during stage two keeps a complete
file listing. Stopping during stage one yields no catalog.

The pilot adopts that publication boundary:

- Publish a source's catalog once its file listing for that scope is complete
  and verified.
- Generate previews afterwards, in the background, while the source is still
  attached.
- During a rescan, keep the previous trusted catalog queryable.

This avoids designing partially-published catalogs and their consistency
rules. Two limits stay visible and are not hidden behind this:

1. Stage one can still take a long time on a slow drive with many small files.
2. Katalog's two-phase design does not by itself prove that its handling of an
   unreadable interior subtree is safe. The completeness state machine is still
   this project's own work.

The pilot does not test whether a completely fresh scan of a large drive is
usable before it finishes. If participants cannot tolerate waiting for the
first complete listing, per-subtree incremental publication becomes a separate
architectural requirement with its own design, not a progress bar.

## User-facing feedback the pilot must include

Modelled on the problem Katalog's progress-report design records: a completion
notice cleared by the next status update. Readiness must be a distinct,
persistent stage result.

The prototype shows, and the study observes whether participants understand:

- Catalog verified and searchable, with the time it was verified
- Photo previews generated: N of M
- Video previews generated: N of M
- Items that could not be read, and which source they belong to
- Which sources are currently disconnected

These numbers are display copy, not measurements of this app.

## Dependencies this document does not settle

- Whether video previews use `AVAssetImageGenerator` at 1, 3, or 5 time points
  is decided by Gate A+C, then fixed for production with its own budget.
- The default preview byte budget is not set here. Coverage measured in Gate A
  plus the cache size implied by that coverage decide it.
- Whether App Sandbox or Mac App Store distribution is wanted stays open.
- How the three volume concepts are kept distinct (the app's own catalog
  identifier, the file system's volume identifier, and the number a user sticks
  on a physical drive) is specified during D1, informed by Katalog's recorded
  identity bugs, not decided here.

## Relationship to D0-D4

Unchanged. D0 proceeds through its existing verification and review. D1 is
implemented in full, including both blocking invariants; the pilot does not
justify weakening D1's reliability to reach a demonstration sooner. The parts
of D4 needed for this pilot are the preview store and removing the
presence filter from search. The rest of D4 keeps its place in the plan and is
not claimed as delivered.

D2 and D3 are paused and hold no execution slot. They resume only if this
pilot's value gate passes and a later decision says the added capability is
what limits retrieval. Being written in the plan is not an execution licence.

## What would make this stop

- Gate C fails on need validity: the loop does not beat the participant's own
  current method.
- Gate C fails on competitive difference: an existing catalog tool does this
  as well and is already available.
- Gate B fails: any wrong deletion or wrong asset association.
- Gate A reveals that previews at an affordable size cannot support confident
  identification at all, which removes the mechanism the whole loop depends on.

Any one of these is a stop or a redesign, not a reason to proceed and hope the
next milestone fixes it.
