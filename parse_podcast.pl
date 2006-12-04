#!/usr/bin/perl

use strict;
use Feed;

use constant TEST => '/home/lstein/podcast.xml';

my $parser = Feed->new();
$parser->parse_file(TEST);
my @channels = $parser->results;
foreach my $channel (@channels) {
  print "\n**",$channel->title,"**\n";
  for my $item ($channel->items) {
    next unless $item->url;
    print $item->title,"\t",$item->pubDate,"\t",$item->url,"\n";
  }
}
