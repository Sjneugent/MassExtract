#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path remove_tree);
use FindBin qw($Bin);
use lib "$Bin/../lib";
use lib "$Bin/lib";

use UnrarExtractor;
use TestHelper qw(create_test_dir cleanup_test_dir create_corrupt_rar);

# Skip tests if rar/unrar not available
eval {
    my $check = `unrar 2>&1`;
    die "unrar not found" unless defined $check;
};

if ($@) {
    plan skip_all => "unrar not available: $@";
} else {
    plan tests => 12;
}

# Test corrupt RAR file
{
    my $test_dir = create_test_dir();
    my $output_dir = "$test_dir/output";
    make_path($output_dir);
    
    # Create a corrupt RAR file
    my $corrupt_rar = create_corrupt_rar($test_dir, 'corrupt');
    
    ok(-f $corrupt_rar, 'Corrupt RAR file created');
    
    my $extractor = UnrarExtractor->new();
    my %result = $extractor->extract($test_dir, $output_dir);
    
    ok(!$result{success}, 'Corrupt RAR extraction fails as expected');
    ok(exists $result{exit_code}, 'Exit code is set');
    isnt($result{exit_code}, 0, 'Exit code indicates failure');
    
    cleanup_test_dir($test_dir);
}

# Test CRC verification on corrupt file
{
    my $test_dir = create_test_dir();
    
    # Create a corrupt RAR
    my $corrupt_rar = create_corrupt_rar($test_dir, 'corrupt_crc');
    
    my $extractor = UnrarExtractor->new();
    my $result = $extractor->verify_crc($corrupt_rar);
    
    ok(!$result, 'CRC verification fails for corrupt archive');
    
    cleanup_test_dir($test_dir);
}

# Test extracting to directory with existing file
{
    my $test_dir = create_test_dir();
    my $output_dir = "$test_dir/output";
    make_path($output_dir);
    
    # Create a test RAR
    my $content = "Original content";
    open(my $cfh, '>', "$test_dir/existing.txt");
    print $cfh $content;
    close($cfh);
    system("cd '$test_dir' && rar a -ep test.rar existing.txt >/dev/null 2>&1");
    unlink("$test_dir/existing.txt");
    
    # Create file in output directory with same name
    my $existing_content = "Existing file content";
    open(my $fh, '>', "$output_dir/existing.txt");
    print $fh $existing_content;
    close($fh);
    
    ok(-f "$output_dir/existing.txt", 'File exists before extraction');
    
    # Extract (should overwrite)
    my $extractor = UnrarExtractor->new();
    my %result = $extractor->extract($test_dir, $output_dir);
    
    ok($result{success}, 'Extraction succeeds even with existing file');
    ok(-f "$output_dir/existing.txt", 'File still exists after extraction');
    
    # Check that file was overwritten
    open($fh, '<', "$output_dir/existing.txt");
    my $new_content = do { local $/; <$fh> };
    close($fh);
    chomp($new_content);
    
    is($new_content, $content, 'Existing file was overwritten with RAR content');
    
    cleanup_test_dir($test_dir);
}

# Test extraction with missing destination directory creation
{
    my $test_dir = create_test_dir();
    my $output_dir = "$test_dir/nested/deep/output";
    
    # Create a test RAR
    system("cd '$test_dir' && echo 'test' > file.txt && rar a -ep test.rar file.txt >/dev/null 2>&1");
    
    ok(!-d $output_dir, 'Nested output directory does not exist initially');
    
    my $extractor = UnrarExtractor->new();
    my %result = $extractor->extract($test_dir, $output_dir);
    
    ok($result{success}, 'Extraction succeeds with nested directory creation');
    ok(-d $output_dir, 'Nested output directory was created');
    
    cleanup_test_dir($test_dir);
}

done_testing();
