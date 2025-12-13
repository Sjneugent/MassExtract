#!/usr/bin/perl

use strict;
use warnings;
use Test::More tests => 15;
use File::Temp qw(tempdir);
use File::Path qw(remove_tree);
use FindBin qw($Bin);

# Test the main script's command line parsing
my $script = "$Bin/../mass_extract.pl";

ok(-f $script, "mass_extract.pl exists");
ok(-x $script, "mass_extract.pl is executable");

# Test help option
{
    my $output = `$script --help 2>&1`;
    my $exit_code = $? >> 8;
    
    is($exit_code, 0, "Help option exits successfully");
    like($output, qr/Usage:/, "Help displays usage information");
    like($output, qr/--root/, "Help mentions --root option");
    like($output, qr/--output/, "Help mentions --output option");
    like($output, qr/--delete/, "Help mentions --delete option");
    like($output, qr/--log/, "Help mentions --log option");
    like($output, qr/--gui/, "Help mentions --gui option");
}

# Test missing required argument
{
    my $output = `$script 2>&1`;
    my $exit_code = $? >> 8;
    
    isnt($exit_code, 0, "Missing required argument exits with error");
    like($output, qr/Error.*required/i, "Error message mentions required argument");
}

# Test invalid directory
{
    my $output = `$script -r /nonexistent/directory/path 2>&1`;
    my $exit_code = $? >> 8;
    
    isnt($exit_code, 0, "Invalid directory exits with error");
    like($output, qr/does not exist/i, "Error message mentions directory doesn't exist");
}

# Test valid directory with no archives
{
    my $temp_dir = tempdir(CLEANUP => 1);
    
    my $output = `$script -r '$temp_dir' 2>&1`;
    my $exit_code = $? >> 8;
    
    is($exit_code, 0, "Valid directory with no archives exits successfully");
    like($output, qr/No RAR archives found/i, "Reports no archives found");
}

done_testing();
