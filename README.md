# MassExtract

A Perl script to iterate through a root directory looking for split-volume RAR archives and extract them.

## Usage

```bash
mass_extract.pl [OPTIONS]
```

## Options

| Option | Description |
|--------|-------------|
| `-r, --root <dir>` | Root directory to recursively search for RAR archives (required) |
| `-o, --output <dir>` | Output directory for extracted files (default: extract in place) |
| `-d, --delete` | Delete RAR files after successful extraction and CRC verification |
| `-l, --log <file>` | Write extraction log to CSV file |
| `-h, --help` | Show help message |
| `-g, --gui` | Launch GUI for selecting options |

## Examples

Extract in place:
```bash
./mass_extract.pl -r ~/downloads
```

Extract to a different directory:
```bash
./mass_extract.pl -r ~/downloads -o ~/movies
```

Extract, verify, and delete original RAR files:
```bash
./mass_extract.pl -r ~/downloads -o ~/movies -d
```

Extract with logging:
```bash
./mass_extract.pl -r ~/downloads -o ~/movies -d -l extraction.log
```

Launch GUI mode:
```bash
./mass_extract.pl -g
```

## GUI Mode

When launched with the `-g` option, the script provides a graphical user interface:

1. **Options Window**: First, a window appears allowing you to:
   - Browse and select the root directory
   - Browse and select an output directory (optional)
   - Enable deletion of RAR files after extraction
   - Select a log file location (optional)

2. **Progress Window**: During extraction, a progress window displays:
   - A progress bar showing overall extraction progress
   - Current directory being processed
   - Real-time output from the unrar command
   - Extraction status messages

The progress window keeps you informed about which archives are being extracted and shows the actual unrar command output as it happens.

## Log Format

When using the `-l` option, a CSV log is created with the following columns:
- **Timestamp**: When the action occurred
- **Source Directory**: Directory containing the RAR files
- **RAR File**: Name of the RAR archive
- **Output Directory**: Where files were extracted to
- **Action**: Type of action (extract, verify, delete, scan)
- **Status**: Result (success, failed, complete)
- **Details**: Additional information about the action

## Directory Structure

The script preserves directory structure when using the `-o` option:

```
Source: ~/downloads/movies/action/movie1/*.rar
Output: ~/output/movies/action/movie1/extracted_files
```

## Supported Archive Formats

- `.rar` files (main archive)
- `.r00`, `.r01`, etc. (old-style split volumes)
- `.part1.rar`, `.part2.rar`, etc. (new-style split volumes)

## Requirements

- Perl 5 with the following modules:
  - File::Find (core)
  - File::Copy (core)
  - File::Basename (core)
  - File::Path (core)
  - Cwd (core)
  - Getopt::Long (core)
  - POSIX (core)
  - Tk (for GUI mode)
  - Tk::ProgressBar (for GUI mode)
- `unrar` command-line tool
