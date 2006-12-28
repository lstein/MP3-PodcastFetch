#!perl
use Config;
use File::Basename qw(&basename &dirname);
use File::Spec;
use FindBin '$Bin';
use Cwd;

my $dir = dirname($0);
$file   = shift || File::Spec->catfile($dir,basename($0, '.PL','.PLS'));

open OUT,">$file" or die "Can't create $file: $!";

print "Extracting $file (with variable substitutions)\n";

my $startperl = $Config{startperl} ne '#!perl' 
  ? $Config{startperl}
  : "#!$Config{perlpath}";

print OUT <<"!GROK!THIS!";
$startperl -w
!GROK!THIS!

# In the following, perl variables are not expanded during extraction.

print OUT <<'!NO!SUBS!';
# $Id
# Warning: do not directly edit this file. Edit fetch_pods.PLS and rerun Build
use strict;
use warnings;
use FindBin '$Bin';
use Config::IniFiles;
use IO::File;
use File::Path 'mkpath';
use File::Spec;
use File::Basename 'dirname';
use POSIX 'strftime';

use lib "$Bin/../lib";
use MP3::PodcastFetch;

use constant CONFIG => "$Bin/../conf/podcasts.conf";

################## clean up nicely ##############
my $pid_file;
$SIG{TERM} = $SIG{INT} = sub { unlink $pid_file if defined $pid_file; exit -1; };
END {
  unlink $pid_file if defined $pid_file;
}
#################################################

my $config_file = shift || find_config_file();
if ($config_file =~ /^-?-h/i) { # a plea for help
  die <<END;
Usage: fetch_pods.pl [/path/to/config/file]

Fetch the podcasts indicated in the configuration file. Default locations
for the config file are:

  ~/.fetchpods
  /usr/local/etc/fetchpods.conf
  /usr/etc/fetchpods.conf
  /etc/fetchpods.conf
  /path/to/this/binary/../etc/fetchpods.conf
  /path/to/this/binary/../conf/fetchpods.conf  # for local installations
END
}

my $cfg = Config::IniFiles->new(-file=>$config_file,-default=>'Globals')
  or die "Couldn't open config file $config_file: $!";

$pid_file = $cfg->val(Globals=>'pidfile');
write_pidfile($pid_file) or exit 0;

my $date = localtime;
print "$date START fetch_pods\n";
STDOUT->flush;

my $verbose           = $cfg->val(Globals=>'verbose');
my $base              = $cfg->val(Globals=>'base');
my $subdirs           = $cfg->val(Globals=>'subdirs')       || 0;
my $generate_playlist = $cfg->val(Globals=>'keep_old')      || 0;
my $playlist_base     = $cfg->val(Globals=>'playlist_base') || $base;
my $playlist_name     = $cfg->val(Globals=>'playlist_name') || '%Y-%m-%d-%H:%S-podcasts.m3u';
my @sections          = grep {!/globals/i} $cfg->Sections;

true_or_false(\$verbose,\$subdirs);

my ($m3ufile,$playlist_path);
if ($generate_playlist) {
  $playlist_name = File::Spec->rel2abs($playlist_name,$base);
  $playlist_path = strftime($playlist_name,localtime);
  my $dir        = dirname($playlist_path);
  -d $dir or mkpath($dir) or die "Couldn't create directory $dir: $!";
  $m3ufile       = IO::File->new($playlist_path,">") or die "Couldn't open $playlist_path for writing: $!";
  print $m3ufile "#EXTM3U\r\n";
}

my ($fetched,$skipped,$deleted,$errors) = (0,0,0,0);
for my $podcast (@sections) {
  my $url               = $cfg->val($podcast=>'url');
  my $limit             = $cfg->val($podcast=>'limit');
  my $subdir            = $cfg->val($podcast=>'subdir');
  my $keep_old          = $cfg->val($podcast=>'keep_old');
  my $rewrite           = $cfg->val($podcast=>'rewrite_filename');
  my $upgrade           = $cfg->val($podcast=>'upgrade_tag');
  my $mode              = $cfg->val($podcast=>'mirror_mode');
  my $timeout           = $cfg->val($podcast=>'timeout');
  my $genre             = $cfg->val($podcast=>'force_genre');

  unless (defined $url) {
    warn "No podcast RSS URL defined for $podcast\n";
    next;
  }

  true_or_false(\$keep_old,\$rewrite,\$generate_playlist);

  $limit = 1000 if $limit eq 'none';
  my $feed   = MP3::PodcastFetch->new(
                                 -base              => $base,
                                 -subdir            => $subdirs ? $subdir : '',
				 -rss               => $url,
				 -max               => $limit,
				 -mirror_mode       => $mode,
				 -rewrite_filename  => $rewrite,
				 -upgrade_tag       => $upgrade,
				 -verbose           => $verbose,
                                 -force_genre       => $genre,
                                 -keep_old          => $keep_old,
                                 -playlist_handle   => $m3ufile,
                                 -playlist_base     => $playlist_base,
                                );
  $feed->fetch_pods;
  $fetched += $feed->fetched;
  $skipped += $feed->skipped;
  $deleted += $feed->deleted;
  $errors  += $feed->errors;
}

$date = localtime;
unlink $playlist_path if $playlist_path && !$fetched;
print "$date END fetch_pods: $fetched fetched, $skipped skipped, $deleted deleted, $errors errors.\n\n";

exit 0;

# either create pidfile or exit gracefully
sub write_pidfile {
  my $file = shift;
  if (-e $file) {  # uh oh, maybe we're running :-(
    open (F,$file) or return;
    my $oldpid = <F>;
    chomp $oldpid;
    kill 0=>$oldpid and return;
    close F;
  }
  open F,">",$file or die "Can't write PID file $file: $!";
  print F $$;
  close F;
  1;
}

sub find_config_file {
  my $self  = shift;
  my $home  = (getpwuid($<))[7] || $ENV{HOME};
  my @paths = ("$home/.fetchpods",
	       "/usr/local/etc/fetchpods.conf",
	       "/usr/etc/fetchpods.conf",
	       "/etc/fetchpods.conf",
	       "$Bin/../etc/fetchpods.conf",
	       "$Bin/../conf/fetchpods.conf");
  foreach (@paths) {
    return $_ if -f $_ && -r _;
  }
}

sub true_or_false {
  for my $ref (@_) {
     next unless $$ref;
     if ($$ref =~ /^no$/i) {
        undef $$ref;
     } elsif ($$ref =~ /^yes$/i) {
        $$ref = 1;
     }
  }
}

__END__

=head1 NAME

fetch_pods.pl -- Fetch and manage podcasts from the command line

=head1 SYNOPSIS

 % fetch_pods.pl /etc/fetchpods.conf
 Wed Dec 27 16:01:54 2006 START fetch_pods
	Updating podcasts for PRI's The World - Geo Quiz. 5 items available...
		PRI's The World - Geo Quiz Podcast 135: skipped
		PRI's The World - Geo Quiz Podcast 136: skipped
		PRI's The World - Geo Quiz Podcast 138: skipped
		PRI's The World - Geo Quiz Podcast 139: skipped
	Updating podcasts for APM: Future Tense. 5 items available...
		A backpack to lighten your load: deleted
		How best to begin using your new tech products: skipped
		Is malware leading Windows users to the Mac side?: skipped
		Last-minute gifts at NetworkforGood.com: skipped
		Where will next Bill Gates come from? Survey says: not the United States: 1993249 bytes fetched
Wed Dec 27 16:01:56 2006 END fetch_pods: 1 fetched, 8 skipped, 1 deleted, 1 errors.


=head1 DESCRIPTION

Use this Perl script to fetch and maintain a directory of podcast
subscriptions. Information about which podcasts to fetch are stored in
a configuration file. You can control how many podcast files to keep,
where to keep them, whether to rationalize their ID3 tags, and whether
to delete inactive podcasts.

=head2 Configuration File

=head1 SEE ALSO

L<MP3::PodcastFetch>,

=head1 AUTHOR

Lincoln Stein E<lt>lstein@cshl.orgE<gt>.

Copyright (c) 2006 Lincoln Stein

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut

!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
