package TestHelper;

use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Path qw(make_path remove_tree);
use File::Copy;
use Exporter 'import';

our @EXPORT_OK = qw(
    create_test_dir
    cleanup_test_dir
    create_test_rar
    create_corrupt_rar
    create_multipart_rar
);

=head1 NAME

TestHelper - Utility functions for MassExtract testing

=head1 DESCRIPTION

Provides helper functions for creating test fixtures, temporary directories,
and test RAR archives.

=cut

=head2 create_test_dir()

Creates a temporary directory for testing.

B<Returns:> Path to temporary directory

=cut

sub create_test_dir {
    my $dir = tempdir(CLEANUP => 0);
    return $dir;
}

=head2 cleanup_test_dir($dir)

Removes a test directory and all its contents.

B<Parameters:>

=over 4

=item $dir - Directory to remove

=back

=cut

sub cleanup_test_dir {
    my ($dir) = @_;
    remove_tree($dir) if -d $dir;
}

=head2 create_test_rar($dir, $name, $content)

Creates a simple test RAR archive.

B<Parameters:>

=over 4

=item $dir - Directory to create RAR in

=item $name - Base name for the archive

=item $content - Content to put in the test file

=back

B<Returns:> Path to created RAR file

=cut

sub create_test_rar {
    my ($dir, $name, $content) = @_;
    
    $content //= "Test content for $name\n";
    
    # Create a test file to archive
    my $test_file = "$dir/${name}.txt";
    open(my $fh, '>', $test_file) or die "Cannot create test file: $!";
    print $fh $content;
    close($fh);
    
    # Create RAR archive
    my $rar_file = "$dir/${name}.rar";
    my $cmd = "cd '$dir' && rar a -ep '$rar_file' '${name}.txt' >/dev/null 2>&1";
    system($cmd);
    
    # Remove original file
    unlink($test_file);
    
    return -f $rar_file ? $rar_file : undef;
}

=head2 create_corrupt_rar($dir, $name)

Creates a corrupt RAR file for testing error handling.

B<Parameters:>

=over 4

=item $dir - Directory to create corrupt RAR in

=item $name - Base name for the archive

=back

B<Returns:> Path to corrupt RAR file

=cut

sub create_corrupt_rar {
    my ($dir, $name) = @_;
    
    my $rar_file = "$dir/${name}.rar";
    
    # Create a file with RAR magic bytes but corrupt content
    open(my $fh, '>', $rar_file) or die "Cannot create corrupt RAR: $!";
    print $fh "Rar!\x1A\x07\x00";  # RAR signature
    print $fh "CORRUPT DATA" x 100;  # Garbage data
    close($fh);
    
    return $rar_file;
}

=head2 create_multipart_rar($dir, $name, $num_parts)

Creates a multi-part RAR archive for testing.

B<Parameters:>

=over 4

=item $dir - Directory to create RAR in

=item $name - Base name for the archive

=item $num_parts - Number of parts to create (minimum 2)

=back

B<Returns:> Path to first part of RAR

=cut

sub create_multipart_rar {
    my ($dir, $name, $num_parts) = @_;
    
    $num_parts //= 3;
    $num_parts = 2 if $num_parts < 2;
    
    # Create a test file large enough to split
    my $test_file = "$dir/${name}.txt";
    open(my $fh, '>', $test_file) or die "Cannot create test file: $!";
    
    # Write enough data to force splitting
    for (1..1000) {
        print $fh "Test line $_ with some content to make it larger\n" x 10;
    }
    close($fh);
    
    # Create split RAR archive (50KB volumes)
    my $rar_base = "$dir/${name}";
    my $cmd = "cd '$dir' && rar a -m0 -v50k -ep '$rar_base.rar' '${name}.txt' >/dev/null 2>&1";
    system($cmd);
    
    # Remove original file
    unlink($test_file);
    
    # Check if first part was created
    my $first_part = "${rar_base}.part1.rar";
    $first_part = "${rar_base}.rar" unless -f $first_part;
    
    return -f $first_part ? $first_part : undef;
}

1;

__END__

=head1 AUTHOR

MassExtract Contributors

=head1 LICENSE

This software is released under the same terms as Perl itself.
