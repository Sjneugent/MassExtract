# MassExtract Module Documentation

## Using the Modules

### Basic Example

```perl
#!/usr/bin/perl
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/lib";

use UnrarExtractor;
use ExtractionLogger;

# Initialize logger
my $logger = ExtractionLogger->new('/path/to/log.csv');

# Create extractor with callbacks
my $extractor = UnrarExtractor->new(
    output_callback => sub {
        my ($text) = @_;
        print $text;
    }
);

# Scan for archives
my @dirs = $extractor->scan_for_archives('/path/to/search');

# Extract each archive
foreach my $dir (@dirs) {
    my %result = $extractor->extract($dir, '/output/path');
    
    if ($result{success}) {
        print "Success: $result{rar_file}\n";
        $logger->log_entry($dir, $result{rar_file}, '/output/path', 
                          'extract', 'success', '');
    } else {
        print "Failed: $result{error}\n";
        $logger->log_entry($dir, '', '/output/path',
                          'extract', 'failed', $result{error});
    }
}

$logger->close();
```

## Module APIs

### UnrarExtractor

```perl
# Constructor
my $extractor = UnrarExtractor->new(
    progress_callback => sub { my ($msg, $pct) = @_; ... },
    output_callback => sub { my ($text) = @_; ... }
);

# Scan for archives
my @dirs = $extractor->scan_for_archives($root_directory);

# Get primary RAR file
my $rar_file = $extractor->get_primary_rar_file($directory);

# Extract archive
my %result = $extractor->extract($source_dir, $dest_dir);
# Returns: (success => 1/0, rar_file => 'filename', exit_code => int, error => 'msg')

# Verify CRC
my $ok = $extractor->verify_crc($rar_path);  # Returns 1 or 0

# Delete archives
my @deleted = $extractor->delete_archives($directory);
```

### ExtractionLogger

```perl
# Constructor
my $logger = ExtractionLogger->new($log_file_path);

# Log an entry
$logger->log_entry(
    $source_dir,    # Source directory
    $rar_file,      # RAR filename
    $dest_dir,      # Destination directory
    $action,        # 'extract', 'verify', 'delete', 'scan'
    $status,        # 'success', 'failed', 'complete'
    $details        # Additional information (optional)
);

# Get log file path
my $path = $logger->get_log_file();

# Close log file
$logger->close();  # Also called automatically on destruction
```

### MassExtractGUI

```perl
# Constructor
my $gui = MassExtractGUI->new();

# Show options dialog
my %options = $gui->show_options_dialog();
# Returns: (root_dir => '...', output_dir => '...', 
#           delete_after => 0/1, log_file => '...')

# Create progress window
$gui->create_progress_window($total_directories);

# Update progress
$gui->update_progress($message, $percent);

# Update directory progress
$gui->update_directory_progress($index, $directory_name);

# Append output
$gui->append_output($text);

# Enable close button
$gui->enable_close_button();

# Show completion dialog
$gui->show_completion_dialog($message);

# Enter main loop
$gui->main_loop();
```

## Callbacks

### Progress Callback

```perl
progress_callback => sub {
    my ($message, $percent) = @_;
    # $message can be undef
    # $percent can be undef
    # Update your UI or print progress
}
```

### Output Callback

```perl
output_callback => sub {
    my ($text) = @_;
    # Handle real-time output from unrar
    # Write to GUI, log file, or stdout
}
```

## Error Handling

```perl
# Extraction errors
my %result = $extractor->extract($src, $dst);
unless ($result{success}) {
    print "Error: $result{error}\n";
    print "Exit code: $result{exit_code}\n" if exists $result{exit_code};
}

# CRC verification
if ($extractor->verify_crc($rar_path)) {
    print "CRC OK\n";
} else {
    print "CRC failed - archive may be corrupt\n";
}
```

## CSV Log Format

The log file uses the following format:

```csv
Timestamp,Source Directory,RAR File,Output Directory,Action,Status,Details
"2025-12-12 10:30:45","/path/to/source","file.rar","/path/to/dest","extract","success",""
"2025-12-12 10:31:02","/path/to/source","file.rar","/path/to/dest","verify","success","CRC check passed"
"2025-12-12 10:31:05","/path/to/source","file.rar","/path/to/dest","delete","success","Deleted: file.rar, file.r00, file.r01"
```

## Platform Compatibility

All modules are platform-independent for basic functionality:
- **UnrarExtractor**: Requires `unrar` command-line tool
- **ExtractionLogger**: Pure Perl, works everywhere
- **MassExtractGUI**: Requires Perl/Tk (install via CPAN)

### Installing Dependencies

```bash
# Ubuntu/Debian
sudo apt-get install unrar perl-tk

# macOS
brew install unrar
cpan Tk

# Windows (Strawberry Perl)
cpan Tk
# Download unrar from rarlab.com
```

## Thread Safety

**Note:** These modules are NOT thread-safe. If using with threads:
- Create separate instances per thread
- Don't share logger instances
- Don't share GUI objects
