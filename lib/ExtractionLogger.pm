package ExtractionLogger;

use strict;
use warnings;
use POSIX qw(strftime);

=head1 NAME

ExtractionLogger - CSV logging for RAR extraction operations

=head1 DESCRIPTION

This module provides CSV logging functionality for tracking extraction
operations, including timestamps, source/destination paths, actions,
and status information.

=cut

=head2 new($log_file)

Creates a new ExtractionLogger instance.

B<Parameters:>

=over 4

=item $log_file - Path to the CSV log file (optional)

=back

=cut

sub new {
    my ($class, $log_file) = @_;
    
    my $self = {
        log_file => $log_file,
        log_fh => undef,
    };
    
    bless $self, $class;
    
    if ($log_file) {
        $self->_open_log_file();
    }
    
    return $self;
}

=head2 log_entry($source_dir, $rar_file, $dest_dir, $action, $status, $details)

Writes a log entry to the CSV log file.

B<Parameters:>

=over 4

=item $source_dir - Directory containing the source archive

=item $rar_file - Name of the RAR archive file

=item $dest_dir - Destination directory for extracted files

=item $action - Type of action (extract, verify, delete, scan)

=item $status - Result status (success, failed, complete)

=item $details - Additional details or error messages (optional)

=back

=cut

sub log_entry {
    my ($self, $source_dir, $rar_file, $dest_dir, $action, $status, $details) = @_;
    
    return unless $self->{log_fh};
    
    my $timestamp = strftime("%Y-%m-%d %H:%M:%S", localtime);
    $details ||= '';
    $details =~ s/"/""/g;  # Escape embedded quotes for CSV
    
    my @fields = (
        $timestamp,
        $source_dir,
        $rar_file,
        $dest_dir,
        $action,
        $status,
        $details
    );
    
    my $line = join(',', map { $self->_quote_csv_field($_) } @fields);
    
    my $fh = $self->{log_fh};
    print $fh "$line\n";
}

=head2 close()

Closes the log file.

=cut

sub close {
    my ($self) = @_;
    
    if ($self->{log_fh}) {
        close($self->{log_fh});
        $self->{log_fh} = undef;
    }
}

=head2 get_log_file()

Returns the path to the log file.

=cut

sub get_log_file {
    my ($self) = @_;
    return $self->{log_file};
}

#=============================================================================
# PRIVATE METHODS
#=============================================================================

sub _open_log_file {
    my ($self) = @_;
    
    my $log_file = $self->{log_file};
    return unless $log_file;
    
    # Expand tilde if present
    $log_file =~ s/^~/$ENV{HOME}/ if $log_file =~ /^~/;
    $self->{log_file} = $log_file;
    
    my $file_exists = -e $log_file;
    
    open(my $fh, '>>', $log_file) or die "Error: Cannot open log file '$log_file': $!\n";
    $self->{log_fh} = $fh;
    
    # Write CSV header if new file
    unless ($file_exists && -s $log_file) {
        print $fh "Timestamp,Source Directory,RAR File,Output Directory,Action,Status,Details\n";
    }
}

sub _quote_csv_field {
    my ($self, $field) = @_;
    $field =~ s/"/""/g;
    return "\"$field\"";
}

sub DESTROY {
    my ($self) = @_;
    $self->close();
}

1;

__END__

=head1 AUTHOR

MassExtract Contributors

=head1 LICENSE

This software is released under the same terms as Perl itself.
