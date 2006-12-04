package Feed::Channel;

use strict;
use warnings;
use Class::Struct;

struct (
	'Feed::Channel' => {
			  title       => '$',
			  description => '$',
			  guid        => '$',
			  pubDate     => '$',
			  author      => '$',
			  link        => '$',
			 }
	);

sub add_item {
  my $self = shift;
  push @{$self->{'Feed::Channel::items'}},@_;
}

sub items {
  my $self = shift;
  my $items = $self->{'Feed::Channel::items'} or return;
  @$items;
}


1;
