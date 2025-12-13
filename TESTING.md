# MassExtract Testing Documentation

## Overview

MassExtract includes a comprehensive test suite using Perl's Test::More framework. The tests ensure all core functionality works correctly and handles edge cases properly.

## Test Structure

```
MassExtract/
├── run_tests.pl              # Test runner script
└── t/                        # Test directory
    ├── lib/
    │   └── TestHelper.pm     # Test utilities and fixtures
    ├── 01-command-line.t     # CLI option parsing tests
    ├── 02-extractor.t        # UnrarExtractor module tests
    ├── 03-logger.t           # ExtractionLogger module tests
    ├── 04-error-handling.t   # Error scenarios and edge cases
    └── 05-gui-cli-equivalence.t  # GUI/CLI compatibility tests
```

## Running Tests

### Run All Tests

```bash
./run_tests.pl
```

### Run Individual Test

```bash
perl t/01-command-line.t
```

### Run Specific Test with Verbose Output

```bash
prove -v t/02-extractor.t
```

## Test Coverage

### 01-command-line.t (15 tests)

**Purpose:** Validates command-line argument parsing and error handling

**Tests:**
- Script exists and is executable
- Help option displays usage information
- All command-line options are documented
- Missing required arguments produce errors
- Invalid directories are rejected
- Empty directories are handled gracefully

**Example:**
```bash
# These should all be tested
./mass_extract.pl --help
./mass_extract.pl                    # Missing -r
./mass_extract.pl -r /invalid/path   # Invalid directory
./mass_extract.pl -r /empty/dir      # Valid but empty
```

### 02-extractor.t (25 tests)

**Purpose:** Tests UnrarExtractor module core functionality

**Tests:**
- Constructor with and without callbacks
- Archive scanning in directory trees
- Primary RAR file identification (.part1.rar vs .rar)
- Extraction to different directories
- In-place extraction
- CRC verification
- Archive deletion after extraction
- Content integrity verification

**Key Scenarios:**
```perl
# Test extraction
my $extractor = UnrarExtractor->new();
my @dirs = $extractor->scan_for_archives($root);
my %result = $extractor->extract($source, $dest);

# Test CRC
my $ok = $extractor->verify_crc($rar_path);

# Test deletion
my @deleted = $extractor->delete_archives($dir);
```

### 03-logger.t (15 tests)

**Purpose:** Validates CSV logging functionality

**Tests:**
- Logger creation with and without file
- CSV header generation
- Log entry writing
- CSV field quoting and escaping
- Handling quotes and commas in data
- File handle management

**Example Log Format:**
```csv
"2025-12-12 10:30:45","/source",file.rar","/dest","extract","success",""
"2025-12-12 10:31:02","/source","file.rar","/dest","verify","success","CRC OK"
```

### 04-error-handling.t (12 tests)

**Purpose:** Tests error conditions and edge cases

**Scenarios Tested:**

#### 1. Corrupt RAR File
```perl
# Creates invalid RAR with correct magic bytes
# Tests that extraction fails gracefully
my %result = $extractor->extract($corrupt_dir, $output);
ok(!$result{success}, 'Corrupt extraction fails');
```

#### 2. CRC Verification on Corrupt Files
```perl
# Verifies that CRC check detects corruption
my $ok = $extractor->verify_crc($corrupt_rar);
ok(!$ok, 'CRC fails for corrupt file');
```

#### 3. Extracting Over Existing Files
```perl
# Creates existing file in destination
# Tests that extraction overwrites (unrar -o+ flag)
ok(-f "$dest/file.txt", 'File exists before');
$extractor->extract($source, $dest);
# Verifies new content replaced old content
```

#### 4. Nested Directory Creation
```perl
# Tests extraction to non-existent nested path
my $deep_path = "$test/nested/deep/output";
ok(!-d $deep_path, 'Path does not exist');
$extractor->extract($source, $deep_path);
ok(-d $deep_path, 'Path created automatically');
```

### 05-gui-cli-equivalence.t (10 tests)

**Purpose:** Ensures GUI and CLI produce identical results

**Tests:**
- CLI extraction produces correct output
- Module-based extraction (as GUI uses) works correctly
- Both approaches create valid log files
- Log file formats match
- File extraction results are identical

**Comparison:**
```perl
# CLI approach
system("./mass_extract.pl -r $source -o $dest -l $log");

# Module approach (GUI equivalent)
my $extractor = UnrarExtractor->new();
my @dirs = $extractor->scan_for_archives($source);
foreach my $dir (@dirs) {
    $extractor->extract($dir, $dest);
}

# Both should produce identical results
```

## Test Utilities (TestHelper.pm)

### Available Functions

#### create_test_dir()
Creates a temporary directory for testing
```perl
my $dir = create_test_dir();
```

#### cleanup_test_dir($dir)
Removes test directory and contents
```perl
cleanup_test_dir($dir);
```

#### create_test_rar($dir, $name, $content)
Creates a simple test RAR archive
```perl
my $rar = create_test_rar($test_dir, 'test', 'content');
```

#### create_corrupt_rar($dir, $name)
Creates a corrupt RAR for error testing
```perl
my $corrupt = create_corrupt_rar($test_dir, 'bad');
```

#### create_multipart_rar($dir, $name, $num_parts)
Creates a multi-part split RAR archive
```perl
my $rar = create_multipart_rar($test_dir, 'split', 3);
```

## Dependencies

### Required
- Perl 5.10 or higher
- Test::More (core module)
- unrar (for extraction tests)
- rar (for creating test archives)

### Installing Dependencies

**Ubuntu/Debian:**
```bash
sudo apt-get install unrar rar
```

**macOS:**
```bash
brew install unrar rar
```

**Check Installation:**
```bash
which unrar && which rar
```

## Skipping Tests

Tests automatically skip if dependencies are unavailable:

```perl
eval {
    my $check = `unrar 2>&1`;
    die "unrar not found" unless defined $check;
};

if ($@) {
    plan skip_all => "unrar not available: $@";
}
```

GUI tests skip if Tk unavailable or no DISPLAY:
```perl
eval {
    require Tk;
    die "DISPLAY not set" unless $ENV{DISPLAY};
};

if ($@) {
    plan skip_all => "Tk not available or no display: $@";
}
```

## Test Results

### Success Output
```
======================================================================
MassExtract Test Suite
======================================================================

Found 5 test file(s)

----------------------------------------------------------------------
Running: 01-command-line.t
----------------------------------------------------------------------
ok 1 - mass_extract.pl exists
ok 2 - mass_extract.pl is executable
...
✓ PASSED: 01-command-line.t

...

======================================================================
Test Summary
======================================================================
Passed: 5
Failed: 0
Total:  5
======================================================================
```

### Failure Output
```
not ok 5 - Extraction succeeds
#   Failed test 'Extraction succeeds'
#   at t/02-extractor.t line 125.

✗ FAILED: 02-extractor.t (exit code: 1)
```

## Adding New Tests

### Template for New Test File

```perl
#!/usr/bin/perl

use strict;
use warnings;
use Test::More tests => 5;  # Or use Test::More; for dynamic
use FindBin qw($Bin);
use lib "$Bin/../lib";
use lib "$Bin/lib";

use UnrarExtractor;
use TestHelper qw(create_test_dir cleanup_test_dir);

# Test 1
{
    my $test_dir = create_test_dir();
    
    # Your test code here
    ok(1, 'Test description');
    
    cleanup_test_dir($test_dir);
}

# Test 2
{
    # More tests...
}

done_testing();  # If using dynamic test count
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Run Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v2
    
    - name: Install dependencies
      run: |
        sudo apt-get update
        sudo apt-get install -y unrar rar perl
    
    - name: Run tests
      run: ./run_tests.pl
```

## Troubleshooting

### Tests Fail with "unrar not found"
```bash
# Install unrar
sudo apt-get install unrar

# Or skip those tests
SKIP_UNRAR=1 ./run_tests.pl
```

### GUI Tests Fail
```bash
# Set DISPLAY for X11
export DISPLAY=:0

# Or run without GUI tests
prove t/01-command-line.t t/02-extractor.t t/03-logger.t
```

### Temporary Directories Not Cleaned
```bash
# Find orphaned test directories
find /tmp -name "tmp*" -type d -user $USER

# Clean manually if needed
rm -rf /tmp/tmp*
```

## Best Practices

1. **Always clean up** - Use cleanup_test_dir() in tests
2. **Use temp directories** - Never test in actual user directories
3. **Test edge cases** - Empty files, missing permissions, corrupt data
4. **Isolate tests** - Each test should be independent
5. **Descriptive names** - Test descriptions should be clear
6. **Skip gracefully** - Handle missing dependencies properly

## Future Test Ideas

- Performance tests (large archives)
- Concurrent extraction tests
- Permission/security tests
- Network path tests
- Unicode filename tests
- Very large file tests (>4GB)
- Memory leak tests
