# Contributing to Zrzutka

Thanks for wanting to help! 🙌

## Development setup
```bash
npm install
npm run compile   # compiles the contract with solc 0.8.24
npm test          # runs the contract tests on a local ganache chain
```

## Guidelines
- Keep the app a single static `index.html` (works on GitHub Pages, no backend).
- Every contract change needs a test.
- Use clear commit messages (e.g. `fix: ...`, `feat: ...`, `docs: ...`).
- Open a pull request with a short description and screenshots for UI changes.
