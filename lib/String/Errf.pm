use 5.12.0;
use warnings;
package String::Errf;

use Carp ();
use Date::Format ();
use Params::Util ();

my $regex = qr/
 (%                   # leading '%'
  (?:{                # {
    (.*?)             #   mandatory argument name
    (?: ; (.*?) )?    #   optional extras after semicolon
  })                  # }
  ([a-z])             # actual conversion character
 )
/xi;

sub __hunk_errf {
  my ($self, $string) = @_;

  my @to_fmt;
  my $pos = 0;

  while ($string =~ m{\G(.*?)$regex}gs) {
    push @to_fmt, $1, {
      literal     => $2,
      argument    => $3,
      extra       => $4,
      conversion  => $5,
    };

    $pos = pos $string;
  }

  push @to_fmt, substr $string, $pos if $pos < length $string;

  return \@to_fmt;
}

sub __replace_errf {
  my ($self, $hunks, $input) = @_;

  my $heap = {};
  my $code = $self->codes;

  for my $i (grep { ref $hunks->[$_] } 0 .. $#$hunks) {
    my $hunk = $hunks->[ $i ];
    my $conv = $code->{ $hunk->{conversion} };

    Carp::croak("Unknown conversion in stringf: $hunk->{conversion}")
      unless defined $conv;

    $hunk->{replacement} = $input->{ $hunk->{argument} };
    $hunk->{args}        = [ $hunk->{extra} ? split /;/, $hunk->{extra} : () ];
  }
}

sub __format_errf {
  my ($self, $hunk) = @_;

  my $conv = $self->codes->{ $hunk->{conversion} };

  Carp::croak("Unknown conversion in stringf: $hunk->{conversion}")
    unless defined $conv;

  return $self->$conv($hunk->{replacement}, $hunk->{args}, $hunk);
}

# Likely integer formatting options are:
#   prefix (+ or SPACE for positive numbers)
# 
# Other options like (minwidth, precision, fillchar) are not out of the
# question, but if this system is to be used for formatting simple
# user-oriented error messages, they seem really unlikely to be used.  Put off
# supplying them! -- rjbs, 2010-07-30
#
# I'm not even sure that a SPACE prefix is useful, since we're not likely to be
# aligning many of these errors. -- rjbs, 2010-07-30
sub _format_int {
  my ($self, $value, $rest) = @_;

  my $first = (defined $rest->[0] and $rest->[0] !~ /=/)
            ? shift @$rest
            : '';

  $value = int $value;

  return $value if $value < 0;

  my $prefix = index($first, '+') >= 0 ? '+'
             : index($first, ' ') >= 0 ? ' '
             :                           '';

  my %arg = (
    prefix => $prefix,
    (map {; split /=/, $_, 2 } @$rest)
  );

  return "$arg{prefix}$value";
}


# fillchar (0)
# precision
# minwidth
# maxwidth
# prefix (like '+' or ' ') ??

# Likely float formatting options are:
#   prefix (+ or SPACE for positive numbers)
#   precision
#
#
sub _format_float {
  my ($self, $value, $rest) = @_;

  my $first = (defined $rest->[0] and $rest->[0] !~ /=/)
            ? shift @$rest
            : '';

  my ($prefix_str, $prec) = $first =~ /\A([ +]*)(?:\.(\d+))?\z/;
  undef $prec if defined $prec and ! length $prec;

  my $prefix = index($first, '+') >= 0 ? '+'
             : index($first, ' ') >= 0 ? ' '
             :                           '';

  my %arg = (
    prefix    => $prefix,
    precision => $prec, 
    (map {; split /=/, $_, 2 } @$rest)
  );

  $value = defined $prec ?  sprintf("%0.${prec}f", $value) : $value;

  return $value < 0 ? $value : "$arg{prefix}$value";
}

sub _format_timestamp {
  my ($self, $value, $rest) = @_;

  my $type   = $rest->[0] || 'datetime';
  my $format = $type eq 'datetime' ? '%Y-%m-%d %T'
             : $type eq 'date'     ? '%Y-%m-%d'
             : $type eq 'time'     ? '%T'
             : Carp::croak("unknown format type for %t: %type");

  return Date::Format::time2str($format, $value);
}

sub _format_string {
  my ($self, $value, $rest) = @_;
  return $value;
}

sub _format_numbered {
  my ($self, $value, $rest, $hunk) = @_;

  my $word = shift @$rest;
  
  my ($singular, $divider, $extra) = $word =~ m{\A(.+?)(?: ([/+]) (.+) )?\z}x;

  $divider = '' unless defined $divider; # just to avoid warnings

  my $formed = abs($value) == 1               ? $singular
             : $divider   eq '/'              ? $extra
             : $divider   eq '+'              ? "$singular$extra"
             : $singular  =~ /(?:[xzs]|sh)\z/ ? "${singular}es"
             # xy -> xies -- rjbs, 2010-07-30
             :                                  "${singular}s";

  return $hunk->{conversion} eq 'N'
       ? $formed
       : $self->_format_float($value, $rest, $hunk) . " $formed";
}

use base 'String::Formatter';

use Sub::Exporter -setup => {
  exports => {
    errf => sub {
      my ($class) = @_;
      my $fmt = $class->new({
        input_processor => 'require_named_input',
        format_hunker   => '__hunk_errf',
        string_replacer => '__replace_errf',
        hunk_formatter  => '__format_errf',

        codes => {
          i => '_format_int',
          f => '_format_float',
          t => '_format_timestamp',
          s => '_format_string',
          n => '_format_numbered',
          N => '_format_numbered',
        },
      });

      return sub { $fmt->format(@_) };
    },
  }
};

1;
