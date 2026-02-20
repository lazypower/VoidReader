// VoidReaderCore - Main module exports
//
// This module provides the core logic for VoidReader:
// - MarkdownDocument: File document model
// - MarkdownRenderer: Renders markdown to AttributedString
// - DebugLog: Debug telemetry (enabled via VOID_READER_DEBUG=1)
//
// Usage:
//   import VoidReaderCore

// Re-export Foundation types used in public API
@_exported import struct Foundation.AttributedString
