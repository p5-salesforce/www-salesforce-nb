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
	use_ok( 'WWW::Salesforce' ) || print "Bail out!\n";
}
# Silence
app->log->level('fatal');
get '/' => {text => 'works!'};
get '/error/query' => {json=>[{errorCode=>'foo',message=>'what?!?'}], status=>401};
get '/services/data' => sub {
	my $c = shift;
	$c->render(json => [
		{label=>"Winter '11",url=>"/services/data/v20.0",version=>"20.0"},
		{label=>"Spring '11",url=>"/services/data/v21.0",version=>"21.0"},
		{label=>"Summer '11",url=>"/services/data/v22.0",version=>"22.0"},
		{label=>"Spring '15",url=>"/services/data/v33.0",version=>"33.0"},
	]);
};
get '/services/data/v33.0/query' => sub {
	my $c = shift;
	my $query = $c->param('q');
	if ( $query eq 'select Id,IsActive,Name from Product2' ) {
		return $c->render(json => {done=>0,nextRecordsUrl=>'/services/data/v33.0/query/test123',records=>[
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
	$c->render(json=>{});
};
get '/services/data/v33.0/query/test123' => sub {
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
	$c->render(json => {instance_url=>Mojo::URL->new('/'),issued_at=>time()*1000,access_token => '123455663452abacbabababababababanenenenene'});
};


my $sf = WWW::Salesforce->new();
isa_ok( $sf, 'WWW::Salesforce', 'Is a proper Salesforce object' );

# Test attributes
{
	my @attributes = ('_api_path', '_access_token', 'api_host', 'consumer_key', 'consumer_secret', 'username', 'password', 'pass_token');
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
is $sf->get('/')->res->code, 200, 'UA: right status';
is $sf->get('/')->res->body, 'works!', 'UA: right body content';

# Test API Path gathering
is($sf->api_path(),'/services/data/v33.0/','api_path: got the correct latest path');

# Test Login attempt
is($sf->login()->_access_token(), '123455663452abacbabababababababanenenenene', 'login: got the right access token');

# Test a simple query
{
	my $res = $sf->query('select Id,IsActive,Name from Product2');
	isa_ok($res,'ARRAY',"query: got back an array ref");
	is( scalar(@{$res}), 2, 'query: got back 2 results');
	is( $res->[0]{Id}, '01t500000016RuaAAE', 'query: first result has proper ID' );
	is( $res->[1]{Id}, '01t500000016RuaAAF', 'query: second result has proper ID' );
}

# Test error handling
{
	my $error;
	$sf->on(error => sub{ $error = pop });
	my $path = $sf->api_path();
	$sf->_api_path('/error/');
	$sf->query('test');
	is($error, 'ERROR: 401 Unauthorized: what?!?: foo', 'error handling: got proper error message');
	#reset back to normal
	$sf->api_path($path);
}

done_testing();
