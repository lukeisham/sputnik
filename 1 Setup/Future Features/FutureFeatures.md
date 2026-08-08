# Future Features

> **Last reviewed:** 2026-06-25 — new app features.

---

## Product Thesis

Before any feature is committed, it must pass one filter:

> **Sputnik is a minimalist, crash-resistant, low-RAM macOS *document environment* — a calm place to read, write, and preview Markdown / HTML / ASCII / PDF alongside a terminal. It is not an IDE and not a cross-platform suite.**

**Deepen the core, resist the sprawl.**  

---

**Before App creation:**
- Seperate Writing Style from Grammar  (seperate help, seperate syntax, seperate autocomplete etc.)
- Expand Writing style section with more open source writing style advice. 
- Find open source Grammar sysytem
- Update Grammar support files. 
- Check Grammar: Adverbial and Adjective order

---

## Before live beta testing. 

#### 1a. Updates

- Editor = Multiple Cursors / Column Editing
- Editor settings per file type: eg wrap off for ASCII art, different Md html tab settings for Markdown files.
- General feature = Conflict resolution when a file is modified both inside and outside Sputnik.
- General feature = Handling of very large files or files with unusual encodings.
- Editor feature = Graceful degradation when syntax highlighting or AI features fail.
- General feature = Protection against rapid external changes (debouncing the reload prompt).
- Editor feature = Undo/Redo behavior: Especially how undo interacts with syntax highlighting and ghost text.
- Editor feature = Performance strategy: How large files and rapid typing are handled (beyond the 10 MB limit).
- General feature = Make all `Supporting AI` features as `Future Feature Plumbing` and hide from user. 
- Capacity to hide my own Resources 


#### 1b. Updates

- Create seperate Lukeatron edition of Sputnik with these features: 
  - Bible Help: Free full text Modern English text of the Bible, Greek and Hebrew lexical and grammar references, Topical Cross-references
  - Theology help: Free Bible symbols text and Archecological information text and systematic theology text.

---

## After successful live beta testing.

### 2. User interface
User registration and release management.
Upgrades system to latest version.

### 3. Licensing & copy protection (research → implement)
**Purpose:** A paid release needs a license-key / activation mechanism before it can ship. Two phases: **(a) research** what comparable indie macOS editors use (Nova, CodeRunner, BBEdit — typically Paddle, or a custom signed-key scheme), then **(b) implement** the chosen approach so it survives app updates, offline use, and refunds.
**Risk:** Highest risk-to-reward item on the list. Easy to under-scope; getting validation wrong (false negatives locking out paying users) is reputationally costly. The research phase has open-ended duration.


___

## Possible future features

### 4. User-installable Help modules
**Purpose:** Let users add their own Help guides alongside the built-in HTML/Markdown/Grammar/ASCII guides — at minimum a drag-and-drop folder convention, at most a small content-registration system.
**Implementation note:** Needs a registration/discovery mechanism and resource bundling; define the file format and trust boundary first.

---

### 5. Multiple personal modules

Bible lookup and Theology lookup Historical context Symbolic context, common commentary interpretation, Narrative place, Socratci Logic anaylsis, rhethoric anayslis, intreptation analysis, OvertonWindow (AI Support?), Square of COntrdiction, Fallacy and Fallacy flipper, Sub-editor (fact and source checking), Fiction scene tension builder, trope matcher, Online argument Bot, 
5b Specicltuty HTML and Markdown formats (Sentence parser, passage breakdown, Greek and Hebrew parser, )
Grammar: adjective and adverb order
Breakt out style from Grammar in App (deepen prose examples)

## After a user base is established 

---

### 6. Remote viewing / light editing from mobile
**Purpose:** View and lightly edit workspace files from a phone or tablet via a companion (local-network sync or cloud relay). A *companion*, not a port — distinct from #13.
**Risk:** Introduces a sync protocol and a security surface (transport encryption, auth) the app does not currently have. High effort, ongoing maintenance.

---

### 7. PDF annotation
**Purpose:** Move the PDF panel from passive viewing toward lightweight annotation — highlight, underline, sticky notes, text selection — making it a real review tool alongside note-taking.
**Implementation note:** The PDF panel is currently **read-only** (10 `PDFView` files, **zero** `PDFAnnotation` usage). PDFKit annotation APIs are well documented, but a correct **undo stack** for annotations is the non-tri4vial part. _ After the an established user base. 

---

## Maybe features 

---

### 8. Windows & Linux versions
**Purpose:** Expand beyond macOS. Requires  a cross-platform framework migration with the core written in RUST and Linux or Windows specfific modules. 
**Category change.** The current architecture leans hard on Apple frameworks (PDFKit, AppKit, `NSSpellChecker`); a port effectively re-implements the app. Defer until the macOS product has a user base. 

---

### 9. Full iOS / iPadOS versions
**Purpose:** Standalone touch-first iOS/iPadOS apps sharing Sputnik's document format and workspace concept, synced via iCloud. Unlike remote editing (**#11**), this is a full native port with mobile file management and on-device AI.
**Category change.** Largest single effort on the list; only sensible after the macOS app is mature and revenue-positive. Defer until the macOS product has a user base.
