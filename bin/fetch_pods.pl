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
$SIG{TERM} = $SIG{INT} = sub { unlink $pid_file if defined $pid_file; exit -1; };
END {
  unlink $pid_file if defined $pid_file;
}
#################################################

my $config_file = shift || CONFIG;

my $cfg = Config::IniFiles->new(-file=>$config_file,-default=>'Globals')
  or die "Couldn't open config file $config_file: $!";

$pid_file = $cfg->val(Globals=>'pidfile');
write_pidfile($pid_file) or exit 0;

chomp(my $date = `date`);
print "START fetch_pods: $date\n";

my $verbose      = $cfg->val(Globals=>'verbose');
my $base         = $cfg->val(Globals=>'base');
my $subdirs      = $cfg->val(Globals=>'subdirs');
my @sections     = grep {!/globals/i} $cfg->Sections;

my ($fetched,$skipped,$deleted) = (0,0,0);
for my $podcast (@sections) {
  my $url               = $cfg->val($podcast=>'url');
  my $limit             = $cfg->val($podcast=>'limit');
  my $subdir            = $cfg->val($podcast=>'subdir');
  my $rewrite           = $cfg->val($podcast=>'rewrite_filenames');
  my $mode              = $cfg->val($podcast=>'mirror_mode');
  my $timeout           = $cfg->val($podcast=>'timeout');

  my $dir    = $subdirs && $subdir ? "$base/$subdir" : $base;

  unless (defined $url) {
    warn "No podcast RSS URL defined for $podcast\n";
    next;
  }

  $limit = 1000 if $limit eq 'none';
  my $feed   = PodcastFetch->new(-base        => $dir,
				 -rss         => $url,
				 -max         => $limit,
				 -mirror_mode      => $mode,
				 -rewrite_filename => $rewrite,
				 -verbose          => $verbose);
  $feed->fetch_pods;
  $fetched += $feed->fetched;
  $skipped += $feed->skipped;
  $deleted += $feed->deleted;
}

print "$fetched fetched, $skipped skipped, $deleted deleted.\n\n";

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
