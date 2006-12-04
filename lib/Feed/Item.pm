package Feed::Item;

use strict;
use warnings;
use Class::Struct;
use Date::Parse 'str2time';

struct (
	title       => '$',
	description => '$',
	guid        => '$',
	pubDate     => '$',
	author      => '$',
	link        => '$',
	url         => '$',
	);

sub timestamp {
  my $date = shift->pubDate or return;
  str2time($date);
}


1;
