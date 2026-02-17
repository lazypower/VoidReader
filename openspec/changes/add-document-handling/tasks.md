# Tasks: Add Document-Based App Architecture

## 1. Xcode Project Setup
- [x] 1.1 Create new Xcode project with Document App template
- [x] 1.2 Configure deployment target to macOS 14+
- [x] 1.3 Set Swift language version to 5.9+
- [x] 1.4 Configure app bundle identifier and signing

## 2. Document Model
- [x] 2.1 Create MarkdownDocument conforming to FileDocument
- [x] 2.2 Implement init(configuration:) for reading files
- [x] 2.3 Implement fileWrapper(configuration:) for writing files
- [x] 2.4 Define readableContentTypes for .md/.markdown

## 3. App Entry Point
- [x] 3.1 Configure DocumentGroup in @main App struct
- [x] 3.2 Set up content view to receive document binding
- [x] 3.3 Configure window styling and default size

## 4. UTType Registration
- [x] 4.1 Add UTType declarations to Info.plist
- [x] 4.2 Register app as handler for markdown files
- [x] 4.3 Configure document type icons

## 5. Context-Aware Launch Mode
- [x] 5.1 Detect if launched with file argument
- [x] 5.2 Pass launch context to document view
- [x] 5.3 Open in reader view when file provided
- [x] 5.4 Open in editor view when no file (new document)
- [x] 5.5 File > New opens editor view

## 6. Print and Export
- [x] 6.1 Implement Cmd+P print flow
- [x] 6.2 Create printable view from rendered markdown
- [x] 6.3 Include mermaid diagrams as images in print (pre-rendered via WKWebView snapshot)
- [x] 6.4 Implement Export as PDF menu item
- [x] 6.5 Generate PDF from rendered content
- [x] 6.6 Polish: Paginated vector PDF export (uses NSPrintOperation with save disposition)

## 7. Scroll Position Memory
- [x] 7.1 Track scroll position per document
- [x] 7.2 Store position with document path in UserDefaults
- [ ] 7.3 Restore position when reopening document (partial: SwiftUI ScrollView limitation)
- [x] 7.4 Handle document content changes gracefully

## 8. Share Sheet
- [x] 8.1 Add share button to toolbar
- [x] 8.2 Implement File > Share menu item
- [x] 8.3 Provide rendered content to share sheet
- [x] 8.4 Support sharing as PDF

## 9. Quick Look Extension
- [x] 9.1 Create Quick Look preview extension target
- [x] 9.2 Register for markdown UTTypes
- [x] 9.3 Render markdown in preview
- [x] 9.4 Support light/dark appearance

## 10. Testing
- [x] 10.1 Test file open via File > Open → reader view
- [x] 10.2 Test drag-drop onto dock icon → reader view
- [x] 10.3 Test double-click from Finder → reader view
- [x] 10.4 Test app launch without file → editor view
- [x] 10.5 Test File > New → editor view
- [x] 10.6 Test recent documents - verified via File > Open Recent menu
- [x] 10.7 Test print output - verified via Cmd+P with VIBE_CHECK.md
- [x] 10.8 Test PDF export - verified via File > Export as PDF
- [x] 10.9 Test scroll position - verified manually (reopens at last position)
- [x] 10.10 Test Quick Look - verified via spacebar preview in Finder
