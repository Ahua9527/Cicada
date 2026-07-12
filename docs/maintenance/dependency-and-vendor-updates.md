# Dependency and vendored source maintenance

Run this maintenance workflow quarterly. Keep each dependency ecosystem and each vendored source update in a separate pull request so every change can be tested and reverted independently.

## Dependency batches

Start with a live inventory:

```bash
pnpm outdated -r
```

Use these batches in order, but do not combine them:

1. Patch/minor releases within the currently selected major versions, including Prettier, `ts-jest`, `ws`, and Wrangler 4.
2. Wrangler and `@cloudflare/workers-types`. Treat a Workers types major change as a separate compatibility review even when Wrangler remains on major 4.
3. TypeScript, ESLint, and typescript-eslint majors. Confirm their supported-version matrix before changing manifests.
4. Jest, `ts-jest`, and `@types/jest` majors. Upgrade the test ecosystem as a unit only after compatibility is confirmed.

Do not remove `ws`: Relay diagnostic scripts use it. Do not cross multiple major-version boundaries merely to make `pnpm outdated` empty.

For every batch, run and record:

```bash
pnpm run lint
pnpm run build
pnpm run test
pnpm --filter @cicada/relay run test:coverage -- --runInBand --silent
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer pnpm run test:agent
pnpm run deploy:relay:dry-run
pnpm run protocol:check
git diff --check
```

## Vendored Sentry and NotchDrop

The production sources are integrated into the Xcode filesystem-synchronized `Sentry/` group. `ThirdParty/` contains provenance and licenses; it is not the source input and neither project is consumed through SPM.

Validate the pinned source mapping locally:

```bash
pnpm run vendor:audit
```

Generate exact diffs from the recorded upstream revisions before considering an update:

```bash
bash apps/agent/scripts/audit-vendored.sh --diff sentry > /tmp/cicada-sentry-vendor.diff
bash apps/agent/scripts/audit-vendored.sh --diff notchdrop > /tmp/cicada-notchdrop-vendor.diff
```

The diff commands clone upstream repositories into a temporary directory, verify the recorded commit for each baseline, emit the source diff, and then remove the checkout. Review the relevant upstream commits and port selected changes manually. Preserve the local-change inventory in each `VENDOR.md`, the license files, bundle identity, Sentinel lifecycle, Cicada IPC, storage paths, tests, and packaging behavior.

When accepting a new upstream baseline:

1. Update only one vendor at a time.
2. Generate and review the old-baseline diff before editing.
3. Port selected upstream changes; never replace the integrated directory wholesale.
4. Update the version or baseline commit and the local-change inventory in that vendor's `VENDOR.md`.
5. Update the pinned revision in `audit-vendored.sh` so metadata and executable verification stay aligned.
6. Run `pnpm run vendor:audit`, the complete validation matrix above, codesign verification, helper inspection, and DMG verification.
7. Commit the source update, provenance update, and its tests together so the batch is independently revertible.

Do not switch Sentry or NotchDrop to SPM and do not split the Native app into another repository as part of routine upstream maintenance.
