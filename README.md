# Aside

A personal macOS assistant. Press a hotkey, ask in a floating panel by typing or speaking, and Claude answers there and can read the answer aloud. It runs on a Claude subscription through the Claude Code CLI.

Requires macOS 26, Xcode 26 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), and [Claude Code](https://code.claude.com) signed in.

```bash
make run     # build and launch; the hotkey is Control-Option-Space
make check   # build and run tests
```

Working on it: start with [CLAUDE.md](CLAUDE.md) and [docs/](docs/).
