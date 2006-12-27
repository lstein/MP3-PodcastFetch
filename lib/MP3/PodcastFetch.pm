package MP3::PodcastFetch;

use strict;
use warnings;
use Feed;
use LWP::UserAgent;
use HTTP::Status;
use Time::ParseDate;
use Carp 'croak';
use File::Basename 'basename';
use File::Path 'mkpath';
use IO::Dir;

# arguments:
# -base             => base directory for podcasts, e.g. /var/podcasts
# -rss              => url of the RSS feed to read
# -max              => maximum number of episodes to keep
# -timeout          => timeout for URL requests
# -mirror_mode      => 'modified-since' (careful) or 'exists' (careless)
# -rewrite_filename => rewrite file name with podcast title
# -upgrade_tag      => upgrade tags to v2.4
# -force_genre      => force/change the genre
# -verbose          => print status reports

sub new {
  my $class = shift;
  my %args  = @_;
  my $self = bless {},ref $class || $class;
  $self->base($args{-base}       || '/tmp/podcasts');
  $self->rss($args{-rss}         || croak 'please provide -rss argument');
  $self->max($args{-max}                             );
  $self->timeout($args{-timeout} || 30               );
  $self->mirror_mode($args{-mirror_mode} || 'exists' );
  $self->verbose($args{-verbose}                     );
  $self->rewrite_filename($args{-rewrite_filename}   );
  $self->upgrade_tags($args{-upgrade_tag}            );
  $self->force_genre($args{-force_genre}             );
  $self->force_artist($args{-force_artist}           );
  $self->force_album($args{-force_artist}            );
  $self->{tabs} = 1;
  $self;
}

sub base {
  my $self = shift;
  my $d    = $self->{base};
  $self->{base} = shift if @_;
  $d;
}

sub rss {
  my $self = shift;
  my $d    = $self->{rss};
  $self->{rss} = shift if @_;
  $d;
}

sub max {
  my $self = shift;
  my $d    = $self->{max};
  $self->{max} = shift if @_;
  $d;
}

sub timeout {
  my $self = shift;
  my $d    = $self->{timeout};
  $self->{timeout} = shift if @_;
  $d;
}

sub mirror_mode {
  my $self = shift;
  my $d    = $self->{mirror_mode};
  $self->{mirror_mode} = shift if @_;
  $d;
}

sub rewrite_filename {
  my $self = shift;
  my $d    = $self->{rewrite_filename};
  $self->{rewrite_filename} = shift if @_;
  $d;
}

sub upgrade_tags {
  my $self = shift;
  my $d    = $self->{upgrade_tags};
  $self->{upgrade_tags} = shift if @_;
  $d;
}

sub force_genre {
  my $self = shift;
  my $d    = $self->{force_genre};
  $self->{force_genre} = shift if @_;
  $d;
}

sub force_artist {
  my $self = shift;
  my $d    = $self->{force_artist};
  $self->{force_artist} = shift if @_;
  $d;
}

sub force_album {
  my $self = shift;
  my $d    = $self->{force_album};
  $self->{force_album} = shift if @_;
  $d;
}

sub verbose {
  my $self = shift;
  my $d    = $self->{verbose};
  $self->{verbose} = shift if @_;
  $d;
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
  my $parser = Feed->new($url) or croak "Couldn't create parser";
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

  # if there are more items than we want, then remove the oldest ones
  if (my $max = $self->max) {
    splice(@items,$max) if @items > $max;
  }

  $self->log("Updating podcasts for $title. ",scalar @items," items available...");
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

  # remove any files that are no longer on %to_fetch
  my @goners = grep {!$to_fetch{$_}} keys %current_files;
  my $gone   = unlink @goners;
  $self->bump_deleted($gone);
  $self->log("$_: deleted") foreach @goners;

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
	  $self->fix_tags($filename,$item,$channel)  if $self->upgrade_tags;
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

sub fix_tags {
  my $self = shift;
  my ($filename,$item,$channel) = @_;
  return if $self->upgrade_tags eq 'no';

  my $mtime   = (stat($filename))[9];
  my $pubdate = $item->pubDate;
  my $secs    = $pubdate ? parsedate($pubdate) : $mtime;
  my $year    = (localtime($secs))[5]+1900;
  my $album   = $self->force_album  || $channel->title;
  my $artist  = $self->force_artist || $channel->author;
  my $comment = $channel->description;
  $comment   .= " " if $comment;
  $comment   .= "[Fetched with podcast_fetch.pl (c) 2006 Lincoln D. Stein]";
  my $genre   = $self->force_genre  || 'Podcast';

  eval {
    $self->{tag_fixer} ||= $self->load_tag_fixer_code or die "Couldn't load appropriate tagging library: $@";
    $self->{tag_fixer}->($filename,
			 {title  => $item->title,
			  genre  => $genre,
			  year   => $year,
			  artist => $artist,
			  album  => $album,
			  comment=> $comment,
			  }
			);
  };

  $self->log_error($@) if $@;
  utime $mtime,$mtime,$filename;  # put the mtime back the way it was
}

sub load_tag_fixer_code {
  my $self = shift;
  my $upgrade_type = $self->upgrade_tags;
  return $self->load_mp3_tag_lib   if lc $upgrade_type eq 'id3v1' or lc $upgrade_type eq 'id3v2.3';
  return $self->load_audio_tag_lib if lc $upgrade_type eq 'id3v2.4';
  return $self->load_audio_tag_lib || $self->load_mp3_tag_lib if lc $upgrade_type eq 'auto';
  return;
}

sub load_mp3_tag_lib {
  my $self   = shift;
  my $loaded = eval {require MP3::Tag; 1; };
  return unless $loaded;
  return lc $self->upgrade_tags eq 'id3v1' ? \&upgrade_to_ID3v1 : \&upgrade_to_ID3v23;
}

sub load_audio_tag_lib {
  my $self = shift;
  my $loaded = eval {require Audio::TagLib; 1; };
  return unless $loaded;
  return \&upgrade_to_ID3v24;
}

sub upgrade_to_ID3v24 {
  my ($filename,$tags) = @_;
  my $mp3   = Audio::TagLib::FileRef->new($filename);
  defined $mp3 or die "Audio::TabLib::FileRef->new: $!";
  $mp3->save;    # this seems to upgrade the tag to v2.4
  undef $mp3;
  $mp3   = Audio::TagLib::FileRef->new($filename);
  my $tag   = $mp3->tag;
  $tag->setGenre(Audio::TagLib::String->new($tags->{genre}))     if defined $tags->{genre};
  $tag->setTitle(Audio::TagLib::String->new($tags->{title}))     if defined $tags->{title};
  $tag->setAlbum(Audio::TagLib::String->new($tags->{album}))     if defined $tags->{album};
  $tag->setArtist(Audio::TagLib::String->new($tags->{artist}))   if defined $tags->{artist};
  $tag->setComment(Audio::TagLib::String->new($tags->{comment})) if defined $tags->{comment};
  $tag->setYear($tags->{year})                                   if defined $tags->{year};
  $mp3->save;
}

sub upgrade_to_ID3v1 {
  my ($filename,$tags,) = @_;
  upgrade_to_ID3v1_or_23($filename,$tags,0);
}

sub upgrade_to_ID3v23 {
  my ($filename,$tags,) = @_;
  upgrade_to_ID3v1_or_23($filename,$tags,1);
}

sub upgrade_to_ID3v1_or_23 {
  my ($filename,$tags,$v2) = @_;
  # quench warnings from MP3::Tag
  open OLDOUT,     ">&", \*STDOUT or die "Can't dup STDOUT: $!";
  open OLDERR,     ">&", \*STDERR or die "Can't dup STDERR: $!";
  open STDOUT, ">","/dev/null";
  open STDERR, ">","/dev/null";
  MP3::Tag->config(autoinfo=> $v2 ? ('ID3v1','ID3v1') : ('ID3v2','ID3v1'));
  my $mp3   = MP3::Tag->new($filename) or die "MP3::Tag->new($filename): $!";
  my $data = $mp3->autoinfo;
  do { $data->{$_} = $tags->{$_} if defined $tags->{$_} } foreach qw(genre title album artist comment year);
  $mp3->update_tags($data,$v2);
  $mp3->close;
  open STDOUT, ">&",\*OLDOUT;
  open STDERR, ">&",\*OLDERR;
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
  my $title   = $self->safestr($channel->title); # potential bug here -- what if two podcasts have same title?
  my $dir     = $self->base . "/$title";

  # create the thing
  unless (-d $dir) {
    mkpath($dir) or croak "Couldn't create directory $dir: $!";
  }

  -w $dir or croak "Can't write to directory $dir";

  return $dir;
}

sub safestr {
  my $self = shift;
  my $str  = shift;
  # turn runs of spaces into _ characters
  $str =~ tr/ /_/s;

  # get rid of odd characters
  $str =~ tr/a-zA-Z0-9_+^:.%$@=,-//cd;

  return $str;
}

1;
