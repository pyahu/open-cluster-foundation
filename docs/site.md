# Website deployment

The OCF website is deployed through Cloudflare Workers Builds with static
assets. This is the same hosting model used by the Pyahu toolchain. The
source lives in `website`, Astro builds the landing page, Starlight builds the
documentation and `wrangler.toml` is the source of truth for the Worker.

## Connect the repository

Connect `pyahu/open-cluster-foundation` to Cloudflare Workers Builds with these
settings:

| Setting | Value |
| --- | --- |
| Production branch | `main` |
| Build command | `./scripts/cloudflare-build.sh` |
| Deploy command | `npx wrangler deploy` |
| Root directory | empty |

The build script installs the locked Node dependencies, type checks the Astro
source, generates `website/dist` and validates the Wrangler contract. The
deploy command reads `[assets]` from `wrangler.toml` and uploads the generated
directory. No runtime environment variables are required.

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

## Public URL

The current canonical origin is
`https://open-cluster-foundation.terson.workers.dev`. Astro generates the
sitemap with that origin. When a custom domain becomes the primary address,
update `site` in `website/astro.config.mjs` and the canonical value in the
landing layout in the same change.

The `website/public/_headers` file applies the browser security policy to static
responses. Review it before adding third party scripts, fonts or forms because
the content security policy blocks those resources by default.
