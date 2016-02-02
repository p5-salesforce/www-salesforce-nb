use Mojo::Base -strict;
use Test::More;
use Mojo::IOLoop;
use Mojolicious;
use Try::Tiny;
use v5.10;

use FindBin;
use lib "$FindBin::Bin/lib";

BEGIN { use_ok( 'WWW::Salesforce' ) || BAIL_OUT("Can't use WWW::Salesforce"); }
my $ERROR_OUT = 0;
my $FIRST = {
	Id=>'01t500000016RuaAAE',
	IsActive=>1,
	Name=>'Test Name',
	attributes=>{
		type=>'Product2',
		url=>'/services/data/v33.0/sobjects/Product2/01t500000016RuaAAE',
	},
};
my $SECOND = {
	Id=>'01t500000016RuaAAF',
	IsActive=>1,
	Name=>'Test Name 2',
	attributes=>{
		type=>'Product2',
		url=>'/services/data/v33.0/sobjects/Product2/01t500000016RuaAAF',
	},
};

my $sf = try { WWW::Salesforce->new(); } catch { BAIL_OUT("Unable to create new instance: $_"); };
isa_ok( $sf, 'WWW::Salesforce', 'Is a proper Salesforce object' ) || BAIL_OUT("can't instantiate");

# setup mock
my $mock = Mojolicious->new;
$mock->log->level('fatal');
$mock->routes->get('/services/data/v33.0/query' => sub {
	my $c = shift;
	return $c->render(status=>401,json=>[{message=>"Session expired or invalid",errorCode=>"INVALID_SESSION_ID"}]) if $ERROR_OUT;
	my $query = $c->param('q');
	if ( $query eq 'select Id,IsActive,Name from Product2' ) {
		return $c->render(json =>{done=>0,nextRecordsUrl=>'/services/data/v33.0/query/test123',records=>[$FIRST,],});
	}
	elsif ( $query eq 'malformed 1' ) {
		return $c->render(json =>{done=>1,nextRecordsUrl=>'/services/data/v33.0/query/test123',});
	}
	elsif ( $query eq 'malformed 2' ) {
		return $c->render(json =>{done=>1,nextRecordsUrl=>'/services/data/v33.0/query/test123',records=>{}});
	}
	elsif ( $query eq 'malformed 3' ) {
		return $c->render(json =>{done=>0,records=>[$FIRST,],});
	}
	elsif ( $query eq 'malformed 4' ) {
		return $c->render(json =>{done=>1,nextRecordsUrl=>'/services/data/v33.0/query/test123',records=>undef});
	}
	elsif ( $query eq 'malformed 5' ) {
		return $c->render(status=>200,text=>'');
	}
	elsif ( $query eq 'malformed 6' ) {
		return $c->render(json =>{done=>1,nextRecordsUrl=>'/services/data/v33.0/query/test123',records=>'123'});
	}
	$c->render(json=>[{errorCode=>'foo',message=>'what?!?'}], status=>401);
});
$mock->routes->get('/services/data/v33.0/query/test123' => sub {
	my $c = shift;
	return $c->render(json => {done=>1,records=>[$SECOND,],});
});
$sf->ua->server->app($mock); #point the client to the mock

# set the login
$sf->version('33.0');
$sf->login_url(Mojo::URL->new('/'));
$sf->_instance_url('/');
$sf->_access_token('123455663452abacbabababababababanenenenene');
$sf->_access_time(time());
# actual testing
can_ok($sf, qw(query) );

# Test a simple query
{
	my $res;
	$res = try {$sf->query()} catch {$_};
	like($res, qr/A query is required/, 'query error: empty call');
	$res = try {$sf->query(undef)} catch {$_};
	like($res, qr/A query is required/, 'query error: undef');
	$res = try {$sf->query([])} catch {$_};
	like($res, qr/A query is required/, 'query error: arrayref');
	$res = try {$sf->query('malformed 1')} catch {$_};
	is_deeply($res,[],"query: malformed response (lacking records)");
	$res = try {$sf->query('malformed 2')} catch {$_};
	is_deeply($res,[],"query: malformed response (records as not an arrayref)");
	$res = try {$sf->query('malformed 3')} catch {$_};
	is_deeply($res,[$FIRST],"query: malformed response (not done but no nextRecordsUrl)");
	$res = try {$sf->query('malformed 4')} catch {$_};
	is_deeply($res,[],"query: malformed response (records as undef)");
	$res = try {$sf->query('malformed 5')} catch {$_};
	is_deeply($res,[],"query: malformed response (no JSON response at all?)");
	$res = try {$sf->query('malformed 6')} catch {$_};
	is_deeply($res,[],"query: malformed response (records as string)");
	$res = try {$sf->query('select Id,IsActive,Name from Product2')} catch {$_};
	is_deeply($res,[$FIRST,$SECOND],"query: Successful query");
	$res = try {$sf->query('bad query')} catch {$_};
	like($res, qr/^401 Unauthorized, foo: what?!?/, 'query error: Got the right error message');
}

{ #error
	my ($err, $res);
	Mojo::IOLoop->delay(
		sub { $sf->query(shift->begin(0));},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in query-nb: ".pop)})->wait;
	like($err, qr/A query is required/, 'query-nb: empty query correctly got an error');
	is_deeply($res, [], "query-nb: got the right empty result");

	$err = undef;
	$res = undef;
	Mojo::IOLoop->delay(
		sub { $sf->query('bad query', shift->begin(0));},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in query-nb: ".pop)})->wait;
	like($err, qr/^401 Unauthorized, foo: what?!?/, 'query-nb: correctly got an error');
	is_deeply($res, [], "query-nb: got the right empty result");

	$err = undef;
	$res = undef;
	Mojo::IOLoop->delay(
		sub { $sf->query('malformed 1', shift->begin(0));},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in query-nb: ".pop)})->wait;
	is($err, undef, 'query-nb: malformed 1');
	is_deeply($res, [], "query-nb: malformed 1 got the right empty result");

	$err = undef;
	$res = undef;
	Mojo::IOLoop->delay(
		sub { $sf->query('malformed 2', shift->begin(0));},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in query-nb: ".pop)})->wait;
	is($err, undef, 'query-nb: malformed 2');
	is_deeply($res, [], "query-nb: malformed 2 got the right empty result");

	$err = undef;
	$res = undef;
	Mojo::IOLoop->delay(
		sub { $sf->query('malformed 3', shift->begin(0));},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in query-nb: ".pop)})->wait;
	is($err, undef, 'query-nb: malformed 3');
	is_deeply($res, [$FIRST], "query-nb: malformed 3 got the right partial result");

	$err = undef;
	$res = undef;
	Mojo::IOLoop->delay(
		sub { $sf->query('malformed 4', shift->begin(0));},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in query-nb: ".pop)})->wait;
	is($err, undef, 'query-nb: malformed 4');
	is_deeply($res, [], "query-nb: malformed 4 got the right empty result");

	$err = undef;
	$res = undef;
	Mojo::IOLoop->delay(
		sub { $sf->query('malformed 5', shift->begin(0));},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in query-nb: ".pop)})->wait;
	is($err, undef, 'query-nb: malformed 5');
	is_deeply($res, [], "query-nb: malformed 5 got the right empty result");

	$err = undef;
	$res = undef;
	Mojo::IOLoop->delay(
		sub { $sf->query('select Id,IsActive,Name from Product2', shift->begin(0));},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in query-nb: ".pop)})->wait;
	is($err, undef, 'query-nb: correctly got no fault');
	is_deeply($res, [$FIRST,$SECOND], "query-nb: got the right result");
}

{ # not logged in problem
	my ($err, $res);
	$sf->_access_token('');
	Mojo::IOLoop->delay(
		sub { $sf->query('bad query', shift->begin(0));},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in query-nb: ".pop)})->wait;
	like($err, qr/^404/, 'query-nb: not logged in: correctly got an error');
	is($res, undef, "query-nb: not logged in: got the right empty result");
}

{ # malformed response problem
	my ($err, $res);
	$ERROR_OUT=1;
	$sf->_access_token('123455663452abacbabababababababanenenenene');
	Mojo::IOLoop->delay(
		sub { $sf->query('bad query', shift->begin(0));},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in query-nb: ".pop)})->wait;
	like($err, qr/^401 Unauthorized/, 'query-nb: correctly got an error');
	is_deeply($res, [], "query-nb: got the right empty result");
}

done_testing;
