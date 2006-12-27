package MP3::PodcastFetch::Feed;

use strict;
use base 'MP3::PodcastFetch::XML::SimpleParser';
use MP3::PodcastFetch::Feed::Channel;
use MP3::PodcastFetch::Feed::Item;

use LWP::UserAgent;

sub new {
  my $class = shift;
  my $url   = shift;
  my $self  = $class->SUPER::new();
  $self->url($url);
  $self->timeout(10);
  $self;
}

sub url {
  my $self = shift;
  my $d    = $self->{url};
  $self->{url} = shift if @_;
  $d;
}

sub errstr {
  my $self = shift;
  my $d    = $self->{error};
  $self->{error} = shift if @_;
  $d;
}

sub timeout {
  my $self = shift;
  my $d    = $self->{timeout};
  $self->{timeout} = shift if @_;
  $d;
}

sub read_feed {
  my $self = shift;
  my $url  = $self->url or return;
  my $ua = LWP::UserAgent->new;
  $ua->timeout($self->timeout);
  my $response = $ua->get($url,':content_cb' => sub { $self->parse($_[0]) } );
  $self->eof;
  unless ($response->is_success) {
    $self->errstr($response->status_line);
    return;
  }
  return $self->results;
}

sub t_channel {
  my $self = shift;
  my $attrs = shift;
  if ($attrs) { # tag is starting
    push @{$self->{current}},MP3::PodcastFetch::Feed::Channel->new;
    return;
  } else {
    $self->add_object(pop @{$self->{current}});
  }
}

sub t_item {
  my $self  = shift;
  my $attrs = shift;
  if ($attrs) { # tag is starting
    push @{$self->{current}},MP3::PodcastFetch::Feed::Item->new;
    return;
  } else {
    my $item =pop @{$self->{current}};
    my $channel = $self->{current}[-1] or return;
    $channel->add_item($item);
  }
}

sub t_title {
  my $self  = shift;
  my $attrs = shift;
  unless ($attrs) { # tag is ending
    my $item = $self->{current}[-1] or return;
    $item->title($self->char_data);
  }
}

sub t_description {
  my $self  = shift;
  my $attrs = shift;
  unless ($attrs) { # tag is ending
    my $item = $self->{current}[-1] or return;
    $item->description($self->char_data);
  }
}

sub t_guid {
  my $self  = shift;
  my $attrs = shift;
  unless ($attrs) { # tag is ending
    my $item = $self->{current}[-1] or return;
    $item->guid($self->char_data);
  }
}

sub t_pubDate {
  my $self = shift;
  my $attrs = shift;
  unless ($attrs) {
    my $item = $self->{current}[-1] or return;
    $item->pubDate($self->char_data);
  }
}

sub t_link {
  my $self = shift;
  my $attrs = shift;
  unless ($attrs) {
    my $item = $self->{current}[-1] or return;
    $item->link($self->char_data);
  }
}

sub t_author {
  my $self = shift;
  my $attrs = shift;
  unless ($attrs) {
    my $item = $self->{current}[-1] or return;
    $item->author($self->char_data);
  }
}

*t_itunes_author = \&t_author;

sub t_enclosure {
  my $self = shift;
  my $attrs = shift;
  if ($attrs) {
    my $item = $self->{current}[-1] or return;
    $item->url($attrs->{url});
  }
}


1;
