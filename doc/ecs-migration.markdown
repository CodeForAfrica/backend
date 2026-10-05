# CivicSignal container runtime

From the repository root, supply the existing PostgreSQL URL and run:

```bash
MC_DATABASE_URL='postgresql://user:password@database-host:5432/mediacloud?sslmode=require' docker compose up
```

Alternatively copy `.env.example` to `.env`, fill in the URL, and run `docker compose up`.
The first run builds the images. Open http://localhost:8082/status (or change
`MC_HTTP_PORT`). Use `docker compose up --build` after changing source code.
Docker Desktop needs up to 20 GiB of container memory plus build overhead;
images are linux/amd64, including on Apple Silicon. If your clone did not include the runtime submodules, initialize them once:

```bash
git submodule update --init apps/common/src/python/mediawords/languages/hi/hindi-hunspell apps/common/src/perl/MediaWords/Util/Mail/Message/Templates/email-templates apps/common/src/python/mediawords/languages/ca/snowball_stemmer apps/common/src/python/mediawords/languages/lt/snowball_stemmer apps/common/src/python/snowball
```

The default stack contains nginx/API, ZooKeeper/Solr, RabbitMQ, crawler provider
and fetcher, article extraction, extraction/vectorization, Solr import, media
rescraping, six topic workers, CLIFF/NYT annotation servers and queue workers, and scheduled maintenance: ten containers. Pipeline and topic
workers run in two supervised groups; a child exit restarts its group, and
shutdown signals reach every child. Container limits match the initial 20 GiB ECS
task: API 1 GiB, nginx 256 MiB, ZooKeeper 512 MiB, Solr 4 GiB, RabbitMQ 512 MiB,
extractor 512 MiB, annotators 4 GiB, pipeline 4 GiB, topics 4 GiB and maintenance
1 GiB. Worker budgets and Java heaps leave room for runtime overhead within these
limits. These are starting estimates; the fixture test does not establish production
peak memory needs. The standard template uses its existing direct CloudWatch logging option to stay within ECS's ten-container task limit. The
component inventory is `runtime-services.json`. SMTP is an external service;
set `MC_SMTP_HOST`, `MC_SMTP_PORT`, and, where needed, `MC_SMTP_STARTTLS=1`,
`MC_SMTP_USERNAME`, and `MC_SMTP_PASSWORD`. Optional legacy integrations such as
Feedly, podcast ingestion, sitemap ingestion, Twitter and Word2Vec snapshots are not enabled by this
runtime. Confirm which of these are active on EC2 before retiring that server.

## Local dev deployment

Apply the CivicSignal dev stack from the IaC checkout first, using its
`scripts/deploy_to_aws_locally.sh` tool. Then, from this repository:

```bash
bash scripts/deploy-locally.sh --infra-repo ../iac-cfa-pulumi --check
bash scripts/deploy-locally.sh --infra-repo ../iac-cfa-pulumi
```

Pass the PR checkout path when testing unmerged infrastructure. The defaults are
`--profile cfa-bootstrap --stack dev`; the tool deliberately supports dev only.
It requires Go, Git, Docker Buildx, AWS CLI and a logged-in Pulumi CLI. Credentials
stay in the normal local AWS/Pulumi credential stores; no database password is
read or passed by the app deploy tool.

The tool resolves all ten containers through the same runtime contract as the
dev workflow, builds and pushes linux/amd64 images sequentially, then uses the
IaC repository's shared `ecs-release-images` helper to replace every image with
an immutable digest in one task revision. It preserves the latest template's
memory limits, secret references and mounts. Local builds and ECR storage carry
costs; this command does not trigger GitHub build jobs. GitHub's scanning,
signing and artifact steps remain part of the shared CI workflow.

It waits for the expected task revision to stabilize and for the public HTTPS
`/status` endpoint to return 200. A failed deployment restores a verified stable
previous revision, unless another operator has already changed the service.
A failed first deployment remains visible because it has no verified rollback
target. The stateful task uses stop-before-start releases. Coordinate old EC2
workers before cutover: both deployments use the existing database, and this
tool does not stop EC2 or restore the production Solr index.
Use `--resume` when deliberately deploying and resuming a paused dev service.
Startup failures stop the tool on the first failed release task.

## Existing data

There is no PostgreSQL container, schema initialization, or schema migration in
this stack. Every DB client receives `MC_DATABASE_URL`. Percent-encode reserved
characters in credentials; a URL without a port uses 5432. Supported libpq URL
options include `sslmode`, `sslrootcert`, `sslcert`, `sslkey`, `connect_timeout`
and `options`. The database must already contain the application schema.
The workers and maintenance jobs perform normal application writes, so starting
the stack against a production database starts real crawling and scheduled work.
Crawler host selection uses an indexed SQL query rather than requiring the newer
`get_downloads_for_queue()` stored function, which the existing database lacks.
The queue still uses the existing `pop_queued_download()` function.

Preserve the existing storage settings as well as the database URL. PostgreSQL
is the default download/public-store backend. If the existing deployment uses
S3, retain its bucket, directory, credentials and `MC_PUBLIC_STORE_SALT` values;
changing the public-store salt changes generated download keys for both backends. The application
supports these environment variables through its existing configuration code.

`runtime-data` persists the Solr index, ZooKeeper state, RabbitMQ state and generated RSS dumps.
`docker compose down` preserves it; `down -v` removes it. Connecting an existing
PostgreSQL database does not populate a new Solr index. Before cutover, preserve
or rebuild the existing search index through the established operator process.
Do not run a database migration to accomplish this move.

## Images and releases

The root Dockerfile selects a component with `CIVICSIGNAL_COMPONENT`. It pins
the deployed CFA dependency images by digest and copies the current checkout's
application and common code over them. This preserves the legacy Perl/Python
runtime while avoiding the inaccessible historical GCR build chain. Dependency
modernization is separate work; these snapshots still contain old dependencies.
RabbitMQ uses a pinned official image. Topic mapping includes its Java runtime
and original ForceAtlas2 dependencies.

The manual `deploy_to_dev` workflow resolves all repositories from the Pulumi
stack, builds and scans all ten images (two builds at a time), then deploys their
immutable digests in one task definition. This costs more build time and ECR
storage than a two-container web deployment. The infrastructure PR's shared
workflow changes must be available on `iac-cfa-pulumi/main` before running it.
Set `CIVICSIGNAL_PULUMI_STACK` to the fully qualified org/project/stack and
provide `PULUMI_ACCESS_TOKEN` in the dev environment.

ECS uses the same container names and images, with localhost communication
inside one Fargate task. Its standard template supplies ALB routing, ECR,
OIDC, logs, alarms and shared EFS storage. See the CivicSignal app README in
`iac-cfa-pulumi` for configuration and cutover order.

## Verification performed for this change

All ten images built on Docker Desktop and ran against a disposable PostgreSQL
13.5 fixture initialized separately with this checkout's schema. The end-to-end
check creates an activated fixture user, authenticates through nginx, creates
and updates a feed through the HTTP API, crawls a local HTTP article, runs
RabbitMQ extraction and CLIFF/NYT annotation, imports the processed story into
Solr, and retrieves it through the HTTP story-search API. Run it again with
`dev/e2e/run.sh`; `.env.e2e.local` must point to a separately initialized database
named `civicsignal_e2e`. The script refuses any other database. `compose.e2e.yaml`
sets an explicit subnet because this workstation's default Docker pools were
exhausted. The prepared `.env` selects this isolated project, so plain
`docker compose up` runs it; the fixture database remains a separate container.

The existing AWS PostgreSQL connection was also verified over an SSH tunnel,
using its actual credentials with read-only transactions. The existing monitoring
API key authenticated with the current application code inside a transaction
that was rolled back (legacy login performs an UPDATE even for read-only users).
No production crawling, schema migration or deployment was performed. Protected,
gitignored `.env.aws.local` contains the existing private database URL;
`.env.production.local` preserves the production storage settings and a read-only
local tunnel URL. Do not start the full worker stack against that production URL
without coordinating the old workers. The tunnel must be reopened before reusing
its local URL.

Configuration/mail regression tests (13), supervisor shutdown/failure tests
(2), and the Go deployment-contract tests passed. Infrastructure resource,
shared-storage, guardrail, compute and release-image tests passed, and both
changed workflows passed offline zizmor checks. Earlier checks verified durable
RabbitMQ and Solr state across complete container replacement. Real topic jobs,
outgoing email, production index restoration and the remaining EC2 integrations
still require cutover verification. This is not yet full EC2 service parity.
