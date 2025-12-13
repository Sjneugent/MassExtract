#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir tempfile);
use File::Path qw(make_path remove_tree);
use FindBin qw($Bin);

# Skip GUI tests if Tk is not available or in headless environment
eval {
    require Tk;
    die "DISPLAY not set" unless $ENV{DISPLAY} || $^O eq 'MSWin32';
};

if ($@) {
    plan skip_all => "Tk not available or no display: $@";
} else {
    plan tests => 10;
}

use lib "$Bin/../lib";
use lib "$Bin/lib";

use UnrarExtractor;
use ExtractionLogger;
use TestHelper qw(create_test_dir cleanup_test_dir);

my $script = "$Bin/../mass_extract.pl";

# Test that GUI and CLI produce equivalent results
{
    my $test_dir = create_test_dir();
    my $cli_output = "$test_dir/cli_output";
    my $cli_log = "$test_dir/cli.log";
    
    make_path($cli_output);
    
    # Create test structure
    my $source = "$test_dir/source";
    make_path($source);
    
    # Create a simple RAR archive - need 2 files for split detection
    open(my $cfh, '>', "$source/testfile.txt");
    print $cfh 'test content';
    close($cfh);
    system("cd '$source' && rar a -ep test.rar testfile.txt >/dev/null 2>&1");
    system("cd '$source' && rar a -ep test2.rar testfile.txt >/dev/null 2>&1");
    unlink("$source/testfile.txt");
    
    ok(-f "$source/test.rar", 'Test RAR created for CLI test');
    
    # Run CLI extraction
    my $cli_result = system("$script -r '$source' -o '$cli_output' -l '$cli_log' 2>&1");
    
    is($cli_result >> 8, 0, 'CLI extraction exits successfully');
    ok(-f "$cli_output/testfile.txt", 'CLI extraction produces output file');
    ok(-f $cli_log, 'CLI creates log file');
    
    # Verify log file format
    open(my $log_fh, '<', $cli_log);
    my @log_lines = <$log_fh>;
    close($log_fh);
    
    ok(scalar(@log_lines) >= 2, 'CLI log has header and entries');
    like($log_lines[0], qr/Timestamp.*Action.*Status/, 'CLI log has proper CSV header');
    
    cleanup_test_dir($test_dir);
}

# Test module-based extraction (what GUI would use)
{
    my $test_dir = create_test_dir();
    my $module_output = "$test_dir/module_output";
    my $module_log = "$test_dir/module.log";
    
    make_path($module_output);
    
    # Create test structure
    my $source = "$test_dir/source";
    make_path($source);
    
    open(my $mfh, '>', "$source/modfile.txt");
    print $mfh 'module test';
    close($mfh);
    system("cd '$source' && rar a -ep mod.rar modfile.txt >/dev/null 2>&1");
    system("cd '$source' && rar a -ep mod2.rar modfile.txt >/dev/null 2>&1");
    unlink("$source/modfile.txt");
    
    ok(-f "$source/mod.rar", 'Test RAR created for module test');
    
    # Use modules directly (as GUI would)
    my $logger = ExtractionLogger->new($module_log);
    my $extractor = UnrarExtractor->new(
        output_callback => sub { }  # Suppress output
    );
    
    my @dirs = $extractor->scan_for_archives($source);
    
    foreach my $dir (@dirs) {
        my %result = $extractor->extract($dir, $module_output);
        
        if ($result{success}) {
            $logger->log_entry($dir, $result{rar_file}, $module_output, 
                             'extract', 'success', '');
        }
    }
    
    $logger->close();
    
    ok(-f "$module_output/modfile.txt", 'Module-based extraction produces output file');
    ok(-f $module_log, 'Module-based approach creates log file');
    
    # Verify both approaches produce similar logs
    open(my $log_fh, '<', $module_log);
    my @mod_log_lines = <$log_fh>;
    close($log_fh);
    
    like($mod_log_lines[0], qr/Timestamp.*Action.*Status/, 'Module log has proper CSV header');
    
    cleanup_test_dir($test_dir);
}

done_testing();
