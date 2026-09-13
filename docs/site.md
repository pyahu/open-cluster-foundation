# Website deployment

The OCF website is deployed through Cloudflare Workers Builds with static
assets. This is the same hosting model used by the Pyahu toolchain. The
deployable files live in `dist` and `wrangler.toml` is the source of truth for
the Worker.

## Connect the repository

Connect `pyahu/open-cluster-foundation` to Cloudflare Workers Builds with these
settings:

| Setting | Value |
| --- | --- |
| Production branch | `main` |
| Build command | `./scripts/cloudflare-build.sh` |
| Deploy command | `npx wrangler deploy` |
| Root directory | empty |

The build script validates the tracked static assets and the Wrangler contract.
The deploy command reads `[assets]` from `wrangler.toml` and uploads `dist`.
No runtime environment variables are required.

## Work locally

Install the pinned CLI and run the development server:

```sh
mise install node npm:wrangler
mise run site:build
mise run site:dev
```

The default address is `http://localhost:4173`. Set `OCF_SITE_PORT` when that
port is already in use.

Run the deeper site validation without starting a server:

```sh
mise run ci:site
```

## Deploy manually

Normal production deployments come from Workers Builds after a push to `main`.
Use the protected manual task when an explicit local deployment is needed:

```sh
wrangler login
mise run site:deploy
```

The task runs the site checks and requires a clean `main` that matches
`origin/main`. It asks for deployment confirmation before running
`wrangler deploy`. Use `--yes` only in an intentional noninteractive workflow.

## Add the public URL

Cloudflare assigns a `workers.dev` address after the first deployment. Add the
final public or custom domain to the README only after the address works. At
that point, add absolute canonical links and a sitemap using the same hostname.

The `_headers` file applies the browser security policy to static responses.
Review it before adding third party scripts, fonts or forms because the content
security policy blocks those resources by default.
