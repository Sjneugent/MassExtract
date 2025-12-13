package UnrarExtractor;

use strict;
use warnings;
use File::Find;
use File::Path qw(make_path);
use File::Basename;

=head1 NAME

UnrarExtractor - RAR archive extraction and management

=head1 DESCRIPTION

This module handles all unrar-related operations including:
- Scanning directories for split RAR archives
- Extracting archives with progress reporting
- CRC verification
- File deletion after successful extraction

=cut

=head2 new(%options)

Creates a new UnrarExtractor instance.

B<Options:>

=over 4

=item * progress_callback - Code ref called with ($message, $percent) during extraction

=item * output_callback - Code ref called with ($text) for output messages

=back

=cut

sub new {
    my ($class, %options) = @_;
    
    my $self = {
        progress_callback => $options{progress_callback},
        output_callback => $options{output_callback},
    };
    
    return bless $self, $class;
}

=head2 scan_for_archives($root_dir)

Recursively searches for directories containing split RAR archives.

A directory is considered to have a split archive if it contains:
- Two or more .rar files, OR
- At least one .rar file AND one or more .r## (old-style volume) files

B<Parameters:>

=over 4

=item $root_dir - Root directory to begin searching

=back

B<Returns:> Array of directory paths containing split archives

=cut

sub scan_for_archives {
    my ($self, $search_dir) = @_;
    
    my %rar_counts;
    my %part_counts;
    my @results;

    # Traverse directory tree counting archive files
    find(sub { 
        return unless -f $_;
        
        if (/\.rar$/i) {
            $rar_counts{$File::Find::dir}++;
        } elsif (/\.r\d{2}$/i) {
            $part_counts{$File::Find::dir}++;
        }
    }, $search_dir);

    # Get unique directories that have archives
    my %all_dirs;
    foreach my $dir (keys %rar_counts) {
        $all_dirs{$dir} = 1;
    }
    foreach my $dir (keys %part_counts) {
        $all_dirs{$dir} = 1;
    }
    
    # Filter to only directories with split archives
    foreach my $dir (keys %all_dirs) {
        my $rar_count = $rar_counts{$dir} || 0;
        my $part_count = $part_counts{$dir} || 0;

        if ($rar_count >= 2 || ($rar_count >= 1 && $part_count >= 1)) {
            push @results, $dir;
        }
    }
    
    return @results;
}

=head2 get_primary_rar_file($dir)

Finds the primary RAR archive file to extract from a directory.

Prioritizes:
1. Files matching .part1.rar (first part of new-style split archives)
2. Files NOT matching .partN.rar pattern (standalone or old-style archives)

B<Parameters:>

=over 4

=item $dir - Directory to scan

=back

B<Returns:> Primary RAR filename or undef if none found

=cut

sub get_primary_rar_file {
    my ($self, $dir) = @_;
    
    my @rar_files;
    my @first_part_files;
    
    opendir(my $dh, $dir) or do {
        warn "Cannot open directory '$dir': $!\n";
        return;
    };
    
    while (my $file = readdir($dh)) {
        next unless $file =~ /\.rar$/i;
        next unless -f "$dir/$file";
        
        push @rar_files, $file;
        
        # Identify extraction starting points
        if ($file =~ /\.part1\.rar$/i || $file !~ /\.part\d+\.rar$/i) {
            push @first_part_files, $file;
        }
    }
    closedir($dh);
    
    # Return first extraction starting point, or first RAR file
    return $first_part_files[0] if @first_part_files;
    return $rar_files[0] if @rar_files;
    return;
}

=head2 extract($source_dir, $dest_dir)

Extracts a RAR archive from source directory to destination.

B<Parameters:>

=over 4

=item $source_dir - Directory containing the RAR archive

=item $dest_dir - Destination directory for extracted files

=back

B<Returns:> Hash with keys: success (boolean), rar_file (filename), exit_code (int)

=cut

sub extract {
    my ($self, $source_dir, $dest_dir) = @_;
    
    $dest_dir ||= $source_dir;
    
    # Validate source directory
    unless (-d $source_dir) {
        $self->_output("Directory '$source_dir' does not exist.\n");
        return (success => 0, error => 'Source directory does not exist');
    }

    # Find RAR file to extract
    my $rar_file = $self->get_primary_rar_file($source_dir);
    
    unless ($rar_file) {
        $self->_output("No .rar file found in '$source_dir'.\n");
        return (success => 0, error => 'No RAR file found');
    }

    my $full_rar_path = "$source_dir/$rar_file";

    # Create destination directory if needed
    unless (-d $dest_dir) {
        eval { make_path($dest_dir) };
        if ($@) {
            $self->_output("Cannot create destination directory '$dest_dir': $@\n");
            return (success => 0, rar_file => $rar_file, error => "Cannot create destination: $@");
        }
    }

    # Run unrar extraction
    my $exit_code = $self->_run_unrar($full_rar_path, $dest_dir);

    if ($exit_code == 0) {
        return (success => 1, rar_file => $rar_file, exit_code => 0);
    } else {
        $self->_output("unrar failed with exit code $exit_code for '$full_rar_path'.\n");
        return (success => 0, rar_file => $rar_file, exit_code => $exit_code);
    }
}

=head2 verify_crc($rar_path)

Verifies the integrity of a RAR archive using CRC checking.

B<Parameters:>

=over 4

=item $rar_path - Full path to the RAR archive

=back

B<Returns:> 1 if verification passed, 0 if failed

=cut

sub verify_crc {
    my ($self, $rar_path) = @_;
    
    my $escaped_path = $self->_shell_escape($rar_path);
    my $output = `unrar t $escaped_path 2>&1`;
    my $exit_code = $? >> 8;
    
    if ($exit_code == 0) {
        if ($output =~ /All OK/i || $output !~ /(error|failed|corrupt|bad|cannot)/i) {
            return 1;
        }
    }
    
    return 0;
}

=head2 delete_archives($dir)

Deletes all RAR archive files from a directory.

B<Parameters:>

=over 4

=item $dir - Directory containing archive files to delete

=back

B<Returns:> Array of deleted filenames

=cut

sub delete_archives {
    my ($self, $dir) = @_;
    
    my @deleted;
    
    opendir(my $dh, $dir) or do {
        warn "Cannot open directory '$dir' for deletion: $!\n";
        return @deleted;
    };
    
    while (my $file = readdir($dh)) {
        next unless -f "$dir/$file";
        next unless $file =~ /\.rar$/i || $file =~ /\.r\d{2}$/i;
        
        my $full_path = "$dir/$file";
        if (unlink($full_path)) {
            push @deleted, $file;
        } else {
            warn "Failed to delete '$full_path': $!\n";
        }
    }
    closedir($dh);
    
    return @deleted;
}

#=============================================================================
# PRIVATE METHODS
#=============================================================================

sub _run_unrar {
    my ($self, $rar_path, $dest_dir) = @_;
    
    my $escaped_rar = $self->_shell_escape($rar_path);
    my $escaped_dest = $self->_shell_escape($dest_dir);
    
    my $cmd = "unrar x -o+ $escaped_rar $escaped_dest 2>&1";
    
    my $pid = open(my $unrar_fh, '-|', $cmd);
    
    unless (defined $pid) {
        $self->_output("Failed to execute unrar: $!\n");
        return -1;
    }
    
    while (my $line = <$unrar_fh>) {
        $self->_output($line);
        
        # Parse progress percentage if available
        if ($line =~ /(\d+)%/) {
            my $file_percent = $1;
            $self->_progress(undef, $file_percent);
        }
    }
    
    close($unrar_fh);
    return $? >> 8;
}

sub _shell_escape {
    my ($self, $str) = @_;
    $str =~ s/'/'\\''/g;
    return "'$str'";
}

sub _output {
    my ($self, $text) = @_;
    
    if ($self->{output_callback}) {
        $self->{output_callback}->($text);
    }
}

sub _progress {
    my ($self, $message, $percent) = @_;
    
    if ($self->{progress_callback}) {
        $self->{progress_callback}->($message, $percent);
    }
}

1;

__END__

=head1 AUTHOR

MassExtract Contributors

=head1 LICENSE

This software is released under the same terms as Perl itself.
