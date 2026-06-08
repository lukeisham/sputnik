Sputnik App

# PURPOSE 

Sputnik is a native macOS development environment that coordinates six concurrent views — a Project File Tree, a Text Editor (Text, Markdown, ASCII art and HTML), a Markdown preview synchronized to the editor, a PDF viewer, a HTML preview also synchronized to the editor, and an integrated Zsh Terminal — within a unified, crash-resistant, memory-efficient minimalist layout.

# BULID ORDER

"numbers are identity, not sequence."

Foundation → Text Editor Window → Project File Tree → Markdown Preview → PDF Viewer → HTML Preview → Terminal

# GITHUB

# NOTES

1. SETUP
  1. Vibe coding rules
    1. Sputnik Rules
      1. Modular design, 
      2. Error and Crash Proof, 
      3. Low Ram usage, 
      4. Fast and efficent
      5. Uses existing MacOS frameworks where possible 
    2. Swift Rules
      1. Use modern Swift Concurrency (async/await, Tasks) over legacy completion handlers.
      2. Strict memory management: Always check for retain cycles; use [weak self] inside escaping closures to prevent RAM spikes.
      3. Use SwiftUI for layout declarative UI, but leverage AppKit via NSViewRepresentable where raw macOS performance demands it (e.g., Terminal rendering, heavy text views).
    3. MacOS Rules
      1. PDF Kit
      2. FileManager and FilePresenter protocols
      3. Grand Central Dispatch (GCD) & Quality of Service (QoS) for offloading heavy tasks (like parsing massive PDFs) from the main UI thread.
      4. Foundation's Process class for spawning the Zsh shell — bind its stdio to the PTY FileHandle (item 5), not a Pipe, so interactive programs work.
      5. Pseudo-Terminal (PTY) system calls (posix_openpt, grantpt, unlockpt) to bridge the Zsh shell input/output streams to your UI.
  3. Coding agent skills
    1. Grill me with context: find out if I want a plan, refractor, fix an error or get an answer 
    2. Generate a plan: read the module guides, read the Swift Coding Rules, invoke Track issues if find issues, update module guides, mark plan as complete. 
    3. Track issues
    4. Create a Module guide: creates a module guide as per 1.4
  4. Module Guides (Each guide = Frontmatter, Purpose statement, ASCI diagram of function or apperance, Technical dot point summary)
  5. Completed and New plans foldera 
2. FOUNDATION = fundamental functions and user interfaces
  1. Inter-panel communication
    1. File Association & Routing
    2. Directory Synchronization
  2. Global State Management
    1. Single Source of Truth (e.g., Observable pattern) to track the "Active Workspace Directory" and "Currently Open File."
    2. Thread Safety: Ensure terminal streaming data and file system watchers update state on the Main Thread safely.
  3. Settings
    4. Determins the appearance and behavior of the app, plus spelling and grammar checking settings
  4. UI / UX 
    1. Appearance 
      1. Light and dark mode
      2. Dailogue boxes, tabs, toggles, sliders, buttons, icons and MacOS related finder icons
      3. Colour and fonts
    2. Functionality 
      1. Adjustable top panels
      2. Panel Toggling (Focus Modes)
      3. Layout State Persistence
      4. Error Types and Messages 
      5. Tabs and Windows 
      6. Panel Relocation (drag any panel to a different slot; Terminal is always pinned to the bottom and cannot be moved)
3. EDITOR WINDOW = the main text editing area where users write Markdown content, opens either text or binary files or Markdown files. 
  1. Line Numbers
  2. Syntax Highlighting
  3. File State & History (eg Undo/Redo)
  4. External File-Watchers 
  5. Search and Replace (Find in File)
  6. SaveAs function 
  7. Auto-Save and Crash Recovery (frequent state serialization to a temporary cache file).
  8. File Size and Encoding Protection (refuse to open or truncate non-text/binary files to prevent RAM exhaustion).
  9. Spelling and Grammar checking (Instant Quickfix)
  10. ASCII art support (Inline Suggestions / Ghost Text, Debouncing, Block Completion)
  11. HTML language support (Inline Suggestions / Ghost Text, Debouncing)
  12. Markdown language support (Inline Suggestions / Ghost Text, Debouncing)
4. MARKDOWN VIEWER = the area where Markdown content is rendered and displayed to the user.
  1. Live Synchronization with Editor Window
  2. Text Selection & Clipboard Copying
  3. Interactive Elements
5. PDF VIEWER = the area where PDF content is rendered and displayed to the user.
  1. Fixed-Layout Rendering Engine
  2. Text Selection & Clipboard Copying
  3. Interactive Elements
  4. Scale and Orientation Control:
  5. Print and SaveAs function
  6. Outline & Table of Contents Sidebar 'aka another new panel = Sputnik' (parsing PDF bookmarks to jump directly to sections).
  7. Thumbnails Sidebar (visual grid navigation) 'aka another new panel = Sputnik' 
6. FILE EXPLORER = the area where users can browse and manage the folder and files to be edited or viewed
  1. Local folder selection
  2. File Status Coloring
  3. Local computer synchronization, 
  4. File System Operations (Right-click context menu to: Create New File, Create New Folder, Delete/Move to Trash, Rename).
  5. Drag-and-Drop Support (Dragging files into or out of the project tree, or reordering folders).
  6. File and Folder icons depending on format (eg folder open or closed, full or empty // eg files markdown, text, html, png etc)
7. TERMINAL = the area where users can interact with the shell and run commands for the folder being viewed in the FILE EXPLORER.
  1. Shell hosting and integration in order to host Zsh on macOS
  2. Text Rendering and Terminal Emulation
  3. The Scrollback Buffer
  4. Customization and Profiles
  5. PTY Lifecycle Management (cleaning up or killing background Zsh shell processes when a terminal tab or the app closes to avoid zombie processes).
  6. Keyboard Input Encoding (translating Special Keys like Arrow Keys, Backspace, Delete, and Ctrl+C into proper ANSI byte streams that Zsh understands).

---

FAQ = Terminal = visual window box, Shell = text-based brain running inside that box, Command Line is the overall environment.

---
