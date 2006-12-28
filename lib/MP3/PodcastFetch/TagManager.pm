package MP3::PodcastFetch::TagManager;
# $Id: TagManager.pm,v 1.1 2006/12/28 16:51:13 lstein Exp $

# Handle various differences between ID3 tag libraries

my $MANAGER; # singleton

use strict;

sub new {
  my $class = shift;
  return $MANAGER ||= bless {},ref $class || $class;
}

sub fix_tags {
  my $self = shift;
  my ($filename,$tags,$upgrade_type) = @_;
  $self->{$upgrade_type} ||= $self->load_tag_fixer_code($upgrade_type) or die "Couldn't load appropriate tagging library: $@";
  $self->{$upgrade_type}->($filename,$tags);
}

sub get_duration {
  my $self     = shift;
  my $filename = shift;
  # try various ways of getting the duration

  unless ($self->{duration_getter}) {

    if (eval {require Audio::TagLib; 1}) {
      $self->{duration_getter} = \&get_duration_from_audiotaglib;
    }
    elsif (eval {require MP3::Info; 1}) {
      $self->{duration_getter} = \&get_duration_from_mp3info;
    }
    elsif (eval {require MP3::Tag; 1}) {
      $self->{duration_getter} = \&get_duration_from_mp3tag;
    }
    else {
      return;
    }
  }
  return $self->{duration_getter}->($filename);
}

sub get_duration_from_mp3info {
  my $filename = shift;
  my $info = MP3::Info::get_mp3info($filename) or return 0;
  return $info->{SS}
}

sub get_duration_from_audiotaglib {
  my $filename = shift;
  my $file     = Audio::TagLib::MPEG::File->new($filename);
  defined $file or return 0;
  my $props    = $file->audioProperties;
  return $props->length;
}

sub get_duration_from_mp3tag {
  my $filename = shift;
  open OLDOUT,     ">&", \*STDOUT or die "Can't dup STDOUT: $!";
  open OLDERR,     ">&", \*STDERR or die "Can't dup STDERR: $!";
  open STDOUT, ">","/dev/null";
  open STDERR, ">","/dev/null";
  my $file     = MP3::Tag->new($filename) or return 0;
  open STDOUT, ">&",\*OLDOUT;
  open STDERR, ">&",\*OLDERR;
  return $file->total_secs_int;
}

sub load_tag_fixer_code {
  my $self = shift;
  my $upgrade_type = shift;
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

1;

__END__
