#!/usr/bin/perl

use strict;
use warnings;
use PodcastFetch;

my $pod = PodcastFetch->new(-base=>'/tmp/podcasts',
			    -rss => 'http://www.onthemedia.org/index.xml',
			    -max => 4,
			    -verbose =>1);
$pod->fetch_pods;

1;
