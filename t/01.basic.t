#-*-Perl-*-

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.t'

use strict;
use warnings;
use Module::Build;
use File::Path 'rmtree';
use FindBin '$Bin';
use File::Spec;
use File::Temp qw(tempdir);
use lib "$Bin/../lib";

use constant TEST_COUNT => 12;
use constant RSS_FILE   => "$Bin/data/test.xml";

BEGIN {
  use Test;
  plan test => TEST_COUNT;
}

use MP3::PodcastFetch;

chdir $Bin;
my $tempdir = tempdir(CLEANUP=>1);
my $rss     = File::Spec->catfile($tempdir,"test.xml");

# we need to create a temporary XML file in which paths are correct
open IN,RSS_FILE or die $!;
open OUT,">",$rss or die $!;
while (<IN>) {
    s!\$PATH!file://$Bin/data!g;
    print OUT;
}
close IN;
close OUT;

my $base = File::Spec->catfile($tempdir,'podcasts');

my $feed = make_feed($base,$rss);
ok($feed);
ok($feed->fetch_pods);
ok($feed->fetched,2);
ok($feed->skipped,0);

my @fetched = $feed->fetched_files;
ok(@fetched == 2);

$feed = make_feed($base,$rss);
ok($feed->fetch_pods);
ok($feed->fetched,0);
ok($feed->skipped,2);
ok(-d $base);
ok(-d File::Spec->catfile($base,'MP3PodcastFetch'));
ok(-e File::Spec->catfile($base,'MP3PodcastFetch','Test_File_1.mp3'));
ok(-e File::Spec->catfile($base,'MP3PodcastFetch','Test_File_2.mp3'));

exit 0;

sub make_feed {
  my ($base,$rss) = @_;
  return MP3::PodcastFetch->new(-base             => $base,
				-rss              => "file://$rss",
				-rewrite_filename => 1,
				-upgrade_tag      => 'auto',
				-verbose          => 0,
				-mirror_mode      => 'exists',
				 );
}
