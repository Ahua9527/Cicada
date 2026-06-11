# Bark Worker Vendor Notice

Source: https://github.com/cwxiaos/bark-worker

Vendored commit: `8bfd70c369b6dba3dbe53aad96d79a4367f57a45`

License: GPL-3.0, preserved in `LICENSE`.

Imported files:

- `main.js`
- `main_kv.js`
- `README.md`
- `README.zh.md`
- `doc/`
- `migrations/`
- `package.json`
- `wrangler.jsonc`
- `test.sh`

Local Cicada changes:

- `main.js` and `main_kv.js` read APNs private key, Team ID, Key ID, Topic, and optional APNs host from Worker env/secrets instead of embedding upstream credentials.
- `main.js` and `main_kv.js` expose the original env to the vendored database wrappers so APNs token generation can read those Worker env values.
- Cicada Relay keeps integration code outside this directory in `src/presentation/routes/bark.route.ts`.

The vendored Bark Worker code is intentionally isolated from Cicada Relay code.
Changes under this directory should preserve upstream license headers and be
recorded here.
