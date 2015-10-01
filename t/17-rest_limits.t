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
my $ERROR_OUT = 0;
my $LIMITS = {
	ConcurrentAsyncGetReportInstances => {
		Max => 200,
		Remaining => 200
	},
	ConcurrentSyncReportRuns => {
		Max => 20,
		Remaining => 20
	},
	DailyApiRequests => {
		Max => 45000,
		Remaining => 40826
	},
};

# Silence
app->log->level('fatal');
get '/services/data/v33.0/limits' => sub {
	my $c = shift;
	return $c->render(status=>401,json=>[{message=>"Session expired or invalid",errorCode=>"INVALID_SESSION_ID"}]) if $ERROR_OUT;
	return $c->render(json=>$LIMITS)
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
can_ok($sf, qw(limits) );
$sf->_instance_url('/');
$sf->_access_time(time());

# first, test a login failure
Mojo::IOLoop->delay(
	sub {$sf->limits(shift->begin(0));},
	sub { my ($delay, $sf, $err, $res) = @_;
		like( $err, qr/404 Not Found/, 'limits-nb error: bad login');
		is($res, undef, 'limits-nb error: bad login correctly got no successful response');
	}
)->catch(sub {BAIL_OUT("Something went wrong in limits-nb: ".pop)})->wait;

# set the login
$sf->_access_token('123455663452abacbabababababababanenenenene');
# back to testing

my $res;
$res = try{return $sf->limits()} catch {return $_};
is_deeply( $res, $LIMITS, "limits: correct");
$res = try{return $sf->limits('')} catch {return $_};
is_deeply( $res, $LIMITS, "limits: correct even with empty string");
$res = try{return $sf->limits({})} catch {return $_};
is_deeply( $res, $LIMITS, "limits: correct even with hashref");
$res = try{return $sf->limits(undef)} catch {return $_};
is_deeply( $res, $LIMITS, "limits: correct even with undef");

# non-blocking limits
Mojo::IOLoop->delay(
	sub {$sf->limits(shift->begin(0))},
	sub { my ($delay, $sf, $err, $res) = @_;
		is($err,undef, 'limits-nb error: correct empty error');
		is_deeply($res,$LIMITS, "limits-nb: correct response" )
	}
)->catch(sub {BAIL_OUT("Something went wrong in limits-nb: ".pop)})->wait;

$ERROR_OUT = 1;
$res = try{return $sf->limits()} catch {return $_};
like( $res, qr/401/, "limits: error out.");
Mojo::IOLoop->delay(
	sub {$sf->limits(shift->begin(0))},
	sub { my ($delay, $sf, $err, $res) = @_;
		like($err,qr/401/, 'limits-nb error: correct error');
		is($res,undef, "limits-nb: correct no response" )
	}
)->catch(sub {BAIL_OUT("Something went wrong in limits-nb: ".pop)})->wait;
done_testing;
