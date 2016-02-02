use Mojo::Base -strict;
use Test::More;
use Mojo::IOLoop;
use Mojolicious;
use Try::Tiny;
use v5.10;

use FindBin;
use lib "$FindBin::Bin/lib";

BEGIN { use_ok( 'WWW::Salesforce' ) || BAIL_OUT("Can't use WWW::Salesforce"); }
my $ERROR_OUT=0;
my $SOSL = 'FIND {Chase Test} RETURNING Account(Id,Name)';
my $SOSL_MAL = 'FIND {Chase TesTURNING Account(Id,Name)';
my $RES = [{
	attributes=> {
		type=> "Account",
		url=> "/services/data/v34.0/sobjects/Account/001W000000KY10hIAD"
	},
	Id=> "001W000000KY10hIAD",
	Name=> "Chase test"
}];
my $RES_EMPTY = {
	layout=>"/services/data/v34.0/search/layout",
	scopeOrder=>"/services/data/v34.0/search/scopeOrder",
	suggestions=>"/services/data/v34.0/search/suggestions"
};

my $sf = try { WWW::Salesforce->new(); } catch { BAIL_OUT("Unable to create new instance: $_"); };
isa_ok( $sf, 'WWW::Salesforce', 'Is a proper Salesforce object' ) || BAIL_OUT("can't instantiate");

# setup mock
my $mock = Mojolicious->new;
$mock->log->level('fatal');
$mock->routes->get('/services/data/v33.0/search' => sub {
	my $c = shift;
	return $c->render(status=>401,json=>[{message=>"Session expired or invalid",errorCode=>"INVALID_SESSION_ID"}]) if $ERROR_OUT;
	my $sosl = $c->param('q') || '';
	$sosl = '' unless $sosl && !ref($sosl);
	if ( $sosl && $sosl eq $SOSL_MAL ) {
		return $c->render(status=>404,json=>[{errorCode=> "MALFORMED_SEARCH", message=>"No search term found. The search term must be enclosed in braces."}]);
	}
	elsif ( $sosl && $sosl eq $SOSL ) {
		return $c->render(json=>$RES);
	}
	return $c->render(json=>$RES_EMPTY);
});
$sf->ua->server->app($mock); #point the client to the mock

# set the login
$sf->version('33.0');
$sf->login_url(Mojo::URL->new('/'));
$sf->_instance_url('/');
$sf->_access_token('123455663452abacbabababababababanenenenene');
$sf->_access_time(time());
# actual testing
can_ok($sf, qw(search) );

# errors
{
	my $res;
	$res = try {$sf->search($SOSL_MAL)} catch {$_};
	like($res,qr/MALFORMED_SEARCH/, "search: error: Malformed SOSL string");
}

{ # successes
	my $res;
	$res = try {$sf->search()} catch {$_};
	is_deeply($res, $RES_EMPTY, "search: empty call");
	$res = try {$sf->search(undef)} catch {$_};
	is_deeply($res, $RES_EMPTY, "search: undef call");
	$res = try {$sf->search({})} catch {$_};
	is_deeply($res, $RES_EMPTY, "search: hashref call");
	$res = try {$sf->search('')} catch {$_};
	is_deeply($res, $RES_EMPTY, "search: empty string call");
	$res = try {$sf->search($SOSL)} catch {$_};
	is_deeply($res, $RES, "search: Proper search and results");
}

{ # non-blocking errors
	my ($err, $res);
	Mojo::IOLoop->delay(
		sub { $sf->search($SOSL_MAL, shift->begin(0));},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in search-nb: ".pop)})->wait;
	like($err, qr/MALFORMED_SEARCH/, 'search-nb: malformed SOSL error');
	is($res, undef, "search-nb: malformed SOSL empty result");

	$err = undef;
	$res = undef;
	$sf->_access_token('');
	Mojo::IOLoop->delay(
		sub { $sf->search($SOSL_MAL, shift->begin(0));},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in search-nb: ".pop)})->wait;
	is($err, '404 Not Found', 'search-nb: not logged in');
	is($res, undef, "search-nb: not logged in");

	$err = undef;
	$res = undef;
	$sf->_access_token('123455663452abacbabababababababanenenenene');
	$ERROR_OUT=1;
	Mojo::IOLoop->delay(
		sub { $sf->search($SOSL_MAL, shift->begin(0));},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in search-nb: ".pop)})->wait;
	like($err, qr/INVALID_SESSION_ID/, 'search-nb: error on purpose');
	is($res, undef, "search-nb: error on purpose");
	$ERROR_OUT=0;
}

{ # successful search-nb
	my ($err, $res);
	Mojo::IOLoop->delay(
		sub { $sf->search($SOSL, shift->begin(0));},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in search-nb: ".pop)})->wait;
	is($err, undef, 'search-nb: success without error');
	is_deeply($res, $RES, "search-nb: proper response");
}

done_testing;
