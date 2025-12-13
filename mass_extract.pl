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

MassExtract recursively searches a directory tree for split-volume RAR
archives and extracts them. Supports old-style (.rar, .r00, .r01) and 
new-style (.part1.rar, .part2.rar) split archives.

=head1 OPTIONS

=over 4

=item B<-r, --root> I<directory> - Root directory to search (required)

=item B<-o, --output> I<directory> - Output directory (default: extract in place)

=item B<-d, --delete> - Delete archives after successful extraction

=item B<-l, --log> I<file> - Write extraction log to CSV file

=item B<-g, --gui> - Launch graphical interface

=item B<-h, --help> - Display usage information

=back

=head1 AUTHOR

MassExtract Contributors

=head1 LICENSE

This software is released under the same terms as Perl itself.

=cut

use strict;
use warnings;
use File::Basename;
use File::Path qw(make_path);
use Cwd 'abs_path';
use Getopt::Long;
use FindBin qw($Bin);
use lib "$Bin/lib";

use UnrarExtractor;
use ExtractionLogger;
use MassExtractGUI;

#=============================================================================
# GLOBAL VARIABLES
#=============================================================================

my $root_dir = '';
my $output_dir = '';
my $delete_after = 0;
my $log_file = '';
my $help = 0;
my $gui = 0;

#=============================================================================
# COMMAND LINE ARGUMENT PARSING
#=============================================================================

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

#=============================================================================
# GUI OPTIONS WINDOW
#=============================================================================

if ($gui) {
    my $gui_obj = MassExtractGUI->new();
    my %options = $gui_obj->show_options_dialog();
    
    if (%options) {
        $root_dir = $options{root_dir};
        $output_dir = $options{output_dir};
        $delete_after = $options{delete_after};
        $log_file = $options{log_file};
    }
}

#=============================================================================
# INPUT VALIDATION
#=============================================================================

unless ($root_dir) {
    print STDERR "Error: Root directory is required. Use -r or --root to specify.\n";
    print_usage();
    exit 1;
}

$root_dir = expand_tilde($root_dir);
$root_dir = abs_path($root_dir);

unless (-d $root_dir) {
    die "Error: Root directory '$root_dir' does not exist.\n";
}

if ($output_dir) {
    $output_dir = expand_tilde($output_dir);
    $output_dir = abs_path($output_dir);
    
    unless (-d $output_dir) {
        eval { make_path($output_dir) };
        if ($@) {
            die "Error: Cannot create output directory '$output_dir': $@\n";
        }
    }
}

#=============================================================================
# INITIALIZE MODULES
#=============================================================================

my $logger = ExtractionLogger->new($log_file);

my $gui_obj;
if ($gui) {
    $gui_obj = MassExtractGUI->new();
}

my $extractor = UnrarExtractor->new(
    progress_callback => sub {
        my ($message, $percent) = @_;
        if ($gui_obj) {
            $gui_obj->update_progress($message, $percent);
        }
    },
    output_callback => sub {
        my ($text) = @_;
        if ($gui_obj) {
            $gui_obj->append_output($text);
        } else {
            print $text;
        }
    }
);

#=============================================================================
# MAIN PROGRAM EXECUTION
#=============================================================================

my @dirs = $extractor->scan_for_archives($root_dir);

if (@dirs == 0) {
    handle_no_archives_found();
} else {
    process_archives(@dirs);
}

#=============================================================================
# CLEANUP
#=============================================================================

$logger->close();

if ($log_file) {
    output_message("\nLog written to: $log_file\n");
}

#=============================================================================
# SUBROUTINES
#=============================================================================

sub handle_no_archives_found {
    print "No RAR archives found in '$root_dir'\n";
    $logger->log_entry($root_dir, '', '', 'scan', 'complete', 'No archives found');
    
    if ($gui) {
        $gui_obj->show_completion_dialog("No RAR archives found in:\n$root_dir");
    }
}

sub process_archives {
    my @dirs = @_;
    
    my $total_dirs = scalar(@dirs);
    output_message("Found $total_dirs directories with RAR archives.\n");
    
    if ($gui) {
        $gui_obj->create_progress_window($total_dirs);
    }
    
    my $current_dir_index = 0;
    
    foreach my $source_dir (@dirs) {
        my $dest_dir = calculate_destination_dir($source_dir);
        
        if ($gui) {
            $gui_obj->update_directory_progress($current_dir_index, $source_dir);
        }
        
        output_message("\nProcessing: $source_dir\n");
        output_message("  -> Extracting to: $dest_dir\n");
        
        my %result = $extractor->extract($source_dir, $dest_dir);
        
        if ($result{success}) {
            output_message("  -> Extraction SUCCESS\n");
            $logger->log_entry($source_dir, $result{rar_file}, $dest_dir, 'extract', 'success', '');
            
            if ($delete_after) {
                handle_deletion($source_dir, $dest_dir, $result{rar_file});
            }
        } else {
            output_message("  -> Extraction FAILED\n");
            my $error = $result{error} || 'Unknown error';
            $logger->log_entry($source_dir, $result{rar_file} || '', $dest_dir, 'extract', 'failed', $error);
        }
        
        $current_dir_index++;
    }
    
    if ($gui) {
        $gui_obj->update_progress("Extraction complete!", 100);
        $gui_obj->enable_close_button();
        $gui_obj->main_loop();
    }
}

sub handle_deletion {
    my ($source_dir, $dest_dir, $rar_file) = @_;
    
    my $full_rar_path = "$source_dir/$rar_file";
    
    output_message("Verifying CRC for '$full_rar_path'...\n");
    
    if ($extractor->verify_crc($full_rar_path)) {
        $logger->log_entry($source_dir, $rar_file, $dest_dir, 'verify', 'success', 'CRC check passed');
        output_message("CRC verification passed. Deleting RAR files...\n");
        
        my @deleted = $extractor->delete_archives($source_dir);
        
        if (@deleted) {
            my $deleted_list = join(', ', @deleted);
            $logger->log_entry($source_dir, $rar_file, $dest_dir, 'delete', 'success', "Deleted: $deleted_list");
            output_message("Deleted " . scalar(@deleted) . " archive file(s) from '$source_dir'\n");
        }
    } else {
        my $msg = "CRC verification failed for '$full_rar_path'. RAR files will not be deleted.\n";
        output_message($msg);
        $logger->log_entry($source_dir, $rar_file, $dest_dir, 'verify', 'failed', 'CRC check failed - files not deleted');
    }
}

sub calculate_destination_dir {
    my ($source_dir) = @_;
    
    if ($output_dir) {
        my $relative = $source_dir;
        my $root_normalized = $root_dir;
        $root_normalized =~ s/\/$//;
        $relative =~ s/^\Q$root_normalized\E\/?//;
        return $relative ? "$output_dir/$relative" : $output_dir;
    } else {
        return $source_dir;
    }
}

sub expand_tilde {
    my ($path) = @_;
    
    if ($path =~ /^~/) {
        $path = glob($path);
    }
    
    return $path;
}

sub output_message {
    my ($text) = @_;
    
    if ($gui_obj) {
        $gui_obj->append_output($text);
    } else {
        print $text;
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
  mass_extract.pl -g
USAGE
}
