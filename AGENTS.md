# AC Control

Native macOS menu-bar application for one user's LG air conditioner. User requirements and verified wire-contract sources are documented in README.md.

## Real accounts and appliances

Never connect to a real LG account or appliance, including read-only requests, without the user's direct explicit authorization for that specific action. Automated tests, previews and agent-led UI checks must use mocks or `--demo`.

## Configuration

The user explicitly chose LG_THINQ_PAT in a local .env file, not Keychain. Keep .env ignored by Git, outside the app bundle, and never print its contents, token, authorization header or raw server diagnostics. .env.example contains no real credentials.

## Build and verification

- `make test`: Swift Testing suite, mocked HTTP; XCTest disabled for Command Line Tools compatibility.
- `make app`: build and ad-hoc sign dist/AC Control.app.
- `make demo`: run simulated app with no network or login-item registration.
- `make run`: real-account execution; do not invoke as an agent without the specific authorization described above.
- Offscreen native previews: `"dist/AC Control.app/Contents/MacOS/ACControl" --demo --render-previews /tmp/ac-control-preview`.

Send a control POST once; never automatically retry a command. Confirm state through subsequent reads. Do not infer the room temperature or device power state from a missing response. Preserve existing operating mode when changing power. Temperature write bounds and steps come from the device profile.

## graphify

When graphify-out/graph.json exists, run graphify query first for codebase questions; use path/explain for relationships and concepts. Expected dirty graph files are not a reason to skip it. After modifying code, run `graphify update .` (AST only, no API/LLM). Use graphify-out/wiki/index.md for broad navigation when present.
