# English detector data provenance

SangKey keeps English auto-detection data local and auditable. The input agent
combines the reviewed files below in memory; it makes no network request to build
or query the detector dictionary.

## 1. CC0 Corpora data

Upstream: `dariusk/corpora`

Pinned upstream commit:
`cf30ca27ab176b63623af1ddcfa2447ac07305ba`

Vendored files:

| SangKey file | Upstream file | Pinned Git blob SHA |
| --- | --- | --- |
| `english_common_cc0.json` | `data/words/common.json` | `8ec4ea53704dfca63f1ee00852c6bcc15411c49e` |
| `english_nouns_cc0.json` | `data/words/nouns.json` | `aca4efb20de9becfd3f949c73e97297be26574f4` |

Both vendored files are byte-for-byte identical to their pinned upstream blobs.
CI verifies them with `git hash-object`; changing either corpus requires an
explicit provenance update and review.

License: Creative Commons CC0 1.0 Universal. The Corpora project explicitly
licenses its data under CC0 and states that submitted data may be used for any
reason without attribution. Reviewed upstream documentation:

- https://github.com/dariusk/corpora/blob/cf30ca27ab176b63623af1ddcfa2447ac07305ba/README.md
- https://github.com/dariusk/corpora/blob/cf30ca27ab176b63623af1ddcfa2447ac07305ba/data/words/common.json
- https://github.com/dariusk/corpora/blob/cf30ca27ab176b63623af1ddcfa2447ac07305ba/data/words/nouns.json

## 2. SangKey detector supplement

File: `english_supplement.dat`

This is a small, sorted, lowercase list maintained directly by SangKey for mixed
Vietnamese/English developer vocabulary and concrete regression cases that are
outside the general-purpose Corpora samples. It is not copied from the former
`google-10000-english` payload or another external word list.

To remove ambiguity for downstream redistributors, SangKey contributors dedicate
the contents of `english_supplement.dat` to the public domain under CC0 1.0 to
the extent they hold copyright or related database rights in those additions.
The rest of SangKey remains GPLv3 as stated in `LICENSE` and `NOTICE`.

## Test-only adversarial data

`core/tests/run_tests.sh` generates a temporary adversarial English superset from
`viet_telex.dat` during tests. It exists only to force compound-collision paths
through the real engine/host simulator and preserve the original C-prop/C-order
anti-vacuity floors after the production corpus change. It is deleted before
source/provenance invariants and is never tracked, bundled, or loaded by SangKey.

## Removed source

The historical `core/data/english_words.dat` was removed before the SangKey
v0.4.0 release because its `google-10000-english` provenance did not provide the
clear redistribution chain required by this project. It is not packaged, loaded,
or used by release builds.
