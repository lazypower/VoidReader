#!/usr/bin/env python3
"""Generate a 50K line markdown test document for performance testing."""

import random
import os

# Change to project root
os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Template header
template = """# Large Test Document - 50,000 Lines

This document is generated for performance testing. It contains varied markdown content:
headings, code blocks, tables, lists, blockquotes, and inline formatting.

---

## Section 1: Introduction

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.

### Key Features

- Feature one with **bold text** and *italic text*
- Feature two with `inline code` examples
- Feature three with [links](https://example.com)
- Feature four with ~~strikethrough~~ text

### Code Example

```swift
struct PerformanceTest {
    let iterations: Int
    var results: [Double] = []

    mutating func run() {
        for i in 0..<iterations {
            let start = CFAbsoluteTimeGetCurrent()
            // Simulate work
            let _ = (0..<1000).reduce(0, +)
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            results.append(elapsed)
        }
    }
}
```

### Data Table

| Metric | Value | Unit | Notes |
|--------|-------|------|-------|
| Scroll FPS | 60 | fps | Target |
| Render Time | 500 | ms | Max allowed |
| Memory | 100 | MB | View layer |

> This is a blockquote that spans multiple lines.
> It contains important information about the test.
> Remember to measure before and after optimization.

---

## Section 2: Content Block

Paragraph with various formatting: **bold**, *italic*, `code`, and [link](https://test.com).

- [ ] Task item unchecked
- [x] Task item checked
- [ ] Another unchecked task

1. Ordered item one
2. Ordered item two
3. Ordered item three
   - Nested unordered
   - Another nested

```python
def fibonacci(n):
    if n <= 1:
        return n
    return fibonacci(n-1) + fibonacci(n-2)

# Calculate first 10 fibonacci numbers
for i in range(10):
    print(f"F({i}) = {fibonacci(i)}")
```

### Subsection 2.1

More content here with inline `code snippets` and **important notes**.

| Column A | Column B | Column C |
|----------|----------|----------|
| Data 1   | Data 2   | Data 3   |
| Data 4   | Data 5   | Data 6   |

---

"""

code_samples = [
    '''```javascript
function processData(items) {
    return items
        .filter(item => item.active)
        .map(item => ({
            id: item.id,
            name: item.name.toUpperCase(),
            value: item.value * 2
        }))
        .sort((a, b) => a.value - b.value);
}
```''',
    '''```rust
fn main() {
    let numbers: Vec<i32> = (1..=100).collect();
    let sum: i32 = numbers.iter().sum();
    println!("Sum: {}", sum);
}
```''',
    '''```go
package main

import "fmt"

func main() {
    ch := make(chan int, 10)
    go func() {
        for i := 0; i < 10; i++ {
            ch <- i * i
        }
        close(ch)
    }()
    for v := range ch {
        fmt.Println(v)
    }
}
```''',
    '''```python
class DataProcessor:
    def __init__(self, data):
        self.data = data

    def transform(self):
        return [x ** 2 for x in self.data if x > 0]

    def aggregate(self):
        return sum(self.transform())
```'''
]

table_samples = [
    '''| ID | Name | Status | Priority |
|---:|:-----|:------:|----------|
| 1 | Alpha | Active | High |
| 2 | Beta | Pending | Medium |
| 3 | Gamma | Done | Low |
| 4 | Delta | Active | High |''',
    '''| Metric | Q1 | Q2 | Q3 | Q4 |
|--------|----|----|----|----|
| Revenue | 100 | 120 | 140 | 160 |
| Costs | 80 | 85 | 90 | 95 |
| Profit | 20 | 35 | 50 | 65 |'''
]

sections = [template]
section_num = 3
line_count = len(template.split('\n'))

while line_count < 50000:
    section = []
    section.append(f'## Section {section_num}: Generated Content Block')
    section.append('')

    # Paragraphs with formatting
    for p in range(random.randint(2, 4)):
        section.append(f'Paragraph {p+1} with **bold text**, *italic*, `inline code`, and [links](https://example.com/{section_num}). This is filler content to test rendering performance with realistic markdown documents.')
        section.append('')

    # Lists
    section.append('### List Items')
    section.append('')
    for i in range(random.randint(3, 6)):
        section.append(f'- Item {i+1} with some content and `code`')
    section.append('')

    # Code block
    if section_num % 3 == 0:
        section.append('### Code Example')
        section.append('')
        section.append(random.choice(code_samples))
        section.append('')

    # Table
    if section_num % 4 == 0:
        section.append('### Data Table')
        section.append('')
        section.append(random.choice(table_samples))
        section.append('')

    # Blockquote
    if section_num % 5 == 0:
        section.append('> This is a blockquote with important information.')
        section.append('> It spans multiple lines for testing purposes.')
        section.append('')

    # Task list
    if section_num % 6 == 0:
        section.append('### Tasks')
        section.append('')
        section.append('- [ ] Unchecked task item')
        section.append('- [x] Checked task item')
        section.append('- [ ] Another unchecked task')
        section.append('')

    # Headings
    section.append(f'#### Subsection {section_num}.1')
    section.append('')
    section.append(f'Content for subsection {section_num}.1 with more **formatting** and details.')
    section.append('')
    section.append('---')
    section.append('')

    section_text = '\n'.join(section)
    sections.append(section_text)
    line_count += len(section)
    section_num += 1

full_doc = '\n'.join(sections)
actual_lines = len(full_doc.split('\n'))

# Append footer
full_doc += f'''

---

## Document Statistics

- **Total Lines**: {actual_lines}
- **Generated Sections**: {section_num - 1}
- **Purpose**: Performance testing for VoidReader

---

*End of test document*
'''

os.makedirs('TestDocuments', exist_ok=True)
with open('TestDocuments/large-test-50k.md', 'w') as f:
    f.write(full_doc)

final_lines = len(full_doc.split('\n'))
file_size = len(full_doc)
print(f'Generated document with {final_lines} lines')
print(f'File size: {file_size} bytes ({file_size/1024/1024:.2f} MB)')
