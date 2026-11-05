# Tackle Mark

Tackle Mark is a native macOS Markdown reader with a Finder Quick Look extension.
Its purpose is simple: select a Markdown file in Finder, press Space, and read a
fully rendered preview rather than raw Markdown source.

## Project status

**First implementation complete.** The project builds as a macOS 14+ app with
an embedded Quick Look Preview Extension and a read-only rendered Markdown
reader. It includes unit tests for the renderer and file-safety boundary.

To build locally, open `Tackle Mark.xcodeproj` in Xcode and select the
**Tackle Mark** scheme. The next validation step is to launch the signed app,
enable its Quick Look extension if macOS asks, then select a `.md` file in
Finder and press Space.

Tackle Mark also declares itself as a Markdown **Viewer**, so after it has been
run once you can select a Markdown file in Finder, choose **Get Info → Open
with → Tackle Mark**, and click **Change All…** to make it the default opener.

Run the automated checks with the dedicated **Tackle Mark Tests** scheme, for
example:

```sh
xcodebuild -project 'Tackle Mark.xcodeproj' -scheme 'Tackle Mark Tests' test
```

## Intended experience

- Open one or more Markdown files in Tackle Mark for clean, rendered reading
  tabs within one reader window.
- Select a `.md` file in Finder and press Space for the same rendered result.
- Respect the system appearance, with light and dark themes available later.
- Render locally and safely, without network access or executable Markdown
  content.
- Render common Markdown now; broader GFM support and local images remain
  planned enhancements.

## Architecture

```text
Tackle Mark.app
├── Single SwiftUI reader window with document tabs
├── Markdown-to-HTML renderer (shared)
└── Tackle Mark Quick Look.appex
    └── QLPreviewProvider → static HTML → Finder Quick Look
```

The Quick Look extension is a data-based preview extension. It reads the
selected file and returns a self-contained HTML document to Finder. The app is
the extension's host and provides the full reading experience.

See [the implementation plan](docs/IMPLEMENTATION_PLAN.md) for milestones,
technical decisions, and the test checklist.
