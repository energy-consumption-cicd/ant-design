# syntax=docker/dockerfile:1

# The dependency tree, the utoo store and the react@18 trio are baked at image
# build time so the measured stages can run with --network none. The hosted
# runner downloads all of them ready-made; none is compiled from source here.
FROM ubuntu@sha256:33ceb71981b602c1a7443a53469e4dba065f7503eab3078a2d7a57a2ab987517

# The build and test jobs of test.yml do not use actions/setup-node: they run on
# the Node the runner image ships. utooland/setup-utoo asks for "latest", which
# would freeze an unrecorded version at bake time. Both are pinned to what the
# runner image and the npm registry served at the tag commit date (D-4).
ARG NODE_VERSION=20.20.2
ARG NODE_SHA256=df770b2a6f130ed8627c9782c988fda9669fa23898329a61a871e32f965e007d
ARG UTOO_VERSION=1.0.30
# Tag commit time; the dependency tree is resolved as of this instant (D-7).
ARG DEPS_BEFORE=2026-05-14T05:30:11Z

ENV DEBIAN_FRONTEND=noninteractive

# unzip: the @puppeteer/browsers of the tag-date tree extracts Chrome for Testing with
# the system binary, which the hosted runner image carries.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates curl xz-utils git python3 make g++ unzip; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz"; \
    echo "${NODE_SHA256}  node-v${NODE_VERSION}-linux-x64.tar.xz" | sha256sum -c -; \
    tar -xJf "node-v${NODE_VERSION}-linux-x64.tar.xz" -C /usr/local --strip-components=1 --no-same-owner; \
    rm -f "node-v${NODE_VERSION}-linux-x64.tar.xz"; \
    node --version; npm --version

RUN npm install -g "utoo@${UTOO_VERSION}" && ut --version

# uid 1000 matches the bench user, so the timing volume run_pipeline.sh mounts is
# writable from inside the container; the base image already holds that uid.
RUN userdel -r ubuntu && useradd -m -u 1000 runner

# The hosted runner owns its Node prefix. Without this, node-gyp cannot be
# installed globally and @parcel/watcher silently skips its build script, a
# divergence that does not appear in the upstream run log.
RUN chown -R runner:runner \
      /usr/local/lib/node_modules /usr/local/bin /usr/local/include /usr/local/share

RUN mkdir -p /opt/react18 /opt/resolved-tree \
    && chown runner:runner /opt/react18 /opt/resolved-tree

COPY --chown=runner:runner . /workspace
WORKDIR /workspace
USER runner

# The Actions runner defines CI for every step; test.yml:202 also sets CI=1
# explicitly on the dist step.
ENV CI=true

# Without a lockfile ut resolves against today's registry; npm's --before writes
# the tree the registry served at the tag commit, and ut installs that lock (D-7).
RUN npm install --package-lock-only --package-lock=true --ignore-scripts \
      --no-audit --no-fund --before="${DEPS_BEFORE}" \
    && cp package-lock.json /opt/resolved-tree/package-lock.tag-date.json

# Installs that tree and runs the postinstall scripts that fetch Chrome for
# Testing and libvips (.npmrc:3-4). Each stage runs in its own container, so
# the test stage cannot see what the build stage installs (D-3).
RUN ut

# Path, name and version of every package under node_modules.
COPY --chmod=755 <<'PYEOF' /usr/local/bin/nm-manifest
#!/usr/bin/env python3
import json, os
root = "/workspace/node_modules"
rows = []
for dirpath, _, filenames in os.walk(root):
    if "package.json" not in filenames:
        continue
    try:
        d = json.load(open(os.path.join(dirpath, "package.json")))
    except Exception:
        continue
    if isinstance(d, dict) and d.get("name") and d.get("version"):
        rows.append("\t".join([os.path.relpath(dirpath, root), d["name"], d["version"]]))
print("\n".join(sorted(rows)))
PYEOF

# Produced as the literal `ut i react@18 react-dom@18 @testing-library/react@16
# --save-dev` would at the tag date, so the measured dist stage can swap the
# trio in instead of contacting the registry (D-5). The literal command re-resolves
# the whole tree against today's registry, so the trio is resolved apart with
# npm's --before at the tag commit (D-7) and node_modules is left untouched;
# package.json gets the ranges --save-dev writes. The cell's test job is
# test-react-latest, which resolves react 19; test-react-legacy is excluded.
RUN set -eux; \
    nm-manifest > /tmp/nm-before-react18.tsv; \
    mkdir -p /tmp/r18; \
    cd /tmp/r18; \
    npm install --no-save --no-package-lock --ignore-scripts --no-audit --no-fund \
      --before="${DEPS_BEFORE}" react@18 react-dom@18 @testing-library/react@16; \
    cp -a node_modules/react /opt/react18/react; \
    cp -a node_modules/react-dom /opt/react18/react-dom; \
    mkdir -p /opt/react18/react-dom/node_modules; \
    cp -a node_modules/scheduler /opt/react18/react-dom/node_modules/scheduler; \
    cd /workspace; \
    node -e 'const fs=require("fs");const p=JSON.parse(fs.readFileSync("package.json"));const v=n=>"^"+require("/tmp/r18/node_modules/"+n+"/package.json").version;for(const n of ["react","react-dom","@testing-library/react"]){p.devDependencies[n]=v(n);}fs.writeFileSync("/opt/react18/package.json",JSON.stringify(p,null,2)+"\n");'; \
    rm -rf /tmp/r18; \
    nm-manifest > /tmp/nm-after-react18.tsv; \
    diff /tmp/nm-before-react18.tsv /tmp/nm-after-react18.tsv; \
    rm -f /tmp/nm-before-react18.tsv /tmp/nm-after-react18.tsv

# Both trees are asserted, so a silent swap failure cannot reach a campaign.
RUN set -eux; \
    node -e 'const v=require("/workspace/node_modules/react/package.json").version; if(!v.startsWith("19.")){console.error("workspace react must be 19.x, got "+v);process.exit(1);} console.log("workspace react "+v)'; \
    node -e 'const v=require("/opt/react18/react/package.json").version; if(!v.startsWith("18.")){console.error("baked react must be 18.x, got "+v);process.exit(1);} console.log("baked react "+v)'; \
    test -d /opt/react18/react-dom/node_modules/scheduler; \
    test -f /opt/react18/package.json

# The resolved tree, archived because the upstream versions no lockfile by
# policy (.npmrc:1, .gitignore:36-39, script clean:lockfiles). It is the only
# record of what this image resolved; the workflow copies it into the artifact.
RUN <<'SH'
set -eux
npm ls --all --json > /opt/resolved-tree/npm-ls-all.json 2>/dev/null || true
python3 - <<'PYEOF' > /opt/resolved-tree/node_modules_manifest.tsv
import json, os
root = "/workspace/node_modules"
rows = []
for dirpath, _, filenames in os.walk(root):
    if "package.json" not in filenames:
        continue
    try:
        d = json.load(open(os.path.join(dirpath, "package.json")))
    except Exception:
        continue
    if isinstance(d, dict) and d.get("name") and d.get("version"):
        rows.append("\t".join([os.path.relpath(dirpath, root), d["name"], d["version"]]))
rows.sort()
print("\n".join(rows))
PYEOF
cd /opt/resolved-tree
sha256sum ./* > SHA256SUMS
cat SHA256SUMS
SH
