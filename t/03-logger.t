#!/usr/bin/perl

use strict;
use warnings;
use Test::More tests => 15;
use File::Temp qw(tempfile);
use FindBin qw($Bin);
use lib "$Bin/../lib";

use ExtractionLogger;

# Test constructor without log file
{
    my $logger = ExtractionLogger->new();
    isa_ok($logger, 'ExtractionLogger', 'Constructor without file creates object');
    
    # Should not die when logging without file
    eval { $logger->log_entry('', '', '', 'test', 'success', '') };
    ok(!$@, 'Logging without file does not die');
}

# Test constructor with log file
{
    my ($fh, $filename) = tempfile(SUFFIX => '.csv', UNLINK => 1);
    close($fh);
    unlink($filename);  # We want the logger to create it
    
    my $logger = ExtractionLogger->new($filename);
    isa_ok($logger, 'ExtractionLogger', 'Constructor with file creates object');
    
    ok(-f $filename, 'Log file is created');
    
    # Check header (may need to reopen file)
    $logger->close();
    
    open(my $log_fh, '<', $filename);
    my $header = <$log_fh>;
    close($log_fh);
    
    ok(defined $header, 'CSV header exists');
    like($header, qr/Timestamp/, 'CSV header contains Timestamp');
    like($header, qr/Source Directory/, 'CSV header contains Source Directory');
    like($header, qr/Action/, 'CSV header contains Action');
    like($header, qr/Status/, 'CSV header contains Status');
    
    $logger->close();
    unlink($filename);
}

# Test log_entry
{
    my ($fh, $filename) = tempfile(SUFFIX => '.csv', UNLINK => 1);
    close($fh);
    unlink($filename);
    
    my $logger = ExtractionLogger->new($filename);
    
    $logger->log_entry(
        '/path/to/source',
        'test.rar',
        '/path/to/dest',
        'extract',
        'success',
        'Test details'
    );
    
    $logger->close();
    
    # Read log file
    open(my $log_fh, '<', $filename);
    my @lines = <$log_fh>;
    close($log_fh);
    
    is(scalar(@lines), 2, 'Log has header and one entry');
    
    my $entry = $lines[1];
    like($entry, qr{/path/to/source}, 'Entry contains source directory');
    like($entry, qr{test\.rar}, 'Entry contains RAR file');
    like($entry, qr{extract}, 'Entry contains action');
    like($entry, qr{success}, 'Entry contains status');
    
    unlink($filename);
}

# Test CSV escaping
{
    my ($fh, $filename) = tempfile(SUFFIX => '.csv', UNLINK => 1);
    close($fh);
    unlink($filename);
    
    my $logger = ExtractionLogger->new($filename);
    
    # Log entry with quotes and commas
    $logger->log_entry(
        '/path/with"quotes',
        'file,with,commas.rar',
        '/output',
        'extract',
        'success',
        'Details with "quotes" and, commas'
    );
    
    $logger->close();
    
    # Read and verify proper CSV formatting
    open(my $log_fh, '<', $filename);
    my @lines = <$log_fh>;
    close($log_fh);
    
    my $entry = $lines[1];
    like($entry, qr/".*".*".*"/, 'Entry properly quoted for CSV');
    
    unlink($filename);
}

done_testing();
