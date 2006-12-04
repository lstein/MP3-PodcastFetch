#!/usr/bin/perl

# this is the script that runs under cron
use strict;
use warnings;
use FindBin '$Bin';
use Config::IniFiles;

use lib "$Bin/../lib";
use PodcastFetch;

use constant CONFIG => "$Bin/../conf/podcasts.conf";

################## clean up nicely ##############
my $pid_file;
$SIG{TERM} = $SIG{INT} = sub { unlink $pid_file if defined $pid_file; die "killed"; };
END {
  unlink $pid_file if defined $pid_file;
}
#################################################

my $cfg = Config::IniFiles->new(-file=>CONFIG,-default=>'Globals') 
  or die "Couldn't open config file ",CONFIG,": $!";

$pid_file = $cfg->val(Globals=>'pidfile');
write_pidfile($pid_file) or exit 0;

my $verbose  = $cfg->val(Globals=>'verbose');
my $base     = $cfg->val(Globals=>'base');
my $timeout  = $cfg->val(Globals=>'timeout');
my @sections = grep {!/globals/i} $cfg->Sections;

my ($fetched,$skipped,$deleted) = (0,0,0);
for my $podcast (@sections) {
  my $url    = $cfg->val($podcast=>'url');
  my $limit  = $cfg->val($podcast=>'limit');
  my $subdir = $cfg->val($podcast=>'subdir');
  my $dir    = $subdir ? "$base/$subdir" : $base;

  unless (defined $url) {
    warn "No podcast RSS URL defined for $podcast\n";
    next;
  }

  my $feed   = PodcastFetch->new(-base    => $dir,
				 -rss     => $url,
				 -max     => $limit,
				 -verbose => $verbose);
  $feed->fetch_pods;
  $fetched += $feed->fetched;
  $skipped += $feed->skipped;
  $deleted += $feed->deleted;
}

warn "$fetched fetched, $skipped skipped, $deleted deleted.\n";

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
