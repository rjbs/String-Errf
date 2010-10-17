use strict;
use warnings;

use Test::More;

use Date::Format qw(time2str);
use JSON 2 ();
use String::Errf qw(errf);

sub errf_is {
  my ($format, $value, $want, $desc) = @_;

  my $have = errf($format, { x => $value });
  
  $desc ||= "$format <- $value ==> $want";
  is($have, $want, $desc);
}

$ENV{TZ} = 'America/New_York';

my %local_time = (
  secs => 1280530906,
  full => '2010-07-30 19:01:46',
  time => '19:01:46',
  date => '2010-07-30',
);

my $tests = do {
  use autodie;
  my $json = do {
    open my $fh, '<', 't/tests.json';
    local $/;
    <$fh>;
  };

  JSON->new->decode($json);
};

for my $test (@$tests) {
  errf_is(@$test);
}

is(
  errf(
    "%{booze}s and %{mixer}s", {
    booze => 'gin',
    mixer => 'tonic',
  }),
  "gin and tonic",
  "gin and tonic",
);

is(
  errf(
    "at %{lunch_time}t, %{user}s tried to eat %{dogs;hot dog}n",
    {
      user => 'rjbs',
      dogs => 5,
      lunch_time => $local_time{secs},
    },
  ),
  "at $local_time{full}, rjbs tried to eat 5 hot dogs",
  "simple test for %t, %s, %n",
);

is(
  errf("There %{lights;is+are}N %{lights;light}n.", { lights => 1 }),
  "There is 1 light.",
  "some inflections",
);

done_testing;
