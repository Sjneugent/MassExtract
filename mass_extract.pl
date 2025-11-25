#!/usr/bin/perl -w
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
my $root_dir = '';
my $output_dir = '';
my $delete_after = 0;
my $log_file = '';
my $help = 0;
my $gui = 0;

# GUI progress window variables
my $progress_window;
my $progress_bar;
my $progress_label;
my $output_text;
my $close_button;
my $progress_value = 0;
my $total_dirs = 0;
my $current_dir_index = 0;
GetOptions(
    'root|r=s'    => \$root_dir,
    'output|o=s'  => \$output_dir,
    'delete|d'    => \$delete_after,
    'log|l=s'     => \$log_file,
    'help|h'      => \$help,
    'gui|g'       => \$gui,
) or die "Error in command line arguments. Use --help for usage.\n";

if ($help) {
    print_usage();
    exit 0;
}
if($gui){
  my $MW = MainWindow->new;
  $MW->title("Mass RAR Extractor Options");
  $MW->Label(-text => "Select Root Directory:")->pack();
  my $root_entry = $MW->Entry(-width => 50);
  $root_entry->pack();
  $MW->Button(-text => "Browse", -command => sub {
      my $dir = $MW->chooseDirectory(-title => "Select Root Directory");
      $root_entry->delete(0, 'end');
      $root_entry->insert(0, $dir) if defined $dir;
  })->pack();
  $MW->Label(-text => "Select Output Directory (optional):")->pack();
  my $output_entry = $MW->Entry(-width => 50);
  $output_entry->pack();
  $MW->Button(-text => "Browse", -command => sub {
      my $dir = $MW->chooseDirectory(-title => "Select Output Directory");
      $output_entry->delete(0, 'end');
      $output_entry->insert(0, $dir) if defined $dir;
  })->pack();
  my $delete_var = 0;
  $MW->Checkbutton(-text => "Delete RAR files after extraction", -variable => \$delete_var)->pack();
  my $log_entry = $MW->Entry(-width => 50);
  $MW->Label(-text => "Log File (optional):")->pack();       
  $MW->Button(-text => "Browse", -command => sub {
      my $file = $MW->getSaveFile(-title => "Select Log File", -defaultextension => '.csv', -filetypes => [['CSV Files', '.csv'], ['All Files', '.*']]);
      $log_entry->delete(0, 'end');
      $log_entry->insert(0, $file) if defined $file;
  })->pack();
  $log_entry->pack();
  $MW->Button(-text => "Start Extraction", -command => sub {
      $root_dir = $root_entry->get();
      $output_dir = $output_entry->get();
      $delete_after = $delete_var;
      $log_file = $log_entry->get();
      $MW->destroy();
  })->pack(); 
  MainLoop;
}
unless ($root_dir) {
    print STDERR "Error: Root directory is required. Use -r or --root to specify.\n";
    print_usage();
    exit 1;
}

$root_dir = glob($root_dir) if $root_dir =~ /^~/;
$root_dir = abs_path($root_dir);

unless (-d $root_dir) {
    die "Error: Root directory '$root_dir' does not exist.\n";
}

if ($output_dir) {
    $output_dir = glob($output_dir) if $output_dir =~ /^~/;
    $output_dir = abs_path($output_dir);
    unless (-d $output_dir) {
        make_path($output_dir) or die "Error: Cannot create output directory '$output_dir': $!\n";
    }
}

my $log_fh;
if ($log_file) {
    $log_file = glob($log_file) if $log_file =~ /^~/;
    open($log_fh, '>>', $log_file) or die "Error: Cannot open log file '$log_file': $!\n";
    if (!-s $log_file) {
        print $log_fh "Timestamp,Source Directory,RAR File,Output Directory,Action,Status,Details\n";
    }
}

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

# Shell-escape a string by replacing single quotes with '\'' and wrapping in single quotes
sub shell_escape {
    my ($str) = @_;
    $str =~ s/'/'\\''/g;
    return "'$str'";
}

# Create and show the progress window for GUI mode
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

# Update progress window with current status
sub update_progress {
    my ($message, $percent) = @_;
    return unless $gui && $progress_window;
    
    if (defined $message) {
        $progress_label->configure(-text => $message);
    }
    
    if (defined $percent) {
        $progress_value = $percent;
    }
    
    $progress_window->update();
}

# Append text to the output window
sub append_output {
    my ($text) = @_;
    
    if ($gui && $output_text) {
        $output_text->insert('end', $text);
        $output_text->see('end');
        $progress_window->update();
    }
    
    # Also print to console
    print $text;
}

# Enable the close button when extraction is complete
sub enable_close_button {
    return unless $gui && $progress_window && $close_button;
    $close_button->configure(-state => 'normal');
    $progress_window->update();
}

sub log_entry {
    my ($source_dir, $rar_file, $dest_dir, $action, $status, $details) = @_;
    return unless $log_fh;
    
    my $timestamp = strftime("%Y-%m-%d %H:%M:%S", localtime);
    $details //= '';
    $details =~ s/"/""/g;
    
    my @fields = ($timestamp, $source_dir, $rar_file, $dest_dir, $action, $status, $details);
    my $line = join(',', map { '"' . $_ . '"' } @fields);
    print $log_fh "$line\n";
}

sub iterate_movies {
    my $search_dir = shift;
    my %rar_counts;
    my %part_counts;
    my @results;

    find(sub { 
        return unless -f $_;
        if (/\.rar$/i) { $rar_counts{$File::Find::dir}++ }
        elsif (/\.r\d{2}$/i) { $part_counts{$File::Find::dir}++ }
    }, $search_dir);

    # Combine keys from both hashes, ensuring uniqueness
    my %all_dirs;
    $all_dirs{$_} = 1 for keys %rar_counts;
    $all_dirs{$_} = 1 for keys %part_counts;
    
    foreach my $dir (keys %all_dirs) {
        my $rar_count = $rar_counts{$dir} // 0;
        my $part_count = $part_counts{$dir} // 0;

        if ($rar_count >= 2 || ($rar_count >= 1 && $part_count >= 1)) {
            push @results, $dir;
        }
    }
    return @results;
}

sub get_rar_files {
    my ($dir) = @_;
    my @rar_files;
    my @first_part_files;
    
    opendir(my $dh, $dir) or do {
        warn "Cannot open directory '$dir': $!\n";
        return;
    };
    
    while (my $file = readdir($dh)) {
        if ($file =~ /\.rar$/i && -f "$dir/$file") {
            push @rar_files, $file;
            # Match .part1.rar (first part of new naming scheme) or .rar without .partX
            if ($file =~ /\.part1\.rar$/i || $file !~ /\.part\d+\.rar$/i) {
                push @first_part_files, $file;
            }
        }
    }
    closedir($dh);
    
    # Prefer first part files, otherwise return all RAR files
    return @first_part_files if @first_part_files;
    return @rar_files;
}

sub get_part_files {
    my ($dir) = @_;
    my @part_files;
    
    opendir(my $dh, $dir) or return;
    
    while (my $file = readdir($dh)) {
        if ($file =~ /\.r\d{2}$/i && -f "$dir/$file") {
            push @part_files, $file;
        }
    }
    closedir($dh);
    
    return @part_files;
}

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

sub delete_rar_files {
    my ($dir) = @_;
    my @deleted;
    
    opendir(my $dh, $dir) or do {
        warn "Cannot open directory '$dir' for deletion: $!\n";
        return @deleted;
    };
    
    while (my $file = readdir($dh)) {
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

# Run unrar command with realtime output capture
# Takes raw (unescaped) paths and handles escaping internally
sub run_unrar_with_output {
    my ($rar_path, $dest_dir) = @_;
    
    # Shell-escape paths for safe command execution
    my $escaped_rar = shell_escape($rar_path);
    my $escaped_dest = shell_escape($dest_dir);
    
    # Build command with properly escaped paths
    my $cmd = "unrar x -o+ $escaped_rar $escaped_dest 2>&1";
    
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
        # unrar shows progress like "...         5%"
        if ($line =~ /(\d+)%/) {
            my $file_percent = $1;
            # Calculate overall progress based on current directory and file progress
            if ($total_dirs > 0) {
                my $dir_progress = ($current_dir_index / $total_dirs) * 100;
                my $file_contribution = ($file_percent / $total_dirs);
                update_progress(undef, $dir_progress + $file_contribution);
            }
        }
        
        # Keep GUI responsive during extraction
        if ($gui && $progress_window) {
            $progress_window->update();
        }
    }
    
    close($unrar_fh);
    my $exit_code = $? >> 8;
    
    return $exit_code;
}

sub extract_rar { 
    my ($dir, $dest_dir) = @_;
    $dest_dir //= $dir;
    
    unless (-d $dir) {
        my $msg = "Directory '$dir' does not exist or is not a directory.\n";
        append_output($msg);
        warn $msg unless $gui;
        log_entry($dir, '', $dest_dir, 'extract', 'failed', 'Source directory does not exist');
        return 0;
    }

    my @rar_files = get_rar_files($dir);

    if (@rar_files == 0) {
        my $msg = "No .rar file found in '$dir'.\n";
        append_output($msg);
        warn $msg unless $gui;
        log_entry($dir, '', $dest_dir, 'extract', 'failed', 'No RAR file found');
        return 0;
    } elsif (@rar_files > 1) {
        my $msg = "Multiple .rar files found in '$dir'. Using the first one: $rar_files[0]\n";
        append_output($msg);
        warn $msg unless $gui;
    }

    my $rar_file = $rar_files[0];
    my $full_rar_path = "$dir/$rar_file";

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
    my $exit_code = run_unrar_with_output($full_rar_path, "$dest_dir/");

    if ($exit_code == 0) {
        log_entry($dir, $rar_file, $dest_dir, 'extract', 'success', '');
        
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
                my $msg = "CRC verification failed for '$full_rar_path'. RAR files will not be deleted.\n";
                append_output($msg);
                warn $msg unless $gui;
                log_entry($dir, $rar_file, $dest_dir, 'verify', 'failed', 'CRC check failed - files not deleted');
            }
        }
        
        return 1;
    } else {
        my $msg = "unrar command failed with exit code $exit_code for '$full_rar_path'.\n";
        append_output($msg);
        warn $msg unless $gui;
        log_entry($dir, $rar_file, $dest_dir, 'extract', 'failed', "unrar exit code: $exit_code");
        return 0;
    }
}

my @dirs = iterate_movies($root_dir);

if (@dirs == 0) {
    print "No RAR archives found in '$root_dir'\n";
    log_entry($root_dir, '', '', 'scan', 'complete', 'No archives found');
    if ($gui) {
        # Show message dialog in GUI mode using a simple window
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
    $total_dirs = scalar(@dirs);
    append_output("Found $total_dirs directories with RAR archives.\n");
    
    # Create progress window for GUI mode
    if ($gui) {
        create_progress_window();
    }
    
    $current_dir_index = 0;
    foreach my $source_dir (@dirs) {
        my $dest_dir;
        
        if ($output_dir) {
            my $relative = $source_dir;
            $relative =~ s/^\Q$root_dir\E\/?//;
            $dest_dir = $relative ? "$output_dir/$relative" : $output_dir;
        } else {
            $dest_dir = $source_dir;
        }
        
        # Update progress bar
        my $percent = ($current_dir_index / $total_dirs) * 100;
        update_progress("Processing ($current_dir_index/$total_dirs): " . basename($source_dir), $percent);
        
        append_output("\nProcessing: $source_dir\n");
        append_output("  -> Extracting to: $dest_dir\n");
        
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
        MainLoop;
    }
}

if ($log_fh) {
    close($log_fh);
    append_output("\nLog written to: $log_file\n");
}
