#!/usr/bin/perl

use strict;
use Feed;

my $url =  shift;
my $parser = Feed->new($url);
my @channels = $parser->read_feed;
die $parser->errstr unless @channels;

foreach my $channel (@channels) {
  print "\n**",$channel->title,"**\n";
  for my $item ($channel->items) {
    next unless $item->url;
    print $item->title,"\t",$item->pubDate,"\t",$item->guid,"\t",$item->url,"\n";
  }
}

exit 0;

