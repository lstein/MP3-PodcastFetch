#!/usr/bin/perl

use strict;
use Feed;
use LWP::UserAgent;

my $parser;

my $url = shift;

my $ua = LWP::UserAgent->new;
$ua->timeout(10);
my $response = $ua->get($url,':content_cb' => \&parse);
$parser->eof;
die $response->status_line unless $response->is_success;

my @channels = $parser->results;
foreach my $channel (@channels) {
  print "\n**",$channel->title,"**\n";
  for my $item ($channel->items) {
    next unless $item->url;
    print $item->title,"\t",$item->pubDate,"\t",$item->url,"\n";
  }
}


exit 0;

sub parse {
  my $data = shift;
  $parser ||= Feed->new();
  $parser->parse($data);
}

