#!/usr/bin/perl

use strict;
use warnings;
use FindBin qw($Bin);
use File::Find;

# Simple test runner for MassExtract tests

print "=" x 70 . "\n";
print "MassExtract Test Suite\n";
print "=" x 70 . "\n\n";

my $test_dir = "$Bin/t";
my @test_files;

# Find all .t files
find(sub {
    push @test_files, $File::Find::name if /\.t$/;
}, $test_dir);

@test_files = sort @test_files;

if (@test_files == 0) {
    die "No test files found in $test_dir\n";
}

print "Found " . scalar(@test_files) . " test file(s)\n\n";

my $total_passed = 0;
my $total_failed = 0;

foreach my $test (@test_files) {
    my $test_name = $test;
    $test_name =~ s/.*\///;  # Get basename
    
    print "-" x 70 . "\n";
    print "Running: $test_name\n";
    print "-" x 70 . "\n";
    
    my $result = system("perl '$test'");
    my $exit_code = $? >> 8;
    
    if ($exit_code == 0) {
        print "\n✓ PASSED: $test_name\n\n";
        $total_passed++;
    } else {
        print "\n✗ FAILED: $test_name (exit code: $exit_code)\n\n";
        $total_failed++;
    }
}

print "=" x 70 . "\n";
print "Test Summary\n";
print "=" x 70 . "\n";
print "Passed: $total_passed\n";
print "Failed: $total_failed\n";
print "Total:  " . ($total_passed + $total_failed) . "\n";
print "=" x 70 . "\n";

exit($total_failed > 0 ? 1 : 0);
