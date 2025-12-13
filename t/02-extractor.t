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
use TestHelper qw(create_test_dir cleanup_test_dir);

# Skip tests if rar/unrar not available
eval {
    my $check = `unrar 2>&1`;
    die "unrar not found" unless defined $check;
};

if ($@) {
    plan skip_all => "unrar not available: $@";
}

# Test constructor
{
    my $extractor = UnrarExtractor->new();
    isa_ok($extractor, 'UnrarExtractor', 'Constructor creates object');
    
    my $output_called = 0;
    my $progress_called = 0;
    
    my $extractor2 = UnrarExtractor->new(
        output_callback => sub { $output_called = 1; },
        progress_callback => sub { $progress_called = 1; }
    );
    
    isa_ok($extractor2, 'UnrarExtractor', 'Constructor with callbacks');
    
    # Test callbacks are stored
    $extractor2->{output_callback}->("test");
    ok($output_called, 'Output callback is callable');
    
    $extractor2->{progress_callback}->("test", 50);
    ok($progress_called, 'Progress callback is callable');
}

# Test scan_for_archives
{
    my $test_dir = create_test_dir();
    
    # Create directory structure
    my $dir1 = "$test_dir/dir1";
    my $dir2 = "$test_dir/dir2";
    my $dir3 = "$test_dir/dir3";
    
    make_path($dir1, $dir2, $dir3);
    
    # Create test RAR files - need 2 RAR files for dir1 to be detected
    system("cd '$dir1' && echo 'test1' > file1.txt && rar a -ep test.rar file1.txt >/dev/null 2>&1");
    system("cd '$dir1' && echo 'test2' > file2.txt && rar a -ep test2.rar file2.txt >/dev/null 2>&1");
    unlink("$dir1/file1.txt", "$dir1/file2.txt");
    
    # Create 2 RAR files for dir2 as well
    system("cd '$dir2' && echo 'test3' > file3.txt && rar a -ep test.rar file3.txt >/dev/null 2>&1");
    system("cd '$dir2' && echo 'test4' > file4.txt && rar a -ep test2.rar file4.txt >/dev/null 2>&1");
    unlink("$dir2/file3.txt", "$dir2/file4.txt");
    
    # dir3 has no RAR files
    
    my $extractor = UnrarExtractor->new();
    my @dirs = $extractor->scan_for_archives($test_dir);
    
    ok(scalar(@dirs) >= 1, 'Scan finds directories with archives');
    
    my %found_dirs = map { $_ => 1 } @dirs;
    ok($found_dirs{$dir1} || $found_dirs{$dir2}, 'Found directories with multiple RAR files');
    ok(!$found_dirs{$dir3}, 'Did not find dir3 without RAR files');
    
    cleanup_test_dir($test_dir);
}

# Test get_primary_rar_file
{
    my $test_dir = create_test_dir();
    
    # Create test files
    system("cd '$test_dir' && echo 'part1' > file1.txt && rar a -ep test.part1.rar file1.txt >/dev/null 2>&1");
    system("cd '$test_dir' && echo 'part2' > file2.txt && rar a -ep test.part2.rar file2.txt >/dev/null 2>&1");
    
    my $extractor = UnrarExtractor->new();
    my $primary = $extractor->get_primary_rar_file($test_dir);
    
    ok(defined $primary, 'get_primary_rar_file returns a file');
    is($primary, 'test.part1.rar', 'Correctly identifies part1 as primary');
    
    cleanup_test_dir($test_dir);
}

# Test extraction
{
    my $test_dir = create_test_dir();
    my $output_dir = "$test_dir/output";
    
    make_path($output_dir);
    
    # Create a test RAR
    my $content = "Test extraction content";
    open(my $cfh, '>', "$test_dir/testfile.txt");
    print $cfh $content;
    close($cfh);
    system("cd '$test_dir' && rar a -ep test.rar testfile.txt >/dev/null 2>&1");
    unlink("$test_dir/testfile.txt");
    
    my $extractor = UnrarExtractor->new();
    my %result = $extractor->extract($test_dir, $output_dir);
    
    ok($result{success}, 'Extraction reports success');
    is($result{rar_file}, 'test.rar', 'Correct RAR file identified');
    is($result{exit_code}, 0, 'Exit code is 0');
    ok(-f "$output_dir/testfile.txt", 'Extracted file exists');
    
    # Verify content
    open(my $fh, '<', "$output_dir/testfile.txt");
    my $extracted_content = do { local $/; <$fh> };
    close($fh);
    chomp($extracted_content);
    
    is($extracted_content, $content, 'Extracted content matches original');
    
    cleanup_test_dir($test_dir);
}

# Test extraction to same directory
{
    my $test_dir = create_test_dir();
    
    # Create a test RAR
    my $content = "In-place extraction test";
    open(my $cfh, '>', "$test_dir/inplace.txt");
    print $cfh $content;
    close($cfh);
    system("cd '$test_dir' && rar a -ep test.rar inplace.txt >/dev/null 2>&1");
    unlink("$test_dir/inplace.txt");
    
    my $extractor = UnrarExtractor->new();
    my %result = $extractor->extract($test_dir, $test_dir);
    
    ok($result{success}, 'In-place extraction succeeds');
    ok(-f "$test_dir/inplace.txt", 'File extracted to same directory');
    
    cleanup_test_dir($test_dir);
}

# Test verify_crc
{
    my $test_dir = create_test_dir();
    
    # Create a valid RAR
    system("cd '$test_dir' && echo 'CRC test' > crctest.txt && rar a -ep test.rar crctest.txt >/dev/null 2>&1");
    
    my $extractor = UnrarExtractor->new();
    my $rar_path = "$test_dir/test.rar";
    
    ok(-f $rar_path, 'Test RAR exists');
    
    my $result = $extractor->verify_crc($rar_path);
    ok($result, 'CRC verification passes for valid archive');
    
    cleanup_test_dir($test_dir);
}

# Test delete_archives
{
    my $test_dir = create_test_dir();
    
    # Create test RAR files
    system("cd '$test_dir' && echo 'test' > file.txt && rar a -ep test.rar file.txt >/dev/null 2>&1");
    system("cd '$test_dir' && touch test.r00 test.r01");
    
    ok(-f "$test_dir/test.rar", 'RAR file exists before deletion');
    ok(-f "$test_dir/test.r00", 'Part file r00 exists');
    ok(-f "$test_dir/test.r01", 'Part file r01 exists');
    
    my $extractor = UnrarExtractor->new();
    my @deleted = $extractor->delete_archives($test_dir);
    
    ok(scalar(@deleted) >= 1, 'delete_archives returns deleted files');
    ok(!-f "$test_dir/test.rar", 'RAR file deleted');
    ok(!-f "$test_dir/test.r00", 'Part file r00 deleted');
    ok(!-f "$test_dir/test.r01", 'Part file r01 deleted');
    
    cleanup_test_dir($test_dir);
}

done_testing();
