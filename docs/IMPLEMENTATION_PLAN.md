# Tackle Mark implementation plan

Last updated: 2026-09-08

## Goal

Build a small native macOS application that renders Markdown documents in an
app window and in Finder's Quick Look interface when a user presses Space.

## Decisions made

| Area | Decision | Reason |
| --- | --- | --- |
| Minimum OS | macOS 14+ | Keeps the first version focused on current SwiftUI and Quick Look APIs. |
| Finder integration | Quick Look **Preview Extension** | This is the supported system mechanism for a rendered Space-bar preview. |
| Quick Look output | Static, self-contained HTML | Supports polished CSS, tables, code blocks, and dark mode without relying on a web process inside the extension. |
| Rendering scope | Safe common-Markdown baseline | The first cut covers headings, links, lists, task lists, blockquotes, tables, and fenced code; full GFM remains future work. |
| Network policy | No network access in previews | Prevents tracking pixels and makes previews predictable and private. |
| Theme | Follow system initially | A manual light/dark/system preference can follow after the first working preview. |

## Target layout

```text
TackleMark.xcodeproj
├── TackleMark/                 # Host macOS app
├── TackleMarkQuickLook/        # Quick Look Preview Extension
├── TackleMarkShared/           # Renderer and shared models
└── TackleMarkTests/            # Renderer and integration tests
```

The host app contains the `.appex` bundle. Installing or launching the host app
allows macOS to register the Quick Look extension.

## Milestones

### 1. Project foundation

- Create a SwiftUI macOS app project named `Tackle Mark`.
- Add a **Quick Look Preview Extension** target.
- Add a shared Swift module for rendering code and document metadata.
- Configure both targets for macOS 14+ and development signing.

**Done when:** the app builds and the extension is embedded in the app bundle.

### 2. In-app rendered reader

- Support opening one or more `.md` files through the File menu and Finder,
  retaining them as tabs in one reader window.
- Read UTF-8 Markdown and produce styled HTML.
- Show the HTML in a native web view with a readable document width.
- Resolve relative links and images only from the selected document's directory.

**Done when:** a representative Markdown file renders correctly in the app.

### 3. Finder Quick Look preview

- Implement `QLPreviewProvider` in the extension.
- Set `QLIsDataBasedPreview` to `true`.
- Register `net.daringfireball.markdown` in `QLSupportedContentTypes`.
- Add `com.unknown.md` as a compatibility content type for apps that assign that
  identifier to `.md` files.
- Return sanitized static HTML in `QLPreviewReply`.

**Done when:** selecting a `.md` file in Finder and pressing Space displays a
rendered preview.

### 4. Quality and safety

- Add a built-in light/dark stylesheet using system colors.
- Escape unsafe HTML and remove scripts, event handlers, and remote resources.
- Add a practical file-size limit with a helpful fallback view.
- Support local images deliberately (as data or Quick Look attachments) and
  document any sandbox constraints.
- Render code blocks with precomputed syntax-highlight markup.

**Done when:** previews are attractive, offline, and robust with untrusted
Markdown content.

### 5. Packaging and polish

- Add an extension status/help screen in the app.
- Document enabling the extension in System Settings if macOS has not enabled it.
- Add an app icon, versioning, and release notes.
- Sign and notarize only when distributing outside the development machine.

**Done when:** a user can install the app and understand how to enable and use
the Finder preview.

## Rendering approach

Foundation can parse Markdown into an `AttributedString`, which is useful for
a very small native reader. For the planned fully rendered experience, the
shared renderer should instead produce static HTML from a CommonMark/GFM
implementation and inject a bundled stylesheet.

The current renderer supports:

- headings, paragraphs, emphasis, links, and inline code;
- unordered and ordered lists, task lists, blockquotes, and horizontal rules;
- fenced code blocks and tables;
- image alt text, with local-image handling added deliberately;
- system light/dark appearance and static code-block styling.

Deferred features include Mermaid diagrams, arbitrary JavaScript, editing,
live reload, and remote images. These are not required for the reader or the
Finder preview and would expand the security and compatibility surface.

## Quick Look configuration checklist

The Preview Extension target's Info.plist must include:

```xml
<key>NSExtension</key>
<dict>
  <key>NSExtensionPointIdentifier</key>
  <string>com.apple.quicklook.preview</string>
  <key>NSExtensionPrincipalClass</key>
  <string>$(PRODUCT_MODULE_NAME).PreviewProvider</string>
  <key>NSExtensionAttributes</key>
  <dict>
    <key>QLIsDataBasedPreview</key>
    <true/>
    <key>QLSupportedContentTypes</key>
    <array>
      <string>net.daringfireball.markdown</string>
      <string>com.unknown.md</string>
    </array>
  </dict>
</dict>
```

The exact target-generated plist may include additional Xcode keys. Preserve
those keys; the entries above identify the extension and its supported files.

## Verification checklist

- Build and launch the host app from Xcode.
- Confirm the embedded `Tackle Mark Quick Look.appex` exists in the built app.
- Open a sample `.md` file in the app and verify headings, a table, a task list,
  links, and a fenced code block.
- In Finder, select that file and press Space.
- If Finder shows raw text, enable the extension in **System Settings → General
  → Login Items & Extensions → Quick Look**.
- Close Quick Look, then re-open it after rebuilding the extension.
- If Finder has retained an old result during development, refresh Quick Look's
  cache and restart Finder before retesting.

## Open questions for product decisions

1. Should the app be read-only, or should it eventually edit and save Markdown?
2. Should local images beside a Markdown file render in Quick Look, or should
   the preview remain text-only for maximum sandbox safety?
3. Do we want a GitHub-like visual style, a typography-first reading style, or
   selectable themes?
4. Is this just for personal use, or should we plan for signing, notarization,
   and public distribution?
