use Mojo::Base -strict;
use Test::More;
use Mojo::IOLoop;
use Mojolicious;
use Try::Tiny;
use v5.10;

use FindBin;
use lib "$FindBin::Bin/lib";

BEGIN { use_ok( 'WWW::Salesforce' ) || BAIL_OUT("Can't use WWW::Salesforce"); }
my @fields = qw(Name MailingStreet MailingCity MailingState MailingCountry Phone);

my $sf = try { WWW::Salesforce->new(); } catch { BAIL_OUT("Unable to create new instance: $_"); };
isa_ok( $sf, 'WWW::Salesforce', 'Is a proper Salesforce object' ) || BAIL_OUT("can't instantiate");

# setup mock
my $mock = Mojolicious->new;
$mock->log->level('fatal');
$mock->routes->post('/services/data/v33.0/sobjects/:type' => sub {
	my $c = shift;
	my $type = $c->stash('type');
	my $params = $c->req->json || undef;
	unless ( $type && $type eq 'Account' ) {
		return $c->render(json=>[{message=>"The requested resource does not exist",errorCode=>"NOT_FOUND"}],status=>404);
	}
	if ( $params && ref($params) eq 'ARRAY' ) {
		return $c->render(json=>[{message=>"Can not deserialize SObject out of START_ARRAY token at [line:1, column:1]",errorCode=>"JSON_PARSER_ERROR"}],status=>400);
	}
	elsif ( $params && ref($params) eq 'HASH' ) {
		unless ( $params->{Name} ) {
			return $c->render(json=>[{message=>"Required fields are missing: [Name]",errorCode=>"REQUIRED_FIELD_MISSING",fields=>["Name",],}],status=>400);
		}
		for my $key (keys %$params) {
			unless ( grep {$key eq $_} @fields ) {
				return $c->render(json=>[{message=>"No such column '$key' on sobject of type $type",errorCode=>"INVALID_FIELD"}],status=>400);
			}
		}
		return $c->render(json=>{success=>'true',id=>'01t500000016RuaAAE',errors=>[]});
	}
	return $c->render(json=>[{message=>"Multipart message must include a non-binary part",errorCode=>"INVALID_MULTIPART_REQUEST"}],status=>400);
});
$sf->ua->server->app($mock); #point the client to the mock

# set the login
$sf->version('33.0');
$sf->login_url(Mojo::URL->new('/'));
$sf->_instance_url('/');
$sf->_access_token('123455663452abacbabababababababanenenenene');
$sf->_access_time(time());
# actual testing
can_ok($sf, qw(create insert) );

{ # error handling
	my $error;
	$error = try {return $sf->create() } catch { $_; };
	like( $error, qr/^No SObject Type defined/, 'create error: invalid object');
	$error = try {return $sf->insert() } catch { $_; };
	like( $error, qr/^No SObject Type defined/, 'insert error: invalid object');
	$error = try {return $sf->create({type=>{}}) } catch { $_; };
	like( $error, qr/^No SObject Type defined/, 'create error: invalid object');
	$error = try {return $sf->create('test', '') } catch { $_; };
	like( $error, qr/Empty SObjects are not allowed/, 'create error: invalid object');
	$error = try {return $sf->create('test', []) } catch { $_; };
	like( $error, qr/Empty SObjects are not allowed/, 'create error: invalid object');
	$error = try {return $sf->create('test', undef) } catch { $_; };
	like( $error, qr/Empty SObjects are not allowed/, 'create error: invalid object');
	$error = try {return $sf->create('', '') } catch { $_; };
	like( $error, qr/^No SObject Type defined/, 'create error: invalid object');
	$error = try {return $sf->create([], []) } catch { $_; };
	like( $error, qr/^No SObject Type defined/, 'create error: invalid object');
	$error = try {return $sf->create(undef, undef) } catch { $_; };
	like( $error, qr/^No SObject Type defined/, 'create error: invalid object');
	$error = try {return $sf->create('badObject', {empty=>'stuff'}) } catch { $_; };
	like( $error, qr/The requested resource does not exist/, 'create error: invalid object type');
	$error = try { return $sf->create({type=>'badObject',empty=>'stuff'}); } catch { $_; };
	like( $error, qr/The requested resource does not exist/, 'create error: invalid object type in-type');
	$error = try { return $sf->create({attributes => {type=>'badObject'},empty=>'stuff'}); } catch { $_; };
	like( $error, qr/The requested resource does not exist/, 'create error: invalid object type in-attributes-type');
	$error = try {return $sf->create('Account', {empty=>'stuff'}) } catch { $_; };
	like( $error, qr/Required fields are missing/, 'create error: missing required field');
	$error = try {return $sf->create('Account', {Name=>'foo',empty=>'stuff'}) } catch { $_; };
	like( $error, qr/INVALID_FIELD: No such column/, 'create error: Invalid Column');
	$error = try { return $sf->create({empty=>'stuff'}); } catch { $_; };
	like( $error, qr/^No SObject Type defined/, 'create error: no type error message');
	$error = try { return $sf->create('type',{}); } catch { $_; };
	like( $error, qr/^Empty SObjects are not allowed/, 'create error: empty object error message');
	$error = try { return $sf->create('type',{}); } catch { $_; };
	like( $error, qr/^Empty SObjects are not allowed/, 'create error: empty object error message');
	$error = try { return $sf->create('type',''); } catch { $_; };
	like( $error, qr/^Empty SObjects are not allowed/, 'create error: non-hashref object error message');
	$error = try { return $sf->create('type',undef); } catch { $_; };
	like( $error, qr/^Empty SObjects are not allowed/, 'create error: non-hashref object error message');
	$error = try { return $sf->create('type'); } catch { $_; };
	like( $error, qr/^Empty SObjects are not allowed/, 'create error: no objects error message');
}

# object creation tests
my $expected_result = {success=>'true',id=>'01t500000016RuaAAE',errors=>[]};
try {
	#type as top-level hash key
	my $res;
	$res = $sf->create({type=>'Account',Name=>'test',});
	is_deeply($res, $expected_result, "create: type_in_object: got a good response");
	#type as attributes hash key
	$res = $sf->create({attributes=>{type=>'Account'},Name=>'test',});
	is_deeply($res, $expected_result, "create: type_in_object: got a good response");
	#type argument overridden in top-level hash key
	$res = $sf->create('Account',{type=>'ThrowawayType',Name=>'test',});
	is_deeply($res, $expected_result, "create: type_in_object: got a good response");
	#type argument overridden in attributes hash key
	$res = $sf->create('Account',{attributes=>{type=>'ThrowawayType'},Name=>'test',});
	is_deeply($res, $expected_result, "create: type_in_object: got a good response");
	#type as first argument and nowhere else
	$res = $sf->create('Account', {Name=>'test',});
	is_deeply($res, $expected_result, "create: type_before_object: got a good response");
} catch {
	BAIL_OUT("Something went wrong in create: $_");
};

# non-blocking errors and successes
{
	my ($err, $res);
	Mojo::IOLoop->delay(
		sub {$sf->create(shift->begin(0));},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in create: ".pop)})->wait;
	like( $err, qr/^No SObject Type defined/, 'create_nb error: empty call');
	is($res, undef, 'create_nb error: correctly got no successful response');
	$res = undef;
	$err = undef;
	Mojo::IOLoop->delay(
		sub {$sf->create('foo',shift->begin(0));},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in create: ".pop)})->wait;
	like( $err, qr/^Empty SObjects are not allowed/, 'create_nb error: invalid object');
	is($res, undef, 'create_nb error: correctly got no successful response');
	$res = undef;
	$err = undef;
	Mojo::IOLoop->delay(
		sub {$sf->create('badObject',{empty=>'stuff'}, shift->begin(0));},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in create: ".pop)})->wait;
	like( $err, qr/The requested resource does not exist/, 'create_nb error: invalid object type');
	is($res, undef, 'create_nb error: correctly got no successful response');
	$res = undef;
	$err = undef;
	Mojo::IOLoop->delay(
		sub {$sf->create({type=>'Account',Name=>'test',}, shift->begin(0));},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in create: ".pop)})->wait;
	is($err, undef, 'create_nb: correctly got no fault');
	isa_ok($res, 'HASH', 'create_nb: got a hashref response');
	is_deeply($res, $expected_result, "create_nb: got the right result");

	# attempt it when logins fail
	$sf->_access_token('');
	$res = undef;
	$err = undef;
	Mojo::IOLoop->delay(
		sub {$sf->create({type=>'Account',Name=>'test',}, shift->begin(0));},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in create: ".pop)})->wait;
	like( $err, qr/404 Not Found/, 'create_nb error: bad login');
	is($res, undef, 'create_nb error: bad login correctly got no successful response');
}
done_testing;
