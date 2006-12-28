package MP3::PodcastFetch;

use strict;
use warnings;
use Carp 'croak';
use MP3::PodcastFetch::Feed;
use MP3::PodcastFetch::TagManager;

use LWP::UserAgent;
use HTTP::Status;

use File::Spec;
use File::Basename 'basename';
use File::Path 'mkpath';
use IO::Dir;

use Date::Parse;

our $VERSION = '1.00';

BEGIN {
  my @accessors = qw(base subdir rss
		     max timeout mirror_mode verbose rewrite_filename upgrade_tags
		     keep_old playlist_handle playlist_base force_genre force_artist
		     force_album);
  for my $accessor (@accessors) {
eval <<END;
sub $accessor {
    my \$self = shift;
    my \$d    = \$self->{$accessor};
    \$self->{$accessor} = shift if \@_;
    return \$d;
}
END
  die $@ if $@;
  }
}

# arguments:
# -base             => base directory for podcasts, e.g. /var/podcasts
# -subdir           => subdirectory for this podcast, e.g. music
# -rss              => url of the RSS feed to read
# -max              => maximum number of episodes to keep
# -timeout          => timeout for URL requests
# -mirror_mode      => 'modified-since' (careful) or 'exists' (careless)
# -rewrite_filename => rewrite file name with podcast title
# -upgrade_tag      => upgrade tags to v2.4
# -force_{genre,artist,album}      => force set the genre, artist and/or album
# -keep_old         => keep old podcasts that are no longer in the RSS
# -playlist_handle  => file handle for playlist
# -playlist_base    => file system base to use for the playlists
# -verbose          => print status reports

sub new {
  my $class = shift;
  my %args  = @_;
  my $self = bless {},ref $class || $class;
  $self->base($args{-base}       || '/tmp/podcasts');
  $self->subdir($args{-subdir});
  $self->rss($args{-rss}         || croak 'please provide -rss argument');
  $self->max($args{-max}                             );
  $self->timeout($args{-timeout} || 30               );
  $self->mirror_mode($args{-mirror_mode} || 'exists' );
  $self->verbose($args{-verbose}                     );
  $self->rewrite_filename($args{-rewrite_filename}   );
  $self->upgrade_tags($args{-upgrade_tag}            );
  $self->keep_old($args{-keep_old}                   );
  $self->playlist_handle($args{-playlist_handle}     );
  $self->playlist_base($args{-playlist_base}         );
  $self->force_genre($args{-force_genre}             );
  $self->force_artist($args{-force_artist}           );
  $self->force_album($args{-force_artist}            );
  $self->{tabs} = 1;
  $self;
}

sub fetched { shift->{stats}{fetched} ||= 0 }
sub errors  { shift->{stats}{error}   ||= 0 }
sub deleted { shift->{stats}{deleted} ||= 0 }
sub skipped { shift->{stats}{skipped} ||= 0 }

sub bump_fetched {shift->{stats}{fetched} += (@_ ? shift : 1)}
sub bump_error  {shift->{stats}{error} += (@_ ? shift : 1)}
sub bump_deleted {shift->{stats}{deleted} += (@_ ? shift : 1)}
sub bump_skipped {shift->{stats}{skipped} += (@_ ? shift : 1)}

sub fetch_pods {
  my $self = shift;
  my $url  = $self->rss or croak 'No URL!';
  my $parser = MP3::PodcastFetch::Feed->new($url) or croak "Couldn't create parser";
  $parser->timeout($self->timeout);
  my @channels = $parser->read_feed;
  $self->log("Couldn't read RSS for $url: ",$parser->errstr) unless @channels;
  $self->update($_) foreach @channels;
}

sub update {
  my $self    = shift;
  my $channel = shift;
  my $title        = $channel->title;
  my $description  = $channel->description;
  my $dir          = $self->generate_directory($channel);
  my @items        = sort {$b->timestamp <=> $a->timestamp} grep {$_->url} $channel->items;
  my $total        = @items;

  # if there are more items than we want, then remove the oldest ones
  if (my $max = $self->max) {
    splice(@items,$max) if @items > $max;
  }

  $self->log("$title: $total podcasts available. Mirroring ",scalar @items,"...");
  {
    $self->{tabs}++; # for formatting
    $self->mirror($dir,\@items,$channel);
    $self->{tabs}--; # for formatting
  }
}

sub mirror {
  my $self = shift;
  my ($dir,$items,$channel) = @_;

  # generate a directory listing of the directory
  my %current_files;
  chdir($dir) or croak "Couldn't changedir to $dir: $!";
  my $d = IO::Dir->new('.') or croak "Couldn't open directory $dir for reading: $!";
  while (my $file = $d->read) {
    next if $file eq '..';
    next if $file eq '.';
    $current_files{$file}++;
  }
  $d->close;

  # generate a list of the basenames of the items
  my %to_fetch;
  for my $i (@$items) {
    my $url   = $i->url;
    my $basename = $self->make_filename($url,$i->title);
    $to_fetch{$basename}{url}     = $url;
    $to_fetch{$basename}{item}    = $i;
  }

  # find files that are no longer on the subscription list
  my @goners = grep {!$to_fetch{$_}} keys %current_files;

  if ($self->keep_old) {
    my $max   = $self->max;
    if (@goners + keys %to_fetch > $max) {
      $self->log_error("The episode limit of $max has been reached. Will not fetch additional podcasts.");
      return;
    }
  }
  else {
    my $gone   = unlink @goners;
    $self->bump_deleted($gone);
    $self->log("$_: deleted") foreach @goners;
  }

  # use LWP to mirror the remainder
  my $ua = LWP::UserAgent->new;
  $ua->timeout($self->timeout);
  for my $basename (sort keys %to_fetch) {
    $self->mirror_url($ua,$to_fetch{$basename}{url},$basename,$to_fetch{$basename}{item},$channel);
  }
}

sub mirror_url {
  my $self = shift;
  my ($ua,$url,$filename,$item,$channel) = @_;

  my $mode = $self->mirror_mode;
  croak "invalid mirror mode $mode" unless $mode eq 'exists' or $mode eq 'modified-since';

  my $title = $item->title;

  # work around buggy servers that don't respect if-modified-since
  if ($mode eq 'exists' && -e $filename) {
      $self->log("$title: skipped");
      $self->bump_skipped;
      return;
  }

  my $response = $ua->mirror($url,$filename);
  if ($response->is_error) {
    $self->log_error("$url: ",$response->status_line);
    $self->bump_error;
    return;
  }

  if ($response->code eq RC_NOT_MODIFIED) {
      $self->bump_skipped;
      $self->log("$title: skipped");
      return;
  }

  if ($response->code eq RC_OK) {
      my $length = $response->header('Content-Length');
      my $size   = -s $filename;

      if (defined $length && $size < $length) {
	  $self->log("$title: ","INCOMPLETE. $size/$length bytes fetched (will retry later)");
	  unlink $filename;
	  $self->bump_error;
      } else {
	  $self->fix_tags($filename,$item,$channel);
	  $self->write_playlist($filename,$item,$channel);
	  $self->bump_fetched;
	  $self->log("$title: $size bytes fetched");
      }
      return;
  }

  $self->log("$title: unrecognized response code ",$response->code);
  $self->bump_error;
}

sub log {
  my $self = shift;
  my @msg  = @_;
  return unless $self->verbose;
  my $tabs = $self->{tabs} || 0;
  foreach (@msg) { $_ ||= '' } # get rid of uninit variables
  chomp @msg;
  warn "\t"x$tabs,@msg,"\n";
}

sub log_error {
  my $self = shift;
  my @msg  = @_;
  my $tabs = $self->{tabs} || 0;
  foreach (@msg) { $_ ||= '' } # get rid of uninit variables
  chomp @msg;
  warn "\t"x$tabs,"*ERROR* ",@msg,"\n";
}

sub write_playlist {
  my $self = shift;
  my ($filename,$item,$channel) = @_;
  my $playlist = $self->playlist_handle or return;
  my $title    = $item->title;
  my $album    = $channel->title;
  my $duration = $self->get_duration($filename,$item);
  my $base     = $self->playlist_base || $self->base;
  my $subdir   = $self->subdir;
  my $dir      = $self->channel_dir($channel);

  # This is dodgy. We may be writing the podcast files onto a Unix mounted SD card
  # and reading it on a Windows-based MP3 player. We try to guess whether the base
  # is a Unix or a Windows base. We assume that OSX will work OK.
  my $path;
  if ($base =~ m!^[A-Z]:\\! or $base =~ m!\\!) {  # Windows style path
    eval { require File::Spec::Win32 } unless File::Spec::Win32->can('catfile');
    $path       = File::Spec::Win32->catfile($base,$subdir,$dir,$filename);
  } else {                                        # Unix style path
    eval { require File::Spec::Unix } unless File::Spec::Unix->can('catfile');
    $path       = File::Spec::Unix->catfile($base,$subdir,$dir,$filename);
  }
  print $playlist "#EXTINF:$duration,$album: $title\r\n";
  print $playlist $path,"\r\n";
}

sub fix_tags {
  my $self = shift;
  my ($filename,$item,$channel) = @_;
  return if $self->upgrade_tags eq 'no';

  my $mtime   = (stat($filename))[9];
  my $pubdate = $item->pubDate;
  my $secs    = $pubdate ? str2time($pubdate) : $mtime;
  my $year    = (localtime($secs))[5]+1900;
  my $album   = $self->force_album  || $channel->title;
  my $artist  = $self->force_artist || $channel->author;
  my $comment = $channel->description;
  $comment   .= " " if $comment;
  $comment   .= "[Fetched with podcast_fetch.pl (c) 2006 Lincoln D. Stein]";
  my $genre   = $self->force_genre  || 'Podcast';

  eval {
    MP3::PodcastFetch::TagManager->new()->fix_tags($filename,
						   {title  => $item->title,
						    genre  => $genre,
						    year   => $year,
						    artist => $artist,
						    album  => $album,
						    comment=> $comment,
						   },
						   $self->upgrade_tags,
						  );
  };

  $self->log_error($@) if $@;
  utime $mtime,$mtime,$filename;  # put the mtime back the way it was
}

sub get_duration {
  my $self     = shift;
  my ($filename,$item) = @_;

  my $duration =  MP3::PodcastFetch::TagManager->new()->get_duration($filename);
  $duration    = $item->duration || 0 unless defined $duration;
  return $duration;
}

sub make_filename {
  my $self = shift;
  my ($url,$title) = @_;
  if ($self->rewrite_filename) {
    my ($extension) = $url =~ /\.(\w+)$/;
    my $name = $self->safestr($title);
    $name   .= ".$extension" if defined $extension;
    return $name;
  }
  return basename($url);
}

sub generate_directory {
  my $self    = shift;
  my $channel = shift;
  my $dir     = File::Spec->catfile($self->base,$self->subdir,$self->channel_dir($channel));

  # create the thing
  unless (-d $dir) {
    mkpath($dir) or croak "Couldn't create directory $dir: $!";
  }

  -w $dir or croak "Can't write to directory $dir";
  return $dir;
}

sub channel_dir {
  my $self    = shift;
  my $channel = shift;
  return $self->safestr($channel->title); # potential bug here -- what if two podcasts have same title?
}

sub safestr {
  my $self = shift;
  my $str  = shift;
  # turn runs of spaces into _ characters
  $str =~ tr/ /_/s;

  # get rid of odd characters
  $str =~ tr/a-zA-Z0-9_+^.%$@=,-//cd;

  return $str;
}

1;
