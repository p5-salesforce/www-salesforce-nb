use Mojo::Base -strict;
use Test::More;
use Mojo::IOLoop;
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
post '/services/oauth2/revoke' => sub {
	my $c = shift;
	my $token = $c->param('token');
	return $c->render(json=>[{error_description=>"invalid token: $token",error=>"unsupported_token_type"}], status=>400) unless $token eq '123455663452abacbabababababababanenenenene';
	return $c->render(json=>[{success=>'true'}]);
};

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
can_ok($sf, qw(logout)) or BAIL_OUT("Something's wrong with the methods!");

# logout errors
{
	$sf->_instance_url('/');
	$sf->_access_token('invalid_token');
	$sf->_access_time(time());
	my $res;
	$res = try { $sf->logout() } catch { $_ };
	like($res, qr/invalid token/, "logout: Invalid logout: invalid token");
	Mojo::IOLoop->delay( sub {$sf->logout(shift->begin(0))},
		sub { my ($delay,$sf,$err,$res) = @_;
			like($err, qr/invalid token/, 'logout-nb: invalid: correct error message');
			is( $res, undef, 'logout-nb: invalid: correct no result' );
		}
	)->catch(sub { BAIL_OUT("logout-nb: something went horribly wrong".pop) })->wait;
}

$sf->_instance_url('/');
$sf->_access_token('123455663452abacbabababababababanenenenene');
$sf->_access_time(time());
try {$sf->logout()} catch { BAIL_OUT("logout: something went horribly wrong".pop) };
is($sf->_access_token(),undef,"logout: _access_token undef");
is($sf->_instance_url(),undef,"logout: _instance_url undef");
is($sf->_access_time(),0,"logout: _instance_url 0");

$sf->_instance_url('/');
$sf->_access_token('123455663452abacbabababababababanenenenene');
$sf->_access_time(time());
try {$sf->logout(undef)} catch { BAIL_OUT("logout: something went horribly wrong".pop) };
is($sf->_access_token(),undef,"logout: _access_token undef");
is($sf->_instance_url(),undef,"logout: _instance_url undef");
is($sf->_access_time(),0,"logout: _instance_url 0");

$sf->_instance_url('/');
$sf->_access_token('123455663452abacbabababababababanenenenene');
$sf->_access_time(time());
try {$sf->logout('nonsense')} catch { BAIL_OUT("logout: something went horribly wrong".pop) };
is($sf->_access_token(),undef,"logout: _access_token undef");
is($sf->_instance_url(),undef,"logout: _instance_url undef");
is($sf->_access_time(),0,"logout: _instance_url 0");

$sf->_instance_url('/');
$sf->_access_token('123455663452abacbabababababababanenenenene');
$sf->_access_time(time());
try {$sf->logout({foo=>'nonsense'})} catch { BAIL_OUT("logout: something went horribly wrong".pop) };
is($sf->_access_token(),undef,"logout: _access_token undef");
is($sf->_instance_url(),undef,"logout: _instance_url undef");
is($sf->_access_time(),0,"logout: _instance_url 0");

$sf->_instance_url('/');
$sf->_access_token('123455663452abacbabababababababanenenenene');
$sf->_access_time(time());
Mojo::IOLoop->delay( sub {$sf->logout(shift->begin(0))},
	sub { my ($delay,$sf,$err,$res) = @_;
		is($err, undef, 'logout-nb: correctly got no fault');
		is($sf->_access_token(),undef,"logout-nb: _access_token undef");
		is($sf->_instance_url(),undef,"logout-nb: _instance_url undef");
		is($sf->_access_time(),0,"logout-nb: _instance_url 0");
	}
)->catch(sub { BAIL_OUT("logout-nb: something went horribly wrong".pop) })->wait;

# run it with no login required
try {$sf->logout()} catch { BAIL_OUT("logout: something went horribly wrong".pop) };
is($sf->_access_token(),undef,"logout: already logged out: _access_token undef");
is($sf->_instance_url(),undef,"logout: already logged out: _instance_url undef");
is($sf->_access_time(),0,"logout: already logged out: _instance_url 0");
Mojo::IOLoop->delay( sub {$sf->logout(shift->begin(0))},
	sub { my ($delay,$sf,$err,$res) = @_;
		is($err, undef, 'logout-nb: already logged out: correctly got no fault');
		is($sf->_access_token(),undef,"logout-nb: already logged out: _access_token undef");
		is($sf->_instance_url(),undef,"logout-nb: already logged out: _instance_url undef");
		is($sf->_access_time(),0,"logout-nb: already logged out: _instance_url 0");
	}
)->catch(sub { BAIL_OUT("logout-nb: something went horribly wrong".pop) })->wait;

done_testing();
