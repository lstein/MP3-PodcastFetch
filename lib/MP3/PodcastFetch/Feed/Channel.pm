package MP3::PodcastFetch::Feed::Channel;

use strict;
use warnings;
use Class::Struct;

struct (
	'MP3::PodcastFetch::Feed::Channel' => {
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
  push @{$self->{'MP3::PodcastFetch::Feed::Channel::items'}},@_;
}

sub items {
  my $self = shift;
  my $items = $self->{'MP3::PodcastFetch::Feed::Channel::items'} or return;
  @$items;
}


1;
