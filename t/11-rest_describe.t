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
# Silence
app->log->level('fatal');
get '/services/data/v33.0/sobjects' => sub {return shift->render(json=>$DES_GLO)};
get '/services/data/v33.0/sobjects/:type/describe' => sub {
	my $c = shift;
	my $type = $c->stash('type') || '';
	unless ( $type eq 'Account' ) {
		return $c->render(status=>404,json=>[{errorCode=> "NOT_FOUND", message=>"The requested resource does not exist"}]);
	}
	return $c->render(json=> $DESCRIBE);
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
can_ok($sf, qw(describe describe_sobject describe_global) );

# describe_global
try {
	my $res = $sf->describe_global();
	is_deeply($res,$DES_GLO, "describe_global: correct response" )
} catch {
	BAIL_OUT("Something went wrong in describe_global: $_");
};

# describe | describe_sobject errors
{
	my $res = try{return $sf->describe('Something')} catch {return $_};
	like( $res, qr/The requested resource does not exist/, "describe: got correct error message on bad object name");
	$res = try{return $sf->describe('')} catch {return $_};
	like( $res, qr/An object is required to describe it/, "describe: got correct error message on empty string object");
	$res = try{return $sf->describe(undef)} catch {return $_};
	like( $res, qr/An object is required to describe it/, "describe: got correct error message on undef object");
	$res = try{return $sf->describe_sobject('Something')} catch {return $_};
	like( $res, qr/The requested resource does not exist/, "describe_sobject: got correct error message on bad object name");
	$res = try{return $sf->describe_sobject('')} catch {return $_};
	like( $res, qr/An object is required to describe it/, "describe_sobject: got correct error message on empty string object");
	$res = try{return $sf->describe_sobject(undef)} catch {return $_};
	like( $res, qr/An object is required to describe it/, "describe_sobject: got correct error message on undef object");
	$res = try{return $sf->describe('Account')} catch {return $_};
	is_deeply($res,$DESCRIBE,"describe: correct response");
	$res = try{return $sf->describe_sobject('Account')} catch {return $_};
	is_deeply($res,$DESCRIBE,"describe_sobject: correct response");
}
done_testing;
