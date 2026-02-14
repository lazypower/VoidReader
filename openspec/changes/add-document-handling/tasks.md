# Tasks: Add Document-Based App Architecture

## 1. Xcode Project Setup
- [ ] 1.1 Create new Xcode project with Document App template
- [ ] 1.2 Configure deployment target to macOS 14+
- [ ] 1.3 Set Swift language version to 5.9+
- [ ] 1.4 Configure app bundle identifier and signing

## 2. Document Model
- [ ] 2.1 Create MarkdownDocument conforming to FileDocument
- [ ] 2.2 Implement init(configuration:) for reading files
- [ ] 2.3 Implement fileWrapper(configuration:) for writing files
- [ ] 2.4 Define readableContentTypes for .md/.markdown

## 3. App Entry Point
- [ ] 3.1 Configure DocumentGroup in @main App struct
- [ ] 3.2 Set up content view to receive document binding
- [ ] 3.3 Configure window styling and default size

## 4. UTType Registration
- [ ] 4.1 Add UTType declarations to Info.plist
- [ ] 4.2 Register app as handler for markdown files
- [ ] 4.3 Configure document type icons (optional)

## 5. Context-Aware Launch Mode
- [ ] 5.1 Detect if launched with file argument
- [ ] 5.2 Pass launch context to document view
- [ ] 5.3 Open in reader view when file provided
- [ ] 5.4 Open in editor view when no file (new document)
- [ ] 5.5 File > New opens editor view

## 6. Print and Export
- [ ] 6.1 Implement Cmd+P print flow
- [ ] 6.2 Create printable view from rendered markdown
- [ ] 6.3 Include mermaid diagrams as images in print
- [ ] 6.4 Implement Export as PDF menu item
- [ ] 6.5 Generate PDF from rendered content

## 7. Scroll Position Memory
- [ ] 7.1 Track scroll position per document
- [ ] 7.2 Store position with document path in UserDefaults
- [ ] 7.3 Restore position when reopening document
- [ ] 7.4 Handle document content changes gracefully

## 8. Share Sheet
- [ ] 8.1 Add share button to toolbar
- [ ] 8.2 Implement File > Share menu item
- [ ] 8.3 Provide rendered content to share sheet
- [ ] 8.4 Support sharing as PDF

## 9. Quick Look Extension
- [ ] 9.1 Create Quick Look preview extension target
- [ ] 9.2 Register for markdown UTTypes
- [ ] 9.3 Render markdown in preview
- [ ] 9.4 Support light/dark appearance

## 10. Testing
- [ ] 10.1 Test file open via File > Open → reader view
- [ ] 10.2 Test drag-drop onto dock icon → reader view
- [ ] 10.3 Test double-click from Finder → reader view
- [ ] 10.4 Test app launch without file → editor view
- [ ] 10.5 Test File > New → editor view
- [ ] 10.6 Test recent documents menu
- [ ] 10.7 Test print output
- [ ] 10.8 Test PDF export
- [ ] 10.9 Test scroll position restores
- [ ] 10.10 Test Quick Look preview in Finder
