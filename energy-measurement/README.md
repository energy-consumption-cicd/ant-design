# Energy measurement

Instrumentation for measuring the energy consumed by this project's CI cell at
release `6.5.0`. Branch `release-6.5.0` is the tag commit
`740ad964dc2397f33e40944367b0536a7314cc32` plus one commit adding these five files; it
modifies none of the upstream tree (`git diff 6.5.0 release-6.5.0` shows only
them). The composition, the literal commands and the pipeline logic are those of
the campaign on the project's HEAD; only what the tag requires differs
(versions, dependency resolution date, ceilings).

```
.github/workflows/energy-measurement.yml
energy-measurement/
├── README.md
├── Dockerfile
├── run_pipeline.sh
└── commands.sh
```

## Measured cell

`.github/workflows/test.yml` is the only workflow that builds and tests. The
measured cell is:

- `build` (`test.yml:167`), `runs-on: ubuntu-latest`;
- `test-react-latest` (`test.yml:82`), `module: [dom]`, whose two shards
  (`1/2`, `2/2`) run here in sequence.

`lint`, `test-vitest` (declared non-blocking by the upstream), `test-node`,
`test-react-legacy`, `test-react-latest-dist`, `test-lib-es` and
`upload-test-coverage` are outside the cell, as are the other 32 workflows.

The two jobs resolve **different dependency trees**: `build` swaps to react 18
inside `dist`, while `test-react-latest` runs on react 19. Each stage runs in
its own `--rm` container from the same image, which preserves that separation.

## Stages

| stage | commands | source |
|---|---|---|
| `build` | `ut compile`, `dist` (expanded, see D-5), `ut test:dekko` | `:186-189`, `:197-202`, `:204-205` |
| `test` | `ut test -- --maxWorkers=2 --shard=1/2 --coverage`, then `--shard=2/2` | `:96` |

Every command in `commands.sh` is literal. The differences against the jobs,
and no others:

| # | difference | why |
|---|---|---|
| D-1 | `ubuntu:24.04` by digest under `docker run`, user `runner` (uid 1000), workspace at `/workspace` | dedicated bench |
| D-2 | one `--rm` container per stage | measurement construct; it also keeps the two dependency trees apart |
| D-3 | `ut` (`test.yml:172`) runs at image build; `node_modules` and the utoo store are frozen in the image, including the Chrome for Testing and libvips downloads of `.npmrc:3-4`, which need `unzip`, present on the hosted runner | the stages run with `--network none`, and the hosted runner resolves against a warm registry with a CDN |
| D-4 | `utoo` pinned to 1.0.32, the `latest` release on npm at the tag commit, and Node to 22.23.0, the default of the ubuntu24/20260622.220 runner image, sha256-verified | `utooland/setup-utoo` asks for `latest`, and the build and test jobs inherit Node from the runner image; neither version would otherwise be recorded |
| D-5 | inside `dist`, `npm run ut-install-react-18` is replaced by swapping in the react@18 trio baked into the image, resolved at the tag commit with npm's `--before` (D-7); `predist` and `antd-tools run dist` run literally, in that order | utoo 1.0.32 has no offline mode, so under `--network none` the literal command fails and `&&` skips the whole webpack build. The output tree is compared by sha256, file by file, with the literal command run with network before the campaign |
| D-6 | the two shards run in sequence in one container | reproducing the concurrency would need two instrumented benches; two containers on one bench would contaminate the RAPL reading, which is per package |
| D-7 | the dependency tree is the one the npm registry served at the tag commit (2026-06-27T15:43:48Z): `npm install --package-lock-only --before` writes it at image build and `ut` installs that lock | the upstream versions no lockfile and resolves against the live registry, so a build today would measure a newer tree than the tag ran |

## Running

```
docker build -t ant-design-measurement-6.5.0 -f energy-measurement/Dockerfile .
gh workflow run energy-measurement.yml -f campaign=validation
gh workflow run energy-measurement.yml -f campaign=full
```

`validation` runs run 0 only. `full` runs a discarded warm-up plus runs 1..10 and
writes the medians. Each run rests 120 s to measure the idle baseline; an idle
package rate above 1.0 W aborts the run before any stage (exit 90), since the
bench is then not idle.

## Network

Both stages run under `--network none`. Every artifact the jobs fetch is
resolved at image build: the dependency tree, the Chrome for Testing and libvips
binaries pulled by postinstall scripts, and the react@18 trio. Node is
sha256-verified. The upstream versions no lockfile by policy (`.npmrc:1`,
`.gitignore:36-39`, script `clean:lockfiles`); the lock written at image build
for the tag date, with the integrity of every package, and the tree the image
installed are archived inside it, at `/opt/resolved-tree`, and published with
the results.

The test stage needs no mitigation: jsdom does not fetch external resources
(`.jest.js` does not set `resources: 'usable'`).

## Sidecars

Besides the CSV and the exit-code sidecar of the HEAD campaign, each stage writes
`swap_run_NN_<stage>.txt` (host `pswpin`/`pswpout` from `/proc/vmstat`) and
`temp_run_NN_<stage>.txt` (package temperature from the `coretemp` hwmon sensor
labelled `Package id 0`), both read on the host immediately before and after the
RAPL window, never inside it. The 14 CSV columns are unchanged.
