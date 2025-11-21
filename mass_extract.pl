#!/usr/bin/perl -w
use strict;
use File::Find;
use Cwd 'abs_path';

sub iterate_movies {
  my $root_dir = shift;
  my %rar_counts;
  my %part_counts;
  my @results;

  $root_dir = glob($root_dir) if $root_dir =~ /^~/;
  $root_dir = abs_path($root_dir);
  unless( -d $root_dir) { 
    warn "Root directory '$root_dir' does not exist.\n";
    return @results;
  }

  find(sub { 
    return unless -f $_;
    if(/\.rar$/i) { $rar_counts{$File::Find::dir}++}
    elsif(/\.r\d{2}$/i) { $part_counts{$File::Find::dir}++}
  }, $root_dir);


  foreach my $dir (keys %rar_counts, keys %part_counts) {
    my $rar_count = $rar_counts{$dir} // 0;
    my $part_count = $part_counts{$dir} // 0;

    if($rar_count >= 2 || ($rar_count >= 1 && $part_count >= 1)) {
      push @results, $dir;
    }

  }
  return @results
}
sub extract_rar { 
 my ($dir) = @_;
    unless (-d $dir) {
        warn "Directory '$dir' does not exist or is not a directory.\n";
        return 0;
    }

    # Find the .rar file in the directory
    opendir(my $dh, $dir) or do {
        warn "Cannot open directory '$dir': $!\n";
        return 0;
    };
    my @rar_files;
    while (my $file = readdir($dh)) {
        if ($file =~ /\.rar$/i && -f "$dir/$file") {
            push @rar_files, $file;
        }
    }
    closedir($dh);

    if (@rar_files == 0) {
        warn "No .rar file found in '$dir'.\n";
        return 0;
    } elsif (@rar_files > 1) {
        warn "Multiple .rar files found in '$dir'. Using the first one: $rar_files[0]\n";
    }

    my $rar_file = $rar_files[0];
    my $full_rar_path = "$dir/$rar_file";

    # Run unrar to extract to the same directory
    my $exit_code = system("unrar x '$full_rar_path' '$dir'");

    if ($exit_code == 0) {
        return 1;  # Success
    } else {
        warn "unrar command failed with exit code $exit_code for '$full_rar_path'.\n";
        return 0;
    }

}

my @r = iterate_movies("~/movies");
print join("\n", @r);
foreach my $r_dir (@r) { 
  if(extract_rar($r_dir)){
    print "Extraction Success for $r_dir\n";
  }else {
    print "Extracted failed for $r_dir\n";
  }
}
