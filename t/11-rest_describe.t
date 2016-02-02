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
my $DES_GLO = {
	encoding => "UTF-8",
	maxBatchSize => 200,
	sobjects => [
		{
			activateable => 'false',
			createable => 'true',
			custom => 'false',
			customSetting => 'false',
			deletable => 'true',
			deprecatedAndHidden => 'false',
			feedEnabled => 'true',
			keyPrefix => "001",
			label => "Account",
			labelPlural => "Accounts",
			layoutable => 'true',
			mergeable => 'true',
			name => "Account",
			queryable => 'true',
			replicateable => 'true',
			retrieveable => 'true',
			searchable => 'true',
			triggerable => 'true',
			undeletable => 'true',
			updateable => 'true',
			urls => {
				compactLayouts => "/services/data/v34.0/sobjects/Account/describe/compactLayouts",
				rowTemplate => "/services/data/v34.0/sobjects/Account/{ID}",
				approvalLayouts => "/services/data/v34.0/sobjects/Account/describe/approvalLayouts",
				listviews => "/services/data/v34.0/sobjects/Account/listviews",
				describe => "/services/data/v34.0/sobjects/Account/describe",
				quickActions => "/services/data/v34.0/sobjects/Account/quickActions",
				layouts => "/services/data/v34.0/sobjects/Account/describe/layouts",
				sobject => "/services/data/v34.0/sobjects/Account",
			},
		},
	],
};
my $DESCRIBE = {
	actionOverrides => [],
	activateable => 'false',
	childRelationships => [],
	compactLayoutable => 'true',
	createable => 'true',
	custom => 'false',
	customSetting => 'false',
	deletable => 'true',
	deprecatedAndHidden => 'false',
	feedEnabled => 'true',
	fields => [],
	keyPrefix => "001",
	label => "Account",
	labelPlural => "Accounts",
	layoutable => 'true',
	listviewable => undef,
	lookupLayoutable => undef,
	mergeable => 'true',
	name => "Account",
	namedLayoutInfos => [],
	queryable => 'true',
	recordTypeInfos => [],
	replicateable => 'true',
	retrieveable => 'true',
	searchLayoutable => 'true',
	searchable => 'true',
	triggerable => 'true',
	undeletable => 'true',
	updateable => 'true',
	urls => {},
};

my $sf = try { WWW::Salesforce->new(); } catch { BAIL_OUT("Unable to create new instance: $_"); };
isa_ok( $sf, 'WWW::Salesforce', 'Is a proper Salesforce object' ) || BAIL_OUT("can't instantiate");

# setup mock
my $mock = Mojolicious->new;
$mock->log->level('fatal');
$mock->routes->get('/services/data/v33.0/sobjects' => sub {
	my $c = shift;
	return $c->render(status=>500,json=>[{message=>"Error in Communication",errorCode=>"UNKNOWN_ERROR"}]) if $ERROR_OUT;
	return $c->render(json=>$DES_GLO)
});
$mock->routes->get('/services/data/v33.0/sobjects/:type/describe' => sub {
	my $c = shift;
	my $type = $c->stash('type') || '';
	unless ( $type eq 'Account' ) {
		return $c->render(status=>404,json=>[{errorCode=> "NOT_FOUND", message=>"The requested resource does not exist"}]);
	}
	return $c->render(json=> $DESCRIBE);
});
$sf->ua->server->app($mock); #point the client to the mock

# set the login
$sf->version('33.0');
$sf->login_url(Mojo::URL->new('/'));
$sf->_instance_url('/');
$sf->_access_token('123455663452abacbabababababababanenenenene');
$sf->_access_time(time());
# actual testing
can_ok($sf, qw(describe describe_sobject describe_global) );

# describe | describe_sobject errors
{
	my $res;
	$res = try{return $sf->describe('Something')} catch {return $_};
	like( $res, qr/The requested resource does not exist/, "describe: got correct error message on bad object name");
	$res = try{return $sf->describe('')} catch {return $_};
	like( $res, qr/An object is required to describe it/, "describe: got correct error message on empty string object");
	$res = try{return $sf->describe({})} catch {return $_};
	like( $res, qr/An object is required to describe it/, "describe: got correct error message on hashref");
	$res = try{return $sf->describe(undef)} catch {return $_};
	like( $res, qr/An object is required to describe it/, "describe: got correct error message on undef object");
	$res = try{return $sf->describe_sobject('Something')} catch {return $_};
	like( $res, qr/The requested resource does not exist/, "describe_sobject: got correct error message on bad object name");
}

# describe_global
{
	my $res;
	$res = try{return $sf->describe_global()} catch {return $_};
	is_deeply( $res, $DES_GLO, "describe_global: correct");
	$res = try{return $sf->describe_global('')} catch {return $_};
	is_deeply( $res, $DES_GLO, "describe_global: correct even with empty string");
	$res = try{return $sf->describe_global({})} catch {return $_};
	is_deeply( $res, $DES_GLO, "describe_global: correct even with hashref");
	$res = try{return $sf->describe_global(undef)} catch {return $_};
	is_deeply( $res, $DES_GLO, "describe_global: correct even with undef");

}

# successful describes
{
	my $res;
	$res = try{return $sf->describe('Account')} catch {return $_};
	is_deeply($res,$DESCRIBE,"describe: correct response");
}

{ # non-blocking describe_global
	my ($err, $res);
	Mojo::IOLoop->delay(
		sub {$sf->describe_global(shift->begin(0))},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in describe_global-nb: ".pop)})->wait;
	is($err,undef, 'describe_global-nb error: correct empty error');
	is_deeply($res,$DES_GLO, "describe_global-nb: correct response" )
}

{ # non-blocking describe errors
	my ($err, $res);
	Mojo::IOLoop->delay(
		sub { $sf->describe('something', shift->begin(0));},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in describe-nb: ".pop)})->wait;
	is($res, undef, 'describe-nb error: correctly got no successful response');
	like( $err, qr/The requested resource does not exist/, "describe-nb error: got correct error message on bad object name");
	$err = undef;
	$res = undef;
	Mojo::IOLoop->delay(
		sub {$sf->describe('', shift->begin(0));},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in describe-nb: ".pop)})->wait;
	is($res, undef, 'describe-nb error: correctly got no successful response');
	like( $err, qr/An object is required to describe it/, "describe-nb error: got correct error message on empty string object");
}

{ # non-blocking describe
	my ($err, $res);
	Mojo::IOLoop->delay(
		sub { $sf->describe('Account',shift->begin(0))},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in describe-nb: ".pop)})->wait;
	is($err,undef, 'describe-nb error: correct empty error');
	is_deeply($res,$DESCRIBE, "describe-nb: correct response" )
}

{ # attempt it when logins fail
	my ($err, $res);
	$sf->_access_token('');
	Mojo::IOLoop->delay(
		sub { $sf->describe('Account', shift->begin(0));},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in describe_global-nb: ".pop)})->wait;
	like( $err, qr/404 Not Found/, 'describe_global-nb error: bad login');
	is($res, undef, 'describe_global-nb error: bad login correctly got no successful response');
	$err = undef;
	$res = undef;
	Mojo::IOLoop->delay(
		sub { $sf->describe_global(shift->begin(0));},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in describe_global-nb: ".pop)})->wait;
	like( $err, qr/404 Not Found/, 'describe_global-nb error: bad login');
	is($res, undef, 'describe_global-nb error: bad login correctly got no successful response');
	$err = undef;
	$res = undef;
	$ERROR_OUT = 1;
	$sf->_access_token('123455663452abacbabababababababanenenenene');
	like( (try{return $sf->describe_global()} catch {return $_}), qr/500 Internal Server Error/, "describe_global: error");
	Mojo::IOLoop->delay(
		sub { $sf->describe_global(shift->begin(0));},
		sub { (undef, undef, $err, $res) = @_; }
	)->catch(sub {BAIL_OUT("Something went wrong in describe_global-nb: ".pop)})->wait;
	like( $err, qr/500 Internal Server Error/, 'describe_global-nb error: bad login');
	is($res, undef, 'describe_global-nb error: bad login correctly got no successful response');
}
done_testing;
