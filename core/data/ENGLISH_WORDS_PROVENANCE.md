# English detector data provenance

SangKey keeps English auto-detection data deliberately small and auditable. The
runtime combines the two files below in memory; no network request is made by the
input agent.

## 1. CC0 common-word corpus

File: `english_common_cc0.json`

Upstream: `dariusk/corpora`, `data/words/common.json`

Pinned upstream commit:
`cf30ca27ab176b63623af1ddcfa2447ac07305ba`

Pinned Git blob SHA:
`8ec4ea53704dfca63f1ee00852c6bcc15411c49e`

The vendored file is byte-for-byte identical to that upstream blob. CI verifies
this with `git hash-object`; changing the data requires an explicit provenance
update and review.

License: Creative Commons CC0 1.0 Universal. The Corpora project explicitly
licenses its data under CC0 and states that submitted data may be used for any
reason without attribution. Upstream license/provenance documentation:

- https://github.com/dariusk/corpora/blob/cf30ca27ab176b63623af1ddcfa2447ac07305ba/README.md
- https://github.com/dariusk/corpora/blob/cf30ca27ab176b63623af1ddcfa2447ac07305ba/data/words/common.json

## 2. SangKey detector supplement

File: `english_supplement.dat`

This is a small, sorted, lowercase list maintained directly by the SangKey
project for mixed Vietnamese/English developer vocabulary and regression cases
that are intentionally outside the general-purpose common-word corpus. It is
not copied from the former `google-10000-english` payload or another external
word list.

To remove ambiguity for downstream redistributors, SangKey contributors dedicate
the contents of `english_supplement.dat` to the public domain under CC0 1.0 to
the extent they hold copyright or related database rights in those additions.
The rest of SangKey remains GPLv3 as stated in `LICENSE` and `NOTICE`.

## Removed source

The historical `core/data/english_words.dat` was removed before the SangKey
v0.4.0 release because its `google-10000-english` provenance did not provide the
clear redistribution chain required by this project. It is not packaged, loaded,
or used by release builds.
