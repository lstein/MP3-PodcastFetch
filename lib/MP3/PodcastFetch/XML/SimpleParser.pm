package MP3::PodcastFetch::XML::SimpleParser;
use HTML::Parser;

=head1 XML::SimpleParser -- a simple sax-based parser

=head2 SYNOPSIS

=head USAGE

=over 4

=cut

use warnings;
use strict;

sub new {
  my $class  = shift;
  my $self   = bless {},ref $class || $class;
  my $parser = HTML::Parser->new(api_version => 3,
				 start_h       => [ sub { $self->tag_starts(@_) },'tagname,attr' ],
				 end_h         => [ sub { $self->tag_stops(@_)  },'tagname' ],
				 text_h        => [ sub { $self->char_data(@_)  },'dtext' ]);
  $parser->xml_mode(1);
  $self->parser($parser);
  return $self;
}

sub parser {
  my $self = shift;
  my $d    = $self->{'XML::SimpleParser::parser'};
  $self->{'XML::SimpleParser::parser'} = shift if @_;
  $d;
}

sub parse_file {
  shift->parser->parse_file(@_);
}

sub parse {
  shift->parser->parse(@_);
}

sub eof {
  shift->parser->eof;
}

=item $request->tag_starts

This method is called internally during the parse to handle a start
tag.  It should not be called by application code.

=cut

# tags will be handled by a method named t_TAGNAME
sub tag_starts {
  my $self = shift;
  my ($tag,$attrs) = @_;
  $tag =~ s/[^\w]/_/g;
  my $method = "t_$tag";
  $self->{char_data} = '';  # clear char data
  $self->can($method)
    ? $self->$method($attrs) 
    : $self->do_tag($tag,$attrs);
}

=item $request->tag_stops

This method is called internally during the parse to handle a stop
tag.  It should not be called by application code.

=cut

# tags will be handled by a method named t_TAGNAME
sub tag_stops {
  my $self = shift;
  my $tag = shift;
  $tag =~ s/[^\w]/_/g;
  my $method = "t_$tag";
  $self->can($method)
    ? $self->$method()
    : $self->do_tag($tag);
}

=item $request->char_data

This method is called internally during the parse to handle character
data.  It should not be called by application code.

=cut

sub char_data {
  my $self = shift;
  if (@_ && length(my $text = shift)>0) {
    $self->{char_data} .= $text;
  } else {
    $self->trim($self->{char_data});
  }
}


=item $request->cleanup

This method is called internally at the end of the parse to handle any
cleanup that is needed.  The default behavior is to do nothing, but it
can be overridden by a subclass to provide more sophisticated
processing.

=cut

sub cleanup {
  my $self = shift;
}

=item $request->clear_results

This method is called internally at the start of the parse to clear
any accumulated results and to get ready for a new parse.

=cut

sub clear_results {
  shift->{results} = [];
}

=item $request->add_object(@objects)

This method is called internally during the parse to add one or more
objects (e.g. a Bio::Das::Feature) to the results list.

=cut

# add one or more objects to our results list
sub add_object {
  my $self = shift;
  if (my $cb = $self->callback) {
    eval {$cb->(@_)};
    warn $@ if $@;
  } else {
    push @{$self->{results}},@_;
  }
}

=item @results = $request->results

In a list context this method returns the accumulated results from the
DAS request. The contents of the results list is dependent on the
particular request, and you should consult each of the subclasses to
see what exactly is returned.

In a scalar context, this method will return an array reference.

=cut

sub results {
  my $self = shift;
  my $r = $self->{results} or return;
  return wantarray ? @$r : $r;
}

=item $request->do_tag

This method is called internally during the parse to handle a tag.  It
should not be called by application code, but can be overridden by a
subclass to provide tag-specific processing.

=cut

sub do_tag {
  my $self = shift;
  my ($tag,$attrs) = @_;
  # do nothing
}

=item $callback = $request->callback([$new_callback])

Internal accessor for getting or setting the callback code that will
be used to process objects as they are generated by the parse.

=cut

# get/set callback
sub callback {
  my $self = shift;
  my $d = $self->{callback};
  $self->{callback} = shift if @_;
  $d;
}

=item $trimmed_string = $request->trim($untrimmed_string)

This internal method strips leading and trailing whitespace from a
string.

=cut

# utilities
sub trim {
  my $self = shift;
  my $string = shift;
  $string =~ s/^\s+//;
  $string =~ s/\s+$//;
  $string;
}

1;

=back

=head2 The Parsing Process

This module and its subclasses use an interesting object-oriented way
of parsing XML documents that is flexible without imposing a large
performance penalty.

When a tag start or tag stop is encountered, the tag and its
attributes are passed to the tag_starts() and tag_stops() methods
respectively.  These methods both look for a defined method called
t_TAGNAME (where TAGNAME is replaced by the actual name of the tag).
If the method exists it is invoked, otherwise the tag and attribute
data are passed to the do_tag() method, which by default simply
ignores the tag.

A Bio::Das::Request subclass that wishes to process the
E<lt>FOOBARE<gt> tag, can therefore define a method called t_FOOBAR
which takes two arguments, the request object and the tag attribute
hashref.  The method can distinguish between E<lt>FOOBARE<gt> and
E<lt>/FOOBARE<gt> by looking at the attribute argument, which will be
defined for the start tag and undef for the end tag.  Here is a simple
example:

  sub t_FOOBAR {
    my $self       = shift;
    my $attributes = shift;
    if ($attributes) {
       print "FOOBAR is starting with the attributes ",join(' ',%$attributes),"\n";
    } else {
       print "FOOBAR is ending\n";
    }
  }

The L<Bio::Das::Request::Dsn> subclass is a good example of a simple
parser that uses t_TAGNAME methods exclusively.
L<Bio::Das::Request::Stylesheet> is an example of a parser that also
overrides do_tag() in order to process unanticipated tags.

=head1 AUTHOR

Lincoln Stein <lstein@cshl.org>.

Copyright (c) 2006 Cold Spring Harbor Laboratory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=head1 SEE ALSO

=cut

