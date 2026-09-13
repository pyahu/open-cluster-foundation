# Website deployment

The OCF website is prepared as a static Cloudflare Pages project. The
deployable files live in `dist` and the Cloudflare configuration lives in
`wrangler.toml`.

## Connect the repository

Create the project in Cloudflare Workers & Pages with Git integration. Use
these settings:

| Setting | Value |
| --- | --- |
| Repository | `pyahu/open-cluster-foundation` |
| Production branch | `main` |
| Build command | `exit 0` |
| Build output directory | `dist` |
| Root directory | empty |

Git integration publishes changes pushed to `main` and creates preview
deployments for other branches. No runtime environment variables are required.

Use the project name `open-cluster-foundation` so it matches `wrangler.toml`.
Choose Git integration when creating the project. A Direct Upload project
cannot be converted to Git integration later.

## Work locally

Install the pinned CLI and run the development server:

```sh
mise install node npm:wrangler
mise run site:dev
```

The default address is `http://localhost:4173`. Set `OCF_SITE_PORT` when that
port is already in use.

Validate the site without starting a server:

```sh
mise run ci:site
```

## Deploy manually

Normal production deployments come from the Cloudflare Git integration after a
push to `main`. If automatic deployments are disabled, use the protected manual
task:

```sh
wrangler login
mise run site:deploy
```

The task runs the site checks and requires a clean `main` that matches
`origin/main`. It also confirms that the existing Cloudflare project has the
same name before asking for deployment confirmation. Use `--yes` only in an
intentional noninteractive workflow.

## Add the public URL

Cloudflare assigns a `pages.dev` address after the first deployment. Add the
final public or custom domain to the README only after the address works. At
that point, add absolute canonical links and a sitemap using the same hostname.

The `_headers` file applies the browser security policy to static responses.
Review it before adding third party scripts, fonts or forms because the content
security policy blocks those resources by default.
