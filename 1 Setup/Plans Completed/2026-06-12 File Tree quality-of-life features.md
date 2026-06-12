---
plan: Add quality-of-life features to the File Tree
status: new
created: 2026-06-12
author: Zed (code analysis)
issue: ISS-058
---

## Summary

The File Tree (module 6) is functionally complete for browsing and file operations, but lacks five quality-of-life features expected in a modern file browser:

1. Drag-to-move files between folders within the tree
2. Inline rename (click name to edit)
3. Multi-select for batch operations
4. Keyboard shortcuts for common operations
5. Display file metadata (modification dates)

---

## Current State

| Feature | Current implementation | Gap |
|---|---|---|
| **Drag-to-move** | `onDrag` on each row exports the URL. `onDrop` on the ScrollView copies files into the **root only** — individual folders have no drop handler | Cannot drag a file from one subfolder to another |
| **Rename** | Right-click → Rename → `NSAlert` text-field prompt with OK/Cancel | Dated UX; no inline editing on the row |
| **Select** | `FileTreeViewModel.selectedNodeID: URL?` — single node only | No `Set<URL>` for multi-select; no ⌘-click or ⇧-click |
| **Shortcuts** | None | No keyboard shortcuts for any file operation |
| **Metadata** | `FileTreeNode.modificationDate` is collected by `loadLevel()` but never rendered | Row shows only the file name |

---

## Design

### 1. Drag-to-move within the tree

Add an `onDrop` handler to each `FileTreeRowView` for directory nodes. When a file URL is dropped onto a folder, move it there via `FileManager.moveItem` and refresh the tree.

**`FileTreeRowView.swift` changes:**
```swift
// Add onDrop to directory rows, after the existing .onDrag:
.onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
    guard node.isDirectory else { return false }
    return viewModel.handleDrop(providers, into: node.id)
}
```

**`FileTreeViewModel.swift` changes:**
- Make the existing `handleDrop(_:into:)` from `FileTreePanel` part of the view model's API (it's currently a private method on the view), so both the ScrollView and individual rows can call it:
  ```swift
  /// Handles a drop of file URLs into `directory`.
  /// - Returns: `true` if at least one file was accepted.
  public func handleDrop(_ providers: [NSItemProvider], into directory: URL) -> Bool { ... }
  ```
- The existing `handleDrop` copies files. Change to **move** for intra-tree drops and keep **copy** for external drops (from Finder). Distinguish by checking whether the source URL is within the active directory tree:
  ```swift
  let isIntraTree = sourceURL.path.hasPrefix(activeDirectory?.path ?? "/dev/null")
  if isIntraTree {
      try FileManager.default.moveItem(at: url, to: dest)
  } else {
      try FileManager.default.copyItem(at: url, to: dest)
  }
  ```

The existing `onDrop` on the outer ScrollView stays as-is for external drops into the root.

### 2. Inline rename

Replace the NSAlert rename prompt with a SwiftUI `TextField` that appears in-place on the row when the user presses Enter (or selects "Rename" from the context menu).

**`FileTreeNode.swift` changes:**
- Add `isRenaming: Bool` state to track whether the node is currently being renamed.

**`FileTreeRowView.swift` changes:**
- Add `@State private var isRenaming = false`
- Replace the static name `Text(node.name)` with a conditional:
  ```swift
  if isRenaming {
      TextField("", text: $editName, onCommit: { commitRename() })
          .textFieldStyle(.plain)
          .font(.system(size: SputnikFont.body))
          .onAppear { editName = node.name }
  } else {
      Text(node.name)
          .font(.system(size: SputnikFont.body))
          ...
  }
  ```
- The context menu "Rename" action should trigger `isRenaming = true`

**`FileContextMenu.swift` changes:**
- Remove the NSAlert `promptRename()` call. Instead, set a binding or use `@Bindable` to set `isRenaming` on the target row. The simplest approach: emit a notification or use a view model state `renamingNodeID: URL?` that `FileTreeRowView` observes.

### 3. Multi-select

Change `selectedNodeID: URL?` to `selectedNodeIDs: Set<URL>`.

**`FileTreeViewModel.swift` changes:**
```swift
// Before:
public var selectedNodeID: URL?

// After:
public var selectedNodeIDs: Set<URL> = []
```

Update all call sites:
- Single-tap: `viewModel.selectedNodeIDs = [node.id]` (replace)
- ⌘-click: `viewModel.selectedNodeIDs.toggle(node.id)` (add/remove)
- ⇧-click: `viewModel.selectedNodeIDs.formUnion(rangeOfNodes(from: existingSelection, to: node))`

**`FileTreeRowView.swift` changes:**
- `isSelected` becomes `viewModel.selectedNodeIDs.contains(node.id)`

**Context menu operations:**
- `trash(nodeID:)` → `trash(nodeIDs: Set<URL>)` — batch trash all selected nodes
- Rename only operates on single selection (last-clicked node)

### 4. Keyboard shortcuts

Add keyboard shortcut handling to `FileTreePanel` (not individual rows, since SwiftUI keyboard shortcuts work on the focused view).

**`FileTreePanel.swift` changes:**
Add `.keyboardShortcut` modifiers and `.onDisappear` cleanup:

```swift
var body: some View {
    VStack(spacing: 0) {
        header
        if showSearch { searchBar }
        Divider()
        treeBody
    }
    .background(SputnikColor.secondaryBackground)
    .task { ... }
    // Keyboard shortcuts for file operations
    .onDeleteCommand {  // ⌘⌫ (Backspace/Delete)
        Task { await viewModel.trashSelected() }
    }
    .onReceive(/* Enter key event */) { _ in
        // Start inline rename on selected node
    }
}
```

Additional shortcuts to add:
| Shortcut | Action | Implementation |
|---|---|---|
| **⌘⌫** | Move selected to Trash | New `trashSelected()` on view model — trashes all `selectedNodeIDs` |
| **⏎** (on selected) | Start inline rename | Set `renamingNodeID` on the view model |
| **⌘N** | New file in active directory | `createFile(named:in:)` |
| **⌘⇧N** | New folder | `createFolder(named:in:)` |
| **⌘C** (on selected) | Copy path | `NSPasteboard.general.setString(node.id.path) |

### 5. File metadata display

Add a secondary text line or column showing the modification date.

**`FileTreeRowView.swift` changes:**
Add a date label beside the name, styled as a caption:

```swift
HStack(spacing: SputnikSpacing.xs) {
    // ... existing chevron + icon ...
    VStack(alignment: .leading, spacing: 1) {
        Text(node.name)
            .font(.system(size: SputnikFont.body))
            .foregroundStyle(...)
            .lineLimit(1)
            .truncationMode(.middle)
        
        if let date = node.modificationDate {
            Text(date.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 9))
                .foregroundStyle(SputnikColor.tertiaryText)
        }
    }
    Spacer(minLength: 0)
}
```

Keep the date compact — abbreviated date + short time fits in ~120 pt. If the panel is narrow, consider making it optional via a settings toggle (future enhancement).

---

## Steps

### Step 1 — Drag-to-move within the tree

1. Move `handleDrop(_:into:)` from `FileTreePanel` (private method on the view) into `FileTreeViewModel` as `public func handleDrop(_:into:) -> Bool`
2. Change the copy logic to **move** for intra-tree drops, **copy** for external drops
3. Add `.onDrop` to `FileTreeRowView` for directory nodes
4. Build and test: drag a file from one subfolder to another in the tree

### Step 2 — Inline rename

1. Add `renamingNodeID: URL?` to `FileTreeViewModel`
2. In `FileTreeRowView`, conditionally show a `TextField` when `viewModel.renamingNodeID == node.id`
3. Update `FileContextMenu.promptRename()` to set `viewModel.renamingNodeID` instead of showing an NSAlert
4. On commit (Enter) or blur, call `viewModel.rename(nodeID:to:)` and clear `renamingNodeID`
5. Build and test: right-click → Rename → type new name inline → press Enter

### Step 3 — Multi-select

1. Change `selectedNodeID: URL?` → `selectedNodeIDs: Set<URL>` in `FileTreeViewModel`
2. Update `FileTreeRowView.isSelected` to check `contains`
3. Update single-tap handler to replace the set (select one, deselect others)
4. Update `⌘-click` to toggle, `⇧-click` to select range
5. Update `rename(nodeID:)` and `trash(nodeID:)` to work on `Set<URL>` (rename is single-only, trash is batch)
6. Build and test: ⌘-click multiple files, then trash them all

### Step 4 — Keyboard shortcuts

1. Add `.onDeleteCommand { Task { await viewModel.trashSelected() } }` to `FileTreePanel`
2. Add `.onContinuous` or `.keyboardShortcut` for ⌘N (new file) and ⌘⇧N (new folder)
3. Wire Enter key to start inline rename
4. Build and test: ⌘⌫ trashes the selected file

### Step 5 — File metadata display

1. In `FileTreeRowView`, add a date label below the file name (compact format)
2. Wrap in a `VStack` so the existing layout shifts minimally
3. Build and verify: modification dates appear below file names

### Step 6 — Update the Module Guide

In `1 Setup/Module Guides/6 Project File Tree/guide.md`:

- **Key types → `FileTreeViewModel`:** Document `selectedNodeIDs: Set<URL>` and `renamingNodeID: URL?`
- **Data flow → File operations:** Update the drag-and-drop section to note intra-tree moves
- **Diagram:** Update the context menu diagram to reflect inline rename (no dialog)

## Risk Assessment

| Risk | Likelihood | Mitigation |
|---|---|---|
| Multi-select breaks existing single-select call sites | Medium | The compiler catches every `selectedNodeID` reference. Systematic search-and-replace. |
| Intra-tree move + external copy distinction is confusing | Low | The heuristic (source path prefix check) matches user expectations — moving a file around your project and copying one in from the desktop. |
| Inline rename TextField loses focus unexpectedly | Low | SwiftUI's `onSubmit` and `onDisappear` both commit the rename. If neither fires, the rename is simply not applied — no data loss. |
| Metadata label makes rows too tall | Low | The secondary text adds ~10 pt of height. For very dense trees, a settings toggle could hide it later. |

## Success Criteria

- User can drag a file from one subfolder to another in the tree
- Right-click → Rename shows an editable text field on the row, not an NSAlert dialog
- User can select multiple files with ⌘-click and batch-trash them with ⌘⌫
- ⌘N creates a new file, ⌘⇧N creates a new folder, ⌘⌫ moves selected to trash
- Modification dates appear below file names

## Post-Plan

- [ ] Move this plan to `Plans Completed/` when all steps are done.
- [ ] Update ISS-058 status to `Resolved` in `References/Issues.md`.
