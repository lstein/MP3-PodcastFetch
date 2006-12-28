#!/usr/bin/perl

use strict;
use Audio::TagLib;

my $filename = shift or die "Usage: taginfo.pl [\$filename]";
my $file     = Audio::TagLib::MPEG::File->new($filename);
defined $file or die "Couldn't open $file: $!";

my $v2       = $file->ID3v2Tag;
if (defined $v2) {
  print "===================== ID3v2 info ===================\n";
  print "Title:   ",$v2->title->toCString,"\n";
  print "Artist:  ",$v2->artist->toCString,"\n";
  print "Album:   ",$v2->album->toCString,"\n";
  print "Year:    ",$v2->year,"\n";
  print "Genre:   ",$v2->genre->toCString,"\n";
  print "Comment: ",$v2->comment->toCString,"\n";
}

my $v1       = $file->ID3v1Tag;
if (defined $v1) {
  print "===================== ID3v1 info ===================\n";
  print "Title:   ",$v1->title->toCString,"\n";
  print "Artist:  ",$v1->artist->toCString,"\n";
  print "Album:   ",$v1->album->toCString,"\n";
  print "Year:    ",$v1->year,"\n";
  print "Genre:   ",$v1->genre->toCString,"\n";
  print "Comment: ",$v1->comment->toCString,"\n";
}
