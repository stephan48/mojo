#!/usr/bin/env perl
use Mojo::Base -strict;

use utf8;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_IOWATCHER}  = 'Mojo::IOWatcher';
  $ENV{MOJO_MODE}       = 'testing';
}

# "Of all the parasites I've had over the years,
#  these worms are among the best."
use Test::More tests => 9;
use Test::Mojo;

use FindBin;
use lib "$FindBin::Bin/external/lib";
my $t = Test::Mojo->new('MyApp');

# GET /
$t->get_ok('/')->status_is(200)->content_is('too!');

# GET /index.html
$t->get_ok('/index.html')->status_is(200)
  ->content_is('External static file!');

# GET /test
$t->get_ok('/test')->status_is(200)->content_is('works!');
