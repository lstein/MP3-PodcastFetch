package PodcastFetch;

use strict;
use warnings;
use Feed;
use LWP::UserAgent;
use HTTP::Status;
use Carp 'croak';
use File::Basename 'basename';
use File::Path 'mkpath';
use IO::Dir;
use Audio::TagLib::FileRef;

# arguments:
# -base      => base directory for podcasts, e.g. /var/podcasts
# -rss       => url of the RSS feed to read
# -max       => maximum number of episodes to keep
# -timeout   => timeout for URL requests
# -mirror_mode      => 'modified-since' (careful) or 'exists' (careless)
# -rewrite_filename => rewrite file name with podcast title
# -upgrade_tag     => upgrade tags to v2.4
# -verbose   => print status reports

sub new {
  my $class = shift;
  my %args  = @_;
  my $self = bless {},ref $class || $class;
  $self->base($args{-base}       || '/tmp/podcasts');
  $self->rss($args{-rss}         || croak 'please provide -rss argument');
  $self->max($args{-max}               );
  $self->timeout($args{-timeout} || 30 );
  $self->mirror_mode($args{-mirror_mode} || 'exists');
  $self->verbose($args{-verbose}       );
  $self->rewrite_filename($args{-rewrite_filename}       );
  $self->upgrade_tags($args{-upgrade_tag}       );
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
    local($self->{tabs});
    $self->{tabs}++; # for formatting
    $self->mirror($dir,\@items);
  }
}

sub mirror {
  my $self = shift;
  my ($dir,$items) = @_;

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
    my $title = $i->title;
    my $basename = $self->make_filename($url,$title);
    $to_fetch{$basename}{url}   = $url;
    $to_fetch{$basename}{title} = $title;
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
    $self->mirror_url($ua,$to_fetch{$basename}{url},$basename,$to_fetch{$basename}{title});
  }
}

sub mirror_url {
  my $self = shift;
  my ($ua,$url,$filename,$title) = @_;

  my $mode = $self->mirror_mode;
  croak "invalid mirror mode $mode" unless $mode eq 'exists' or $mode eq 'modified-since';

  # work around buggy servers that don't respect if-modified-since
  if ($mode eq 'exists' && -e $filename) {
      $self->log("$title: skipped");
      $self->bump_skipped;
      return;
  }

  my $response = $ua->mirror($url,$filename);
  if ($response->is_error) {
      warn "$url: ",$response->status_line;
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
	  $self->fix_tags($filename,$title)  if $self->upgrade_tags;
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

sub fix_tags {
  my $self = shift;
  my ($filename,$title) = @_;
  my $mtime = (stat($filename))[9];
  my $year  = (localtime($mtime))[5]+1900;

  eval {
    my $mp3   = Audio::TagLib::FileRef->new($filename);
    defined $mp3 or die "Audio::TabLib::FileRef->new: $!";
    $mp3->save;    # this seems to upgrade the tag to v2.4
    undef $mp3;
    $mp3   = Audio::TagLib::FileRef->new($filename);
    my $tag   = $mp3->tag;
    $tag->setGenre(Audio::TagLib::String->new('Podcast'));
    $tag->setTitle(Audio::TagLib::String->new($title));
    $tag->setYear($year);
    $mp3->save;
  };
  croak $@ if $@;

  utime $mtime,$mtime,$filename;  # put the mtime back the way it was
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
