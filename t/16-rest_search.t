use Mojo::Base -strict;
use Test::More;
use Mojo::IOLoop::Delay;
use Mojo::JSON;
use Mojolicious::Lite;
use Try::Tiny;
use v5.10;

use FindBin;
use lib "$FindBin::Bin/lib";

BEGIN {
	$ENV{MOJO_NO_SOCKS} = $ENV{MOJO_NO_TLS} = 1;
	$ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
	use_ok( 'WWW::Salesforce' ) || BAIL_OUT("Can't use WWW::Salesforce");
}
# Silence
app->log->level('fatal');
my $sf = try {
	WWW::Salesforce->new(
		login_url => Mojo::URL->new('/'),
		login_type => 'oauth2_up',
		version => '33.0',
		username => 'test',
		password => 'test',
		pass_token => 'toke',
		consumer_key => 'test_id',
		consumer_secret => 'test_secret',
	);
} catch {
	BAIL_OUT("Unable to create new instance: $_");
	return undef;
};
isa_ok( $sf, 'WWW::Salesforce', 'Is a proper Salesforce object' ) || BAIL_OUT("can't instantiate");
# set the login
$sf->_instance_url('/');
$sf->_access_token('123455663452abacbabababababababanenenenene');
$sf->_access_time(time());
# actual testing
can_ok($sf, qw(search) );

done_testing;
