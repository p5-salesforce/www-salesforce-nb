use Mojo::Base -strict;
BEGIN {
	$ENV{MOJO_NO_SOCKS} = $ENV{MOJO_NO_TLS} = 1;
	$ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Mojo::JSON;
use Mojolicious::Lite;
use Data::Dumper;

use FindBin;
use lib "$FindBin::Bin/lib";

BEGIN {
	use_ok( 'ITI::Salesforce' ) || print "Bail out!\n";
}
# Silence
app->log->level('fatal');
get '/' => {text => 'works!'};
get '/error/query' => {text=>'what?!?', status=>401};
get '/services/data' => sub {
	my $c = shift;
	$c->render(json => [
		{label=>"Winter '11",url=>"/services/data/v20.0",version=>"20.0"},
		{label=>"Spring '11",url=>"/services/data/v21.0",version=>"21.0"},
		{label=>"Summer '11",url=>"/services/data/v22.0",version=>"22.0"},
		{label=>"Spring '15",url=>"/services/data/v33.0",version=>"33.0"},
	]);
};
get '/services/data/v33.0/sobjects/:sobject/describe' => sub {
	my $c = shift;
	my $sobject = $c->stash('sobject');
	if ( $sobject eq 'Account' ) {
		return $c->render(json => {'namedLayoutInfos' => [], 'name' => 'Account', 'triggerable' => 1, 'customSetting' => 0, 'label' => 'Account', 'undeletable' => 1, 'urls' => {'sobject' => '/services/data/v33.0/sobjects/Account'}, 'deletable' => 1, 'feedEnabled' => 1, 'retrieveable' => 1, 'replicateable' => 1, 'actionOverrides' => [], 'listviewable' => undef, 'lookupLayoutable' => undef, 'searchable' => 1, 'createable' => 1, 'deprecatedAndHidden' => 0, 'custom' => 0, 'keyPrefix' => '001', 'childRelationships' => [{'field' => 'AccountId','childSObject' => 'AcceptedEventRelation',}], 'activateable' => 0, 'compactLayoutable' => 1, 'mergeable' => 1, 'searchLayoutable' => 1, 'queryable' => 1, 'fields' => [{'defaultValue' => undef,'type' => 'phone','label' => 'ITE Phone','name' => 'ITE_PHONE__c','custom' => 1,}], 'updateable' => 1, 'layoutable' => 1, 'labelPlural' => 'Accounts', 'recordTypeInfos' => [{'urls' => {'layout' => '/services/data/v33.0/sobjects/Account/describe/layouts/012000000000000AAA'}, 'recordTypeId' => '012000000000000AAA','defaultRecordTypeMapping' => 0,'name' => 'Master','available' => 1}]});
	}
	$c->render(json => []);
};
patch '/services/data/v33.0/sobjects/:sobject/:id' => sub {
	my $c = shift;
	my $sobject = $c->stash('sobject');
	my $id = $c->stash('id');
	if ( $sobject eq 'Account' && $id eq '00130000006rhDFAAY' ) {
		return $c->render(json=>'', status =>201);
	}
	$c->render(json =>{message=>"The requested resource does not exist",errorCode=>"NOT_FOUND"}, status => 404);
};
post '/services/data/v33.0/sobjects/:sobject' => sub {
	my $c = shift;
	my $sobject = $c->stash('sobject');
	if ( $sobject eq 'Account' ) {
		return $c->render(json=>{id=>"00130000006rhDFAAY",errors=>[],success=>Mojo::JSON->true}, status =>201);
	}
	return $c->render(json=>{errors=>['Invalid attempt to update'],success=>Mojo::JSON->false}, status =>404);
};
get '/services/data/v33.0/query' => sub {
	my $c = shift;
	my $query = $c->param('q');
	if ( $query eq 'select Id,IsActive,Name from Product2' ) {
		return $c->render(json => {done=>0,nextRecordsUrl=>'/services/data/v33.0/queryMore/test123',records=>[
			{
				Id=>'01t500000016RuaAAE',
				IsActive=>1,
				Name=>'Test Name',
				attributes=>{
					type=>'Product2',
					url=>'/services/data/v33.0/sobjects/Product2/01t500000016RuaAAE',
				},
			},
		],});
	}
	$c->render(json=>[]);
};
get '/services/data/v33.0/queryMore/test123' => sub {
	my $c = shift;
	return $c->render(json => {done=>1,records=>[
		{
			Id=>'01t500000016RuaAAF',
			IsActive=>1,
			Name=>'Test Name 2',
			attributes=>{
				type=>'Product2',
				url=>'/services/data/v33.0/sobjects/Product2/01t500000016RuaAAF',
			},
		},
	],});
};
post '/services/oauth2/token' => sub {
	my $c = shift;
	$c->render(json => {access_token => '123455663452abacbabababababababanenenenene'});
};
my $sf = ITI::Salesforce->new();
isa_ok( $sf, 'ITI::Salesforce', 'Is a proper Salesforce object' );

# Test attributes
{
	my @attributes = ('_api_path', '_ua', 'access_token', 'api_host', 'consumer_key', 'consumer_secret', 'username', 'password', 'pass_token');
	can_ok($sf, @attributes);
	for my $attr (@attributes) {
		my $orig = $sf->$attr;
		$sf->$attr('test');
		is($sf->$attr, 'test', "attribute: $attr set properly set to 'test'");
		$sf->$attr($orig);
		is($sf->$attr, $orig, "attribute: $attr returned to normal");
	}
}

# force the URL to point to our mock-server
$sf->api_host(Mojo::URL->new('/'));

# Test UA
isa_ok($sf->ua, 'Mojo::UserAgent', 'UA: Got a proper UA');
is $sf->ua->get('/')->res->code, 200, 'UA: right status';
is $sf->ua->get('/')->res->body, 'works!', 'UA: right body content';

# Test API Path gathering
is($sf->api_path(),'/services/data/v33.0/','api_path: got the correct latest path');

# Test Login attempt
is($sf->login()->access_token(), '123455663452abacbabababababababanenenenene', 'login: got the right access token');

# Test a simple query
{
	my $res = $sf->query('select Id,IsActive,Name from Product2');
	isa_ok($res,'ARRAY',"query: got back an array ref");
	is( scalar(@{$res}), 2, 'query: got back 2 results');
	is( $res->[0]{Id}, '01t500000016RuaAAE', 'query: first result has proper ID' );
	is( $res->[1]{Id}, '01t500000016RuaAAF', 'query: second result has proper ID' );
}

# Test an SObject describe
{
	my $res = $sf->describe('Account');
	isa_ok($res,'HASH',"describe: got back a hash ref");
	is( $res->{label}, 'Account', 'describe: got the right label');
	is( scalar(@{$res->{fields}}), 1, 'describe: got back the fields array' );
}

# Test error handling
{
	my $error;
	$sf->on(error => sub{ $error = pop });
	my $path = $sf->api_path();
	$sf->api_path('/error/');
	$sf->query('test');
	is($error, 'ERROR: 401, Unauthorized: what?!?', 'error handling: got proper error message');
	#reset back to normal
	$sf->api_path($path);
}

# test update
{
	$sf->on(error => sub{ say pop });
	my $res = $sf->update('Account','00130000006rhDFAAY', {Name=>'Chase, co.'});
	is($res,1, "update: properly updated the record");
}

# test create
{
	my $res = $sf->create('Account', {Name=>'Chase, co.'});
	isa_ok($res,'HASH', 'create: got back a hash ref');
	is($res->{id},'00130000006rhDFAAY', "create: Got back the created ID");
}

done_testing();
