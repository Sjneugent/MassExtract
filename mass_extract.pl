#!/usr/bin/perl -w

=head1 NAME

mass_extract.pl - Batch extraction tool for split-volume RAR archives

=head1 SYNOPSIS

    mass_extract.pl [OPTIONS]
    
    # Command line mode
    mass_extract.pl -r ~/downloads
    mass_extract.pl -r ~/downloads -o ~/movies -d -l extraction.log
    
    # GUI mode
    mass_extract.pl -g

=head1 DESCRIPTION

MassExtract is a Perl script that recursively searches a directory tree for
split-volume RAR archives and extracts them. It supports both old-style
(.rar, .r00, .r01, etc.) and new-style (.part1.rar, .part2.rar, etc.) 
split archives.

The script can operate in two modes:

=over 4

=item * B<Command Line Mode> - Specify options via command line arguments

=item * B<GUI Mode> - Use a graphical interface to select options and monitor progress

=back

=head1 OPTIONS

=over 4

=item B<-r, --root> I<directory>

Root directory to recursively search for RAR archives. This option is required
unless using GUI mode.

=item B<-o, --output> I<directory>

Output directory for extracted files. If not specified, files are extracted
in place (same directory as the source archive). The directory structure
relative to the root is preserved.

=item B<-d, --delete>

Delete RAR archive files after successful extraction and CRC verification.
Archives are only deleted if the CRC check passes.

=item B<-l, --log> I<file>

Write extraction log to the specified CSV file. The log includes timestamps,
source directories, archive names, actions taken, and status information.

=item B<-g, --gui>

Launch the graphical user interface for selecting options. In GUI mode,
a progress bar and real-time extraction output are displayed.

=item B<-h, --help>

Display usage information and exit.

=back

=head1 GUI MODE FEATURES

When running in GUI mode (-g), the application provides:

=over 4

=item * B<Options Window> - Browse and select directories, configure extraction options

=item * B<Progress Bar> - Visual indication of overall extraction progress

=item * B<Real-time Output> - Live display of unrar command output as extraction proceeds

=item * B<Status Updates> - Current directory being processed and completion status

=back

=head1 SUPPORTED ARCHIVE FORMATS

=over 4

=item * C<.rar> - Main RAR archive files

=item * C<.r00>, C<.r01>, etc. - Old-style split volume extensions

=item * C<.part1.rar>, C<.part2.rar>, etc. - New-style split volume naming

=back

=head1 DEPENDENCIES

=head2 Perl Modules

=over 4

=item * File::Find - Directory tree traversal (core module)

=item * File::Copy - File copying operations (core module)

=item * File::Basename - Path parsing utilities (core module)

=item * File::Path - Directory creation (core module)

=item * Cwd - Current working directory utilities (core module)

=item * Getopt::Long - Command line option parsing (core module)

=item * POSIX - POSIX functions for timestamps (core module)

=item * Tk - Perl/Tk GUI toolkit (required for GUI mode)

=item * Tk::ProgressBar - Progress bar widget (required for GUI mode)

=back

=head2 External Programs

=over 4

=item * B<unrar> - Command line RAR extraction utility

=back

=head1 LOG FILE FORMAT

When using the -l option, a CSV log file is created with the following columns:

    Timestamp,Source Directory,RAR File,Output Directory,Action,Status,Details

Actions include: extract, verify, delete, scan
Status values: success, failed, complete

=head1 EXIT STATUS

=over 4

=item 0 - Success

=item 1 - Error (missing required options, invalid directories, etc.)

=back

=head1 EXAMPLES

Extract all archives in place:

    mass_extract.pl -r ~/downloads

Extract to a different directory:

    mass_extract.pl -r ~/downloads -o ~/extracted

Extract, verify, and delete original archives:

    mass_extract.pl -r ~/downloads -o ~/extracted -d

Extract with logging:

    mass_extract.pl -r ~/downloads -o ~/extracted -d -l ~/extraction.log

Use the graphical interface:

    mass_extract.pl -g

=head1 AUTHOR

MassExtract Contributors

=head1 LICENSE

This software is released under the same terms as Perl itself.

=cut

use strict;
use File::Find;
use File::Copy;
use File::Basename;
use File::Path qw(make_path);
use Cwd 'abs_path';
use Getopt::Long;
use POSIX qw(strftime);
use Tk;
use Tk::ProgressBar;

#=============================================================================
# GLOBAL CONFIGURATION VARIABLES
#=============================================================================

# Command line options - populated by GetOptions or GUI
my $root_dir = '';       # Root directory to search for RAR archives
my $output_dir = '';     # Output directory for extracted files (optional)
my $delete_after = 0;    # Flag: delete archives after successful extraction
my $log_file = '';       # Path to CSV log file (optional)
my $help = 0;            # Flag: show help and exit
my $gui = 0;             # Flag: use GUI mode

#=============================================================================
# GUI PROGRESS WINDOW VARIABLES
#=============================================================================

# These variables hold references to Tk widgets for the progress window
# They are initialized when create_progress_window() is called in GUI mode

my $progress_window;     # Main progress window (Tk::MainWindow)
my $progress_bar;        # Progress bar widget (Tk::ProgressBar)
my $progress_label;      # Label showing current operation
my $output_text;         # Scrolled text widget for real-time output
my $close_button;        # Close button (disabled during extraction)
my $progress_value = 0;  # Current progress percentage (0-100)
my $total_dirs = 0;      # Total number of directories to process
my $current_dir_index = 0;  # Index of currently processing directory

#=============================================================================
# COMMAND LINE ARGUMENT PARSING
#=============================================================================

# Parse command line options using Getopt::Long
# Options can use either short (-r) or long (--root) format
GetOptions(
    'root|r=s'    => \$root_dir,     # -r or --root: root search directory
    'output|o=s'  => \$output_dir,   # -o or --output: extraction destination
    'delete|d'    => \$delete_after, # -d or --delete: remove archives after extraction
    'log|l=s'     => \$log_file,     # -l or --log: CSV log file path
    'help|h'      => \$help,         # -h or --help: show usage
    'gui|g'       => \$gui,          # -g or --gui: enable GUI mode
) or die "Error in command line arguments. Use --help for usage.\n";

# Display help and exit if requested
if ($help) {
    print_usage();
    exit 0;
}

#=============================================================================
# GUI OPTIONS WINDOW
#=============================================================================
# When GUI mode is enabled, display a window for the user to configure
# extraction options before processing begins.

if ($gui) {
    my $MW = MainWindow->new;
    $MW->title("Mass RAR Extractor Options");
    
    # Root directory selection (required)
    $MW->Label(-text => "Select Root Directory:")->pack();
    my $root_entry = $MW->Entry(-width => 50);
    $root_entry->pack();
    $MW->Button(-text => "Browse", -command => sub {
        my $dir = $MW->chooseDirectory(-title => "Select Root Directory");
        $root_entry->delete(0, 'end');
        $root_entry->insert(0, $dir) if defined $dir;
    })->pack();
    
    # Output directory selection (optional - defaults to in-place extraction)
    $MW->Label(-text => "Select Output Directory (optional):")->pack();
    my $output_entry = $MW->Entry(-width => 50);
    $output_entry->pack();
    $MW->Button(-text => "Browse", -command => sub {
        my $dir = $MW->chooseDirectory(-title => "Select Output Directory");
        $output_entry->delete(0, 'end');
        $output_entry->insert(0, $dir) if defined $dir;
    })->pack();
    
    # Delete after extraction checkbox
    my $delete_var = 0;
    $MW->Checkbutton(
        -text => "Delete RAR files after extraction",
        -variable => \$delete_var
    )->pack();
    
    # Log file selection (optional)
    $MW->Label(-text => "Log File (optional):")->pack();
    my $log_entry = $MW->Entry(-width => 50);
    $log_entry->pack();
    $MW->Button(-text => "Browse", -command => sub {
        my $file = $MW->getSaveFile(
            -title => "Select Log File",
            -defaultextension => '.csv',
            -filetypes => [['CSV Files', '.csv'], ['All Files', '.*']]
        );
        $log_entry->delete(0, 'end');
        $log_entry->insert(0, $file) if defined $file;
    })->pack();
    
    # Start button - captures values and closes options window
    $MW->Button(-text => "Start Extraction", -command => sub {
        $root_dir = $root_entry->get();
        $output_dir = $output_entry->get();
        $delete_after = $delete_var;
        $log_file = $log_entry->get();
        $MW->destroy();  # Close options window to proceed with extraction
    })->pack();
    
    MainLoop;  # Wait for user to configure options and click Start
}

#=============================================================================
# INPUT VALIDATION
#=============================================================================

# Verify that a root directory was specified (required)
unless ($root_dir) {
    print STDERR "Error: Root directory is required. Use -r or --root to specify.\n";
    print_usage();
    exit 1;
}

# Expand tilde (~) to home directory if present
$root_dir = glob($root_dir) if $root_dir =~ /^~/;
# Convert to absolute path for consistent handling
$root_dir = abs_path($root_dir);

# Verify the root directory exists
unless (-d $root_dir) {
    die "Error: Root directory '$root_dir' does not exist.\n";
}

# If output directory specified, validate and create if needed
if ($output_dir) {
    print "Line 330 => $output_dir\n";
    $output_dir = glob($output_dir) if $output_dir =~ /^~/;
    $output_dir = abs_path($output_dir);
    unless (-d $output_dir) {
        make_path($output_dir) or die "Error: Cannot create output directory '$output_dir': $!\n";
    }
}

#=============================================================================
# LOG FILE INITIALIZATION
#=============================================================================

my $log_fh;  # File handle for CSV log file
if ($log_file) {
    $log_file = glob($log_file) if $log_file =~ /^~/;
    open($log_fh, '>>', $log_file) or die "Error: Cannot open log file '$log_file': $!\n";
    # Write CSV header if file is empty (new file)
    if (!-s $log_file) {
        print $log_fh "Timestamp,Source Directory,RAR File,Output Directory,Action,Status,Details\n";
    }
}

#=============================================================================
# MAIN PROGRAM EXECUTION
#=============================================================================

# Scan for directories containing split RAR archives
my @dirs = iterate_movies($root_dir);

if (@dirs == 0) {
    # No archives found - inform user and exit
    print "No RAR archives found in '$root_dir'\n";
    log_entry($root_dir, '', '', 'scan', 'complete', 'No archives found');
    
    if ($gui) {
        # Show message dialog in GUI mode
        my $msg_win = MainWindow->new;
        $msg_win->title("Mass RAR Extractor - Complete");
        $msg_win->Label(
            -text => "No RAR archives found in:\n$root_dir",
            -justify => 'center'
        )->pack(-padx => 20, -pady => 15);
        $msg_win->Button(
            -text => "OK",
            -width => 10,
            -command => sub { $msg_win->destroy(); }
        )->pack(-pady => 10);
        $msg_win->update();
        MainLoop;
    }
} else {

    # Archives found - process each directory
    $total_dirs = scalar(@dirs);
    append_output("Found $total_dirs directories with RAR archives.\n");
    
    # Create progress window for GUI mode
    if ($gui) {
        create_progress_window();
    }
    
    # Process each directory containing archives
    $current_dir_index = 0;
    foreach my $source_dir (@dirs) {
        my $dest_dir;
        
        # Determine destination directory
        # If output_dir specified, preserve relative path structure
        if ($output_dir) {
            print "Line 1091 source_dir=$source_dir\troot_dir=$root_dir\toutput_dir=$output_dir\n";
            # Use File::Spec or manual path computation to get relative path
            my $relative = $source_dir;
            # Ensure root_dir ends without trailing slash for consistent matching
            my $root_normalized = $root_dir;
            $root_normalized =~ s/\/$//;
            $relative =~ s/^\Q$root_normalized\E\/?//;  # Remove root prefix
            print "$relative\n";
            $dest_dir = $relative ? "$output_dir/$relative" : $output_dir;
            print "new dest_dir=$dest_dir\trelative=$relative\t$output_dir/$relative\n";
        } else {
            # Extract in place
            $dest_dir = $source_dir;
        }
        # Update progress bar with current directory info
        my $percent = ($current_dir_index / $total_dirs) * 100;
        update_progress("Processing ($current_dir_index/$total_dirs): " . basename($source_dir), $percent);
        
        append_output("\nProcessing: $source_dir\n");
        append_output("  -> Extracting to: $dest_dir\n");
        
        # Perform extraction and report result
        print "1108 extract_rar($source_dir, $dest_dir)\n";
        if (extract_rar($source_dir, $dest_dir)) {
            append_output("  -> Extraction SUCCESS\n");
        } else {
            append_output("  -> Extraction FAILED\n");
        }
        
        $current_dir_index++;
        
    }
    
    # Update progress to 100% when complete
    update_progress("Extraction complete!", 100);
    
    # Enable close button and wait for user to close the window
    if ($gui && $progress_window) {
        enable_close_button();
        MainLoop;  # Keep window open until user closes it
    }
}

#=============================================================================
# CLEANUP
#=============================================================================

# Close log file if it was opened
if ($log_fh) {
    close($log_fh);
    append_output("\nLog written to: $log_file\n");
}

#=============================================================================
# UTILITY FUNCTIONS
#=============================================================================

=head2 print_usage()

Displays command line usage information to STDOUT.

This function prints a summary of available command line options and
example usage patterns. Called when -h or --help is specified, or
when required arguments are missing.

=cut

sub print_usage {
    print <<'USAGE';
Usage: mass_extract.pl [OPTIONS]

Options:
  -r, --root <dir>    Root directory to recursively search for RAR archives (required)
  -o, --output <dir>  Output directory for extracted files (default: extract in place)
  -d, --delete        Delete RAR files after successful extraction and CRC verification
  -l, --log <file>    Write extraction log to CSV file
  -h, --help          Show this help message
  -g, --gui           Launch GUI for selecting options
Examples:
  mass_extract.pl -r ~/downloads
  mass_extract.pl -r ~/downloads -o ~/movies
  mass_extract.pl -r ~/downloads -o ~/movies -d
  mass_extract.pl -r ~/downloads -o ~/movies -d -l extraction.log
  mass_extract.pl -g # Launch GUI
USAGE
}

=head2 shell_escape($string)

Safely escapes a string for use in shell commands.

This function wraps the string in single quotes and escapes any
embedded single quotes using the '\'' technique. This prevents
command injection attacks when passing user-provided paths to
shell commands.

B<Parameters:>

=over 4

=item $string - The string to escape

=back

B<Returns:> The escaped string, wrapped in single quotes

B<Example:>

    my $safe_path = shell_escape("/path/with spaces/and'quotes");
    # Returns: '/path/with spaces/and'\''quotes'

=cut

sub shell_escape {
    my ($str) = @_;
    $str =~ s/'/'\\''/g;  # Replace ' with '\'' (end quote, escaped quote, start quote)
    return "'$str'";
}

#=============================================================================
# GUI PROGRESS WINDOW FUNCTIONS
#=============================================================================

=head2 create_progress_window()

Creates and displays the extraction progress window for GUI mode.

This function initializes a Tk window containing:

=over 4

=item * A label showing the current operation/directory

=item * A progress bar indicating overall completion percentage

=item * A scrolled text widget displaying real-time unrar output

=item * A close button (initially disabled, enabled upon completion)

=back

The window is 700x500 pixels and uses a blue progress bar.

=cut

sub create_progress_window {
    $progress_window = MainWindow->new;
    $progress_window->title("Mass RAR Extractor - Progress");
    $progress_window->geometry("700x500");
    
    # Progress label showing current file
    $progress_label = $progress_window->Label(
        -text => "Initializing...",
        -font => [-size => 10, -weight => 'bold']
    )->pack(-pady => 10, -padx => 10, -fill => 'x');
    
    # Progress bar
    $progress_bar = $progress_window->ProgressBar(
        -width => 30,
        -length => 650,
        -from => 0,
        -to => 100,
        -variable => \$progress_value,
        -colors => [0, 'blue']
    )->pack(-pady => 10, -padx => 10);
    
    # Scrolled text widget for realtime output
    my $output_frame = $progress_window->Frame()->pack(-fill => 'both', -expand => 1, -padx => 10, -pady => 5);
    $output_frame->Label(-text => "Extraction Output:")->pack(-anchor => 'w');
    
    $output_text = $output_frame->Scrolled('Text',
        -scrollbars => 'e',
        -height => 20,
        -width => 80,
        -font => ['Courier', 9],
        -state => 'normal',
        -wrap => 'word'
    )->pack(-fill => 'both', -expand => 1);
    
    # Close button (disabled until extraction is complete)
    $close_button = $progress_window->Button(
        -text => "Close",
        -state => 'disabled',
        -command => sub { $progress_window->destroy(); }
    )->pack(-pady => 10);
    
    $progress_window->update();
}

=head2 update_progress($message, $percent)

Updates the progress window with new status information.

B<Parameters:>

=over 4

=item $message - (optional) New text for the progress label

=item $percent - (optional) New progress percentage (0-100)

=back

Either parameter can be undef to leave that element unchanged.
This function does nothing if not in GUI mode.

=cut

sub update_progress {
    my ($message, $percent) = @_;
    return unless $gui && $progress_window;
    
    # Update the status label if a new message was provided
    if (defined $message) {
        $progress_label->configure(-text => $message);
    }
    
    # Update the progress bar percentage if provided
    if (defined $percent) {
        $progress_value = $percent;
    }
    
    # Force immediate GUI update to ensure responsiveness
    $progress_window->update();
}

=head2 append_output($text)

Appends text to the output display and console.

This function writes text to both the GUI output text widget (if in GUI mode)
and to STDOUT. This ensures output is visible regardless of the execution mode.

B<Parameters:>

=over 4

=item $text - The text to append

=back

=cut

sub append_output {
    my ($text) = @_;
    
    # In GUI mode, append to the scrolled text widget
    if ($gui && $output_text) {
        $output_text->insert('end', $text);
        $output_text->see('end');  # Auto-scroll to show new content
        $progress_window->update();
    }
    
    # Always print to console for logging/debugging
    print $text;
}

=head2 enable_close_button()

Enables the close button on the progress window.

This function is called when extraction is complete to allow the user
to close the progress window. The button is disabled during extraction
to prevent premature closure.

=cut

sub enable_close_button {
    return unless $gui && $progress_window && $close_button;
    $close_button->configure(-state => 'normal');
    $progress_window->update();
}

#=============================================================================
# LOGGING FUNCTIONS
#=============================================================================

=head2 log_entry($source_dir, $rar_file, $dest_dir, $action, $status, $details)

Writes a log entry to the CSV log file.

This function appends a timestamped entry to the log file (if logging is enabled).
All fields are properly quoted for CSV format, and embedded quotes are escaped.

B<Parameters:>

=over 4

=item $source_dir - Directory containing the source archive

=item $rar_file - Name of the RAR archive file

=item $dest_dir - Destination directory for extracted files

=item $action - Type of action (extract, verify, delete, scan)

=item $status - Result status (success, failed, complete)

=item $details - Additional details or error messages

=back

=cut

sub log_entry {
    my ($source_dir, $rar_file, $dest_dir, $action, $status, $details) = @_;
    return unless $log_fh;  # Skip if logging not enabled
    
    my $timestamp = strftime("%Y-%m-%d %H:%M:%S", localtime);
    $details //= '';
    $details =~ s/"/""/g;  # Escape embedded quotes for CSV
    
    # Build CSV line with all fields quoted
    my @fields = ($timestamp, $source_dir, $rar_file, $dest_dir, $action, $status, $details);
    my $line = join(',', map { '"' . $_ . '"' } @fields);
    print $log_fh "$line\n";
}

#=============================================================================
# DIRECTORY SCANNING FUNCTIONS
#=============================================================================

=head2 iterate_movies($search_dir)

Recursively searches for directories containing split RAR archives.

This function traverses the directory tree starting at $search_dir and
identifies directories that contain split-volume RAR archives. A directory
is considered to have a split archive if it contains:

=over 4

=item * Two or more .rar files, OR

=item * At least one .rar file AND one or more .r## (old-style volume) files

=back

B<Parameters:>

=over 4

=item $search_dir - Root directory to begin searching

=back

B<Returns:> Array of directory paths containing split archives

=cut

sub iterate_movies {
    my $search_dir = shift;
    my %rar_counts;   # Count of .rar files per directory
    my %part_counts;  # Count of .r## files per directory
    my @results;

    # Traverse directory tree counting archive files
    find(sub { 
        return unless -f $_;
        if (/\.rar$/i) { $rar_counts{$File::Find::dir}++ }
        elsif (/\.r\d{2}$/i) { $part_counts{$File::Find::dir}++ }
    }, $search_dir);

    # Combine keys from both hashes, ensuring uniqueness
    # This prevents processing the same directory twice
    my %all_dirs;
    $all_dirs{$_} = 1 for keys %rar_counts;
    $all_dirs{$_} = 1 for keys %part_counts;
    
    # Filter to only directories with split archives
    foreach my $dir (keys %all_dirs) {
        my $rar_count = $rar_counts{$dir} // 0;
        my $part_count = $part_counts{$dir} // 0;

        # Include if: multiple .rar files OR (.rar + .r## files)
        if ($rar_count >= 2 || ($rar_count >= 1 && $part_count >= 1)) {
            push @results, $dir;
        }
    }
    return @results;
}

=head2 get_rar_files($dir)

Finds the primary RAR archive file(s) in a directory.

This function scans a directory for .rar files and returns the ones that
should be used to start extraction. It prioritizes:

=over 4

=item 1. Files matching .part1.rar (first part of new-style split archives)

=item 2. Files NOT matching .partN.rar pattern (standalone or old-style archives)

=back

B<Parameters:>

=over 4

=item $dir - Directory to scan

=back

B<Returns:> Array of RAR filenames suitable for extraction

=cut

sub get_rar_files {
    my ($dir) = @_;
    my @rar_files;         # All .rar files found
    my @first_part_files;  # Files that should be extraction starting points
    
    opendir(my $dh, $dir) or do {
        warn "Cannot open directory '$dir': $!\n";
        return;
    };
    
    while (my $file = readdir($dh)) {
        if ($file =~ /\.rar$/i && -f "$dir/$file") {
            push @rar_files, $file;
            # Identify extraction starting points:
            # - .part1.rar (first part of new naming scheme)
            # - .rar without .partX (standalone or old-style first file)
            if ($file =~ /\.part1\.rar$/i || $file !~ /\.part\d+\.rar$/i) {
                push @first_part_files, $file;
            }
        }
    }
    closedir($dh);
    
    # Prefer first part files (extraction starting points),
    # fall back to all RAR files if none identified
    return @first_part_files if @first_part_files;
    return @rar_files;
}

=head2 get_part_files($dir)

Finds old-style split volume files (.r00, .r01, etc.) in a directory.

B<Parameters:>

=over 4

=item $dir - Directory to scan

=back

B<Returns:> Array of part filenames

=cut

sub get_part_files {
    my ($dir) = @_;
    my @part_files;
    
    opendir(my $dh, $dir) or return;
    
    while (my $file = readdir($dh)) {
        # Match old-style volume extensions: .r00, .r01, .r02, etc.
        if ($file =~ /\.r\d{2}$/i && -f "$dir/$file") {
            push @part_files, $file;
        }
    }
    closedir($dh);
    
    return @part_files;
}

#=============================================================================
# EXTRACTION FUNCTIONS
#=============================================================================

=head2 verify_extraction_crc($rar_path)

Verifies the integrity of a RAR archive using CRC checking.

This function runs 'unrar t' (test) on the archive to verify that all
files can be extracted without errors. It handles both standard unrar
(which outputs "All OK") and unrar-free (which may not output that message).

B<Parameters:>

=over 4

=item $rar_path - Full path to the RAR archive

=back

B<Returns:> 1 if verification passed, 0 if failed

=cut

sub verify_extraction_crc {
    my ($rar_path) = @_;
    
    my $escaped_path = shell_escape($rar_path);
    my $output = `unrar t $escaped_path 2>&1`;
    my $exit_code = $? >> 8;
    
    # Handle both standard unrar ("All OK") and unrar-free (exit code 0 without errors)
    if ($exit_code == 0) {
        # Check for success indicators or absence of failure indicators
        if ($output =~ /All OK/i || $output !~ /(error|failed|corrupt|bad|cannot)/i) {
            return 1;
        }
    }
    return 0;
}

=head2 delete_rar_files($dir)

Deletes all RAR archive files from a directory.

This function removes both .rar files and old-style .r## volume files
from the specified directory. It should only be called after successful
extraction and CRC verification.

B<Parameters:>

=over 4

=item $dir - Directory containing archive files to delete

=back

B<Returns:> Array of deleted filenames

=cut

sub delete_rar_files {
    my ($dir) = @_;
    my @deleted;
    
    opendir(my $dh, $dir) or do {
        warn "Cannot open directory '$dir' for deletion: $!\n";
        return @deleted;
    };
    
    while (my $file = readdir($dh)) {
        # Match .rar files and old-style .r## volume files
        if (($file =~ /\.rar$/i || $file =~ /\.r\d{2}$/i) && -f "$dir/$file") {
            my $full_path = "$dir/$file";
            if (unlink($full_path)) {
                push @deleted, $file;
            } else {
                warn "Failed to delete '$full_path': $!\n";
            }
        }
    }
    closedir($dh);
    
    return @deleted;
}

=head2 run_unrar_with_output($rar_path, $dest_dir)

Executes the unrar command with real-time output capture.

This function runs unrar to extract the archive and captures the output
line-by-line, displaying it in the GUI (if enabled) and on the console.
It also parses progress percentages from the unrar output to update
the progress bar.

B<Parameters:>

=over 4

=item $rar_path - Full path to the RAR archive (will be escaped)

=item $dest_dir - Destination directory for extracted files (will be escaped)

=back

B<Returns:> Exit code from unrar (0 = success)

B<Note:> The -o+ flag tells unrar to overwrite existing files without prompting.

=cut

sub run_unrar_with_output {
    my ($rar_path, $dest_dir) = @_;
    print "Line 883 run_unrar_with_output: Extracting '$rar_path' to '$dest_dir'\n";
    # Shell-escape paths for safe command execution
    my $escaped_rar = shell_escape($rar_path);
    my $escaped_dest = shell_escape($dest_dir);
    print "$escaped_dest\n";
    # Build command: x=extract with paths, -o+=overwrite, redirect stderr to stdout
    my $cmd = "unrar x -o+ $escaped_rar $escaped_dest 2>&1";
    print "LINE 890 $cmd\n\n\n";
    # Open pipe to read unrar output in realtime
    my $pid = open(my $unrar_fh, '-|', $cmd);
    
    if (!defined $pid) {
        append_output("Failed to execute unrar: $!\n");
        return -1;
    }
    
    # Read output line by line and display in realtime
    while (my $line = <$unrar_fh>) {
        append_output($line);
        
        # Parse progress percentage from unrar output if available
        # Standard unrar shows progress like "...         5%"
        if ($line =~ /(\d+)%/) {
            my $file_percent = $1;
            # Calculate overall progress based on current directory and file progress
            if ($total_dirs > 0) {
                my $dir_progress = ($current_dir_index / $total_dirs) * 100;
                my $file_contribution = ($file_percent / $total_dirs);
                update_progress(undef, $dir_progress + $file_contribution);
            }
        }
        
        # Keep GUI responsive during extraction by processing pending events
        if ($gui && $progress_window) {
            $progress_window->update();
        }
    }
    
    close($unrar_fh);
    my $exit_code = $? >> 8;  # Extract exit code from child status
    
    return $exit_code;
}

=head2 extract_rar($dir, $dest_dir)

Extracts a RAR archive from a directory.

This is the main extraction function. It:

=over 4

=item 1. Validates the source directory exists

=item 2. Finds the appropriate RAR file to extract

=item 3. Creates the destination directory if needed

=item 4. Runs unrar with real-time output display

=item 5. Optionally verifies CRC and deletes archives (if -d flag set)

=back

B<Parameters:>

=over 4

=item $dir - Source directory containing the RAR archive

=item $dest_dir - (optional) Destination directory; defaults to $dir

=back

B<Returns:> 1 on success, 0 on failure

=cut

sub extract_rar { 
    my ($dir, $dest_dir) = @_;
    print "dir=> $dir\tdest_dir=> $dest_dir\n";
    $dest_dir //= $dir;  # Default to in-place extraction
    
    # Validate source directory
    unless (-d $dir) {
        my $msg = "Directory '$dir' does not exist or is not a directory.\n";
        append_output($msg);
        warn $msg unless $gui;
        log_entry($dir, '', $dest_dir, 'extract', 'failed', 'Source directory does not exist');
        return 0;
    }

    # Find RAR file(s) to extract
    my @rar_files = get_rar_files($dir);

    if (@rar_files == 0) {
        my $msg = "No .rar file found in '$dir'.\n";
        append_output($msg);
        warn $msg unless $gui;
        log_entry($dir, '', $dest_dir, 'extract', 'failed', 'No RAR file found');
        return 0;
    } elsif (@rar_files > 1) {
        # Multiple starting points found - warn user and use first one
        my $msg = "Multiple .rar files found in '$dir'. Using the first one: $rar_files[0]\n";
        append_output($msg);
        warn $msg unless $gui;
    }

    my $rar_file = $rar_files[0];
    my $full_rar_path = "$dir/$rar_file";

    # Create destination directory if it doesn't exist
    unless (-d $dest_dir) {
        make_path($dest_dir) or do {
            my $msg = "Cannot create destination directory '$dest_dir': $!\n";
            append_output($msg);
            warn $msg unless $gui;
            log_entry($dir, $rar_file, $dest_dir, 'extract', 'failed', "Cannot create destination: $!");
            return 0;
        };
    }

    # Run unrar with realtime output capture (paths are escaped inside the function)
    print "Line 1006 $full_rar_path => $full_rar_path => $dest_dir/\n";
    my $exit_code = run_unrar_with_output($full_rar_path, "$dest_dir/");

    if ($exit_code == 0) {
        # Extraction successful
        log_entry($dir, $rar_file, $dest_dir, 'extract', 'success', '');
        
        # If delete flag is set, verify and then delete archives
        if ($delete_after) {
            append_output("Verifying CRC for '$full_rar_path'...\n");
            if (verify_extraction_crc($full_rar_path)) {
                log_entry($dir, $rar_file, $dest_dir, 'verify', 'success', 'CRC check passed');
                append_output("CRC verification passed. Deleting RAR files...\n");
                my @deleted = delete_rar_files($dir);
                if (@deleted) {
                    my $deleted_list = join(', ', @deleted);
                    log_entry($dir, $rar_file, $dest_dir, 'delete', 'success', "Deleted: $deleted_list");
                    append_output("Deleted " . scalar(@deleted) . " archive file(s) from '$dir'\n");
                }
            } else {
                # CRC failed - don't delete to preserve potentially recoverable data
                my $msg = "CRC verification failed for '$full_rar_path'. RAR files will not be deleted.\n";
                append_output($msg);
                warn $msg unless $gui;
                log_entry($dir, $rar_file, $dest_dir, 'verify', 'failed', 'CRC check failed - files not deleted');
            }
        }
        
        return 1;
    } else {
        # Extraction failed
        my $msg = "unrar command failed with exit code $exit_code for '$full_rar_path'.\n";
        append_output($msg);
        warn $msg unless $gui;
        log_entry($dir, $rar_file, $dest_dir, 'extract', 'failed', "unrar exit code: $exit_code");
        return 0;
    }
}
